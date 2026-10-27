# Moopa Packages

Moopa supports convention-based multi-app projects. One codebase can run several app runtimes, with each runtime selecting exactly one active app via `APP_NAME`.

## Project shape

```txt
code/
  moopa/              # Moopa framework
  apps/
    hub/              # control-plane/admin app, APP_NAME=hub
    www/              # example public app, APP_NAME=www
  shared/             # project-owned shared tables/libs/routes/tags/controls/navs
  www/                # common web root / Application.cfc
```

There is intentionally no separate `domain/` package. Project-wide business code and table definitions live in `shared/`. If code is needed by every app in this project, put it in `shared`; if it belongs to one app, put it under `apps/{app}`; if it belongs to the framework, put it in `moopa`.

## Runtime app selection

Each container/runtime sets:

```txt
APP_NAME=hub
APP_NAME=www
```

Moopa then loads packages in this order:

```txt
moopa
shared
apps/{APP_NAME}
```

`APP_NAME` must match a directory under `code/apps/`.

## Load capabilities

Moopa scans conventional subdirectories from the active packages.

| Capability | Directory | Loaded into |
|---|---|---|
| `routes` | `{path}/routes` | runtime route registry |
| `tables` | `{path}/tables` | `application.service` and database schema |
| `lib` | `{path}/lib` | `application.lib` |
| `controls` | `{path}/controls` | `application.control` |
| `navs` | `{path}/navs` | `application.navs` |

Load rules:

- `routes`: loaded from `shared` and the active app, and in Hub also from `moopa` (the System pages).
- `navs`: loaded from `shared` and the active app, and in Hub also from `moopa` (the System menu).
- `tables`, `lib`, `controls`: loaded from `moopa`, `shared`, and the active app.

Missing directories are ignored.

## Where code belongs

### `code/moopa`

Framework-owned services, controls, tags, tables, and routes. Code here must be generic enough to be used by other Moopa projects.

### `code/shared`

Project-owned code available to every app in the repo:

```txt
code/shared/tables
code/shared/lib
code/shared/routes
code/shared/tags
code/shared/controls
code/shared/navs
```

Use this for project-wide table definitions, business services, integrations, shared route helpers, shared tags, and shared controls.

### `code/apps/{app}`

App-owned code for one runtime only:

```txt
code/apps/hub/routes
code/apps/hub/lib
code/apps/hub/tables
code/apps/hub/tags
code/apps/hub/controls
code/apps/hub/navs
```

Routes and navigation are normally app-owned because each app has its own URL space.

### Nav files

Each `navs/*.json` file is an array of items. An item is one of:

- a link: `{ "icon": "...", "title": "...", "route": "/path" }` — shown only when the user can `GET` the route
- a menu: `{ "icon": "...", "title": "...", "items": [ ... ] }` — shown only when at least one child survives filtering
- a divider: `{ "divider": true }` — a separator line; nothing else is allowed on it

`moo_profile.buildNavs()` filters items by route access, then drops any divider left at the start or end of a list, or directly after another divider, so access filtering never leaves an orphaned separator.

## Hub as the control plane

Every Moopa project should include a `hub` app. Hub is the control-plane/admin app for framework features such as:

- schema management
- profiles
- roles and permissions
- route management
- sysadmin tools

### System pages are Moopa's

Hub serves Moopa's System pages (`/sysadmin/*`: roles, routes, route access, profiles, impersonation, error log, schema, app summary) and the System menu straight from `code/moopa/routes/sysadmin` and `code/moopa/navs/sysadmin.json`. Every project gets the same pages, and they change only when Moopa does. No other app serves them.

The pages render inside Hub's `layout_default` tag and use Tailwind and daisyUI classes, so a project's Hub needs a `layout_default` tag and a Tailwind + daisyUI stylesheet built with `code/moopa` among its sources (`moopa-starter`'s Hub has both). Rebuild that stylesheet after a Moopa update, as pages may use new classes.

They cover Moopa's own features and are never customised per project. `/sysadmin` and the `sysadmin` menu are reserved: a project route under `routes/sysadmin` (in `shared` or any app) or a project `navs/sysadmin.json` stops the application at startup, naming the file. A project needs no symlink or copy; delete any it has.

Project admin belongs in the project's own Hub routes and menu, for example:

```txt
code/apps/hub/routes/admin/audit.cfc        -> /admin/audit/
code/apps/hub/navs/admin.json               -> an "Admin" menu
```

That includes extending a framework feature. A project that keeps more about a person than `moo_profile` holds stores it in its own table and edits it on its own route (say `/admin/people/[profile_id]`), not by changing the System Profiles page.

#### Upgrading a project that linked or copied the System pages

1. Move any page the project added under `routes/sysadmin` (one Moopa doesn't have) to a route of its own, such as `/admin/...`, with its own menu entry, and update links to it.
2. Delete `code/apps/hub/routes/sysadmin` and `code/apps/hub/navs/sysadmin.json`, whether links or copies. A copy's edits to a Moopa page are dropped; anything worth keeping belongs in Moopa (a pull request) or in a project route.
3. Remove `MOOPA_ENABLE_SYSADMIN` from the environment. Hub no longer reads it.
4. Re-initialise Hub. Routes are matched to their saved rows by URL, so role grants on the System pages carry over.

## Routes

A file like:

```txt
code/apps/www/routes/about.cfc
```

maps to:

```txt
/about/
```

for the `www` runtime.

The same route path can exist in different apps because each app has its own runtime route registry:

```txt
code/apps/hub/routes/profile.cfc -> /profile/ in Hub
code/apps/www/routes/profile.cfc -> /profile/ in WWW
```

Within one runtime, duplicate route URLs throw an error.

## App-scoped profiles

Profiles are app-scoped through `moo_profile.app_name`.

The active runtime app is selected by `APP_NAME`, and authenticated profiles must belong to that app. Auth provider choice is separate from app ownership and is stored in linked auth identity records.

`moo_profile.app_name` identifies the app that owns the profile. `moo_profile_auth.provider` identifies how the profile signs in.

## Login/provider model

Authentication provider choice is app-owned, not framework-global.

Recommended shape:

```txt
code/apps/{app}/routes/login/index.cfc
code/apps/{app}/routes/login/logout.cfc
```

`/login/` is the user-facing login route for the current app. It can delegate to any provider:

```cfml
<cfreturn application.lib.auth_local_password.handlePost() />
```

or:

```cfml
<cfreturn application.lib.auth_microsoft.handlePost() />
```

Unauthenticated users should be redirected to the current app's `/login/` route. A shared `/logout/` route may redirect to `/login/logout/` so provider-specific logout remains app-owned.

## Custom tags

Custom tag paths should be app-scoped at the Lucee/runtime level.

Recommended search order:

```txt
/code/apps/{APP_NAME}/tags
/code/shared/tags
/code/moopa/tags
```

This lets the active app override shared/framework tags without seeing tags from sibling apps.

In Docker/CFConfig this can be expressed with `{env:APP_NAME}`:

```json
"customTagMappings": [
  { "physical": "/var/www/code/apps/{env:APP_NAME}/tags", "virtual": "/app" },
  { "physical": "/var/www/code/shared/tags", "virtual": "/shared" },
  { "physical": "/var/www/code/moopa/tags", "virtual": "/moopa" }
]
```

## Duplicate handling

Moopa fails loudly on ambiguous package definitions:

- duplicate route URLs within one runtime throw
- duplicate libs/controls/navs throw
- duplicate table definitions normally throw

Table definitions are the exception when a later conventional package intentionally overrides an earlier one. This allows project code in `shared/tables` or app code in `apps/{app}/tables` to override a framework table definition when necessary.

## First-run route persistence

Moopa route registration normally persists route metadata to `moo_route` and `moo_route_endpoint`.

For first-run/starter scenarios, those tables may not exist yet. The package-aware route loader can fall back to in-memory route registration when the route persistence tables are missing, allowing `/login/` or other public setup routes to render before schema is applied.

Production apps should still apply schema and use persistent route metadata for permissions/security management.
