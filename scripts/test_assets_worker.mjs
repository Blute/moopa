// Regression harness for the signed assets Worker (config/init/cloudflare-signed-assets-worker.js): what a raw
// asset (/a/) answers, by the type it was stored with. Media and PDFs open in the browser; anything else, an SVG
// included, is a download, so a signed link can never show a page on the asset hostname; and every answer is
// nosniff. Runs the Worker's own fetch() against an in-memory bucket and a test signing key, on Node 20 or later.
//
// Run from Moopa's root:
//   node scripts/test_assets_worker.mjs

import { webcrypto } from "node:crypto";

if (!globalThis.crypto) globalThis.crypto = webcrypto;

const worker = (await import(new URL("../config/init/cloudflare-signed-assets-worker.js", import.meta.url))).default;

const KEY_B64 = Buffer.from("test-signing-key-for-the-harness-only").toString("base64");
const objects = new Map();
const env = {
  SIGNING_KEY_B64: KEY_B64,
  ASSETS_BUCKET: {
    async get(key) {
      const object = objects.get(key);
      if (!object) return null;
      return { body: object.body, size: object.body.length, etag: "e", httpMetadata: { contentType: object.contentType } };
    },
    async head(key) {
      const object = objects.get(key);
      return object ? { size: object.body.length } : null;
    },
  },
};

async function hmacHex(message) {
  const key = await crypto.subtle.importKey("raw", Buffer.from(KEY_B64, "base64"), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return Buffer.from(signature).toString("hex");
}

// A signed URL for a key (a raw asset, /a/, unless another kind is named), as the CFML and SQL signers make it: the
// decoded path and the query without sig.
async function signedUrl(key, kind = "a") {
  const exp = Math.floor(Date.now() / 1000) + 600;
  const path = `/${kind}/${key}`;
  const sig = await hmacHex(`${path}?exp=${exp}`);
  return `https://assets.example.com${encodeURI(path)}?exp=${exp}&sig=${sig}`;
}

let failures = 0;
let checks = 0;
function check(label, actual, expected) {
  checks++;
  if (actual === expected) {
    console.log(`PASS  ${label}`);
  } else {
    failures++;
    console.log(`FAIL  ${label} (expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)})`);
  }
}

async function fetchAsset(key, contentType) {
  objects.set(key, { body: Buffer.from("<html><script>alert(1)</script></html>"), contentType });
  return worker.fetch(new Request(await signedUrl(key)), env, { waitUntil() {} });
}

const inline = [
  ["photos/house.jpg", "image/jpeg"],
  ["photos/house.heic", "image/heic"],
  ["docs/contract.pdf", "application/pdf"],
  ["clips/walkthrough.mp4", "video/mp4"],
  ["clips/voice.m4a", "audio/mp4"],
];
for (const [key, type] of inline) {
  const response = await fetchAsset(key, type);
  check(`${type} answers 200`, response.status, 200);
  check(`${type} opens in the browser`, response.headers.get("Content-Disposition"), null);
  check(`${type} is nosniff`, response.headers.get("X-Content-Type-Options"), "nosniff");
}

const downloads = [
  ["uploads/page.html", "text/html", 'attachment; filename="page.html"'],
  ["uploads/drawing.svg", "image/svg+xml", 'attachment; filename="drawing.svg"'],
  ["uploads/photo.jpg", "text/html; charset=utf-8", 'attachment; filename="photo.jpg"'],
  ["uploads/script.js", "application/javascript", 'attachment; filename="script.js"'],
  ["uploads/odd name \"x\".bin", "application/octet-stream", 'attachment; filename="odd_name__x_.bin"'],
];
for (const [key, type, disposition] of downloads) {
  const response = await fetchAsset(key, type);
  check(`${type} answers 200`, response.status, 200);
  check(`${type} is a download, whatever its name`, response.headers.get("Content-Disposition"), disposition);
  check(`${type} is nosniff`, response.headers.get("X-Content-Type-Options"), "nosniff");
}

// A thumbnail (/i/) or a PDF's text (/m/) already in the edge cache: the Workers runtime hands back a cached answer
// whose headers can't be changed, so the Worker must still add its own without throwing.
class ImmutableHeaders extends Headers {
  set() { throw new TypeError("Can't modify immutable headers."); }
  append() { throw new TypeError("Can't modify immutable headers."); }
}
globalThis.caches = {
  default: {
    async match() {
      const cached = new Response("cached thumbnail", { status: 200 });
      Object.defineProperty(cached, "headers", { value: new ImmutableHeaders({ "Content-Type": "image/webp" }) });
      return cached;
    },
    async put() {},
  },
};
for (const kind of ["i", "m"]) {
  const response = await worker.fetch(new Request(await signedUrl("photos/house.jpg", kind)), { ...env, AI: { toMarkdown() {} } }, { waitUntil() {} });
  check(`a cached /${kind}/ answer is served`, response.status, 200);
  check(`...with its own body`, await response.text(), "cached thumbnail");
  check(`...and is nosniff`, response.headers.get("X-Content-Type-Options"), "nosniff");
}

const unsigned = await worker.fetch(new Request("https://assets.example.com/a/photos/house.jpg"), env, { waitUntil() {} });
check("an unsigned URL is refused", unsigned.status, 401);
check("...and its refusal is nosniff too", unsigned.headers.get("X-Content-Type-Options"), "nosniff");

console.log(`\n${checks} checks, ${failures} failing`);
process.exit(failures ? 1 : 0);
