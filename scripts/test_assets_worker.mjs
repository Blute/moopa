// Regression harness for the signed assets Worker (config/init/cloudflare-signed-assets-worker.js): what a raw
// asset (/a/) answers, by the type it was stored with, what a page of a PDF (/p/) asks of the PDF service, and how
// published files (PUBLIC_SITES) answer, and that without that setting nothing changes. Media and PDFs open in the browser; anything else, an SVG
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
      return {
        body: object.body,
        size: object.body.length,
        etag: "e",
        httpMetadata: { contentType: object.contentType },
        async arrayBuffer() { return object.body.buffer.slice(object.body.byteOffset, object.body.byteOffset + object.body.length); },
      };
    },
    async head(key) {
      const object = objects.get(key);
      return object ? { size: object.body.length, httpMetadata: { contentType: object.contentType } } : null;
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

// A page of a PDF as an image (/p/). The PDF service (the PDF_PAGES binding) is a stand-in that records what it
// was asked for; nothing is in the edge cache.
globalThis.caches = { default: { async match() {}, async put() {} } };
const rendered = [];
const pdfPages = {
  async fetch(url, init) {
    const asked = JSON.parse(init.body);
    rendered.push({ path: new URL(url).pathname, method: init.method, ...asked });
    if (asked.page === 9) return new Response("No such page", { status: 404 });
    return new Response("PNG", { status: 200, headers: { "Content-Type": "image/png" } });
  },
};
const pdfEnv = { ...env, PDF_PAGES: pdfPages };
// A signed /p/ URL with options, as the SQL signer makes it: the query sorted by name, signed without sig.
async function signedPageUrl(key, options) {
  const params = { ...options, exp: String(Math.floor(Date.now() / 1000) + 600) };
  const query = Object.keys(params).sort().map((name) => `${name}=${params[name]}`).join("&");
  const path = `/p/${key}`;
  return `https://assets.example.com${encodeURI(path)}?${query}&sig=${await hmacHex(`${path}?${query}`)}`;
}
objects.set("docs/contract.pdf", { body: Buffer.from("%PDF-1.7 a contract"), contentType: "application/pdf" });
objects.set("photos/house.jpg", { body: Buffer.from("a photo"), contentType: "image/jpeg" });

const noBinding = await worker.fetch(new Request(await signedPageUrl("docs/contract.pdf", { render: "400" })), env, { waitUntil() {} });
check("/p/ without the PDF_PAGES binding says so", await noBinding.text(), "Missing PDF_PAGES binding");
check("...as a failure", noBinding.status, 500);

const page = await worker.fetch(new Request(await signedPageUrl("docs/contract.pdf", { page: "2", render: "400" })), pdfEnv, { waitUntil() {} });
check("/p/ with render answers the page", page.status, 200);
check("...as a PNG", page.headers.get("Content-Type"), "image/png");
check("...and is nosniff", page.headers.get("X-Content-Type-Options"), "nosniff");
check("...having asked the PDF service for the page at that width", JSON.stringify({ path: rendered.at(-1).path, method: rendered.at(-1).method, page: rendered.at(-1).page, width: rendered.at(-1).width }), JSON.stringify({ path: "/page", method: "POST", page: 2, width: 400 }));
// The address the service is given to read the PDF from is this Worker's own, signed: asked for, it answers the file.
const source = await worker.fetch(new Request(rendered.at(-1).source), env, { waitUntil() {} });
check("...and given it an address that answers the PDF", `${source.status} ${await source.text()}`, "200 %PDF-1.7 a contract");
check("...an address of the raw asset", new URL(rendered.at(-1).source).pathname, "/a/docs/contract.pdf");

const firstPage = await worker.fetch(new Request(await signedPageUrl("docs/contract.pdf", { render: "400" })), pdfEnv, { waitUntil() {} });
check("/p/ without a page is page 1", firstPage.status === 200 && rendered.at(-1).page, 1);

const noSuchPage = await worker.fetch(new Request(await signedPageUrl("docs/contract.pdf", { page: "9", render: "400" })), pdfEnv, { waitUntil() {} });
check("a page the PDF doesn't have is not found", noSuchPage.status, 404);

const notPdf = await worker.fetch(new Request(await signedPageUrl("photos/house.jpg", { render: "400" })), pdfEnv, { waitUntil() {} });
check("/p/ of a file that isn't a PDF is refused", notPdf.status, 415);

const missing = await worker.fetch(new Request(await signedPageUrl("docs/gone.pdf", { render: "400" })), pdfEnv, { waitUntil() {} });
check("/p/ of a file the bucket doesn't hold is not found", missing.status, 404);

for (const [label, options] of [["a render too wide", { render: "5000" }], ["a page that isn't a number", { page: "x", render: "400" }]]) {
  const refused = await worker.fetch(new Request(await signedPageUrl("docs/contract.pdf", options)), pdfEnv, { waitUntil() {} });
  check(`${label} is refused`, refused.status, 400);
}

const tooLarge = await worker.fetch(new Request(await signedPageUrl("docs/contract.pdf", { render: "400" })), { ...pdfEnv, MAX_PDF_PAGE_BYTES: "10" }, { waitUntil() {} });
check("a PDF over the size limit is refused", tooLarge.status, 413);

// A resized page: image resizing is asked for this Worker's own rendering of the page, at an address signed here.
// The resizing fetch is a stand-in that follows that address back into the Worker, as Cloudflare does.
const realFetch = globalThis.fetch;
const resizes = [];
globalThis.fetch = async (source, init) => {
  resizes.push({ source: new URL(source), image: init.cf.image });
  return worker.fetch(new Request(source), pdfEnv, { waitUntil() {} });
};
const thumb = await worker.fetch(new Request(await signedPageUrl("docs/contract.pdf", { fit: "cover", height: "120", page: "3", width: "120" })), pdfEnv, { waitUntil() {} });
globalThis.fetch = realFetch;
check("a resized /p/ answers", thumb.status, 200);
check("...resized as asked", JSON.stringify(resizes[0].image), JSON.stringify({ fit: "cover", width: 120, height: 120 }));
check("...from its own rendering of that page", `${resizes[0].source.pathname} page=${resizes[0].source.searchParams.get("page")}`, "/p/docs/contract.pdf page=3");
check("...wide enough to cut the size from", resizes[0].source.searchParams.get("render"), "400");
check("...which the PDF service rendered", JSON.stringify({ page: rendered.at(-1).page, width: rendered.at(-1).width }), JSON.stringify({ page: 3, width: 400 }));

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

// Published files (PUBLIC_SITES). The bucket stand-in answers R2's onlyIf (etagDoesNotMatch) as R2 does: the object
// without a body when the browser's copy is this one.
const publishedBucket = {
  async get(key, options = {}) {
    const object = objects.get(key);
    if (!object) return null;
    const etag = object.etag || "e1";
    const meta = { size: object.body.length, etag, httpMetadata: { contentType: object.contentType } };
    if (options.onlyIf?.etagDoesNotMatch === etag) return meta;
    return { ...meta, body: object.body };
  },
  async head(key) { return env.ASSETS_BUCKET.head(key); },
};
const publicEnv = { ...env, ASSETS_BUCKET: publishedBucket, PUBLIC_SITES: JSON.stringify({ "www.example.com": "www" }), ASSETS_ORIGIN: "https://assets.example.com" };
objects.set("public/www/datasheets/product.pdf", { body: Buffer.from("%PDF-1.7 a datasheet"), contentType: "application/pdf", etag: "d1" });
objects.set("public/www/images/product/front.webp", { body: Buffer.from("webp"), contentType: "image/webp" });
objects.set("public/www/pages/page.html", { body: Buffer.from("<script>alert(1)</script>"), contentType: "text/html" });
objects.set("public/other/datasheets/secret.pdf", { body: Buffer.from("%PDF other site"), contentType: "application/pdf" });
objects.set("moo_file/2026-11/abc/private.pdf", { body: Buffer.from("%PDF private"), contentType: "application/pdf" });

const pub = (path, init) => worker.fetch(new Request(`https://www.example.com${path}`, init), publicEnv, { waitUntil() {} });

const datasheet = await pub("/datasheets/product.pdf");
check("a published file answers unsigned on its site", `${datasheet.status} ${await datasheet.text()}`, "200 %PDF-1.7 a datasheet");
check("...as the type it was stored with", datasheet.headers.get("Content-Type"), "application/pdf");
check("...opening in the browser", datasheet.headers.get("Content-Disposition"), null);
check("...kept briefly, since it can be replaced", datasheet.headers.get("Cache-Control"), "public, max-age=300, s-maxage=300");
check("...with an ETag to check it again", datasheet.headers.get("ETag"), '"d1"');
check("...readable by any page", datasheet.headers.get("Access-Control-Allow-Origin"), "*");
check("...and nosniff", datasheet.headers.get("X-Content-Type-Options"), "nosniff");

const notModified = await pub("/datasheets/product.pdf", { headers: { "If-None-Match": '"d1"' } });
check("a browser holding the current copy is told so", notModified.status, 304);
const changed = await pub("/datasheets/product.pdf", { headers: { "If-None-Match": '"old"' } });
check("...and one holding an older copy gets the file", changed.status, 200);

const headAnswer = await pub("/datasheets/product.pdf", { method: "HEAD" });
check("HEAD of a published file answers without a body", `${headAnswer.status} ${(await headAnswer.text()).length}`, "200 0");
const post = await pub("/datasheets/product.pdf", { method: "POST" });
check("anything but GET or HEAD is refused", post.status, 405);

const publishedPage = await pub("/pages/page.html");
check("a published page is a download, never a page on the site", publishedPage.headers.get("Content-Disposition"), 'attachment; filename="page.html"');

for (const [label, path] of [
  ["an address the site hasn't published", "/datasheets/missing.pdf"],
  ["a signed asset's path, unsigned", "/a/moo_file/2026-11/abc/private.pdf"],
  ["another site's file, by climbing out", "/datasheets/..%2F..%2Fother/datasheets/secret.pdf"],
  ["a path with ..", "/datasheets/../../other/datasheets/secret.pdf"],
  ["an encoded slash", "/datasheets%2Fproduct.pdf"],
  ["an empty segment", "/datasheets//product.pdf"],
  ["a directory", "/datasheets/"],
]) {
  const refused = await pub(path);
  check(`${label} is not found`, refused.status, 404);
}

const signedOnSite = await worker.fetch(new Request((await signedUrl("moo_file/2026-11/abc/private.pdf")).replace("assets.example.com", "www.example.com")), publicEnv, { waitUntil() {} });
check("a signed link on a published site's hostname reaches nothing private", signedOnSite.status, 404);
const signedOnAssets = await worker.fetch(new Request(await signedUrl("moo_file/2026-11/abc/private.pdf")), publicEnv, { waitUntil() {} });
check("...while it still works on the assets hostname", signedOnAssets.status, 200);
const unsignedPublicKey = await worker.fetch(new Request("https://assets.example.com/a/public/www/datasheets/product.pdf"), publicEnv, { waitUntil() {} });
check("the assets hostname still wants a signature, for published keys too", unsignedPublicKey.status, 401);

const withoutSetting = await worker.fetch(new Request("https://www.example.com/datasheets/product.pdf"), env, { waitUntil() {} });
check("without PUBLIC_SITES nothing is published", withoutSetting.status, 404);
const signedWithout = await worker.fetch(new Request(await signedUrl("moo_file/2026-11/abc/private.pdf")), env, { waitUntil() {} });
check("...and signed links answer as before", signedWithout.status, 200);
check("...kept until they expire, as before", /^public, max-age=\d+, s-maxage=\d+$/.test(signedWithout.headers.get("Cache-Control")) && signedWithout.headers.get("Expires") !== null, true);
const otherHost = await worker.fetch(new Request("https://elsewhere.example.com/datasheets/product.pdf"), publicEnv, { waitUntil() {} });
check("a hostname PUBLIC_SITES doesn't name publishes nothing", otherHost.status, 404);

for (const [label, value] of [["not JSON", "{www"], ["a list", "[]"], ["a bad site name", JSON.stringify({ "www.example.com": "../x" })]]) {
  const broken = await worker.fetch(new Request("https://www.example.com/datasheets/product.pdf"), { ...publicEnv, PUBLIC_SITES: value }, { waitUntil() {} });
  check(`PUBLIC_SITES ${label} fails loudly`, broken.status, 500);
}

// Resized published images: only the fixed widths, read through the assets hostname, cached under address and width.
const resized = [];
const cachePuts = [];
globalThis.caches = { default: { async match() {}, async put(key) { cachePuts.push(key.url); } } };
globalThis.fetch = async (source, init) => {
  resized.push({ source: new URL(source), image: init.cf.image });
  return worker.fetch(new Request(source), publicEnv, { waitUntil() {} });
};
const pending = [];
const image = await worker.fetch(new Request("https://www.example.com/images/product/front.webp?width=800&utm_source=x"), publicEnv, { waitUntil(p) { pending.push(p); } });
await Promise.all(pending);
check("a published image at an offered width answers", image.status, 200);
check("...resized to it", JSON.stringify(resized[0].image), JSON.stringify({ width: 800, fit: "scale-down" }));
check("...from the original, read through the assets hostname", `${resized[0].source.host} ${resized[0].source.pathname}`, "assets.example.com /a/public/www/images/product/front.webp");
check("...cached under its address and width alone", cachePuts[0], "https://www.example.com/images/product/front.webp?width=800");
check("...kept briefly", image.headers.get("Cache-Control"), "public, max-age=300, s-maxage=300");
const oddWidth = await pub("/images/product/front.webp?width=801");
check("a width not offered is refused", oddWidth.status, 400);
const pdfWidth = await pub("/datasheets/product.pdf?width=800");
check("only images are resized", pdfWidth.status, 400);
const noOrigin = await worker.fetch(new Request("https://www.example.com/images/product/front.webp?width=800"), { ...publicEnv, ASSETS_ORIGIN: "" }, { waitUntil() {} });
check("a resize without ASSETS_ORIGIN fails loudly", noOrigin.status, 500);
const missingImage = await pub("/images/product/gone.webp?width=800");
check("a resize of an image not published is not found", missingImage.status, 404);
globalThis.fetch = realFetch;

const unsigned = await worker.fetch(new Request("https://assets.example.com/a/photos/house.jpg"), env, { waitUntil() {} });
check("an unsigned URL is refused", unsigned.status, 401);
check("...and its refusal is nosniff too", unsigned.headers.get("X-Content-Type-Options"), "nosniff");

console.log(`\n${checks} checks, ${failures} failing`);
process.exit(failures ? 1 : 0);
