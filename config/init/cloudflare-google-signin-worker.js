// Moopa's "Continue with Google": one Worker, on its own hostname (e.g. https://auth.example.com), signs people in
// with Google for every Moopa app it serves. Google needs each redirect address registered by hand, and has no API
// for it, so the apps share this one address instead of registering their own.
//
//   app  --GET /google/start?return_to=<app>/login/&state=<app's secret>-->  this Worker  --> Google
//   Google  --GET /google/callback?code&state-->  this Worker  --> <app>/login/?google=<assertion>
//
// The assertion is the person's verified Google email (and name and picture), for that app's origin and the state
// it asked with, signed with MOOPA_AUTH_KEY and good for two minutes. The app checks all of that (docs/signin.md).
//
// Settings:
//   GOOGLE_CLIENT_ID      (Var)     the Google OAuth "Web application" client
//   GOOGLE_CLIENT_SECRET  (Secret)  its secret
//   MOOPA_AUTH_KEY        (Secret)  shared with the apps as MOOPA_AUTH_KEY; signs assertions and this Worker's cookie
//   ALLOWED_RETURN_HOSTS  (Var)     comma-separated hosts an app may be on: "example.com" exactly, ".example.com" any
//                                   subdomain. localhost and *.localhost are always allowed, for development.
//
// The Google client's authorised redirect URI is this Worker's /google/callback (and http://localhost:8787/google/callback
// for `wrangler dev`).

const COOKIE = "moopa_google";
const COOKIE_SECONDS = 600;
const ASSERTION_SECONDS = 120;
const GOOGLE_AUTHORIZE = "https://accounts.google.com/o/oauth2/v2/auth";
const GOOGLE_TOKEN = "https://oauth2.googleapis.com/token";
const GOOGLE_ISSUERS = ["https://accounts.google.com", "accounts.google.com"];

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (request.method !== "GET") return text("Method not allowed", 405);
      if (url.pathname === "/google/start") return await start(url, env);
      if (url.pathname === "/google/callback") return await callback(request, url, env);
      return text("Not found", 404);
    } catch (error) {
      console.error("google sign-in failed", error && error.message);
      return page("Something went wrong", "Google sign-in didn't work this time. Go back and try again.", 502);
    }
  },
};

async function start(url, env) {
  const returnTo = allowedReturn(url.searchParams.get("return_to"), env.ALLOWED_RETURN_HOSTS);
  const state = url.searchParams.get("state") || "";
  if (!returnTo) return page("Can't sign in from there", "That address isn't one this sign-in serves.", 400);
  if (!/^[A-Za-z0-9_-]{16,128}$/.test(state)) return page("Can't sign in", "The sign-in request was incomplete. Go back and try again.", 400);

  const nonce = randomToken();
  const verifier = randomToken();
  const cookie = await seal(env.MOOPA_AUTH_KEY, "cookie", {
    n: nonce, v: verifier, r: returnTo, s: state, e: now() + COOKIE_SECONDS,
  });

  const google = new URL(GOOGLE_AUTHORIZE);
  google.search = new URLSearchParams({
    client_id: env.GOOGLE_CLIENT_ID,
    redirect_uri: url.origin + "/google/callback",
    response_type: "code",
    scope: "openid email profile",
    state: nonce,
    code_challenge: base64url(await sha256(verifier)),
    code_challenge_method: "S256",
    prompt: "select_account",
  }).toString();

  return new Response(null, {
    status: 302,
    headers: {
      Location: google.toString(),
      "Set-Cookie": cookieHeader(url, cookie, COOKIE_SECONDS),
      "Cache-Control": "no-store",
    },
  });
}

async function callback(request, url, env) {
  const held = await unseal(env.MOOPA_AUTH_KEY, "cookie", readCookie(request, COOKIE));
  if (!held || held.e < now()) {
    return page("This sign-in has expired", "Go back to the app and choose Continue with Google again.", 400);
  }
  if (url.searchParams.get("state") !== held.n) {
    return page("Can't sign in", "This sign-in didn't come from this browser. Go back and try again.", 400);
  }

  const clear = cookieHeader(url, "", 0);
  const back = new URL(held.r);

  if (url.searchParams.get("error")) {
    // Cancelled at Google (access_denied) or refused: the app says so and offers the other ways in
    back.searchParams.set("google_error", url.searchParams.get("error") === "access_denied" ? "cancelled" : "failed");
    back.searchParams.set("state", held.s);
    return redirect(back, clear);
  }

  const tokens = await exchange(url.searchParams.get("code") || "", held.v, url.origin + "/google/callback", env);
  // Straight from Google's token endpoint over TLS, so the ID token's signature needn't be checked (OpenID Connect
  // Core 3.1.3.7); its claims still are.
  const claims = decodeJwtPayload(tokens.id_token);
  if (!GOOGLE_ISSUERS.includes(claims.iss) || claims.aud !== env.GOOGLE_CLIENT_ID || !(claims.exp > now())) {
    throw new Error("ID token claims didn't check out");
  }
  if (claims.email_verified !== true || !claims.email) {
    back.searchParams.set("google_error", "unverified");
    back.searchParams.set("state", held.s);
    return redirect(back, clear);
  }

  const issued = now();
  const assertion = await seal(env.MOOPA_AUTH_KEY, "assertion", {
    v: 1,
    email: String(claims.email).toLowerCase(),
    name: claims.name || "",
    picture: claims.picture || "",
    hd: claims.hd || "",
    aud: back.origin,
    state: held.s,
    iat: issued,
    exp: issued + ASSERTION_SECONDS,
  });
  back.searchParams.set("google", assertion);
  return redirect(back, clear);
}

async function exchange(code, verifier, redirectUri, env) {
  const response = await fetch(GOOGLE_TOKEN, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      code,
      client_id: env.GOOGLE_CLIENT_ID,
      client_secret: env.GOOGLE_CLIENT_SECRET,
      redirect_uri: redirectUri,
      grant_type: "authorization_code",
      code_verifier: verifier,
    }).toString(),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.id_token) {
    throw new Error("Google token exchange failed: " + (body.error || response.status));
  }
  return body;
}

// ---------------------------------------------------------------------------------------------
// Where an app may be sent back to
// ---------------------------------------------------------------------------------------------

export function allowedReturn(value, allowedHosts) {
  let target;
  try {
    target = new URL(value || "");
  } catch {
    return "";
  }
  if (target.username || target.password || target.hash) return "";

  const host = target.hostname.toLowerCase();
  const local = host === "localhost" || host === "127.0.0.1" || host.endsWith(".localhost");
  if (target.protocol !== "https:" && !(local && target.protocol === "http:")) return "";
  if (local) return target.toString();

  const rules = String(allowedHosts || "").split(",").map((rule) => rule.trim().toLowerCase()).filter(Boolean);
  const ok = rules.some((rule) => (rule.startsWith(".") ? host.endsWith(rule) && host.length > rule.length : host === rule));
  return ok ? target.toString() : "";
}

// ---------------------------------------------------------------------------------------------
// Signed values: base64url(JSON) + "." + hex HMAC-SHA256 of "moopa-google-<purpose>." + that, keyed with the
// text of MOOPA_AUTH_KEY. Hex and a text key keep the app's side to CFML's hmac().
// ---------------------------------------------------------------------------------------------

export async function seal(key, purpose, value) {
  const body = base64url(new TextEncoder().encode(JSON.stringify(value)));
  return body + "." + (await hmacHex(key, "moopa-google-" + purpose + "." + body));
}

export async function unseal(key, purpose, sealed) {
  const [body, signature] = String(sealed || "").split(".");
  if (!body || !signature) return null;
  const expected = await hmacHex(key, "moopa-google-" + purpose + "." + body);
  if (!timingSafeEqual(expected, signature.toLowerCase())) return null;
  try {
    return JSON.parse(new TextDecoder().decode(fromBase64url(body)));
  } catch {
    return null;
  }
}

async function hmacHex(key, message) {
  if (!key) throw new Error("MOOPA_AUTH_KEY is not set");
  const cryptoKey = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(message));
  return [...new Uint8Array(signature)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ---------------------------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------------------------

function decodeJwtPayload(jwt) {
  const part = String(jwt || "").split(".")[1];
  if (!part) throw new Error("No ID token");
  return JSON.parse(new TextDecoder().decode(fromBase64url(part)));
}

async function sha256(value) {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)));
}

function randomToken() {
  return base64url(crypto.getRandomValues(new Uint8Array(32)));
}

function base64url(bytes) {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function fromBase64url(value) {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((value.length + 3) % 4);
  return Uint8Array.from(atob(base64), (char) => char.charCodeAt(0));
}

function now() {
  return Math.floor(Date.now() / 1000);
}

function readCookie(request, name) {
  const header = request.headers.get("Cookie") || "";
  for (const part of header.split(";")) {
    const [key, ...rest] = part.trim().split("=");
    if (key === name) return rest.join("=");
  }
  return "";
}

function cookieHeader(url, value, maxAge) {
  const secure = url.protocol === "https:" ? "; Secure" : "";
  return `${COOKIE}=${value}; Path=/google; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${secure}`;
}

function redirect(target, cookie) {
  return new Response(null, {
    status: 303,
    headers: { Location: target.toString(), "Set-Cookie": cookie, "Cache-Control": "no-store", "Referrer-Policy": "no-referrer" },
  });
}

function text(body, status) {
  return new Response(body, { status, headers: { "Content-Type": "text/plain; charset=utf-8" } });
}

function page(title, message, status) {
  const escape = (value) => value.replace(/[&<>"]/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[char]);
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escape(title)}</title>
<style>body{font:16px/1.5 system-ui,sans-serif;margin:0;display:grid;place-items:center;min-height:100vh;background:#f7f6f3;color:#1f2328}main{max-width:28rem;padding:2rem}h1{font-size:1.25rem;margin:0 0 .5rem}p{margin:0;color:#57606a}</style>
</head><body><main><h1>${escape(title)}</h1><p>${escape(message)}</p></main></body></html>`;
  return new Response(html, { status, headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" } });
}
