export default {
  // Every answer for a signed asset (/a/) can be read by any page, refusals and failures included: a signed URL is its
  // own authorisation (no cookies are involved), and a web app that keeps a copy to work offline (Cache API,
  // IndexedDB) reads it with a CORS request, so it needs to see a 404 or a 416 as that, not as a network failure.
  //
  // No answer may be read as anything but the type it says it is (nosniff): a browser never runs a file as script or
  // styles because its bytes look like them.
  //
  // The answer is copied before these headers go on: one from the edge cache (caches.default.match) has immutable
  // headers, and setting one would throw.
  //
  // A request to a hostname named in PUBLIC_SITES is a published file's, never a signed asset's (handlePublishedFile).
  // Without PUBLIC_SITES every request is a signed asset's, answered as before published files. A PUBLIC_SITES that
  // can't be read leaves signed requests answered as ever and fails every other request loudly.
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    let site = "";
    let sitesError = null;
    try {
      site = publishedSiteFor(url.hostname, env);
    } catch (error) {
      sitesError = error;
    }

    let answer;
    if (site) {
      answer = await handlePublishedFile({ request, env, ctx, url, site });
    } else if (sitesError && !(getKind(url.pathname) && url.searchParams.has("sig"))) {
      answer = new Response(`Worker error: ${normalizeErrorMessage(sitesError, "Bad PUBLIC_SITES")}`, {
        status: 500,
        headers: { "Cache-Control": "no-store" },
      });
    } else {
      answer = await handleRequest(request, env, ctx);
    }

    const response = new Response(answer.body, answer);
    if (site || url.pathname.startsWith("/a/")) {
      response.headers.set("Access-Control-Allow-Origin", "*");
    }
    response.headers.set("X-Content-Type-Options", "nosniff");
    return response;
  },
};

// ---------------------------------------------------------------------------------------------------------------
// Published files (docs/object-storage.md: Published files)
//
// A project publishes a file at an address on one of its own sites, such as /datasheets/product.pdf on its public
// website. Moopa's published_files library copies the file to the bucket key public/<site>/<address>, and this Worker,
// routed on that site's hostname for the address's prefixes, answers it there without a signature.
//
// PUBLIC_SITES names the sites, as JSON: {"www.example.com": "www"} answers www.example.com/<address> from
// public/www/<address>. A hostname in it only ever answers published files: no signed asset, and no key outside its
// site's public/ prefix, can be reached through it. Unset, nothing is published and every request is answered as it
// was before published files; the signed path below (handleRequest) doesn't read it.
//
// An address can be replaced, so it is kept briefly (five minutes) and checked again (ETag), never kept forever as a
// signed link is. Each file has one address: any percent-encoding is refused, since an address never needs it.
//
// An image is resized with ?width=, from a fixed set of widths only, and only when the stored file is a raster image,
// so an unsigned address can't run up image transformations. The resizer reads the original through ASSETS_ORIGIN
// (this Worker's own hostname: a request to the site's hostname would go to the site's app, not back here), at an
// address that stays the same for each version of the file, and each width is kept at the edge per version.
// ---------------------------------------------------------------------------------------------------------------

const PUBLISHED_PREFIX = "public";
const PUBLISHED_MAX_AGE_SECONDS = 300;
const PUBLISHED_RESIZED_EDGE_SECONDS = 30 * 24 * 60 * 60;
const PUBLISHED_IMAGE_WIDTHS = [160, 320, 480, 640, 800, 1024, 1200, 1600, 2000];
const PUBLISHED_RESIZABLE_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif", "image/avif"];
const PUBLISHED_MAX_KEY_BYTES = 1024; // R2's limit
const SIGNED_NEVER_EXPIRES = "253402300799";

// PUBLIC_SITES parsed once per isolate (and again only when the setting changes).
let publishedSitesSetting;
let publishedSitesParsed;

// The site a hostname publishes (PUBLIC_SITES), or "" when it publishes none. Throws when PUBLIC_SITES is set but
// isn't a JSON object of hostname to site name.
function publishedSiteFor(hostname, env) {
  const sites = publishedSites(env);
  return sites.get(String(hostname).toLowerCase()) || "";
}

function publishedSites(env) {
  const setting = env.PUBLIC_SITES;
  if (setting === publishedSitesSetting && publishedSitesParsed) return publishedSitesParsed;
  const sites = new Map();
  if (setting !== undefined && setting !== null && String(setting).trim() !== "") {
    let parsed;
    try {
      parsed = typeof setting === "string" ? JSON.parse(setting) : setting;
    } catch (_error) {
      throw new Error("PUBLIC_SITES is not JSON");
    }
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("PUBLIC_SITES is not an object of hostname to site name");
    }
    for (const [host, site] of Object.entries(parsed)) {
      if (typeof site !== "string" || !/^[a-z0-9][a-z0-9-]{0,62}$/.test(site)) {
        throw new Error(`PUBLIC_SITES names a bad site for ${host}`);
      }
      sites.set(host.toLowerCase(), site);
    }
  }
  publishedSitesSetting = setting;
  publishedSitesParsed = sites;
  return sites;
}

// The address of a published file without its leading slash, or "" when the path can't be one: no percent-encoding
// (an address never needs it, so a file has one address), segments of letters, digits, dot, dash and underscore,
// none of them empty, "." or "..". The same rule as published_files.cfc's.
function publishedAddress(pathname) {
  if (!pathname.startsWith("/") || /[%\\]/.test(pathname)) return "";
  const segments = pathname.slice(1).split("/");
  for (const segment of segments) {
    if (!/^[A-Za-z0-9._-]{1,200}$/.test(segment) || segment === "." || segment === "..") return "";
  }
  return segments.join("/");
}

async function handlePublishedFile({ request, env, ctx, url, site }) {
  try {
    const method = request.method.toUpperCase();
    if (method !== "GET" && method !== "HEAD") {
      return new Response("Method not allowed", { status: 405 });
    }
    const address = publishedAddress(url.pathname);
    const objectKey = address ? `${PUBLISHED_PREFIX}/${site}/${address}` : "";
    if (!objectKey || objectKey.length > PUBLISHED_MAX_KEY_BYTES) {
      return new Response("Not found", { status: 404 });
    }

    const widthParam = url.searchParams.get("width");
    if (widthParam === null) {
      return await handlePublishedRaw({ request, env, method, objectKey });
    }
    const width = Number(widthParam);
    if (!PUBLISHED_IMAGE_WIDTHS.includes(width)) {
      return new Response(`Width must be one of ${PUBLISHED_IMAGE_WIDTHS.join(", ")}`, { status: 400 });
    }
    return await handlePublishedImage({ request, env, ctx, url, method, objectKey, address, width });
  } catch (error) {
    const message = normalizeErrorMessage(error, "Unhandled worker error");
    return new Response(`Worker error: ${message}`, { status: 500, headers: { "Cache-Control": "no-store" } });
  }
}

// A published file as stored. If-None-Match is answered 304 before any range. A range is served only when its
// If-Range, if any, names the current version; otherwise the whole file is the answer, so a resumed download never
// splices two versions of a replaced file. Only media and PDFs open in the browser; anything else is a download typed
// application/octet-stream, so it can't be used as a script or style on the site either.
async function handlePublishedRaw({ request, env, method, objectKey }) {
  // A malformed If-None-Match can name no version: ignored, as RFC 9110 allows, rather than handed to R2.
  const ifNoneMatchHeader = request.headers.get("If-None-Match");
  const ifNoneMatch = ifNoneMatchHeader && isEtagList(ifNoneMatchHeader) ? ifNoneMatchHeader : null;

  if (method === "HEAD") {
    const head = await publishedHead(env, objectKey);
    if (head instanceof Response) return head;
    if (ifNoneMatch && etagListMatches(ifNoneMatch, head.etag)) return publishedNotModified(head.etag);
    const headers = publishedFileHeaders(head, objectKey);
    headers.set("Content-Length", String(head.size));
    return new Response(null, { status: 200, headers });
  }

  const rangeHeader = request.headers.get("Range");
  const ifRange = request.headers.get("If-Range");
  let range = rangeHeader ? parseRange(rangeHeader) : null;
  let rangeVersion = null;

  // With a range, the current version decides first whether the browser's copy is current and whether the range is
  // for this version, before R2 is asked for (or refuses) the bytes.
  if (range) {
    const head = await publishedHead(env, objectKey);
    if (head instanceof Response) return head;
    if (ifNoneMatch && etagListMatches(ifNoneMatch, head.etag)) return publishedNotModified(head.etag);
    if (ifRange && ifRange.trim() !== `"${head.etag}"`) {
      range = null;
    } else if (!servedRange(range, head.size)) {
      return new Response(null, { status: 416, headers: { "Content-Range": `bytes */${head.size}` } });
    } else {
      rangeVersion = head.etag;
    }
  }

  const options = range ? { range } : ifNoneMatch ? { onlyIf: new Headers({ "If-None-Match": ifNoneMatch }) } : {};
  const obj = await publishedGet(env, objectKey, options);
  if (obj instanceof Response) return obj;

  // R2 answers an object without a body when onlyIf failed: the browser's copy is this one.
  if (!("body" in obj) || !obj.body) return publishedNotModified(obj.etag);

  const headers = publishedFileHeaders(obj, objectKey);
  // Replaced between the look and the read, the range was for another version: the whole file is the answer.
  if (range && obj.etag !== rangeVersion) {
    await obj.body.cancel();
    const whole = await publishedGet(env, objectKey, {});
    if (whole instanceof Response) return whole;
    const wholeHeaders = publishedFileHeaders(whole, objectKey);
    wholeHeaders.set("Content-Length", String(whole.size));
    return new Response(whole.body, { status: 200, headers: wholeHeaders });
  }
  if (!range) {
    headers.set("Content-Length", String(obj.size));
    return new Response(obj.body, { status: 200, headers });
  }
  const served = servedRange(range, obj.size);
  headers.set("Content-Range", `bytes ${served.offset}-${served.offset + served.length - 1}/${obj.size}`);
  headers.set("Content-Length", String(served.length));
  return new Response(obj.body, { status: 206, headers });
}

// R2's head() or get() for a published file, or the answer to give instead: 404 when it isn't there, 502 when R2
// fails.
async function publishedHead(env, objectKey) {
  try {
    return (await env.ASSETS_BUCKET.head(objectKey)) || new Response("Not found", { status: 404 });
  } catch (_error) {
    return new Response("Upstream error", { status: 502, headers: { "Cache-Control": "no-store" } });
  }
}

async function publishedGet(env, objectKey, options) {
  try {
    return (await env.ASSETS_BUCKET.get(objectKey, options)) || new Response("Not found", { status: 404 });
  } catch (_error) {
    return new Response("Upstream error", { status: 502, headers: { "Cache-Control": "no-store" } });
  }
}

function publishedFileHeaders(obj, objectKey) {
  const headers = new Headers();
  // Only the bare type that was checked goes out: parameters or a second type after it can't change what the
  // browser does with the file.
  const contentType = String(obj.httpMetadata?.contentType || guessContentType(objectKey) || "").split(";")[0].trim().toLowerCase();
  if (opensInline(contentType)) {
    headers.set("Content-Type", contentType);
  } else {
    headers.set("Content-Type", "application/octet-stream");
    headers.set("Content-Disposition", `attachment; filename="${downloadFilename(objectKey)}"`);
  }
  headers.set("ETag", `"${obj.etag}"`);
  headers.set("Accept-Ranges", "bytes");
  applyPublishedCaching(headers);
  return headers;
}

function publishedNotModified(etag) {
  const headers = new Headers({ ETag: `"${etag}"` });
  applyPublishedCaching(headers);
  return new Response(null, { status: 304, headers });
}

// A published image at one of the fixed widths, only when the stored file is a raster image. Looked up first, so an
// address with nothing published never reaches the resizer; kept at the edge under the address, width and version.
async function handlePublishedImage({ request, env, ctx, url, method, objectKey, address, width }) {
  const origin = assetsOrigin(env);
  if (!env.SIGNING_KEY_B64) {
    return new Response("Missing SIGNING_KEY_B64", { status: 500, headers: { "Cache-Control": "no-store" } });
  }

  const head = await publishedHead(env, objectKey);
  if (head instanceof Response) return head;
  const storedType = String(head.httpMetadata?.contentType || guessContentType(objectKey) || "").split(";")[0].trim().toLowerCase();
  if (!PUBLISHED_RESIZABLE_TYPES.includes(storedType)) {
    return new Response("Only images are resized", { status: 415 });
  }

  const version = `${head.etag}-w${width}`;
  const ifNoneMatch = request.headers.get("If-None-Match");
  if (ifNoneMatch && isEtagList(ifNoneMatch) && etagListMatches(ifNoneMatch, version)) {
    return publishedNotModified(version);
  }

  const cacheKey = new Request(`${url.origin}/${address}?width=${width}&v=${encodeURIComponent(head.etag)}`, { method: "GET" });
  const cached = await caches.default.match(cacheKey);
  if (cached) {
    const headers = new Headers(cached.headers);
    applyPublishedCaching(headers);
    if (method === "HEAD") {
      // Not awaited: a cached body may be one branch of a tee, whose cancel settles only with the other's.
      cached.body?.cancel().catch(() => {});
      return new Response(null, { status: 200, headers });
    }
    return new Response(cached.body, { status: 200, headers });
  }

  // The same source address for every request for this version of the file, so it is one image to the resizer.
  const source = await buildSignedUrl({
    origin,
    pathname: `/a/${objectKey}`,
    params: { exp: SIGNED_NEVER_EXPIRES, v: head.etag },
    signingKeyB64: env.SIGNING_KEY_B64,
  });
  let transformed;
  try {
    transformed = await fetch(source, { cf: { image: { width, fit: "scale-down" } } });
  } catch (_error) {
    return new Response("Resize failed", { status: 502, headers: { "Cache-Control": "no-store" } });
  }
  const resizedType = String(transformed.headers.get("Content-Type") || "").split(";")[0].trim().toLowerCase();
  if (transformed.status !== 200 || !PUBLISHED_RESIZABLE_TYPES.includes(resizedType)) {
    await transformed.body?.cancel();
    return new Response("Resize failed", { status: 502, headers: { "Cache-Control": "no-store" } });
  }

  const headers = new Headers({ "Content-Type": resizedType, ETag: `"${version}"` });
  const length = transformed.headers.get("Content-Length");
  if (length) headers.set("Content-Length", length);
  const answerHeaders = new Headers(headers);
  applyPublishedCaching(answerHeaders);

  // Kept at the edge only when it was resized (Cf-Resized: a zone without image transformations answers the original)
  // and the file is still the version looked up, so a replacement made meanwhile is never kept under the old version.
  const current = transformed.headers.has("Cf-Resized") ? await env.ASSETS_BUCKET.head(objectKey).catch(() => null) : null;
  if (!current || current.etag !== head.etag) {
    if (method === "HEAD") {
      await transformed.body?.cancel();
      return new Response(null, { status: 200, headers: answerHeaders });
    }
    return new Response(transformed.body, { status: 200, headers: answerHeaders });
  }

  // Long at the edge (the key changes with the file), five minutes in a browser.
  headers.set("Cache-Control", `public, max-age=${PUBLISHED_MAX_AGE_SECONDS}, s-maxage=${PUBLISHED_RESIZED_EDGE_SECONDS}`);
  const response = new Response(transformed.body, { status: 200, headers });
  if (method === "HEAD") {
    ctx.waitUntil(caches.default.put(cacheKey, response));
    return new Response(null, { status: 200, headers: answerHeaders });
  }
  ctx.waitUntil(caches.default.put(cacheKey, response.clone()));
  return new Response(response.body, { status: 200, headers: answerHeaders });
}

// ASSETS_ORIGIN as https://host (no path, query or fragment), and not a published site's hostname, whose requests
// would come back to the site's app. Throws, failing loudly, when it isn't.
function assetsOrigin(env) {
  let parsed;
  try {
    parsed = new URL(String(env.ASSETS_ORIGIN || "").trim());
  } catch (_error) {
    throw new Error("Missing ASSETS_ORIGIN");
  }
  if (!/^https?:$/.test(parsed.protocol) || (parsed.pathname !== "/" && parsed.pathname !== "") || parsed.search || parsed.hash) {
    throw new Error("ASSETS_ORIGIN must be http(s)://<the asset hostname>, with no path");
  }
  if (publishedSites(env).has(parsed.hostname.toLowerCase())) {
    throw new Error("ASSETS_ORIGIN must be the asset hostname, not a published site's");
  }
  return parsed.origin;
}

// Whether a header is * or a list of entity tags (RFC 9110), which is all R2 or etagListMatches should be given.
function isEtagList(header) {
  return /^\s*(\*|(W\/)?"[^"]*"(\s*,\s*(W\/)?"[^"]*")*)\s*$/.test(String(header));
}

// Whether an If-None-Match list (or *) names this etag (bare, without quotes). Weak comparison, as RFC 9110 asks.
function etagListMatches(header, etag) {
  const value = String(header).trim();
  if (value === "*") return true;
  return value.split(",").some((tag) => tag.trim().replace(/^W\//, "") === `"${etag}"`);
}

function applyPublishedCaching(headers) {
  headers.set("Cache-Control", `public, max-age=${PUBLISHED_MAX_AGE_SECONDS}`);
  headers.delete("Expires");
}

async function handleRequest(request, env, ctx) {
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

    if (kind === "p") {
      return handlePdfPage({ request, env, objectKey, method, url, ctx });
    }

    return handleVideoStream({ env, objectKey, method, url });
  } catch (error) {
    const message = normalizeErrorMessage(error, "Unhandled worker error");
    return new Response(`Worker error: ${message}`, { status: 500 });
  }
}

function getKind(pathname) {
  if (pathname.startsWith("/a/")) return "a";
  if (pathname.startsWith("/i/")) return "i";
  if (pathname.startsWith("/m/")) return "m";
  if (pathname.startsWith("/p/")) return "p";
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
  // Only media and PDFs open in the browser. Anything else (a page, an SVG, a script, whatever type an upload was
  // stored with) is a download, so a signed link to it can never show a page on this hostname.
  if (!opensInline(contentType)) {
    headers.set("Content-Disposition", `attachment; filename="${downloadFilename(objectKey)}"`);
  }
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

  applySignedExpiryCaching(headers, url);

  if (method === "HEAD") {
    return new Response(null, { status, headers });
  }

  return new Response(obj.body, { status, headers });
}

function handleImageTransform({ request, env, objectKey, method, url, ctx }) {
  return transformImage({
    request,
    env,
    method,
    url,
    ctx,
    sourcePath: `/a/${objectKey.replace(/^\/+/, "")}`,
    sourceParams: {},
  });
}

// Answers the image at sourcePath (an address of this Worker's own, signed here for a minute) resized as the
// request's width, height, fit and quality ask, through Cloudflare's image resizing.
async function transformImage({
  request,
  env,
  method,
  url,
  ctx,
  sourcePath,
  sourceParams,
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
  const source = await buildSignedUrl({
    origin: url.origin,
    pathname: sourcePath,
    params: { ...sourceParams, exp: String(internalExp) },
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

// The widths a PDF page is rendered at for resizing: a resized page (/p/ with width or height) is cut from the
// smallest of these that has the pixels for it.
const PDF_PAGE_RENDER_WIDTHS = [400, 800, 1200, 1600, 2000];

// /p/<key>?page=1: one page of a PDF as an image (page counts from 1, and is 1 when not given).
//   render=<width>             the page as a PNG that many pixels wide (16 to 4000), straight from the PDF service
//                              (the PDF_PAGES binding; docs/object-storage.md says what that service answers).
//   width, height, fit, quality  the page resized as /i/ resizes an image, from this Worker's own rendering of it.
//   neither                    the page 1600 pixels wide, through image resizing (so in the format the browser takes).
async function handlePdfPage({ request, env, objectKey, method, url, ctx }) {
  if (!env.PDF_PAGES || typeof env.PDF_PAGES.fetch !== "function") {
    return new Response("Missing PDF_PAGES binding", { status: 500 });
  }

  const pageParam = url.searchParams.get("page");
  const page = pageParam == null ? 1 : toPositiveInt(pageParam);
  if (!page) {
    return new Response("Bad page", { status: 400 });
  }

  const renderParam = url.searchParams.get("render");
  if (renderParam != null) {
    const renderWidth = toPositiveInt(renderParam);
    if (!renderWidth || renderWidth < 16 || renderWidth > 4000) {
      return new Response("Bad render", { status: 400 });
    }
    return handlePdfPageRender({ env, objectKey, method, url, ctx, page, renderWidth });
  }

  // A page's shape isn't known until it is rendered, and a wide page cut to a tall thumbnail needs more pixels across
  // than the thumbnail has: half as many again as the longer side asked for covers pages up to 3:2.
  const longest = Math.max(
    toPositiveInt(url.searchParams.get("width")) || 0,
    toPositiveInt(url.searchParams.get("height")) || 0,
  );
  const wanted = longest ? Math.ceil(longest * 1.5) : 1600;
  const renderWidth =
    PDF_PAGE_RENDER_WIDTHS.find((w) => w >= wanted) ||
    PDF_PAGE_RENDER_WIDTHS[PDF_PAGE_RENDER_WIDTHS.length - 1];

  return transformImage({
    request,
    env,
    method,
    url,
    ctx,
    sourcePath: `/p/${objectKey.replace(/^\/+/, "")}`,
    sourceParams: { page: String(page), render: String(renderWidth) },
  });
}

// The page from the PDF service. This Worker does not read the PDF: it checks the file is one, then gives the
// service an address of its own to read it from (/a/, signed here for five minutes), so a PDF of any size the
// service takes can be rendered.
async function handlePdfPageRender({ env, objectKey, method, url, ctx, page, renderWidth }) {
  const maxPdfBytes = toPositiveInt(env.MAX_PDF_PAGE_BYTES);
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
    obj = await env.ASSETS_BUCKET.head(objectKey);
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

  if (maxPdfBytes && typeof obj.size === "number" && obj.size > maxPdfBytes) {
    return new Response("PDF too large", { status: 413 });
  }

  const headers = new Headers({ "Content-Type": "image/png" });
  applySignedExpiryCaching(headers, url);

  if (method === "HEAD") {
    return new Response(null, { status: 200, headers });
  }

  const source = await buildSignedUrl({
    origin: url.origin,
    pathname: `/a/${objectKey.replace(/^\/+/, "")}`,
    params: { exp: String(Math.floor(Date.now() / 1000) + 300) },
    signingKeyB64: env.SIGNING_KEY_B64,
  });

  let rendered;
  try {
    rendered = await env.PDF_PAGES.fetch("https://pdf-pages/page", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ source, page, width: renderWidth }),
    });
  } catch (error) {
    return new Response(
      `PDF rendering failed: ${normalizeErrorMessage(error, "the PDF service did not answer")}`,
      { status: 502 },
    );
  }

  // The PDF service's own refusals are the asker's to see: no such page (404), too large (413), not a PDF it can
  // open (422).
  if (rendered.status === 404 || rendered.status === 413 || rendered.status === 422) {
    return new Response(await rendered.text(), { status: rendered.status });
  }
  if (rendered.status !== 200) {
    return new Response("PDF rendering failed", { status: 502 });
  }

  const response = new Response(rendered.body, { status: 200, headers });

  if (cacheKey) {
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

// Whether a raw asset of this type may open in the browser: images (but not SVG, a document that can run script),
// video, audio and PDF.
function opensInline(contentType) {
  const type = String(contentType).split(";")[0].trim().toLowerCase();
  if (type === "image/svg+xml") return false;
  return /^(image|video|audio)\/[a-z0-9.+-]+$/.test(type) || type === "application/pdf";
}

// The last segment of an object key, kept to characters that are safe inside a quoted header value.
function downloadFilename(objectKey) {
  const name = String(objectKey).split("/").pop() || "download";
  return name.replace(/[^A-Za-z0-9._-]/g, "_");
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
