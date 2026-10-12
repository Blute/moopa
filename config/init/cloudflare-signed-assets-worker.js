export default {
  async fetch(request, env, ctx) {
    try {
      const url = new URL(request.url);
      const method = request.method.toUpperCase();

      if (method !== "GET" && method !== "HEAD") {
        return new Response("Method not allowed", { status: 405 });
      }

      const kind = getKind(url.pathname);
      if (!kind) {
        return new Response("Not found", { status: 404 });
      }

      const sig = url.searchParams.get("sig");
      const expStr = url.searchParams.get("exp");
      if (!sig || !expStr) {
        return new Response("Unauthorized", { status: 401 });
      }

      const exp = Number(expStr);
      if (!Number.isFinite(exp)) {
        return new Response("Bad exp", { status: 400 });
      }

      const now = Math.floor(Date.now() / 1000);
      if (now > exp) {
        return new Response("Expired", { status: 403 });
      }

      const decodedPathname = decodePathname(url.pathname);
      if (!decodedPathname) {
        return new Response("Bad path", { status: 400 });
      }

      const signingKeyB64 = resolveSigningKeyB64(
        env,
        url.searchParams.get("kid"),
      );
      if (!signingKeyB64) {
        return new Response("Unauthorized", { status: 401 });
      }

      const canonical = buildCanonical(url, decodedPathname);
      const expectedSig = await hmacSha256Hex(canonical, signingKeyB64);
      if (!constantTimeEqualHex(expectedSig, sig)) {
        return new Response("Unauthorized", { status: 401 });
      }

      const objectKey = getObjectKey(decodedPathname, kind);
      if (!objectKey) {
        return new Response("Not found", { status: 404 });
      }

      if (kind === "a") {
        return handleAssetProxy({ request, env, objectKey, method, url });
      }

      if (kind === "i") {
        return handleImageTransform({
          request,
          env,
          objectKey,
          method,
          url,
          ctx,
        });
      }

      if (kind === "m") {
        return handleMarkdownTransform({ env, objectKey, method, url, ctx });
      }

      return handleVideoStream({ env, objectKey, method, url });
    } catch (error) {
      const message = normalizeErrorMessage(error, "Unhandled worker error");
      return new Response(`Worker error: ${message}`, { status: 500 });
    }
  },
};

function getKind(pathname) {
  if (pathname.startsWith("/a/")) return "a";
  if (pathname.startsWith("/i/")) return "i";
  if (pathname.startsWith("/m/")) return "m";
  if (pathname.startsWith("/v/")) return "v";
  return "";
}

function getObjectKey(pathname, kind) {
  return pathname.slice(3).trim();
}

function buildCanonical(url, decodedPathname) {
  const params = [];
  const rawQuery = url.search.startsWith("?")
    ? url.search.slice(1)
    : url.search;

  for (const segment of rawQuery.split("&")) {
    if (!segment) continue;

    const equals = segment.indexOf("=");
    const key = equals === -1 ? segment : segment.slice(0, equals);
    if (key === "sig") continue;

    const value = equals === -1 ? "" : segment.slice(equals + 1);
    params.push([key, value]);
  }
  params.sort((a, b) => a[0].localeCompare(b[0]));
  const canonicalQuery = params.map(([k, v]) => `${k}=${v}`).join("&");
  return `${decodedPathname}?${canonicalQuery}`;
}

function decodePathname(pathname) {
  try {
    return decodeURIComponent(pathname);
  } catch (_error) {
    return "";
  }
}

async function handleAssetProxy({ request, env, objectKey, method, url }) {
  // A range R2 can serve, or null for the whole object (a Range header this can't read is ignored, as RFC 9110
  // allows: the whole object is the answer).
  const rangeHeader = request.headers.get("Range");
  const range = rangeHeader ? parseRange(rangeHeader) : null;

  let obj;
  try {
    obj = range
      ? await env.ASSETS_BUCKET.get(objectKey, { range })
      : await env.ASSETS_BUCKET.get(objectKey);
  } catch (_error) {
    // R2 throws for a range past the end of the object: that's the asker's (416), not R2 failing.
    const head = range ? await env.ASSETS_BUCKET.head(objectKey).catch(() => null) : null;
    if (head && !servedRange(range, head.size)) {
      return new Response(null, {
        status: 416,
        headers: { "Content-Range": `bytes */${head.size}` },
      });
    }
    return new Response("Upstream error", { status: 502 });
  }

  if (!obj) {
    return new Response("Not found", { status: 404 });
  }

  const headers = new Headers();
  const contentType =
    obj.httpMetadata?.contentType ||
    guessContentType(objectKey) ||
    "application/octet-stream";
  headers.set("Content-Type", contentType);
  if (obj.etag) headers.set("ETag", obj.etag);

  // Partial only when a range was asked for: R2 reports a range on every object it returns, asked for or not, so
  // obj.range can't say whether this answer is partial.
  let status = 200;
  headers.set("Accept-Ranges", "bytes");
  if (range) {
    const served = servedRange(range, obj.size);
    if (!served) {
      return new Response(null, {
        status: 416,
        headers: { "Content-Range": `bytes */${obj.size}` },
      });
    }
    status = 206;
    headers.set(
      "Content-Range",
      `bytes ${served.offset}-${served.offset + served.length - 1}/${obj.size}`,
    );
    headers.set("Content-Length", String(served.length));
  } else {
    headers.set("Content-Length", String(obj.size));
  }

  // A signed URL is its own authorisation (no cookies are involved), so any page may read what it returns: a web app
  // that keeps a copy to work offline (Cache API, IndexedDB) reads it with a CORS request.
  headers.set("Access-Control-Allow-Origin", "*");

  applySignedExpiryCaching(headers, url);

  if (method === "HEAD") {
    return new Response(null, { status, headers });
  }

  return new Response(obj.body, { status, headers });
}

async function handleImageTransform({
  request,
  env,
  objectKey,
  method,
  url,
  ctx,
}) {
  const width = toPositiveInt(url.searchParams.get("width"));
  const height = toPositiveInt(url.searchParams.get("height"));
  /** @type {"contain"|"cover"|"crop"|"pad"|"scale-down"|"squeeze"} */
  const fit = normalizeImageFit(url.searchParams.get("fit"));
  const quality = toPositiveInt(url.searchParams.get("quality"));
  const ttl = getSignedTtlSeconds(url);

  const now = Math.floor(Date.now() / 1000);
  const outerExp = Number(url.searchParams.get("exp"));
  const internalExp = Number.isFinite(outerExp)
    ? Math.min(outerExp, now + 60)
    : now + 60;
  const sourcePath = `/a/${objectKey.replace(/^\/+/, "")}`;
  const source = await buildSignedUrl({
    origin: url.origin,
    pathname: sourcePath,
    params: { exp: String(internalExp) },
    signingKeyB64: env.SIGNING_KEY_B64,
  });

  const image = { fit };
  if (width) image.width = width;
  if (height) image.height = height;
  if (quality) image.quality = quality;

  const range = request.headers.get("Range");
  const canEdgeCache = method === "GET" && !range && ttl > 0;
  const cacheKey = canEdgeCache
    ? new Request(url.toString(), { method: "GET" })
    : null;

  if (cacheKey) {
    const cached = await caches.default.match(cacheKey);
    if (cached) {
      return cached;
    }
  }

  const reqHeaders = new Headers();
  if (range) reqHeaders.set("Range", range);

  const transformed = await fetch(source, {
    method,
    headers: reqHeaders,
    cf: { image },
  });

  const headers = new Headers(transformed.headers);
  applySignedExpiryCaching(headers, url);

  if (method === "HEAD") {
    return new Response(null, { status: transformed.status, headers });
  }

  const response = new Response(transformed.body, {
    status: transformed.status,
    headers,
  });

  if (cacheKey && transformed.status === 200) {
    ctx.waitUntil(caches.default.put(cacheKey, response.clone()));
  }

  return response;
}

async function handleMarkdownTransform({ env, objectKey, method, url, ctx }) {
  if (!env.AI || typeof env.AI.toMarkdown !== "function") {
    return new Response("Missing AI binding", { status: 500 });
  }

  const responseFormat = normalizeMarkdownFormat(
    url.searchParams.get("format"),
  );
  const includePdfMetadata = toBooleanFlag(
    url.searchParams.get("metadata"),
    true,
  );
  const maxPdfBytes =
    toPositiveInt(env.MAX_MARKDOWN_PDF_BYTES) || 25 * 1024 * 1024;
  const ttl = getSignedTtlSeconds(url);
  const canEdgeCache = method === "GET" && ttl > 0;
  const cacheKey = canEdgeCache
    ? new Request(url.toString(), { method: "GET" })
    : null;

  if (cacheKey) {
    const cached = await caches.default.match(cacheKey);
    if (cached) {
      return cached;
    }
  }

  let obj;
  try {
    obj =
      method === "HEAD"
        ? await env.ASSETS_BUCKET.head(objectKey)
        : await env.ASSETS_BUCKET.get(objectKey);
  } catch (_error) {
    return new Response("Upstream error", { status: 502 });
  }

  if (!obj) {
    return new Response("Not found", { status: 404 });
  }

  const contentType =
    obj.httpMetadata?.contentType ||
    guessContentType(objectKey) ||
    "application/octet-stream";
  if (!isPdfSource({ objectKey, contentType })) {
    return new Response("Unsupported media type", { status: 415 });
  }

  const filename = getFilenameFromObjectKey(objectKey);
  const headers = new Headers();
  setMarkdownResponseHeaders(headers, { responseFormat, filename });
  applySignedExpiryCaching(headers, url);

  if (method === "HEAD") {
    return new Response(null, { status: 200, headers });
  }

  if (typeof obj.size === "number" && obj.size > maxPdfBytes) {
    return new Response("PDF too large", { status: 413 });
  }

  const pdfBuffer = await obj.arrayBuffer();
  if (pdfBuffer.byteLength > maxPdfBytes) {
    return new Response("PDF too large", { status: 413 });
  }

  let conversion;
  try {
    conversion = await env.AI.toMarkdown(
      {
        name: filename,
        blob: new Blob([pdfBuffer], { type: "application/pdf" }),
      },
      {
        conversionOptions: {
          pdf: {
            metadata: includePdfMetadata,
          },
        },
      },
    );
  } catch (error) {
    const message = normalizeErrorMessage(error, "Markdown conversion failed");
    return new Response(message, { status: 502 });
  }

  const result = Array.isArray(conversion) ? conversion[0] : conversion;
  if (!result) {
    return new Response("Markdown conversion failed: empty response", {
      status: 502,
    });
  }

  if (result.format === "error") {
    return new Response(
      `Markdown conversion failed: ${normalizeErrorMessage(result.data, "conversion service returned an error")}`,
      { status: 502 },
    );
  }

  if (result.format !== "markdown" || typeof result.data !== "string") {
    return new Response("Markdown conversion failed: invalid response shape", {
      status: 502,
    });
  }

  const response = buildMarkdownResponse({
    headers,
    responseFormat,
    result,
    sourcePath: url.pathname,
  });

  if (cacheKey && response.status === 200) {
    ctx.waitUntil(caches.default.put(cacheKey, response.clone()));
  }

  return response;
}

function handleVideoStream({ env, objectKey, method, url }) {
  const streamBase = (env.CF_STREAM_BASE_URL || "").replace(/\/+$/, "");
  if (!streamBase) {
    return new Response("Missing CF_STREAM_BASE_URL", { status: 500 });
  }

  const streamPath = objectKey.replace(/^\/+/, "");
  if (!streamPath) {
    return new Response("Not found", { status: 404 });
  }

  const passthroughParams = new URLSearchParams(url.searchParams);
  passthroughParams.delete("sig");
  passthroughParams.delete("exp");
  passthroughParams.delete("kid");

  const query = passthroughParams.toString();
  const target = query
    ? `${streamBase}/${streamPath}?${query}`
    : `${streamBase}/${streamPath}`;
  const headers = new Headers({ Location: target });
  applySignedExpiryCaching(headers, url);
  if (method === "HEAD") {
    return new Response(null, { status: 302, headers });
  }
  return new Response(null, { status: 302, headers });
}

// Key versioning: URLs carrying a kid param are verified against the
// SIGNING_KEYS_JSON keyring secret ({"v1": "<b64>", "v2": "<b64>"}); URLs
// without kid fall back to the legacy SIGNING_KEY_B64 secret. Rotation adds
// a new kid to the keyring; deleting a kid revokes its URLs immediately.
let keyringCache = null;
let keyringCacheSource = null;

function resolveSigningKeyB64(env, kid) {
  if (!kid) {
    return env.SIGNING_KEY_B64 || null;
  }

  const source = env.SIGNING_KEYS_JSON || "";
  if (!source) {
    return null;
  }

  if (keyringCacheSource !== source) {
    try {
      keyringCache = JSON.parse(source);
    } catch (_error) {
      keyringCache = null;
    }
    keyringCacheSource = source;
  }

  if (!keyringCache || typeof keyringCache !== "object") {
    return null;
  }

  const key = keyringCache[kid];
  return typeof key === "string" && key ? key : null;
}

async function hmacSha256Hex(message, base64Key) {
  const keyBytes = Uint8Array.from(atob(base64Key), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(message),
  );
  return [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function constantTimeEqualHex(a, b) {
  if (a.length !== b.length) return false;
  let out = 0;
  for (let i = 0; i < a.length; i++) {
    out |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return out === 0;
}

// One byte range ("bytes=a-b", "bytes=a-" or "bytes=-n") as R2's get() takes it: { offset, length }, { offset } or
// { suffix }. null for anything else (several ranges, other units), which is answered with the whole object.
function parseRange(rangeHeader) {
  const match = /^bytes=(\d*)-(\d*)$/i.exec(rangeHeader.trim());
  if (!match || (!match[1] && !match[2])) return null;

  if (!match[1]) {
    const suffix = Number(match[2]);
    return suffix > 0 ? { suffix } : null;
  }

  const offset = Number(match[1]);
  if (!match[2]) return { offset };

  const end = Number(match[2]);
  return end >= offset ? { offset, length: end - offset + 1 } : null;
}

// The bytes a range covers of an object of `size`: { offset, length }, or null when it covers none (416).
function servedRange(range, size) {
  const offset = "suffix" in range ? Math.max(0, size - range.suffix) : range.offset;
  if (offset >= size) return null;
  const length = "length" in range ? Math.min(range.length, size - offset) : size - offset;
  return { offset, length };
}

function toPositiveInt(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return null;
  return Math.floor(n);
}

function toBooleanFlag(value, defaultValue) {
  if (value == null) return defaultValue;

  switch (String(value).trim().toLowerCase()) {
    case "1":
    case "true":
    case "yes":
    case "on":
      return true;
    case "0":
    case "false":
    case "no":
    case "off":
      return false;
    default:
      return defaultValue;
  }
}

function normalizeMarkdownFormat(value) {
  return (value || "").toLowerCase() === "json" ? "json" : "markdown";
}

function isPdfSource({ objectKey, contentType }) {
  return (
    contentType === "application/pdf" ||
    objectKey.toLowerCase().endsWith(".pdf")
  );
}

function getFilenameFromObjectKey(objectKey) {
  const parts = objectKey.split("/").filter(Boolean);
  return parts[parts.length - 1] || "document.pdf";
}

function setMarkdownResponseHeaders(headers, { responseFormat, filename }) {
  if (responseFormat === "json") {
    headers.set("Content-Type", "application/json; charset=utf-8");
    return;
  }

  headers.set("Content-Type", "text/markdown; charset=utf-8");
  headers.set(
    "Content-Disposition",
    `inline; filename="${toMarkdownFilename(filename)}"`,
  );
}

function buildMarkdownResponse({
  headers,
  responseFormat,
  result,
  sourcePath,
}) {
  if (responseFormat === "json") {
    return new Response(
      JSON.stringify({
        format: result.format,
        name: result.name,
        mime_type: result.mimeType || result.mimetype || "application/pdf",
        tokens: normalizeTokenCount(result.tokens),
        markdown: result.data,
        source_path: sourcePath,
      }),
      {
        status: 200,
        headers,
      },
    );
  }

  return new Response(result.data, {
    status: 200,
    headers,
  });
}

function toMarkdownFilename(filename) {
  const clean = getFilenameFromObjectKey(filename);
  return clean.toLowerCase().endsWith(".pdf")
    ? `${clean.slice(0, -4)}.md`
    : `${clean}.md`;
}

function normalizeTokenCount(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function normalizeErrorMessage(error, fallback) {
  if (typeof error === "string" && error.trim()) {
    return error.trim();
  }

  if (error && typeof error.message === "string" && error.message.trim()) {
    return error.message.trim();
  }

  return fallback;
}

/**
 * @returns {"contain"|"cover"|"crop"|"pad"|"scale-down"|"squeeze"}
 */
function normalizeImageFit(value) {
  switch ((value || "cover").toLowerCase()) {
    case "contain":
      return "contain";
    case "cover":
      return "cover";
    case "crop":
      return "crop";
    case "pad":
      return "pad";
    case "scale-down":
      return "scale-down";
    case "squeeze":
      return "squeeze";
    default:
      return "cover";
  }
}

async function buildSignedUrl({ origin, pathname, params, signingKeyB64 }) {
  const entries = Object.entries(params || {}).map(([k, v]) => [k, String(v)]);
  entries.sort((a, b) => a[0].localeCompare(b[0]));

  const canonicalQuery = entries.map(([k, v]) => `${k}=${v}`).join("&");
  const canonical = `${pathname}?${canonicalQuery}`;
  const sig = await hmacSha256Hex(canonical, signingKeyB64);
  const query = canonicalQuery ? `${canonicalQuery}&sig=${sig}` : `sig=${sig}`;

  return `${origin}${pathname}?${query}`;
}

function applySignedExpiryCaching(headers, url) {
  const now = Math.floor(Date.now() / 1000);
  const ttl = getSignedTtlSeconds(url);

  headers.set("Cache-Control", `public, max-age=${ttl}, s-maxage=${ttl}`);
  headers.set("Expires", new Date((now + ttl) * 1000).toUTCString());
}

function getSignedTtlSeconds(url) {
  const exp = Number(url.searchParams.get("exp"));
  const now = Math.floor(Date.now() / 1000);
  return Number.isFinite(exp) ? Math.max(0, exp - now) : 0;
}

function guessContentType(key) {
  const lower = key.toLowerCase();
  if (lower.endsWith(".pdf")) return "application/pdf";
  if (lower.endsWith(".png")) return "image/png";
  if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) return "image/jpeg";
  if (lower.endsWith(".webp")) return "image/webp";
  if (lower.endsWith(".avif")) return "image/avif";
  if (lower.endsWith(".gif")) return "image/gif";
  if (lower.endsWith(".mp4")) return "video/mp4";
  if (lower.endsWith(".mov")) return "video/quicktime";
  return null;
}
