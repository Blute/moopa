# moopa

Agents: read [AGENTS.md](AGENTS.md) first.

- [Packages](docs/packages.md): how one codebase runs several apps, where code belongs, and why Hub's System pages (`/sysadmin`) are Moopa's alone.
- [Route access](docs/route-access.md): who opens a route at each `open_to` level, the order the checks run, and `this.moopa_validated_without_login` (with its session check, `this.moopa_validated_session_check`) for projects that validate visitors without a login.
- [Route links](docs/route-links.md): `route_links.json`, the record of which pages each route links to, read by System → Route Access.
- [Object storage](docs/object-storage.md): S3 and Cloudflare R2 through Moopa's own client, and uploads from the browser checked at both ends (`file_upload`, and `video_upload` for Cloudflare Stream videos). **Apps upgrading from a Moopa that used the Lucee S3 extension must add `this.s3.defaultLocation`**; see its "Upgrading an existing app". **Apps upgrading to checked uploads must sync the schema, move their upload endpoints to `file_upload` and redeploy the assets Worker**; see "Upgrading to checked uploads". **Apps upgrading to checked video uploads must sync the schema and start and finish videos through `video_upload`**; see "Upgrading to checked video uploads".
- [Schema](docs/schema.md): System → Schema, the statements a project's `schemaSync` returns, and destructive statements hidden by default. **Apps upgrading must mark every statement `destructive`**; see its "Upgrading an existing app".
- [Re-initialising](docs/reinitialising.md): `?init`, who may restart an app (development, a sysadmin through `req()`, or an operator with `PROJECT_INIT_KEY`), and how.
- [Agent skills](docs/agent-skills.md): Moopa's skills for agents, and linking them into a project with `scripts/link-skills.sh`.
- [Email](docs/email.md): transactional email through Cloudflare Email Sending (`application.lib.email`), and how framework email falls back to a project's Postmark library.
- [Sign-in](docs/signin.md): passwordless sign-in by emailed link, Continue with Google, invitations and sign-in activity.
- [Account pages](docs/account.md): the profile pages Moopa serves, and replacing one in a project.
- [Errors](docs/errors.md): what Moopa does with an uncaught error, who sees its details (`this.moopa_error_details`), and replacing the error page.
- [Search](docs/search.md): `db.search()`'s arguments, `sql_type` for linked records, and the order of text-search results (score, then primary key).
- [Design](docs/design.md): Moopa's own vanilla-CSS design for the System pages, the `moopa_layout` tag a project page can opt in to, theming by tokens, and serving the static files under content-hash names (`this.moopa_anonymous_static_path`).
