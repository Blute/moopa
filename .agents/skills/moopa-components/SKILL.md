---
name: moopa-components
description: Write form fields, pickers, uploads and admin lists inline on a Moopa page with the Alpine components in moopa.js (numberInput, currencyInput, comboSingle, comboMany, addressSearch, fileUpload, adminList and the rest). Use when building or changing a page's form or list markup, replacing a cf_control / cf_table_controls form, or when a page needs search-as-you-type, chips, drag-to-sort, file upload or formatted numbers.
---

# Moopa Components

Moopa's `static/moopa.js` is the one JavaScript library a Moopa page needs. Beside `req()` and `toast()` it registers **components**: `Alpine.data()` factories that own behaviour (search, formatting, selection, upload) and nothing visual. The page writes the markup inline, with Moopa's classes (`docs/design.md`), and binds each component to its own model.

This is how new pages are built. Forms are written out in the route: no `<cf_control>`, no `<cf_table_controls>`, no per-project `controls.js`. The `cf_control` path (the `moopa-controls` skill) stays for older projects only.

**See them live:** System → Components (`/sysadmin/components`) shows every component working, its bound value and the markup to copy. System → Theme shows the look of each piece.

## Rules

- **Markup is the page's; behaviour is Moopa's.** Copy the markup below and change ids, labels and the model. Keep the class names (`combo`, `combo-shell`, `dropzone`, `file-item`…) so `moopa.css` styles it.
- **Bind with `x-modelable` + `x-model`.** The component's value (`value`, `selected`, `items` or `files`) is exposed with `x-modelable`, and `x-model` ties it to the page's model: `x-data="comboSingle({...})" x-modelable="selected" x-model="form.customer_id"`.
- **`moopa.js` loads before Alpine.** `moopa_layout` does this. A project layout must load `system.staticUrl('moopa.js')` before Alpine's deferred script, or the components never register.
- **Page workflow stays on the page.** A page's own state, saving and dialogs are its own `x-data` or an `Alpine.data()` in a `<script>` in the route (the `moopa-routes` skill). A page can listen for a component's events (`@model-change="save()"`).
- **Missing behaviour goes into Moopa.** If a page needs a component that does not exist, or a component lacks an option, add it to `moopa.js` in a Moopa pull request, with its section on the Components page and here. Do not copy a component into a project or write a project-wide copy of one.
- **Fail loudly.** Components throw when a dependency is missing (Trix, SortableJS, a Maps key). Do not catch and hide it.
- **Icons are Font Awesome Free** in Moopa's examples (`fa-solid`). A project with its own kit may use its own styles.

## Endpoints

An `endpoint` option is the name of an endpoint on the current route, or the object `application.lib.auth.signedEndpoint(route=..., endpoint=...)` returns, to call another route.

| Kind | Request | Answer |
|---|---|---|
| Search | `req({ endpoint, q, limit, exclude_ids })`, so `url.q`, `url.limit`, `url.exclude_ids` (comma-joined) | `[{ id, label, disabled?, ...extra }]` |
| Address | `req({ endpoint, q })` | `{ suggestions: [{ formatted_address, ... }] }` |
| Upload | presign `{ file_name, file_size, parent_table_name, parent_field, parent_id }`, then finalise `{ file_id }` | `{ presignedURL, file }`, then the file record |

Search endpoints are named `search.<field>`, upload endpoints `uploadFileToServerWithProgress.<field>`:

```cfml
<cffunction name="search.customer_id">
    <cfquery name="local.rows" returntype="array">
        SELECT id, name AS label FROM customer
        WHERE name ILIKE <cfqueryparam value="%#url.q ?: ''#%">
        <cfif len(url.exclude_ids ?: "")>AND NOT id = ANY(string_to_array(<cfqueryparam value="#url.exclude_ids#">, ',')::uuid[])</cfif>
        ORDER BY name LIMIT <cfqueryparam value="#val(url.limit ?: 20)#" cfsqltype="integer">
    </cfquery>
    <cfreturn local.rows />
</cffunction>

<cffunction name="uploadFileToServerWithProgress.attachments">
    <cfreturn application.lib.db.getService(table_name="moo_file").uploadFileToServerWithProgress(data=request.data) />
</cffunction>
```

## Components

| Component | Model | For |
|---|---|---|
| `numberInput({ min, max, places })` | number or null | a formatted number |
| `currencyInput({ places })` | number or null | money, two places by default |
| `percentInput({ places })` | fraction (`0.225` shows `22.5`) | a percentage |
| `checkboxList([[value, text], ...])` | comma-joined string | several of a fixed list |
| `dateQuick()` | `yyyy-mm-dd` (local date) | a date with quick picks |
| `datetimeUtc()` | ISO string in UTC | a date and time |
| `comboSingle({ endpoint, placeholder, limit, groupBy, request })` | option or null | one record, searched |
| `comboMany({ endpoint, placeholder, limit, request })` | array of options | several records, as chips |
| `sortList({ endpoint, limit })` | ordered array of `{ id, label }` | an ordered many, drag to sort |
| `addressSearch({ endpoint })` | suggestion or null | an address from the project's own lookup |
| `addressGoogle({ key, country, language, bias })` | place or null | an address from Google Places |
| `emailRecipients()` | comma-joined string | email addresses as chips |
| `fileUpload({ endpoint, table, field, parentId })` | array of finished files | uploads with progress |
| `richText()` | HTML string | Trix, loaded by the page |
| `sortableRows({ endpoint \| onMove, handle, row, enabled })` | none | drag table rows, SortableJS loaded by the page |
| `adminList({ endpoints, filters, blank, persist })` | none (owns `records`) | a simple admin screen |

`autosize(el)` is a plain function: `<textarea class="textarea textarea-auto" x-init="$nextTick(() => autosize($el))" @input="autosize($el)">`.

Plain fields need no component: `<input class="input" x-model="form.name">`, `<select class="select" x-model="form.status">`, `<label class="option"><input type="checkbox" class="switch" x-model="form.is_active"> Active</label>`.

### Numbers

```html
<div class="field" x-data="numberInput({ min: 0, max: 9999, places: 0 })" x-modelable="value" x-model="form.qty">
    <label class="label" for="qty">Quantity</label>
    <input id="qty" class="input input-narrow text-right" type="text" inputmode="numeric"
           :value="display()" @change="commit($event.target.value)" @focus="$el.select()">
</div>

<div class="field" x-data="currencyInput()" x-modelable="value" x-model="form.price">
    <label class="label" for="price">Unit price</label>
    <div class="input-group input-narrow">
        <span class="input-addon">$</span>
        <input id="price" class="input text-right money" type="text" inputmode="decimal"
               :value="display()" @change="commit($event.target.value)" @focus="$el.select()">
    </div>
</div>
```

`percentInput()` is the same with `<span class="input-addon">%</span>` after the input.

### Checkbox group

```html
<div class="field" x-data="checkboxList([['quote', 'Quote'], ['order', 'Order'], ['invoice', 'Invoice']])" x-modelable="value" x-model="form.copies">
    <span class="label">Send copies of</span>
    <div class="option-box">
        <template x-for="[val, text] in options" :key="val">
            <label class="option"><input type="checkbox" class="checkbox" :checked="has(val)" @change="toggle(val)"> <span x-text="text"></span></label>
        </template>
    </div>
</div>
```

### Dates

```html
<div class="field" x-data="dateQuick()" x-modelable="value" x-model="form.due">
    <label class="label" for="due">Due date</label>
    <div class="input-group">
        <input id="due" class="input" type="date" x-model="value">
        <details class="dropdown">
            <summary class="btn btn-icon" aria-label="Quick pick"><i class="fa-solid fa-calendar-days"></i></summary>
            <div class="dropdown-menu dropdown-menu-end">
                <button type="button" class="dropdown-item" @click="set(0); $el.closest('details').open = false">Today</button>
                <button type="button" class="dropdown-item" @click="set(7); $el.closest('details').open = false">In a week</button>
                <button type="button" class="dropdown-item" @click="set(1, 'month'); $el.closest('details').open = false">In a month</button>
            </div>
        </details>
    </div>
</div>

<div class="field" x-data="datetimeUtc()" x-modelable="value" x-model="form.starts_at">
    <label class="label" for="starts">Starts</label>
    <input id="starts" class="input" type="datetime-local" :value="toLocal()" @change="fromLocal($event.target.value)">
</div>
```

### Combobox, one

The model is the chosen option, `{ id, label, ... }`. To save a foreign key, send `form.customer_id?.id`, or let `db.save()` take the option. `groupBy` is a path into each option that heads runs of options. `request: () => ({ body: { model_record: form } })` adds parameters read at every search (a dependent field). Choosing dispatches `model-change` with `detail.selected_option`.

```html
<div class="field" x-data="comboSingle({ endpoint: 'search.customer_id', placeholder: 'Search customers…' })"
     x-modelable="selected" x-model="form.customer_id">
    <label class="label" for="customer">Customer</label>
    <div class="combo" @keydown.escape.prevent="close()" @click.outside="close()">
        <div class="combo-shell" @click="$refs.input.focus()">
            <input id="customer" x-ref="input" type="text" autocomplete="off" :placeholder="placeholder"
                   :value="open ? query : (selected?.label ?? '')"
                   @focus="openList()" @input="query = $event.target.value; search()"
                   @keydown.down.prevent="move(1)" @keydown.up.prevent="move(-1)" @keydown.enter.prevent="choose(options[active])" @keydown.tab="close()">
            <div class="combo-tools">
                <i class="fa-solid fa-spinner fa-spin" x-show="loading"></i>
                <button type="button" x-show="selected && !loading" @click.stop="clear()" aria-label="Clear"><i class="fa-solid fa-xmark"></i></button>
                <button type="button" @click.stop="open ? close() : openList()" aria-label="Show options"><i class="fa-solid fa-chevron-down"></i></button>
            </div>
        </div>
        <ul class="combo-list" x-show="open" x-cloak>
            <template x-for="row in grouped()" :key="row.key">
                <li>
                    <div class="combo-group" x-show="row.group !== undefined" x-text="row.group"></div>
                    <div class="combo-option" :class="{ 'is-active': row.index === active, 'is-selected': selected?.id === row.item.id, 'is-disabled': row.item.disabled }"
                         @mouseenter="active = row.index" @click="choose(row.item)"><span x-text="row.item.label"></span></div>
                </li>
            </template>
            <li class="combo-empty" x-show="!loading && !options.length">No matches</li>
        </ul>
    </div>
</div>
```

### Combobox, many

The model is an array of options; the search leaves out those chosen. For a many-to-many field, `db.save()` on the parent takes the array of ids (`moopa-table-definitions`).

```html
<div class="field" x-data="comboMany({ endpoint: 'search.tag_ids', placeholder: 'Add a tag…' })" x-modelable="selected" x-model="form.tag_ids">
    <label class="label" for="tags">Tags</label>
    <div class="combo" @keydown.escape.prevent="close()" @click.outside="close()">
        <div class="combo-shell" @click="$refs.input.focus()">
            <template x-for="item in selected" :key="item.id">
                <span class="combo-chip"><span x-text="item.label"></span><button type="button" @click.stop="remove(item)" aria-label="Remove"><i class="fa-solid fa-xmark"></i></button></span>
            </template>
            <input id="tags" x-ref="input" type="text" autocomplete="off" :placeholder="placeholder" x-model="query"
                   @focus="openList()" @input="search()"
                   @keydown.down.prevent="move(1)" @keydown.up.prevent="move(-1)" @keydown.enter.prevent="choose(options[active])"
                   @keydown.backspace="if (!query && selected.length) remove(selected[selected.length - 1])">
            <div class="combo-tools"><i class="fa-solid fa-spinner fa-spin" x-show="loading"></i></div>
        </div>
        <ul class="combo-list" x-show="open" x-cloak>
            <template x-for="(item, i) in options" :key="item.id">
                <li class="combo-option" :class="{ 'is-active': i === active }" @mouseenter="active = i" @click="choose(item)"><span x-text="item.label"></span></li>
            </template>
            <li class="combo-empty" x-show="!loading && !options.length">No matches</li>
        </ul>
    </div>
</div>
```

### Ordered list

Drag to reorder with the browser's own drag and drop; search to add. `remove(i)` takes the index.

```html
<div class="field" x-data="sortList({ endpoint: 'search.contact_ids' })" x-modelable="items" x-model="form.contact_ids">
    <span class="label">Contacts, in order</span>
    <ul class="sort-list">
        <template x-for="(item, i) in items" :key="item.id">
            <li class="sort-item" draggable="true" :class="{ 'is-dragging': dragging === i }"
                @dragstart="dragging = i" @dragover.prevent @drop.prevent="dropOn(i)" @dragend="dragging = null">
                <i class="fa-solid fa-grip-vertical grip"></i>
                <span class="grow truncate" x-text="item.label"></span>
                <button type="button" class="btn btn-ghost btn-icon btn-xs" @click="remove(i)" aria-label="Remove"><i class="fa-solid fa-xmark"></i></button>
            </li>
        </template>
        <li class="sort-item muted" x-show="!items.length">None yet</li>
    </ul>
    <div class="combo" style="margin-top: var(--sp-2)" @click.outside="open = false">
        <div class="combo-shell is-sm">
            <input type="text" placeholder="Search to add…" x-model="query" @focus="search()" @input="search()">
            <div class="combo-tools"><i class="fa-solid fa-spinner fa-spin" x-show="loading"></i></div>
        </div>
        <ul class="combo-list" x-show="open" x-cloak>
            <template x-for="o in options" :key="o.id"><li class="combo-option" :class="{ 'is-disabled': o.disabled }" @click="add(o)"><span x-text="o.label"></span></li></template>
            <li class="combo-empty" x-show="!loading && !options.length">No matches</li>
        </ul>
    </div>
</div>
```

### Address

`addressSearch({ endpoint })` asks the page's own endpoint (a proxy to the lookup service the project uses). `addressGoogle({ key, country: 'au', bias: { lat, lng, radius } })` asks Google Places from the browser with the project's Maps key, and its model is `{ place_id, name, formatted_address, geometry: { location: { lat, lng } }, state, postcode, suburb }`. The markup is the same for both; Google's options are keyed by `place_id`.

```html
<div class="field" x-data="addressSearch({ endpoint: 'search.address' })" x-modelable="value" x-model="form.address">
    <label class="label" for="address">Delivery address</label>
    <div class="combo" @keydown.escape.prevent="close()" @click.outside="close()">
        <div class="combo-shell" @click="$refs.input.focus()">
            <input id="address" x-ref="input" type="text" autocomplete="off" placeholder="Start typing an address…"
                   :value="open ? query : (value?.formatted_address ?? '')"
                   @focus="open = true" @input="query = $event.target.value; search()" @keydown.tab="close()">
            <div class="combo-tools">
                <i class="fa-solid fa-spinner fa-spin" x-show="loading"></i>
                <button type="button" x-show="value && !loading" @click.stop="clear()" aria-label="Clear"><i class="fa-solid fa-xmark"></i></button>
            </div>
        </div>
        <ul class="combo-list" x-show="open && (options.length || (query && !loading))" x-cloak>
            <template x-for="s in options" :key="s.formatted_address"><li class="combo-option" @click="pick(s)"><span x-text="s.formatted_address"></span></li></template>
            <li class="combo-empty" x-show="!loading && !options.length">No matching addresses</li>
        </ul>
    </div>
</div>
```

The Maps key goes in from the environment, never written into code: `x-data="addressGoogle({ key: '#encodeForJavaScript(server.system.environment.GOOGLE_MAP_API_KEY)#' })"` inside `<cfoutput>`.

### Email addresses

```html
<div class="field" x-data="emailRecipients()" x-modelable="value" x-model="form.to">
    <label class="label" for="to">To</label>
    <div class="cluster" x-show="addresses().length">
        <template x-for="email in addresses()" :key="email">
            <span class="chip"><span x-text="email"></span><button type="button" @click="remove(email)" aria-label="Remove"><i class="fa-solid fa-xmark"></i></button></span>
        </template>
    </div>
    <input id="to" class="input" x-model="query" placeholder="name@example.com"
           @keydown.enter.prevent="add()" @keydown.comma.prevent="add()" @blur="add()" @paste.prevent="add($event.clipboardData.getData('text'))">
    <span class="help text-danger" x-show="query && !valid(query)">Not an email address</span>
</div>
```

### File upload

`table`, `field` and `parentId` name the record the files belong to. The model holds finished uploads only. `rows()` lists finished, uploading and removed files for display; `remove(f)` and `restore(f)` undo, `retry(f)` and `dismiss(f)` handle a failed upload. It dispatches `files-uploading`, `file-uploaded` (`detail.file`) and `files-uploaded`, so a page can save when a batch is done (`@files-uploaded="save()"`). A failed upload raises a toast. Keep the file input in the zone (the `dropzone` class hides it), so the keyboard reaches it.

```html
<div class="field" x-data="fileUpload({ endpoint: 'uploadFileToServerWithProgress.attachments', table: 'job', field: 'attachments', parentId: job.id })"
     x-modelable="files" x-model="form.attachments">
    <span class="label">Attachments</span>
    <label class="dropzone" :class="{ 'is-over': over, 'is-busy': uploading }"
           @dragenter.prevent="dragEnter()" @dragover.prevent @dragleave="dragLeave()" @drop.prevent="drop($event)">
        <i class="fa-solid fa-cloud-arrow-up"></i>
        <span x-show="!uploading"><strong>Choose files</strong> or drop them here</span>
        <span x-show="uploading" x-text="busyText()"></span>
        <input type="file" multiple :disabled="uploading" @change="add($event.target.files); $event.target.value = ''">
    </label>
    <ul class="file-list" x-show="rows().length">
        <template x-for="f in rows()" :key="f.id">
            <li class="file-item" :class="{ 'is-removed': f.removed, 'is-error': f.status === 'error' }">
                <span class="file-icon"><i class="fa-solid" :class="icon(f)"></i></span>
                <span class="file-body">
                    <button type="button" class="file-name truncate" x-text="label(f)" :title="label(f)" :disabled="!canPreview(f)"></button>
                    <span class="file-meta" x-show="meta(f)" x-text="meta(f)"></span>
                </span>
                <span class="file-status">
                    <template x-if="f.status === 'uploading'"><span class="progress"><span :style="'width:' + f.progress + '%'"></span></span></template>
                    <span x-show="f.status === 'uploading'" x-text="f.progress + '%'"></span>
                    <span class="badge badge-danger" x-show="f.status === 'error'">Failed</span>
                    <span class="badge" x-show="f.removed">Removed</span>
                </span>
                <span class="file-actions">
                    <template x-if="f.status === 'error'">
                        <span class="file-actions">
                            <button type="button" class="btn btn-ghost btn-icon btn-sm" @click="retry(f)" :disabled="uploading" aria-label="Retry"><i class="fa-solid fa-rotate-right"></i></button>
                            <button type="button" class="btn btn-ghost btn-icon btn-sm" @click="dismiss(f)" :disabled="uploading" aria-label="Dismiss"><i class="fa-solid fa-xmark"></i></button>
                        </span>
                    </template>
                    <template x-if="f.status !== 'error'">
                        <button type="button" class="btn btn-ghost btn-icon btn-sm" @click="f.removed ? restore(f) : remove(f)" :disabled="uploading || f.status === 'uploading'"
                                :aria-label="f.removed ? 'Restore' : 'Remove'"><i class="fa-solid" :class="f.removed ? 'fa-rotate-left' : 'fa-trash'"></i></button>
                    </template>
                </span>
            </li>
        </template>
    </ul>
</div>
```

### Rich text

Load Trix once in the route (its CSS and script). Each editor needs its own input id. Only the user's edits dispatch `model-change` (`detail.value`); loading a value does not, so an autosave never fires on load.

```html
<div class="field" x-data="richText()" x-modelable="value" x-model="form.message">
    <label class="label" for="message">Message</label>
    <input id="message-value" x-ref="input" type="hidden">
    <trix-editor id="message" input="message-value" x-ref="editor" class="textarea"
                 @trix-initialize="sync()" @trix-change="change()" @trix-file-accept.prevent></trix-editor>
</div>
```

### Sortable rows

Load SortableJS once in the route. Put the component on the rows' parent; each row has `data-id`. With `endpoint`, a drop posts `{ ids: 'a,b,c' }`. With `onMove: (oldIndex, newIndex) => ...` instead, Sortable's change is undone and the page moves the item in its own array, so an `x-for` list stays the one source of the order. `enabled` is read reactively.

```html
<tbody x-data="sortableRows({ endpoint: 'sortLines', handle: '.line-handle', row: '.line-row', enabled: () => !locked })">
    <template x-for="line in lines" :key="line.id">
        <tr class="line-row" :data-id="line.id">
            <td><button type="button" class="btn btn-ghost btn-icon btn-xs line-handle" aria-label="Move"><i class="fa-solid fa-grip-vertical"></i></button></td>
            <td x-text="line.description"></td>
        </tr>
    </template>
</tbody>
```

### Admin list

A simple admin screen: filtered records, an edit dialog and a delete dialog. State: `records`, `filters` (every change reloads), `current_record`, `action_status` (`'Loading…'`, `'Saving…'`, `'Deleting…'` or `''`) and `error` (the server's message from a failed save or delete). Methods: `load()`, `resetFilters()`, `openNew()`, `openEdit(record)`, `closeEdit()`, `save()`, `openDelete(record)`, `confirmDelete()`.

The route's endpoints: `load` (`request.data.filters`, returns the array), `new` (a blank record; or pass `blank: () => ({ ... })`), optional `read` (`url.id`, the full record before editing), `save` (the record) and `delete` (`url.id`). Rename any with `endpoints: { load: 'list' }`. `persist: 'key'` keeps the filters for the browser tab.

```html
<div class="card" x-data="adminList({ persist: 'admin-kinds', blank: () => ({ name: '' }) })">
    <div class="card-header">
        <input class="input input-sm" type="search" placeholder="Search" x-model.debounce.300ms="filters.term">
        <button type="button" class="btn btn-sm btn-primary" @click="openNew()"><i class="fa-solid fa-plus"></i> New</button>
    </div>
    <div class="table-wrap">
        <table class="table table-sm table-hover">
            <tbody>
                <template x-for="item in records" :key="item.id">
                    <tr @click="openEdit(item)"><td x-text="item.name"></td>
                        <td class="text-right"><button type="button" class="btn btn-ghost btn-icon btn-xs" @click.stop="openDelete(item)" aria-label="Delete"><i class="fa-solid fa-trash"></i></button></td></tr>
                </template>
            </tbody>
        </table>
    </div>
    <dialog class="modal" x-ref="editDialog" @close="error = ''">
        <div class="field"><label class="label" for="kind-name">Name</label><input id="kind-name" class="input" x-model="current_record.name"></div>
        <div class="alert alert-danger" x-show="error" x-text="error"></div>
        <button type="button" class="btn" @click="closeEdit()">Cancel</button>
        <button type="button" class="btn btn-primary" @click="save()" :disabled="!!action_status">Save</button>
    </dialog>
    <dialog class="modal" x-ref="deleteDialog">
        <p>Delete <strong x-text="current_record.name"></strong>?</p>
        <button type="button" class="btn" @click="$refs.deleteDialog.close()">Cancel</button>
        <button type="button" class="btn btn-danger-solid" @click="confirmDelete()" :disabled="!!action_status">Delete</button>
    </dialog>
</div>
```

A page with more behaviour spreads the factory into its own component:

```html
<script>
document.addEventListener('alpine:init', () => {
    Alpine.data('people', () => ({
        ...adminList({ endpoints: { read: 'read' }, filters: () => ({ term: '', role_id: null }), persist: 'admin-people' }),
        resetPassword() { /* … */ }
    }));
});
</script>
```

## Checking a page

Render it in the browser, use each control (search, choose, clear, keyboard, upload), watch the bound value change, and check the console for errors. `node --check static/moopa.js` after changing the library.
