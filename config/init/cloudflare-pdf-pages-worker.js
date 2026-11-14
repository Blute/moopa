// The PDF pages Worker: turns one page of a PDF into a PNG, for the signed assets Worker's /p/ addresses
// (config/init/cloudflare-signed-assets-worker.js, binding PDF_PAGES). It holds no files and no keys: the PDF comes
// in the request and the picture goes back in the answer, so one Worker serves every app.
//
//   POST /?page=1&width=400   body: the PDF   ->   200 image/png, that many pixels wide (16 to 2000)
//   404 no such page; 413 a PDF over 16 MiB; 422 not a PDF it can open (damaged, or needing a password).
//
// Deploy it with no address of its own (no route, no workers.dev): only a service binding reaches it. It is three
// modules, the last two from the npm package @hyzyla/pdfium, version 3.0.0, taken as they are (the package is MIT;
// PDFium, which it builds as WebAssembly, is under BSD-style and Apache 2.0 licences):
//   worker.js     this file (the main module)
//   pdfium.js     the package's dist/index.esm.browser.js
//   pdfium.wasm   the package's dist/pdfium.wasm
import { PDFiumLibrary } from "./pdfium.js";
import pdfiumWasm from "./pdfium.wasm";

// Both limits keep a rendering inside a Worker's 128 MB: the PDF is held twice while it is opened (the request's
// bytes and PDFium's copy), then the page's bitmap (4 bytes a pixel) beside PDFium's own working memory.
const MAX_PDF_BYTES = 16 * 1024 * 1024;
// An A4 page 2000 pixels wide is 5.7 million. A page far taller than it is wide (a till receipt) is rendered
// narrower than asked rather than past this.
const MAX_PIXELS = 6_000_000;
const MIN_WIDTH = 16;
const MAX_WIDTH = 2000;

// PDFium starts once per isolate. Workers can't compile WebAssembly from bytes, so it is given the module the
// runtime already compiled.
let libraryPromise;
function library() {
  libraryPromise ??= PDFiumLibrary.init({
    instantiateWasm(imports, done) {
      const instance = new WebAssembly.Instance(pdfiumWasm, imports);
      done(instance, pdfiumWasm);
      return instance.exports;
    },
  }).catch((error) => {
    libraryPromise = undefined;
    throw error;
  });
  return libraryPromise;
}

export default {
  async fetch(request) {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    const url = new URL(request.url);
    const page = toPositiveInt(url.searchParams.get("page") ?? "1");
    const width = toPositiveInt(url.searchParams.get("width") ?? "400");
    if (!page) return new Response("Bad page", { status: 400 });
    if (!width || width < MIN_WIDTH || width > MAX_WIDTH) {
      return new Response("Bad width", { status: 400 });
    }

    const declared = Number(request.headers.get("Content-Length"));
    if (Number.isFinite(declared) && declared > MAX_PDF_BYTES) {
      return new Response("PDF too large", { status: 413 });
    }
    let pdf = new Uint8Array(await request.arrayBuffer());
    if (pdf.byteLength > MAX_PDF_BYTES) {
      return new Response("PDF too large", { status: 413 });
    }

    const pdfium = await library();

    let doc;
    try {
      doc = await pdfium.loadDocument(pdf);
    } catch (_error) {
      return new Response("Not a PDF that can be opened", { status: 422 });
    }
    // PDFium has its own copy now: let go of the request's before the page is rendered.
    pdf = null;

    try {
      if (page > doc.getPageCount()) {
        return new Response("No such page", { status: 404 });
      }

      const pdfPage = doc.getPage(page - 1);
      const size = pdfPage.getOriginalSize();
      if (!(size.originalWidth > 0) || !(size.originalHeight > 0)) {
        return new Response("Not a PDF that can be opened", { status: 422 });
      }

      let scale = width / size.originalWidth;
      const pixels = width * (size.originalHeight * scale);
      if (pixels > MAX_PIXELS) scale *= Math.sqrt(MAX_PIXELS / pixels);

      const image = await pdfPage.render({ scale, render: "bitmap" });
      const png = await encodePng(image.width, image.height, image.data);
      return new Response(png, { headers: { "Content-Type": "image/png" } });
    } finally {
      doc.destroy();
    }
  },
};

function toPositiveInt(value) {
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : null;
}

// An RGBA bitmap as a PNG without its alpha (a rendered page has none): 8-bit RGB, every row unfiltered, the
// pixels deflated by the runtime a band of rows at a time, so the page is never held a second time whole.
async function encodePng(width, height, rgba) {
  const BAND_ROWS = 64;
  let y = 0;
  let at = 0;
  const rows = new ReadableStream({
    pull(controller) {
      if (y >= height) {
        controller.close();
        return;
      }
      const count = Math.min(BAND_ROWS, height - y);
      const band = new Uint8Array((width * 3 + 1) * count);
      let out = 0;
      for (let row = 0; row < count; row++) {
        band[out++] = 0;
        for (let x = 0; x < width; x++) {
          band[out++] = rgba[at];
          band[out++] = rgba[at + 1];
          band[out++] = rgba[at + 2];
          at += 4;
        }
      }
      y += count;
      controller.enqueue(band);
    },
  });

  const deflated = new Uint8Array(
    await new Response(rows.pipeThrough(new CompressionStream("deflate"))).arrayBuffer(),
  );

  const header = new Uint8Array(13);
  const view = new DataView(header.buffer);
  view.setUint32(0, width);
  view.setUint32(4, height);
  header[8] = 8; // bits per channel
  header[9] = 2; // colour type: RGB

  return new Blob([
    new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10]),
    ...pngChunk("IHDR", header),
    ...pngChunk("IDAT", deflated),
    ...pngChunk("IEND", new Uint8Array(0)),
  ]);
}

function pngChunk(type, data) {
  const head = new Uint8Array(8);
  new DataView(head.buffer).setUint32(0, data.length);
  head.set(new TextEncoder().encode(type), 4);
  const tail = new Uint8Array(4);
  new DataView(tail.buffer).setUint32(0, crc32(head.subarray(4), data));
  return [head, data, tail];
}

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(...parts) {
  let c = 0xffffffff;
  for (const part of parts) {
    for (let i = 0; i < part.length; i++) c = CRC_TABLE[(c ^ part[i]) & 0xff] ^ (c >>> 8);
  }
  return (c ^ 0xffffffff) >>> 0;
}
