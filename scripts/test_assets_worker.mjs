// Regression harness for the signed assets Worker (config/init/cloudflare-signed-assets-worker.js): what a raw
// asset (/a/) answers, by the type it was stored with, and what a page of a PDF (/p/) asks of the PDF service. Media and PDFs open in the browser; anything else, an SVG
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

const unsigned = await worker.fetch(new Request("https://assets.example.com/a/photos/house.jpg"), env, { waitUntil() {} });
check("an unsigned URL is refused", unsigned.status, 401);
check("...and its refusal is nosniff too", unsigned.headers.get("X-Content-Type-Options"), "nosniff");

console.log(`\n${checks} checks, ${failures} failing`);
process.exit(failures ? 1 : 0);
