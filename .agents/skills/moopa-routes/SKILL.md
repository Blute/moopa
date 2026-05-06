---
name: moopa-routes
description: Create Moopa route CFCs with endpoints and frontend API calls. Use when creating new routes, adding endpoints (load, save, search, delete), calling backend with req(), or understanding how body{} maps to request.data.
---

# Moopa Routes - Endpoints and API Patterns

## Core Concept: File-Based Routing

Routes are CFC files in `code/project/routes/` that map directly to URLs:

| File Path | URL |
|-----------|-----|
| `routes/index.cfc` | `/` |
| `routes/hub/agencies.cfc` | `/hub/agencies/` |
| `routes/hub/sell_addresses.cfc` | `/hub/sell_addresses/` |
| `routes/hub/[agency_id]/agency.cfc` | `/hub/{agency_id}/agency/` |

**URL slug convention:** filenames and directory names map verbatim — underscores stay underscores, they are **not** converted to hyphens. Pick filenames that read well as URL slugs (e.g. `coming_soon.cfc` → `/hub/coming_soon/`).

Dynamic slugs like `[agency_id]` become `arguments.agency_id` in endpoint functions.

## Route CFC Structure

```cfml
<cfcomponent key="a1b2c3d4-e5f6-7890-abcd-ef1234567890" open_to="security">

    <!--- Data endpoint: returns JSON --->
    <cffunction name="load">
        <cfreturn application.lib.db.read(table_name="my_table", id=arguments.id) />
    </cffunction>

    <!--- Save endpoint: returns JSON --->
    <cffunction name="save">
        <cfreturn application.lib.db.save(table_name="my_table", data=request.data) />
    </cffunction>

    <!--- Render HTML page (default endpoint, no return statement) --->
    <cffunction name="get">
        <cf_layout_default>
            <div x-data="my_component">
                <!-- HTML with Alpine.js -->
            </div>
        </cf_layout_default>
    </cffunction>

</cfcomponent>
```

**Important:** Always start with `open_to="security"` (sysadmin only) for new routes. This ensures the route is locked down by default until you explicitly grant broader access.

### Component Attributes

| Attribute | Values | Purpose |
|-----------|--------|---------|
| `key` | UUID | **Required.** Unique identifier — generate via `uuidgen`, never hand-crafted. Keys must be globally unique across the entire codebase. Missing or empty key throws `No Key Defined for <route>` from `moo_route.cfc` on first request — this is the framework-side check that route identity is wired up before any authorisation logic runs. |
| `open_to` | `public`, `validated`, `security` | Access control (see below) |

### Access Control: open_to Options

| Value | Description | Use Case |
|-------|-------------|----------|
| `security` | Requires security/admin role | **Default for new routes** - Admin panels, system settings |
| `logged_in` | Requires authenticated user | User dashboards, app pages after access granted |
| `bearer` | Requires Bearer token in Authorization header | External API integrations, webhooks |
| `public` | No authentication required | Landing pages, login, public APIs |

**Best Practice:** Always use `open_to="security"` for new routes unless otherwise specified. This locks the route to sysadmin only until you explicitly grant broader access.

- Unauthenticated users accessing `logged_in` or `security` routes are redirected to login
- `bearer` validates against `BEARER_TOKEN` environment variable
- Default is `security` if omitted

```cfml
<!--- New route - start with security (sysadmin only) --->
<cfcomponent key="..." open_to="security">

<!--- After access granted - logged-in users --->
<cfcomponent key="..." open_to="logged_in">

<!--- API route - requires Bearer token --->
<cfcomponent key="..." open_to="bearer">

<!--- Public route - anyone can access --->
<cfcomponent key="..." open_to="public">
```

For `bearer` routes, clients must include the Authorization header:
```
Authorization: Bearer <token>
```

## Return Behavior

Moopa automatically handles return values:

| Scenario | Result |
|----------|--------|
| No `<cfreturn>` | Generated output returned as HTML |
| Return struct or array | Automatically serialized to JSON |
| Return query | Automatically serialized to JSON |
| Return string (already JSON) | Returned as-is |

**Important:** Route endpoints should not declare `output="true"`. Leave `output` unset on route `cffunction`s, including `get` endpoints that render HTML. Moopa handles endpoint output/returns without needing `output="true"`, and adding it is considered an anti-pattern in this codebase.

**Best practice:** Have queries return JSON directly from PostgreSQL (see `moopa-queries` skill). This avoids double-serialization:

```cfml
<!--- GOOD: Query returns JSON string, returned as-is --->
<cffunction name="load">
    <cfquery name="qData">
    SELECT COALESCE(row_to_json(data)::text, '{}') as recordset
    FROM (SELECT * FROM my_table WHERE id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />) AS data
    </cfquery>
    <cfreturn qData.recordset />
</cffunction>

<!--- AVOID: Returns query object, Moopa must serialize --->
<cffunction name="load">
    <cfquery name="qData">SELECT * FROM my_table</cfquery>
    <cfreturn qData />
</cffunction>
```

## Escaping Hash Signs

In CFML, `#` is used for variable interpolation. Use `##` to output a literal `#` character:

| Context | Syntax | Output |
|---------|--------|--------|
| Variable | `#name#` | Value of `name` |
| Literal hash | `##` | `#` |
| CSS color | `color: ##ff0000;` | `color: #ff0000;` |
| HTML anchor | `href="##section"` | `href="#section"` |

```cfml
<!--- Variable interpolation --->
<cfset var name = "John" />
<p>Hello, #name#</p>    <!--- Outputs: Hello, John --->

<!--- Literal hashes in output --->
<div style="color: ##ff0000;">Red text</div>
<a href="##section">Jump to section</a>
```

## HTTP Method → Function Name Routing

Moopa routes HTTP methods directly to CFC functions with matching names. A `GET` request calls `get()`, a `POST` request calls `post()`, etc. The `req()` helper on the frontend uses the `x-endpoint` URL parameter to override this default, allowing named endpoints like `load`, `save`, `search`.

| HTTP Method | Function Called | How It's Triggered |
|-------------|---------------|-------------------|
| `GET` (no endpoint) | `get()` | Browser navigation, direct URL |
| `POST` (no endpoint) | `post()` | Direct POST (e.g. webhooks, external services) |
| via `req({endpoint: 'load'})` | `load()` | Frontend `req()` adds `?x-endpoint=load` |
| via `req({endpoint: 'save', body: ...})` | `save()` | Frontend `req()` adds `?x-endpoint=save` |

**Key implication:** For webhooks and external callbacks that POST directly (without `x-endpoint`), the function **must** be named `post`, not a custom name like `webhook`:

```cfml
<!--- Webhook route: external service POSTs directly --->
<cfcomponent key="..." open_to="public">
    <cffunction name="post">
        <!--- Handle inbound POST from external service --->
    </cffunction>
</cfcomponent>
```

### Named Endpoints (via req)

For frontend-driven routes, use descriptive function names. The `req()` function passes the endpoint name via `x-endpoint`:

| Endpoint Name | Purpose | Triggered By |
|---------------|---------|-------------|
| `get` | Render HTML page | Browser GET request |
| `load` | Fetch single record or list | `req({endpoint: 'load'})` |
| `save` | Create or update record | `req({endpoint: 'save', body: ...})` |
| `search` | Search with filters | `req({endpoint: 'search', body: ...})` |
| `delete` | Delete record | `req({endpoint: 'delete', body: ...})` |

### Nested Endpoints (Dot Notation)

Use dots to organize related endpoints:

```cfml
<cffunction name="load.agents">
    <!--- Called via endpoint: 'load.agents' --->
</cffunction>

<cffunction name="search.filters.status">
    <!--- Called via endpoint: 'search.filters.status' --->
</cffunction>
```

### Route Initialisation

After adding a new route CFC or renaming/adding functions in an existing route, you must re-initialise the application for Moopa to register the changes. Visit `/init` or restart the app server.

## Frontend API Calls with req()

The `req()` function in `app.js` calls backend endpoints.

### Basic Usage

```javascript
// GET request (no body)
const data = await req({ endpoint: 'load' });

// POST request (body present)
const result = await req({ 
    endpoint: 'save', 
    body: { name: 'John', email: 'john@example.com' } 
});
```

### Method Detection

- **No body** → GET request
- **Body present** → POST request

### req() Parameters

| Parameter | Type | Purpose |
|-----------|------|---------|
| `endpoint` | string | Backend function to call (e.g., 'load', 'save') |
| `body` | object | POST data → becomes `request.data` on backend |
| `route` | string | Override URL path (defaults to current page) |
| `q` | string | Search query → becomes `url.q` |
| `id` | string | Record ID → becomes `url.id` |
| `limit` | number | Result limit → becomes `url.limit` |
| `url_params` | object | Additional URL params |

## Data Flow: Frontend → Backend

```
Frontend                          Backend
─────────────────────────────────────────────
req({                            
    endpoint: 'save',            → cffunction name="save"
    body: {                      → request.data
        name: 'John',               request.data.name
        status: 'active'            request.data.status
    }
})
```

### Example: Save Endpoint

**Frontend (Alpine.js):**
```javascript
Alpine.data('edit_form', () => ({
    record: { id: '', name: '', status: 'active' },
    
    async save() {
        await req({ 
            endpoint: 'save', 
            body: this.record 
        });
    }
}));
```

**Backend (CFC):**
```cfml
<cffunction name="save">
    <!--- request.data contains the body from req() --->
    <cfreturn application.lib.db.save(
        table_name = "my_table",
        data = request.data
    ) />
</cffunction>
```

## Dynamic URL Slugs → arguments

For routes with slugs like `[agency_id]`:

**Route file:** `routes/hub/rea/[agency_id]/agency.cfc`
**URL:** `/hub/rea/abc-123/agency/`

```cfml
<cffunction name="load">
    <!--- arguments.agency_id = "abc-123" --->
    <cfquery name="qData">
    SELECT COALESCE(row_to_json(data)::text, '{}') as recordset
    FROM (
        SELECT * FROM rea_agency 
        WHERE id = <cfqueryparam cfsqltype="other" value="#arguments.agency_id#" />
    ) AS data
    </cfquery>
    <cfreturn qData.recordset />
</cffunction>

<cffunction name="delete">
    <!--- Same: arguments.agency_id available --->
    <cfreturn application.lib.db.delete(
        table_name = "rea_agency", 
        id = "#arguments.agency_id#"
    ) />
</cffunction>
```

## Complete CRUD Route Example

```cfml
<cfcomponent key="f47ac10b-58cc-4372-a567-0e02b2c3d479" open_to="security">

    <!--- List all records --->
    <cffunction name="search">
        <cfquery name="qData">
        SELECT COALESCE(array_to_json(array_agg(row_to_json(data)))::text, '[]') AS recordset
        FROM (
            SELECT #application.lib.db.select(table_name="customers", field_list="id,name,email,status")#
            FROM customers
            WHERE 1 = 1
            <cfif len(request.data.filter.status?:'')>
                AND status = <cfqueryparam cfsqltype="varchar" value="#request.data.filter.status#" />
            </cfif>
            <cfif len(request.data.filter.term?:'')>
                AND name ILIKE <cfqueryparam cfsqltype="varchar" value="%#request.data.filter.term#%" />
            </cfif>
            ORDER BY name
            LIMIT 100
        ) AS data
        </cfquery>
        <cfreturn qData.recordset />
    </cffunction>

    <!--- Load single record --->
    <cffunction name="load">
        <cfreturn application.lib.db.read(table_name="customers", id=request.data.id) />
    </cffunction>

    <!--- Create new record --->
    <cffunction name="create">
        <cfreturn application.lib.db.save(
            table_name = "customers",
            data = request.data
        ) />
    </cffunction>

    <!--- Save/update record --->
    <cffunction name="save">
        <cfreturn application.lib.db.save(
            table_name = "customers",
            data = request.data
        ) />
    </cffunction>

    <!--- Delete record --->
    <cffunction name="delete">
        <cfreturn application.lib.db.delete(
            table_name = "customers",
            id = request.data.id
        ) />
    </cffunction>

    <!--- Render page (no return = outputs HTML) --->
    <cffunction name="get">
        <cf_layout_default>
            <div x-data="customers_list" x-cloak>
                <!-- UI here -->
            </div>

            <script>
            document.addEventListener('alpine:init', () => {
                Alpine.data('customers_list', () => ({
                    records: [],
                    filters: { term: '', status: '' },
                    loading: false,

                    async init() {
                        await this.load();
                    },

                    async load() {
                        this.loading = true;
                        this.records = await req({ 
                            endpoint: 'search', 
                            body: { filter: this.filters } 
                        });
                        this.loading = false;
                    },

                    async save(record) {
                        await req({ endpoint: 'save', body: record });
                        await this.load();
                    },

                    async remove(record) {
                        await req({ endpoint: 'delete', body: { id: record.id } });
                        await this.load();
                    }
                }));
            });
            </script>
        </cf_layout_default>
    </cffunction>

</cfcomponent>
```

## File Upload Endpoint

Any route that renders a form with an editable file field needs a per-field upload handler. The canonical pattern is a one-line delegation to the moo_file table service — never reinvent the upload pipeline, because the table service is what wires up the signed Cloudflare Worker thumbnail URL.

```cfml
<!--- Pattern: uploadFileToServerWithProgress.<field_id> --->
<cffunction name="uploadFileToServerWithProgress.profile_picture_id">
    <cfreturn application.lib.db.getService(table_name="moo_file").uploadFileToServerWithProgress(data="#request.data#") />
</cffunction>
```

The function name suffix (`profile_picture_id`) must match the field id used in the form — Alpine's file control posts to `endpoint: 'uploadFileToServerWithProgress.<field_id>'` so a single route can host several upload fields without colliding.

The implementation lives in `code/moopa/tables/moo_file.cfc` `uploadFileToServerWithProgress`. It runs in two legs (presign + finalise), signs the resulting thumbnail via `application.lib.cloudflare.signed_asset_url(..., kind='i', ...)`, and writes the signed URL into `moo_file.thumbnail`. Don't write your own version of this — see Blute/moopa#6 for the framework-level concern about the asset signer being implicit.

## Self-Edit Profile Recipe

Different shape from the CRUD example: the logged-in user edits their *own* record, not one identified by a URL slug.

```cfml
<cfcomponent key="<uuidgen>" open_to="logged_in">

    <!--- Upload handler for the user's profile picture --->
    <cffunction name="uploadFileToServerWithProgress.profile_picture_id">
        <cfreturn application.lib.db.getService(table_name="moo_file").uploadFileToServerWithProgress(data="#request.data#") />
    </cffunction>

    <!--- Load — uses session.auth.profile.id, not request.data.id --->
    <cffunction name="load">
        <cfset var profileId = session.auth.profile.id />
        <cfquery name="qProfile">
            SELECT COALESCE(row_to_json(data)::text, '{}') as recordset
            FROM (
                SELECT p.id::text, p.full_name, p.email, p.mobile,
                       signed_asset_url(mf.path, 'NEVER', 'i', 'width=240&height=240&fit=cover') AS picture_url
                FROM moo_profile p
                LEFT JOIN moo_file mf ON mf.id = p.profile_picture_id
                WHERE p.id = <cfqueryparam cfsqltype="other" value="#profileId#" />
            ) AS data
        </cfquery>
        <cfreturn qProfile.recordset />
    </cffunction>

    <!--- Save — same. Refresh session.auth.profile so the layout picks up changes --->
    <cffunction name="save">
        <cfset var profileId = session.auth.profile.id />
        <cfset var saveData = { id = profileId } />

        <!--- Allow-list editable fields explicitly; never pass request.data straight through --->
        <cfif structKeyExists(request.data, "full_name")>
            <cfset saveData.full_name = trim(request.data.full_name) />
        </cfif>
        <cfif structKeyExists(request.data, "mobile")>
            <cfset saveData.mobile = trim(request.data.mobile) />
        </cfif>

        <cfset application.lib.db.save(table_name="moo_profile", data=saveData) />

        <!--- Refresh the session profile so the hub layout/avatar picks up the change without re-login --->
        <cfset session.auth.profile = application.lib.db.read(
            table_name = "moo_profile",
            id = profileId,
            field_list = "id,full_name,email,mobile,auth_type,profile_avatar_id,profile_picture_id,can_login,roles",
            returnAsCFML = true
        ) />

        <cfreturn { success: true } />
    </cffunction>

</cfcomponent>
```

Two points worth stressing:

1. **Allow-list fields on save.** Don't `data = request.data` — it lets the browser write fields the user shouldn't be editing (`can_login`, `roles`, `external_auth_id`). Copy each editable field explicitly into a fresh `saveData` struct.
2. **Refresh `session.auth.profile` after save.** The hub layout reads from the session, not from the DB on every render, so without the refresh the avatar/name in the bottom-left menu stays stale until the user logs out and back in.

Existing implementations to crib from: `code/project/routes/easy/profile.cfc` (gday), `code/project/routes/agent/profile.cfc` (agent), `code/project/routes/hub/profile.cfc` (hub).

## Frontend Patterns with Alpine.js

### Loading Data on Init

```javascript
Alpine.data('my_page', () => ({
    record: {},
    loading: true,

    async init() {
        this.record = await req({ endpoint: 'load' });
        this.loading = false;
    }
}));
```

### Parallel Data Loading

```javascript
async init() {
    this.loading = true;
    const [mainData, relatedData] = await Promise.all([
        req({ endpoint: 'load' }),
        req({ endpoint: 'load.related' })
    ]);
    this.record = mainData;
    this.related = relatedData;
    this.loading = false;
}
```

### Search with Filters

```javascript
async applyFilters() {
    this.loading = true;
    this.records = await req({ 
        endpoint: 'search', 
        body: { filter: this.filters } 
    });
    this.loading = false;
}
```

### Typeahead/Autocomplete Search

```javascript
async searchItems(term) {
    return await req({ 
        endpoint: 'search.items', 
        q: term,  // Available as url.q on backend
        limit: 10 
    });
}
```

## Returning Custom Responses

### Success/Error Object

```cfml
<cffunction name="toggle">
    <cfif someCondition>
        <cfreturn {
            "success": true,
            "action": "added",
            "message": "Record added successfully"
        } />
    <cfelse>
        <cfreturn {
            "success": false,
            "message": "Operation failed"
        } />
    </cfif>
</cffunction>
```

### With New Record ID

```cfml
<cffunction name="create">
    <cfset var newRecord = application.lib.db.save(
        table_name = "my_table",
        data = request.data,
        returnAsCFML = true
    ) />
    <cfreturn {
        "success": true,
        "id": newRecord.id,
        "message": "Created successfully"
    } />
</cffunction>
```

## Quick Reference: Accessing Data

| Frontend | Backend |
|----------|---------|
| `body: { name: 'John' }` | `request.data.name` |
| `body: { filter: { status: 'active' } }` | `request.data.filter.status` |
| URL slug `[id]` | `arguments.id` |
| `q: 'search term'` | `url.q` |
| `id: 'abc-123'` | `url.id` |
| `limit: 50` | `url.limit` |

## Null-Safe Access Pattern

Use Elvis operator for optional data:

```cfml
<cfset var status = request.data.filter.status ?: '' />
<cfset var limit = url.limit ?: 100 />
<cfset var term = request.data.term ?: '' />
```
