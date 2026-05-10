# Moopa Packages

Moopa supports package-based application loading. A project can run multiple app runtimes from one shared codebase, with each runtime selecting exactly one active app via `APP_NAME`.

## Why packages exist

Older Moopa projects used a two-folder model:

```txt
code/moopa
code/project
```

That works for a single app, but becomes awkward when one codebase contains multiple related apps such as:

```txt
hub
generic
```

Packages let a project split code by responsibility while still sharing framework, domain, and project-level code.

## Typical project shape

```txt
code/
  moopa/              # Moopa framework
  apps/
    hub/              # control-plane/admin app
    generic/          # generic app scaffold
  domain/             # shared table definitions and domain services
  shared/             # shared project routes/tags/controls/libs
  www/                # common web root / Application.cfc
```

## Defining packages

Projects define packages in the application component that extends `moopa.application`:

```cfml
<cfcomponent extends="moopa.application">

    <cfset this.moopa_packages = [
        {
            name: "moopa",
            path: "/moopa",
            kind: "core",
            load: ["tables", "lib", "controls"]
        },
        {
            name: "moopa_hub",
            path: "/moopa",
            kind: "app",
            app_name: "hub",
            route_mount: "",
            auth_type: "hub",
            default_open_to: "security",
            load: ["routes", "navs"]
        },
        {
            name: "domain",
            path: "/domain",
            kind: "domain",
            load: ["tables", "lib"]
        },
        {
            name: "shared",
            path: "/shared",
            kind: "shared",
            load: ["routes", "lib", "controls"]
        },
        {
            name: "hub",
            path: "/apps/hub",
            kind: "app",
            app_name: "hub",
            route_mount: "",
            auth_type: "hub",
            default_open_to: "security",
            load: ["routes", "tables", "lib", "controls", "navs"]
        },
        {
            name: "generic",
            path: "/apps/generic",
            kind: "app",
            app_name: "generic",
            route_mount: "",
            auth_type: "generic",
            default_open_to: "security",
            load: ["routes", "tables", "lib", "controls", "navs"]
        }
    ] />

</cfcomponent>
```

If `this.moopa_packages` is not defined, Moopa falls back to the legacy package layout:

```txt
/moopa
/project
```

## Package fields

| Field | Required | Description |
|---|---:|---|
| `name` | yes | Unique logical package name. Used in diagnostics and `application.path`. |
| `path` | yes | Lucee mapping path, e.g. `/moopa`, `/apps/hub`, `/shared`. |
| `kind` | no | Package role. Common values: `core`, `domain`, `shared`, `app`. |
| `app_name` | for app packages | Runtime `APP_NAME` value that activates this package. Defaults to `name` if omitted. |
| `load` | yes | Array of capabilities to load from this package. |
| `route_mount` | no | URL prefix applied to this package's routes. Empty string means mount at `/`. |
| `auth_type` | no | Default app-level identity realm for routes in this package. |
| `default_open_to` | no | Default `open_to` value for routes in this package. Defaults to `security`. |

## Load capabilities

`load` controls which subdirectories Moopa scans.

| Capability | Directory | Loaded into |
|---|---|---|
| `routes` | `{path}/routes` | runtime route registry |
| `tables` | `{path}/tables` | `application.service` and database schema |
| `lib` | `{path}/lib` | `application.lib` |
| `controls` | `{path}/controls` | `application.control` |
| `navs` | `{path}/navs` | `application.navs` |

Missing directories are ignored.

## Runtime app selection

Each container/runtime sets:

```txt
APP_NAME=hub
APP_NAME=generic
```

Packages with `kind="app"` only load when:

```cfml
(package.app_name ?: package.name) EQ application.app_name
```

Non-app packages load in every runtime.

This means every runtime can share framework/domain/shared code while registering only one app's routes.

## Hub as the control plane

Every Moopa project should include a `hub` app. Hub is the control-plane/admin app for framework features such as:

- schema management
- profiles
- roles and permissions
- route management
- sysadmin tools

Moopa's core services are needed by every app, but Moopa's admin UI should only be exposed in Hub.

Use two logical packages pointing at the same physical `/moopa` directory:

```cfml
{
    name: "moopa",
    path: "/moopa",
    kind: "core",
    load: ["tables", "lib", "controls"]
},
{
    name: "moopa_hub",
    path: "/moopa",
    kind: "app",
    app_name: "hub",
    route_mount: "",
    auth_type: "hub",
    default_open_to: "security",
    load: ["routes", "navs"]
}
```

This gives all apps access to framework internals while only Hub registers Moopa admin routes like:

```txt
/schema/
/security/
/sysadmin/
```

## Routes

Routes are loaded from active packages with `load` containing `routes`.

A file like:

```txt
code/apps/generic/routes/about.cfc
```

maps to:

```txt
/about/
```

for the `generic` runtime.

The same route path can exist in different apps because each app has its own runtime route registry:

```txt
code/apps/hub/routes/profile.cfc  -> /profile/ in Hub
code/apps/generic/routes/profile.cfc  -> /profile/ in Generic
```

Within one runtime, duplicate route URLs throw an error.

### Route mounts

`route_mount` prefixes the package's routes.

```cfml
{
    name: "api",
    path: "/apps/api",
    kind: "app",
    app_name: "api",
    route_mount: "/api",
    load: ["routes"]
}
```

Then:

```txt
/apps/api/routes/products.cfc -> /api/products/
```

Most app packages mount at `/` because the domain/subdomain identifies the app.

## App-level auth type

Packages can define `auth_type`.

```cfml
{
    name: "generic",
    app_name: "generic",
    auth_type: "generic"
}
```

Routes in that package inherit the package auth type unless the route or endpoint declares its own `auth_type`/`auth` metadata.

In the multi-app model, most route CFCs do not need an `auth_type` attribute. The app package is the normal source of truth.

Use route-level `auth_type` only for unusual cross-realm cases.

Two apps can intentionally share a user/session identity realm by using the same app-level `auth_type`. If those apps live on sibling subdomains and should share login, cookie domain and session storage must also be configured to allow that.

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

or later:

```cfml
<cfreturn application.lib.auth_microsoft.handlePost() />
```

Unauthenticated users should be redirected to the current app's `/login/` route. A shared `/logout/` route may redirect to `/login/logout/` so provider-specific logout remains app-owned.

`auth_type` identifies the app's identity realm. The auth provider identifies how users sign in.

## Custom tags

Custom tag paths should be app-scoped at the Lucee/runtime level.

Recommended search order:

```txt
/code/apps/{APP_NAME}/tags
/code/shared/tags
/code/moopa/tags
```

This lets the active app override/shared tags without seeing tags from sibling apps.

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
- duplicate table definitions throw
- duplicate libs/controls/navs throw

This is intentional. Package boundaries should be explicit, and silent precedence bugs are difficult to diagnose.

## First-run route persistence

Moopa route registration normally persists route metadata to `moo_route` and `moo_route_endpoint`.

For first-run/starter scenarios, those tables may not exist yet. The package-aware route loader can fall back to in-memory route registration when the route persistence tables are missing, allowing `/login/` or other public setup routes to render before schema is applied.

Production apps should still apply schema and use persistent route metadata for permissions/security management.

## Backwards compatibility

If no `this.moopa_packages` is configured, Moopa keeps the legacy default:

```txt
/moopa
/project
```

Legacy projects can continue to work while newer projects adopt the package model.
