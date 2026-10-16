# moopa

- [Packages](docs/packages.md): how one codebase runs several apps, and where code belongs.
- [Object storage](docs/object-storage.md): S3 and Cloudflare R2 through Moopa's own client. **Apps upgrading from a Moopa that used the Lucee S3 extension must add `this.s3.defaultLocation`**; see its "Upgrading an existing app".
