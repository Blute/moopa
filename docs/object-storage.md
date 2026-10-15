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

Leave both keys empty to sign with the ECS task role (AWS S3 only; R2 needs keys). A missing bucket, endpoint or region throws `s3.config.missing` naming the store.

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

```cfml
store = application.lib.s3_client.defaultStore();
application.lib.s3_client.writeObject(store, "reports/#id#.pdf", pdfBytes, "application/pdf");
uploadUrl = application.lib.s3_client.presignedUrl(store, "uploads/#name#", "PUT", 300);
```
