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

      const canonical = buildCanonical(url, decodedPathname);
      const expectedSig = await hmacSha256Hex(canonical, env.SIGNING_KEY_B64);
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
          return handleImageTransform({ request, env, objectKey, method, url, ctx });
        }

        if (kind === "m") {
          return handleMarkdownTransform({ env, objectKey, method, url, ctx });
        }
    
        return handleVideoStream({ env, objectKey, method, url });
      } catch (error) {
        const message = normalizeErrorMessage(error, "Unhandled worker error");
        return new Response(`Worker error: ${message}`, { status: 500 });
      }
    }
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
  const rawQuery = url.search.startsWith("?") ? url.search.slice(1) : url.search;
  
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
    const rangeHeader = request.headers.get("Range");
    const range = rangeHeader ? parseRange(rangeHeader) : null;
  
    let obj;
    try {
      obj = range
        ? await env.ASSETS_BUCKET.get(objectKey, { range })
        : await env.ASSETS_BUCKET.get(objectKey);
    } catch (_error) {
      return new Response("Upstream error", { status: 502 });
    }
  
    if (!obj) {
      return new Response("Not found", { status: 404 });
    }
  
    const headers = new Headers();
    const contentType =
      obj.httpMetadata?.contentType || guessContentType(objectKey) || "application/octet-stream";
    headers.set("Content-Type", contentType);
    if (obj.etag) headers.set("ETag", obj.etag);
  
    let status = 200;
    if (obj.range) {
      status = 206;
      headers.set("Accept-Ranges", "bytes");
      headers.set("Content-Range", `bytes ${obj.range.offset}-${obj.range.end}/${obj.size}`);
      headers.set("Content-Length", String(obj.range.length));
    } else if (typeof obj.size === "number") {
      headers.set("Content-Length", String(obj.size));
      headers.set("Accept-Ranges", "bytes");
    }
  
    applySignedExpiryCaching(headers, url);
  
    if (method === "HEAD") {
      return new Response(null, { status, headers });
    }
  
    return new Response(obj.body, { status, headers });
  }
  
  async function handleImageTransform({ request, env, objectKey, method, url, ctx }) {
    const width = toPositiveInt(url.searchParams.get("width"));
    const height = toPositiveInt(url.searchParams.get("height"));
    /** @type {"contain"|"cover"|"crop"|"pad"|"scale-down"|"squeeze"} */
    const fit = normalizeImageFit(url.searchParams.get("fit"));
    const quality = toPositiveInt(url.searchParams.get("quality"));
    const ttl = getSignedTtlSeconds(url);
  
    const now = Math.floor(Date.now() / 1000);
    const outerExp = Number(url.searchParams.get("exp"));
    const internalExp = Number.isFinite(outerExp) ? Math.min(outerExp, now + 60) : now + 60;
    const sourcePath = `/a/${objectKey.replace(/^\/+/, "")}`;
    const source = await buildSignedUrl({
      origin: url.origin,
      pathname: sourcePath,
      params: { exp: String(internalExp) },
      signingKeyB64: env.SIGNING_KEY_B64
    });
  
    const image = { fit };
    if (width) image.width = width;
    if (height) image.height = height;
    if (quality) image.quality = quality;
  
    const range = request.headers.get("Range");
    const canEdgeCache = method === "GET" && !range && ttl > 0;
    const cacheKey = canEdgeCache ? new Request(url.toString(), { method: "GET" }) : null;
  
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
      cf: { image }
    });
  
    const headers = new Headers(transformed.headers);
    applySignedExpiryCaching(headers, url);
  
    if (method === "HEAD") {
      return new Response(null, { status: transformed.status, headers });
    }
  
    const response = new Response(transformed.body, {
      status: transformed.status,
      headers
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

    const responseFormat = normalizeMarkdownFormat(url.searchParams.get("format"));
    const includePdfMetadata = toBooleanFlag(url.searchParams.get("metadata"), true);
    const maxPdfBytes = toPositiveInt(env.MAX_MARKDOWN_PDF_BYTES) || 25 * 1024 * 1024;
    const ttl = getSignedTtlSeconds(url);
    const canEdgeCache = method === "GET" && ttl > 0;
    const cacheKey = canEdgeCache ? new Request(url.toString(), { method: "GET" }) : null;

    if (cacheKey) {
      const cached = await caches.default.match(cacheKey);
      if (cached) {
        return cached;
      }
    }

    let obj;
    try {
      obj = method === "HEAD"
        ? await env.ASSETS_BUCKET.head(objectKey)
        : await env.ASSETS_BUCKET.get(objectKey);
    } catch (_error) {
      return new Response("Upstream error", { status: 502 });
    }

    if (!obj) {
      return new Response("Not found", { status: 404 });
    }

    const contentType =
      obj.httpMetadata?.contentType || guessContentType(objectKey) || "application/octet-stream";
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
          blob: new Blob([pdfBuffer], { type: "application/pdf" })
        },
        {
          conversionOptions: {
            pdf: {
              metadata: includePdfMetadata
            }
          }
        }
      );
    } catch (error) {
      const message = normalizeErrorMessage(error, "Markdown conversion failed");
      return new Response(message, { status: 502 });
    }

    const result = Array.isArray(conversion) ? conversion[0] : conversion;
    if (!result) {
      return new Response("Markdown conversion failed: empty response", { status: 502 });
    }

    if (result.format === "error") {
      return new Response(
        `Markdown conversion failed: ${normalizeErrorMessage(result.data, "conversion service returned an error")}`,
        { status: 502 }
      );
    }

    if (result.format !== "markdown" || typeof result.data !== "string") {
      return new Response("Markdown conversion failed: invalid response shape", { status: 502 });
    }

    const response = buildMarkdownResponse({
      headers,
      responseFormat,
      result,
      sourcePath: url.pathname
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
  
    const query = passthroughParams.toString();
    const target = query ? `${streamBase}/${streamPath}?${query}` : `${streamBase}/${streamPath}`;
    const headers = new Headers({ Location: target });
    applySignedExpiryCaching(headers, url);
    if (method === "HEAD") {
      return new Response(null, { status: 302, headers });
    }
    return new Response(null, { status: 302, headers });
  }
  
  async function hmacSha256Hex(message, base64Key) {
    const keyBytes = Uint8Array.from(atob(base64Key), c => c.charCodeAt(0));
    const key = await crypto.subtle.importKey(
      "raw",
      keyBytes,
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["sign"]
    );
    const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
    return [...new Uint8Array(sig)].map(b => b.toString(16).padStart(2, "0")).join("");
  }
  
  function constantTimeEqualHex(a, b) {
    if (a.length !== b.length) return false;
    let out = 0;
    for (let i = 0; i < a.length; i++) {
      out |= a.charCodeAt(i) ^ b.charCodeAt(i);
    }
    return out === 0;
  }
  
  function parseRange(rangeHeader) {
    const match = /^bytes=(\d*)-(\d*)$/i.exec(rangeHeader.trim());
    if (!match) return null;
  
    const startStr = match[1];
    const endStr = match[2];
  
    if (startStr && endStr) {
      const offset = Number(startStr);
      const end = Number(endStr);
      if (!Number.isFinite(offset) || !Number.isFinite(end) || end < offset) return null;
      return { offset, end };
    }
  
    if (startStr && !endStr) {
      const offset = Number(startStr);
      if (!Number.isFinite(offset)) return null;
      return { offset };
    }
  
    return null;
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
    return contentType === "application/pdf" || objectKey.toLowerCase().endsWith(".pdf");
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
    headers.set("Content-Disposition", `inline; filename="${toMarkdownFilename(filename)}"`);
  }

  function buildMarkdownResponse({ headers, responseFormat, result, sourcePath }) {
    if (responseFormat === "json") {
      return new Response(JSON.stringify({
        format: result.format,
        name: result.name,
        mime_type: result.mimeType || result.mimetype || "application/pdf",
        tokens: normalizeTokenCount(result.tokens),
        markdown: result.data,
        source_path: sourcePath
      }), {
        status: 200,
        headers
      });
    }

    return new Response(result.data, {
      status: 200,
      headers
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
  
