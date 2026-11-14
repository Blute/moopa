# Object storage (S3 and R2)

Moopa talks to S3-compatible stores, AWS S3 and Cloudflare R2, through its own client, `application.lib.s3_client`. It signs requests itself (`aws_sigv4`) with static keys or the ECS task role (`aws_credentials`), so no Lucee S3 extension is needed.

## The default store

Moopa's uploads (`moo_file` through `file_upload`, and `moo_video`) use the application's default store, `s3_client.defaultStore()`:

- **Bucket:** the `S3_BUCKET` environment variable.
- **Endpoint, region and keys:** the application's S3 settings in `Application.cfc`, in Lucee's own names:

```cfml
this.s3 = {
    host: server.system.environment.S3_HOST,                 // https://<account>.r2.cloudflarestorage.com, or s3.<region>.amazonaws.com
    defaultLocation: server.system.environment.S3_REGION,    // the signing region; R2 signs as "auto"
    accessKeyId: server.system.environment.S3_ACCESSKEYID,
    awsSecretKey: server.system.environment.S3_AWSSECRETKEY
};
```

Leave both keys empty to sign with the ECS task role (AWS S3 only; R2 needs keys). A missing bucket, endpoint or region throws `s3.config.missing` naming the variable or `this.s3` key to set.

## Upgrading an existing app

Before this, Moopa's uploads went through the Lucee S3 extension (`s3generatePresignedUrl`), which read only `this.s3.host`, `accessKeyId` and `awsSecretKey`. Moopa now signs the request itself, and SigV4 signing needs the region too. So when an existing app moves to this version of Moopa:

1. **Add `defaultLocation` to `this.s3`** in `Application.cfc`: the store's signing region, `"auto"` for Cloudflare R2, the bucket's region (e.g. `"ap-southeast-2"`) for AWS S3. Without it, every `moo_file` and `moo_video` upload fails with `s3.config.missing: … set this.s3.defaultLocation in Application.cfc …`.
2. **Use `defaultLocation`, not a key of your own** such as `region`: Lucee rewrites `this.s3` into its fixed set of keys (`host`, `defaultLocation`, `accessKeyId`, `awsSecretKey`) and drops any other.
3. **Rename any libs of your own called `s3_client`, `aws_sigv4` or `aws_credentials`**: Moopa refuses two libs with one name, so the app would fail to start.
4. **Keep or drop the S3 extension as your own code needs.** Moopa no longer uses it. If the app still calls `s3write()`, `s3readBinary()`, `s3generatePresignedUrl()` or reads `s3://` paths itself, keep the extension installed until those calls move to `s3_client`. Once nothing calls them, remove it from the image.

## Using the client

Every call takes a store: `defaultStore()`, or one built with `configure(label, bucket, region, endpoint, accessKeyId, secretAccessKey)` for another bucket.

| Call | Does |
|---|---|
| `readObject(store, objectKey)` | the object as text |
| `readObjectBinary(store, objectKey)` | the object as bytes, in memory |
| `downloadObject(store, objectKey, filePath)` | streams the object to a file, for anything large |
| `writeObject(store, objectKey, value, contentType)` | writes text or bytes |
| `objectExists(store, objectKey)` | asks the store (HEAD): true, false, or throws |
| `headObject(store, objectKey)` | what the store holds (HEAD): `{ exists, size, contentType }` |
| `readObjectStart(store, objectKey, bytes)` | the first `bytes` bytes (a ranged GET), to read a file's signature |
| `deleteObject(store, objectKey)` | deletes it |
| `listObjects(store, prefix)` | `[{ key, etag, size, last_modified }]` under a prefix |
| `presignedUrl(store, objectKey, method, expiresSeconds, signedHeaders)` | a URL a browser can GET or PUT without credentials; with `signedHeaders` (such as `{ "Content-Type": "image/jpeg", "Content-Length": 48213 }`) the browser must send each with exactly that value, or the store refuses it |

A failed request throws `s3.request.failed` with the store's status and answer in the detail.

## Engines

The client is plain CFML: no Java classes and no XPath, so it runs the same on Lucee and on RustCFML (verified on 0.653.14 against AWS's SigV4 and presigned-URL examples and live against R2). One RustCFML gap remains: until [RustCFML#490](https://github.com/RustCFML/RustCFML/pull/490) is fixed, `cfhttp` sends a binary body as the text `<Binary>`, so `writeObject` with bytes fails there (`XAmzContentSHA256Mismatch`). Text writes, reads, downloads, presigned URLs and Moopa's own uploads (which only presign) are unaffected.

```cfml
store = application.lib.s3_client.defaultStore();
application.lib.s3_client.writeObject(store, "reports/#id#.pdf", pdfBytes, "application/pdf");
uploadUrl = application.lib.s3_client.presignedUrl(store, "uploads/#name#", "PUT", 300);
```

## Uploads from the browser

A browser uploads a file straight to the store through `application.lib.file_upload`, which checks it at both ends. Never hand a browser a bare `presignedUrl` for PUT: it lets it store any body of any length and type under your key.

1. **Start** (`start(file_name, file_size, owner, kinds, max_bytes)`): refuses a file of a kind the caller doesn't accept, an empty one or one over `max_bytes` (`{ success: false, error_code, error }`, with `error_code` `file_type`, `empty` or `file_size`). Otherwise it makes the `moo_file`, records the upload under way (`moo_file_upload`), and returns `{ success: true, file, presignedURL, headers }`. The URL is signed for the file's Content-Type, chosen by the server from its extension, and its exact Content-Length, so the store refuses any other body.
2. **PUT**: the browser sends the file to `presignedURL` with exactly `headers`. Its Content-Length is the browser's own, from the file.
3. **Finish** (`finish(file_id, owner)`): checks the store holds the file at its signed size and type, and that its first bytes are a file of its kind (a page named `.jpg` is not an image). Returns `{ success: true, file }`, with an image's thumbnail now its own picture. A file that never arrived, or isn't what its name says, is removed: `{ success: false, error_code }`, `not_uploaded` or `file_content`.

`kinds` is a list of `image` (JPEG, PNG, GIF, WebP, HEIC/HEIF, TIFF, BMP), `pdf`, `video` (MP4, M4V, MOV, WebM, Matroska, AVI) and `zip`. SVG is no kind: it is a document that can run script.

**An endpoint that only uploads** answers with `answer(data, owner, kinds, max_bytes)`: `finish()` when the request names a `file_id`, `start()` otherwise, and a refusal as a 422 marked `X-Refusal`, which `req()` shows. An endpoint that does more, such as attaching the file to a record or capping how many a record holds, calls `start()` and `finish()` itself.

**The owner** is whatever the caller vouches the upload belongs to: `"moo_profile:" & session.auth.profile.id` for a signed-in person, or a record an anonymous visitor owns, checked by the route first. Only an ask naming the same owner may finish or `discard()` the upload, so one visitor can't finish another's. `underWay(owner)` counts the owner's uploads still under way, for a caller that caps how many files an owner holds.

**Abandoned uploads**: a browser that starts an upload and never finishes it leaves a file and maybe an object. `sweep()` removes every upload left unfinished for a day. Run it on a schedule.

### Videos

A video for Cloudflare Stream uploads the same way through `application.lib.video_upload`, onto a `moo_video` instead of a `moo_file`:

1. **Start** (`start(file_name, file_size, owner, max_bytes, metadata)`): the same refusals (`file_type` for anything but a video, `empty`, `file_size`). Otherwise it makes the `moo_video` with `metadata` merged into its own (what the video is for, a length limit), records the upload (`moo_video_upload`), and returns `{ success: true, video, video_id, presignedURL, headers }`. The URL works for 30 minutes.
2. **PUT** with exactly `headers`.
3. **Finish** (`finish(video_id, owner, source)`): the same check (`file_upload.storedFault()`), and only then hands the file to Stream (`moo_video` `sendToStream()`). Returns `{ success: true, video }`. A file that fails is removed with its video, and Stream is never asked. Of two finishes at once only one copies to Stream. A copy Stream refuses throws `moo_video.streamRefused` and puts the upload back as it was, to finish again or be swept; any other failure (no answer, or one after Stream took the copy) throws and leaves the upload finished, because Stream may hold a video and asking again could bill a second one. A caller whose own record refers to the video before its upload finishes passes `release`, a function given the video id that lets go of it before the video is removed.

An endpoint answers a refusal with `refused(result)`, a 422 marked `X-Refusal` that `req()` shows. `discard(video_id, owner)` drops an upload the browser gave up on, `underWay(owner)` lists an owner's, and `sweep()` removes those left a day. A record that refers to a video before its upload finishes lets go of those `abandoned()` lists before the sweep, because the sweep deletes the `moo_video`. The `moo_video` service's `handleVideoAction()` now only polls Stream (`video_ids`) and deletes (`delete`, `video_id`).

## Serving uploaded files

The signed assets Worker (`config/init/cloudflare-signed-assets-worker.js`) answers every request `X-Content-Type-Options: nosniff`, and opens only images, video, audio and PDFs in the browser. Anything else a raw asset (`/a/`) is stored as, SVG and HTML included, is a download (`Content-Disposition: attachment`), so a signed link can never show a page on the asset hostname. `node scripts/test_assets_worker.mjs` checks it, and what `/p/` asks of the PDF pages Worker.

### A page of a PDF as an image

`/p/` answers one page of a stored PDF as an image, so a PDF gets a thumbnail or a page preview without anything being made or stored when it is uploaded. Sign it like any other asset, with kind `p` (or `page`):

```sql
SELECT signed_asset_url(moo_file.path, 'EOW', 'p', 'page=1&width=120&height=120&fit=cover') AS thumbnail
```

- `page` counts from 1 and is 1 when not given. A page the PDF doesn't have is a 404.
- `width`, `height`, `fit` and `quality` resize the page exactly as `/i/` resizes an image, in the format the browser takes. With none of them the page comes 1600 pixels wide.
- `render=<width>` (16 to 2000) answers the page as a PNG that many pixels wide without image resizing, for a zone that doesn't have Images Transformations.
- A file that isn't a PDF is a 415, one that can't be opened (damaged, or needing a password) a 422, and one over 16 MiB a 413 (the limit is the PDF pages Worker's memory; `MAX_PDF_PAGE_BYTES` on the signed assets Worker lowers it).

The rendering is done by a second Worker, the **PDF pages Worker** (`config/init/cloudflare-pdf-pages-worker.js`), which the signed assets Worker reaches through a service binding named `PDF_PAGES`. It holds no files and no keys, so one of it serves every app: the signed assets Worker checks the signature, reads the PDF from its own bucket and sends it over. Its file says how to deploy it: three modules (itself and two files of the npm package `@hyzyla/pdfium`), and no address of its own. Without the binding `/p/` answers 500 `Missing PDF_PAGES binding`.

A page is rendered each time an address is first asked for, then kept in the edge cache until the address expires, so sign with a period-aligned expiry (`EOW`, `EOM`) as for thumbnails.

### Upgrading to PDF pages

1. **Run `config/init/cloudflare.sql` again**: `signed_asset_url()` learns kind `p`. Until then it signs a `p` as a raw asset (`/a/`).
2. **Deploy the PDF pages Worker** once, from `config/init/cloudflare-pdf-pages-worker.js`.
3. **Redeploy the signed assets Worker** from `config/init/cloudflare-signed-assets-worker.js`, with the `PDF_PAGES` service binding.

## Upgrading to checked uploads

`moo_file`'s `uploadFileToServerWithProgress()` is gone: it signed an upload URL for any body, checked nothing when the upload finished, and let anyone finish any file. When a project moves to this version of Moopa:

1. **Sync the schema** (System → Schema): it adds the `moo_file_upload` table. Without it every upload fails.
2. **Move each upload endpoint to `file_upload`**: `answer(request.data, owner, kinds, max_bytes)`, naming the owner and the kinds the field accepts (the `moopa-routes` skill, File Upload Endpoint). A finished upload answers `{ success, file }`, not the bare file.
3. **PUT with the `headers` the start returns**, not the file's own type. Moopa's `fileUpload` component and its own pages already do. An upload sending another Content-Type is refused by the store (403).
4. **Schedule `application.lib.file_upload.sweep()`**, daily.
5. **Redeploy the signed assets Worker** from `config/init/cloudflare-signed-assets-worker.js`, so raw assets carry `nosniff` and only media and PDFs open inline.

### Upgrading to checked video uploads

`moo_video`'s `uploadVideoInit()` is gone, and `uploadVideoComplete(data, source)` is `sendToStream(video_id, source)`: the old start signed an upload URL for any body, and `handleVideoAction()` finished any video it was given an id for. When a project moves to this version:

1. **Sync the schema**: it adds the `moo_video_upload` table.
2. **Start and finish video uploads through `video_upload`**, naming the owner; `handleVideoAction()` throws for anything but a poll or a delete.
3. **PUT with the `headers` the start returns.**
4. **Schedule `application.lib.video_upload.sweep()`**, daily, after letting go of any `abandoned()` video a record refers to.
