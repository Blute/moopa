# moopa

- [Packages](docs/packages.md): how one codebase runs several apps, where code belongs, and why Hub's System pages (`/sysadmin`) are Moopa's alone.
- [Route links](docs/route-links.md): `route_links.json`, the record of which pages each route links to, read by System → Route Access.
- [Object storage](docs/object-storage.md): S3 and Cloudflare R2 through Moopa's own client. **Apps upgrading from a Moopa that used the Lucee S3 extension must add `this.s3.defaultLocation`**; see its "Upgrading an existing app".
- [Re-initialising](docs/reinitialising.md): `?init`, who may restart an app (development, a sysadmin through `req()`, or an operator with `PROJECT_INIT_KEY`), and how.
- [Agent skills](docs/agent-skills.md): Moopa's skills for agents, and linking them into a project with `scripts/link-skills.sh`.
