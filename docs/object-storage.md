# Object storage (S3 and R2)

Moopa talks to S3-compatible stores, AWS S3 and Cloudflare R2, through its own client, `application.lib.s3_client`. It signs requests itself (`aws_sigv4`) with static keys or the ECS task role (`aws_credentials`), so no Lucee S3 extension is needed.

## The default store

Moopa's uploads (`moo_file`, `moo_video`) use the application's default store, `s3_client.defaultStore()`:

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
| `deleteObject(store, objectKey)` | deletes it |
| `listObjects(store, prefix)` | `[{ key, etag, size, last_modified }]` under a prefix |
| `presignedUrl(store, objectKey, method, expiresSeconds)` | a URL a browser can GET or PUT without credentials |

A failed request throws `s3.request.failed` with the store's status and answer in the detail.

## Engines

The client is plain CFML: no Java classes and no XPath, so it runs the same on Lucee and on RustCFML (verified on 0.653.14 against AWS's SigV4 and presigned-URL examples and live against R2). One RustCFML gap remains: until [RustCFML#490](https://github.com/RustCFML/RustCFML/pull/490) is fixed, `cfhttp` sends a binary body as the text `<Binary>`, so `writeObject` with bytes fails there (`XAmzContentSHA256Mismatch`). Text writes, reads, downloads, presigned URLs and Moopa's own uploads (which only presign) are unaffected.

```cfml
store = application.lib.s3_client.defaultStore();
application.lib.s3_client.writeObject(store, "reports/#id#.pdf", pdfBytes, "application/pdf");
uploadUrl = application.lib.s3_client.presignedUrl(store, "uploads/#name#", "PUT", 300);
```
