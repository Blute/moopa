---
name: moopa-controls
description: Design, refactor, or debug Moopa form controls. Use when working with cf_control, cf_table_controls, control CFM templates, controls.js Alpine components, table-definition UI metadata, control package overrides, or form rendering conventions.
---

# Moopa Controls

This skill documents the Moopa controls architecture used by Moopa Starter and future bare-bones Moopa projects.

Controls are deliberately split into:

1. **Table metadata** — default field UI behaviour.
2. **CFML custom tags** — server-side form rendering helpers.
3. **Control CFM templates** — markup/config only.
4. **`controls.js`** — reusable Alpine control behaviour.
5. **Route/page code** — page workflow and endpoint implementation.

The goal is a system that is explicit, strict, easy to reason about, and free of hidden runtime magic.

---

## Core Principles

- **Table definitions may define default UI behaviour.** This is a feature, not a smell.
- **Routes must remain readable.** `<cf_table_controls>` is acceptable when it is explicit about table and fields.
- **Controls must fail loudly.** Missing fields, unknown controls, or missing package setup are errors.
- **CFM control templates render markup only.** They must not register Alpine components or inject scripts.
- **Shared browser behaviour lives in `controls.js`.** Alpine components are registered once before Alpine starts.
- **Page workflow belongs to the page.** Controls dispatch events; pages decide what those events mean.
- **No legacy fallbacks.** Controls resolve through `application.moopa_packages`, not hardcoded `/project` paths.
- **No page internals.** Control JavaScript must not inspect `_x_dataStack` or search for arbitrary page components.

---

## Runtime File Map

Core custom tags:

- `/code/moopa/tags/control.cfm`
- `/code/moopa/tags/table_controls.cfm`
- `/code/moopa/tags/once.cfm`

Core control templates:

- `/code/moopa/controls/*.cfm`

Shared control behaviour:

- `/code/www/_static/js/controls.js`
- `/code/www/_static/js/sonner-alpine.js`

Shared UI styles:

- `/code/shared/src/sonner.css`

Generated app CSS:

- `/code/apps/hub/src/app.css`
- `/code/www/_static/css/hub.css`

App script include:

- `/code/apps/hub/tags/app_scripts.cfm`

Table definitions:

- `/code/moopa/tables/*.cfc`
- `/code/shared/tables/*.cfc`
- `/code/apps/{app}/tables/*.cfc`

---

## Architecture Flow

```text
Table definition field metadata
        ↓
<cf_table_controls table_name="..." fields="...">
        ↓
control attributes merged from metadata + call-site config
        ↓
<cf_control ...>
        ↓
package-resolved /controls/{control}.cfm template
        ↓
HTML markup with x-data="registeredControl(...)" if needed
        ↓
/_static/js/controls.js Alpine component
```

---

## Table Definition UI Metadata

Use the existing `html` struct for field-level default UI behaviour.

Example:

```cfml
"status": {
    "type": "varchar",
    "max_length": 20,
    "default": "'draft'",
    "html": {
        "control": "list",
        "label": "Status",
        "placeholder": "Choose a status",
        "list_items": [
            {"value": "draft", "name": "Draft"},
            {"value": "published", "name": "Published"},
            {"value": "archived", "name": "Archived"}
        ]
    }
}
```

Appropriate `html` metadata:

- `control` — preferred explicit control name, e.g. `text`, `combobox`, `file`.
- `type` — input-style alias for simple controls, e.g. `email`, `tel`, `textarea`.
- `label` — field label override.
- `placeholder` — placeholder text.
- `hidden` — skip from generated table controls.
- `multiple` — multiple-value control mode.
- `route` — route for signed control endpoints when needed.
- `endpoint` — endpoint name for control requests.
- `list_items` — static list options.
- `options` — static combobox options when a control supports them.
- control-specific attributes, if they are genuinely reusable field defaults.

Do **not** put these in table definitions:

- modal state names
- page-specific Alpine methods
- page-specific layout decisions
- workflow decisions such as “after save, reload this list”
- one-off route-specific hacks

### Default Type Mapping

The database normalisation layer sets sensible defaults when `html.control` is omitted.
Important defaults include:

| Field type | Default control |
| --- | --- |
| `varchar` | `text` |
| `text` | `textarea` |
| `numeric` | `number` |
| `int2`, `int4`, `int8` | `number` |
| `bool`, `boolean` | `switch` |
| `date` | `date` |
| `timestamptz` | `datetime` |
| non-primary-key `uuid` | `combobox` |
| `jsonb` | `textarea` |
| `many_to_many` | `combobox` with `multiple=true` |
| `relation`, `tsvector` | no rendered control |

---

## `<cf_table_controls>`

Use this tag when a route wants to render explicit fields from a table definition.

```cfml
<cf_table_controls
    table_name="moo_profile"
    fields="full_name,email,mobile,roles"
    model_record="current_record" />
```

With overrides:

```cfml
<cf_table_controls
    table_name="moo_profile"
    fields="full_name,email,roles"
    model_record="current_record"
    config={
        roles: {
            placeholder: "Search roles...",
            endpoint: "search.roles"
        }
    } />
```

Rules:

- `table_name` is required.
- `fields` is required.
- Every requested field must exist in the table definition.
- Missing fields must throw a clear error; never silently skip them.
- `html.hidden=true` fields are not rendered.
- Field metadata is copied from `field.html`.
- The generated `model` is `model_record.field_name`.
- The generated `id` is `table_name_field_name`.
- Call-site `config[field_name]` overrides table metadata.
- Rendering delegates to `<cf_control>`.

### New Form Records

When a route prepares a new record for a `<cf_table_controls>` form, use `returnFormat="cfml"` if the server will modify the object before returning it. `db.getNewObject()` returns serialized JSON by default.

Preferred pattern:

```cfml
<cffunction name="new">
    <cfreturn application.lib.db.getNewObject(
        table_name = "moo_profile",
        data = {
            app_name = application.app_name ?: "hub"
        },
        returnFormat="cfml"
    ) />
</cffunction>
```

Avoid this:

```cfml
<cfset var record = application.lib.db.getNewObject("moo_profile") />
<cfset record.app_name = "hub" />
```

The default return is not safe to mutate server-side and can fail with `Can't assign value to an Object of this type [String] with key [...]`.

### Why `<cf_table_controls>` Is Acceptable

This is good:

```cfml
<cf_table_controls table_name="product" fields="name,status,price" model_record="current_record" />
```

It is explicit about:

- the table
- the fields
- the model binding

This is bad and should not be introduced:

```cfml
<cf_table_controls table_name="product" />
```

because it hides which fields render and invites surprising changes when table definitions change.

---

## `<cf_control>`

`<cf_control>` is the primitive control renderer.

Example:

```cfml
<cf_control
    control="combobox"
    label="Role"
    model="current_record.role_id"
    placeholder="Search roles..."
    endpoint="search.roles" />
```

Responsibilities:

- normalize control names, e.g. `control_text` → `text`, `input_email` → `email`
- build a predictable attribute collection for the control template
- generate a stable `id` if none is provided
- render label/layout wrappers
- resolve the control template through `application.moopa_packages`
- throw if the template cannot be found

Package resolution rules:

- Only packages in `application.moopa_packages` are considered.
- Only packages whose `load` array contains `controls` are considered.
- App packages only apply when their `app_name` matches `application.app_name`.
- Resolution is reverse package order, so app controls override shared/core controls.
- There is no `/project/controls` fallback.

---

## Tailwind/daisyUI Source Scanning

Moopa Starter uses Tailwind v4 with daisyUI. Tailwind only emits classes it can discover from configured sources.

Because core Moopa routes and controls live outside the app package, app CSS must source-scan core/shared CFML as well as app CFML. Otherwise daisyUI classes like `btn`, `card`, `input`, `select`, `table`, `checkbox`, and `badge` can disappear from generated CSS, making forms look unstyled.

For the Hub app, `/code/apps/hub/src/app.css` should source-scan:

```css
@source "../routes/**/*.cfc";
@source "../tags/**/*.cfm";
@source "../controls/**/*.cfm";
@source "../../../moopa/**/*.cfc";
@source "../../../moopa/**/*.cfm";
@source "../../../shared/**/*.cfc";
@source "../../../shared/**/*.cfm";

```

The frontend asset watcher container must mount every directory referenced by these `@source` rules. If `/code/moopa` is not mounted into the watcher, classes used only by Moopa core routes/controls will not be emitted.

Hub CSS should also import shared Sonner toast styles:

```css
@import "../../../shared/src/sonner.css";
```

Use Sonner toasts for transient success/error feedback instead of inline alerts that permanently take up layout space.

After changing sources or control markup, rebuild CSS:

```bash
npm run build:hub
```

Then verify generated CSS contains the expected daisyUI components before debugging markup.

## Control CFM Templates

Control templates live in package `controls/` directories.

Example path:

```text
/code/moopa/controls/text.cfm
/code/apps/hub/controls/custom_picker.cfm
```

Control templates should:

- render markup only
- accept attributes using `cfparam`
- use `x-model` or `x-modelable` consistently
- pass configuration into an Alpine component via `x-data` when needed
- avoid script tags
- avoid registering Alpine components
- avoid reaching into page-level state except through explicit attributes/events

Example simple control:

```cfml
<cfif thisTag.executionMode EQ "start">
    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.class" default="input w-full" />
    <cfparam name="attributes.placeholder" default="" />
    <cfparam name="attributes.id" default="" />

    <cfoutput>
        <input
            type="text"
            class="#attributes.class#"
            placeholder="#attributes.placeholder#"
            x-model="#attributes.model#"
            <cfif len(attributes.id)>id="#attributes.id#"</cfif>
        >
    </cfoutput>
</cfif>
```

Example Alpine-backed control template:

```cfml
<cfif thisTag.executionMode EQ "start">
    <cfparam name="attributes.model" default="" />
    <cfparam name="attributes.placeholder" default="Select..." />

    <cfoutput>
        <div
            x-data="moopaCombobox({ placeholder: '#attributes.placeholder#' })"
            x-modelable="value"
            x-model="#attributes.model#"
        >
            <!-- markup only -->
        </div>
    </cfoutput>
</cfif>
```

The `moopaCombobox` component must be defined in `controls.js`, not in this CFM template.

---

## `controls.js`

`controls.js` owns reusable Alpine components for form controls.

It should:

- register on `document.addEventListener('alpine:init', ...)`
- guard against duplicate registration
- define reusable control components only
- keep component names stable and descriptive
- use `x-modelable` for control value binding
- clean up global event listeners in `destroy()`
- dispatch events for page-level actions
- avoid direct dependency on route/page component names

Example skeleton:

```javascript
document.addEventListener('alpine:init', () => {
    Alpine.data('exampleControl', (config = {}) => ({
        value: null,
        config,
        documentClickHandler: null,

        init() {
            this.documentClickHandler = (event) => {
                if (!this.$el.contains(event.target)) {
                    // close dropdown, etc.
                }
            };
            document.addEventListener('click', this.documentClickHandler);
        },

        destroy() {
            if (this.documentClickHandler) {
                document.removeEventListener('click', this.documentClickHandler);
                this.documentClickHandler = null;
            }
        }
    }));
});
```

### Events Over Page Internals

Controls should dispatch events instead of calling page methods directly.

Good:

```javascript
this.$dispatch('preview-document', { document_id });
```

Page markup can then choose to handle it:

```html
<div x-data="page" @preview-document="openPreview($event.detail.document_id)">
    ...
</div>
```

Bad:

```javascript
const page = document.querySelector('[x-data*=page]')._x_dataStack[0];
page.openPreview(id);
```

That couples the control to Alpine internals and page naming conventions.

---

## Adding a New Control

When adding a new control, do all of this.

### 1. Decide Whether It Needs Alpine

No Alpine needed:

- simple text input
- email input
- tel input
- static checkbox/switch

Alpine likely needed:

- combobox/search
- date picker
- file upload
- address lookup
- popover/dropdown with keyboard navigation

### 2. Add the CFM Template

Create:

```text
/code/moopa/controls/{control_name}.cfm
```

or app-specific override:

```text
/code/apps/{app}/controls/{control_name}.cfm
```

The template renders markup/config only.

### 3. Add Alpine Component If Needed

Add to:

```text
/code/www/_static/js/controls.js
```

Register on `alpine:init` and use `destroy()` for cleanup.

### 4. Add Table Definition Defaults If Appropriate

For reusable field behaviour:

```cfml
"field_name": {
    "type": "varchar",
    "html": {
        "control": "your_control",
        "label": "Field Name"
    }
}
```

### 5. Render Through `<cf_control>` or `<cf_table_controls>`

Direct:

```cfml
<cf_control control="your_control" model="current_record.field_name" />
```

Table-driven:

```cfml
<cf_table_controls table_name="example" fields="field_name" model_record="current_record" />
```

### 6. Validate

At minimum:

- render a page using the control
- confirm no CFML errors
- confirm no browser console errors
- run `node --check code/www/_static/js/controls.js` after editing JavaScript
- test `x-model` reads/writes correctly
- if the control uses global listeners, confirm `destroy()` removes them

---

## Package Overrides

Apps may override core controls by adding a same-named template to their package controls directory.

Example:

```text
/code/apps/hub/controls/combobox.cfm
```

If the `hub` package is loaded after `moopa`, this app template overrides:

```text
/code/moopa/controls/combobox.cfm
```

Do not add ad-hoc path checks to `cf_control`. Package order is the override mechanism.

---

## Endpoint Conventions

Controls that call the backend should accept explicit endpoint config.

Combobox example:

```cfml
<cf_control
    control="combobox"
    model="current_record.role"
    endpoint="search.roles" />
```

For route-signed endpoints:

```cfml
<cf_control
    control="combobox"
    model="current_record.role"
    route="/security/profiles/"
    endpoint="search.roles" />
```

Rules:

- Control templates may build signed endpoint config server-side.
- Alpine components receive endpoint config as plain data.
- Alpine components call `req(...)` with the supplied config.
- Do not hardcode page routes inside shared control JavaScript.

---

## Form and Filter Layout

Forms and filter bars should not stretch every field to the full page width just because space is available.

Preferred pattern for a filter card:

```html
<div class="card card-border bg-base-100 shadow-sm w-full max-w-5xl">
    <div class="card-body gap-4">
        <div class="flex flex-col gap-4 xl:flex-row xl:items-end">
            <fieldset class="fieldset w-full xl:max-w-xs">
                <!-- short select/input -->
            </fieldset>

            <fieldset class="fieldset w-full xl:max-w-2xl xl:flex-1">
                <!-- longer search/input -->
            </fieldset>

            <div class="flex flex-wrap gap-2">
                <!-- actions -->
            </div>
        </div>
    </div>
</div>
```

Guidelines:

- Put a `max-w-*` on filter cards or form sections unless the content genuinely benefits from full width.
- Short controls such as table/status selects should usually be `xl:max-w-xs` or `xl:max-w-sm`.
- Long text/search controls can be `xl:max-w-2xl` or `xl:flex-1` within a capped parent.
- Data tables and SQL/code panels may use the remaining page width; filter forms generally should not.
- Avoid huge single-line inputs spanning the entire viewport.

## Alpine Scoping Rules

Also read the `alpine` skill when editing Alpine controls.

Key control-specific rules:

- `$refs` only works inside the same `x-data` root.
- Popover/dialog refs must live under the same root as the methods using them.
- Prefer stable DOM for controls with refs.
- Use `x-show` when a referenced element must remain mounted.
- Use `template x-if` only when the control handles mount/unmount safely.
- Clean up document/window listeners in `destroy()`.

---

## Anti-Patterns

Do not introduce these:

```cfml
<!-- Bad: hidden field list -->
<cf_table_controls table_name="product" />
```

```cfml
<!-- Bad: script registration inside control template -->
<cf_once id="my_control_script">
    <script>Alpine.data(...)</script>
</cf_once>
```

```javascript
// Bad: reaching into page component internals
const page = document.querySelector('[x-data*=page]')._x_dataStack[0];
```

```cfml
<!-- Bad: hardcoded legacy fallback path in cf_control -->
<cfif fileExists(expandPath('/project/controls/text.cfm'))>
```

```cfml
<!-- Bad: silently ignoring requested fields -->
<cfif structKeyExists(table.fields, field_name)>
    ...
</cfif>
```

---

## Refactor Checklist

When refactoring an existing control:

- [ ] Move Alpine component registration to `controls.js`.
- [ ] Remove script blocks from the CFM control template.
- [ ] Keep the CFM template focused on markup/config.
- [ ] Keep table metadata defaults intact when they are reusable field behaviour.
- [ ] Replace page-internal calls with events.
- [ ] Add `destroy()` cleanup for global listeners.
- [ ] Run JavaScript syntax validation.
- [ ] Render a page using the control.
- [ ] Check browser console and page errors.
- [ ] Document any intentional behavioural changes.

---

## Current Intentional Behaviour Changes

The file upload control dispatches a `preview-document` event when a preview is requested. It does not search for a page component or call page methods directly.

Pages that support document preview should listen explicitly:

```html
<div x-data="myPage" @preview-document="handleDocumentPreview($event.detail.document_id)">
    ...
</div>
```

This is intentional. It removes coupling to Alpine internals.

---

## Quality Bar

A controls change is not complete until the runtime and the convention both make sense.

Prefer to stop and report a missing architectural capability rather than adding:

- local fallbacks
- silent skips
- page-specific hacks in shared controls
- duplicate Alpine registrations in templates
- undocumented endpoint assumptions
- undocumented behaviour changes
