<cfcomponent key="77293fdc-2a5b-4615-8ce8-0eda3e779394" open_to="security">

    <!---
        System > Components: Moopa's Alpine components (moopa.js), live, with the markup to copy. Each is
        behaviour only: the page writes the markup with moopa.css's classes and binds the component's value to
        its own model. The moopa-components skill is the same contract in words. The endpoints below are stubs
        with made-up data, so the page works without a database or storage.
    --->

    <cffunction name="get">
        <cfset var sections = components() />

        <cfmodule template="/moopa/tags/moopa_layout.cfm" title="Components">
            <style>
                .cx-split > aside { top: var(--sp-6); }
                .cx-nav { display: flex; flex-direction: column; gap: 1px; }
                .cx-nav a { padding: 0.3rem 0.625rem; border-radius: var(--radius-sm); color: var(--ink-secondary); font-size: var(--text-sm); text-decoration: none; }
                .cx-nav a:hover { background: var(--canvas-soft); color: var(--ink); }
                @media (max-width: 1099px) { .cx-nav { flex-direction: row; flex-wrap: wrap; gap: 0.375rem; } .cx-nav a { border: 1px solid var(--hairline); border-radius: 999px; background: var(--canvas); } }
                .cx-section { scroll-margin-top: var(--sp-6); }
                .cx-section + .cx-section { margin-top: var(--sp-8); }
                .cx-section h2 { font-size: var(--text-lg); }
                .cx-section > p { margin-top: 0.25rem; color: var(--ink-mute); font-size: var(--text-sm); max-width: 48rem; }
                .cx-preview { margin-top: var(--sp-3); padding: var(--sp-6); border: 1px solid var(--hairline); border-radius: var(--radius-lg) var(--radius-lg) 0 0; background: var(--surface); }
                .cx-preview > .field, .cx-preview > div > .field { max-width: 28rem; }
                .cx-value { margin: 0; padding: 0.5rem var(--sp-4); border: 1px solid var(--hairline); border-top: 0; background: var(--canvas-cream); color: var(--ink-mute); font-family: var(--font-mono); font-size: var(--text-xs); white-space: pre-wrap; overflow-wrap: anywhere; }
                .cx-code { border: 1px solid var(--hairline); border-top: 0; border-radius: 0 0 var(--radius-lg) var(--radius-lg); background: var(--canvas-cream); }
                .cx-code.is-only { margin-top: var(--sp-3); border-top: 1px solid var(--hairline); border-radius: var(--radius-lg); }
                .cx-code > summary { display: flex; align-items: center; justify-content: space-between; padding: 0.5rem var(--sp-4); color: var(--ink-mute); font-size: var(--text-xs); letter-spacing: 0.06em; text-transform: uppercase; cursor: pointer; list-style: none; }
                .cx-code > summary::-webkit-details-marker { display: none; }
                .cx-code > summary:hover { color: var(--ink); }
                .cx-code .code-block { margin: 0; border-radius: 0 0 var(--radius-lg) var(--radius-lg); max-height: 28rem; }
            </style>

            <cfoutput>
            <div class="page">
                <div class="page-header">
                    <div>
                        <div class="eyebrow">Design</div>
                        <h1>Components</h1>
                        <p class="page-lede">Behaviour for forms and lists, from <code class="code-inline">moopa.js</code>. A page writes the markup with Moopa's classes, like the examples, and binds each component's value to its own model with <code class="code-inline">x-modelable</code> and <code class="code-inline">x-model</code>. The look of each piece is on <a href="/sysadmin/theme">Theme</a>.</p>
                    </div>
                    <div class="page-actions">
                        <a class="btn btn-sm" href="#encodeForHTMLAttribute(application.lib.system.staticUrl('moopa.js'))#" target="_blank"><i class="fa-solid fa-file-code"></i> moopa.js</a>
                    </div>
                </div>

                <div class="split cx-split" style="--split-aside: 12rem">
                    <aside>
                        <nav class="cx-nav" aria-label="Components">
                            <cfloop array="#sections#" index="local.section">
                                <a href="##cx-#local.section.id#">#encodeForHTML(local.section.title)#</a>
                            </cfloop>
                        </nav>
                    </aside>
                    <div>
                        <cfloop array="#sections#" index="local.section">
                            <section class="cx-section" id="cx-#local.section.id#">
                                <h2>#encodeForHTML(local.section.title)# <code class="code-inline">#encodeForHTML(local.section.name)#</code></h2>
                                <p>#local.section.description#</p>
                                <cfif len(local.section.model)>
                                    <div x-data="{ form: #encodeForHTMLAttribute(local.section.model)# }">
                                        <div class="cx-preview">#local.section.html#</div>
                                        <pre class="cx-value" x-text="JSON.stringify(form)"></pre>
                                    </div>
                                </cfif>
                                <details class="cx-code#len(local.section.model) ? '' : ' is-only'#"#len(local.section.model) ? '' : ' open'#>
                                    <summary><span>Markup</span><button type="button" class="btn btn-ghost btn-xs" @click.prevent="navigator.clipboard.writeText($el.closest('details').querySelector('pre').innerText); toast({ type: 'success', message: 'Copied' })"><i class="fa-solid fa-copy"></i> Copy</button></summary>
                                    <pre class="code-block">#encodeForHTML(trim(local.section.html))#</pre>
                                </details>
                            </section>
                        </cfloop>
                    </div>
                </div>
            </div>
            </cfoutput>
        </cfmodule>
    </cffunction>


    <!--- The stubs: a search, an address lookup and the three steps of an upload, with made-up data --->

    <cffunction name="matching" access="private" returntype="array" output="false">
        <cfargument name="items" type="array" required="true" />
        <cfset var q = trim(url.q ?: "") />
        <cfset var exclude = listToArray(url.exclude_ids ?: "") />
        <cfset var out = [] />
        <cfset var item = {} />
        <cfloop array="#arguments.items#" item="item">
            <cfif arrayFindNoCase(exclude, item.id)><cfcontinue /></cfif>
            <cfif NOT len(q) OR findNoCase(q, item.label)><cfset arrayAppend(out, item) /></cfif>
        </cfloop>
        <cfreturn out />
    </cffunction>

    <cffunction name="search.customer">
        <cfreturn matching([
            { "id": "c1", "label": "Northwind Traders", "state": "NSW", "kind": "Retailer" },
            { "id": "c2", "label": "Harbour Joinery", "state": "NSW", "kind": "Builder" },
            { "id": "c3", "label": "Southern Cross Logistics", "state": "VIC", "kind": "Freight" },
            { "id": "c4", "label": "Example Pty Ltd", "state": "QLD", "kind": "Builder" },
            { "id": "c5", "label": "Blue Range Supplies", "state": "VIC", "kind": "Retailer" },
            { "id": "c6", "label": "Closed Account Co", "state": "WA", "kind": "Retailer", "disabled": true }
        ]) />
    </cffunction>

    <cffunction name="search.tag">
        <cfreturn matching([
            { "id": "t1", "label": "Priority" }, { "id": "t2", "label": "Approved" }, { "id": "t3", "label": "Deposit paid" },
            { "id": "t4", "label": "On hold" }, { "id": "t5", "label": "Site visit" }, { "id": "t6", "label": "Follow up" }
        ]) />
    </cffunction>

    <cffunction name="search.address">
        <cfset var q = trim(url.q ?: "") />
        <cfset var out = [] />
        <cfset var a = {} />
        <cfset var all = [
            { "formatted_address": "1 Example Street, Sydney NSW 2000, Australia", "lat": -33.87, "lng": 151.21 },
            { "formatted_address": "22 Sample Road, Melbourne VIC 3000, Australia", "lat": -37.81, "lng": 144.96 },
            { "formatted_address": "5 Placeholder Lane, Brisbane QLD 4000, Australia", "lat": -27.47, "lng": 153.03 }
        ] />
        <cfloop array="#all#" item="a">
            <cfif NOT len(q) OR findNoCase(q, a.formatted_address)><cfset arrayAppend(out, a) /></cfif>
        </cfloop>
        <cfreturn { "suggestions": out } />
    </cffunction>

    <!---
        A real page delegates to moo_file: application.lib.db.getService("moo_file").uploadFileToServerWithProgress(request.data).
        Here the presign step hands back this route's demoPut endpoint as the upload URL, and nothing is stored.
    --->
    <cffunction name="uploadFileToServerWithProgress.attachments">
        <cfif len(request.data.file_id ?: "")>
            <cfreturn { "id": request.data.file_id, "created_at": dateTimeFormat(now(), "iso") } />
        </cfif>
        <cfreturn {
            "presignedURL": "/sysadmin/components?X-Endpoint=demoPut",
            "file": { "id": createUUID(), "name": request.data.file_name ?: "file", "size": request.data.file_size ?: 0 }
        } />
    </cffunction>

    <cffunction name="demoPut">
        <cfreturn { "stored": false } />
    </cffunction>


    <!--- The components, in the order a form meets them. model is the page's form object for a live example; "" shows the markup only. --->
    <cffunction name="components" access="private" returntype="array" output="false">
        <cfset var out = [] />
        <cfset var html = "" />

        <cfsavecontent variable="html">
<div class="field" x-data="numberInput({ min: 0, max: 9999, places: 0 })" x-modelable="value" x-model="form.qty">
    <label class="label" for="cx-qty">Quantity</label>
    <input id="cx-qty" class="input input-narrow text-right" type="text" inputmode="numeric"
           :value="display()" @change="commit($event.target.value)" @focus="$el.select()">
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "number", name: "numberInput", title: "Number", model: "{ qty: 1200 }", html: html, description: "Shows the number formatted and stores a number, committed on change. Options: <code class='code-inline'>min</code>, <code class='code-inline'>max</code>, <code class='code-inline'>places</code>." }) />

        <cfsavecontent variable="html">
<div class="field" x-data="currencyInput()" x-modelable="value" x-model="form.price">
    <label class="label" for="cx-price">Unit price</label>
    <div class="input-group input-narrow">
        <span class="input-addon">$</span>
        <input id="cx-price" class="input text-right money" type="text" inputmode="decimal"
               :value="display()" @change="commit($event.target.value)" @focus="$el.select()">
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "currency", name: "currencyInput", title: "Currency", model: "{ price: 1250.5 }", html: html, description: "Two decimal places by default (<code class='code-inline'>places</code>); the model is a number." }) />

        <cfsavecontent variable="html">
<div class="field" x-data="percentInput()" x-modelable="value" x-model="form.margin">
    <label class="label" for="cx-margin">Margin</label>
    <div class="input-group input-narrow">
        <input id="cx-margin" class="input text-right" type="text" inputmode="decimal"
               :value="display()" @change="commit($event.target.value)" @focus="$el.select()">
        <span class="input-addon">%</span>
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "percent", name: "percentInput", title: "Percent", model: "{ margin: 0.225 }", html: html, description: "Shows 22.5 and stores the fraction 0.225." }) />

        <cfsavecontent variable="html">
<div class="field" x-data="checkboxList([['quote', 'Quote'], ['order', 'Order'], ['invoice', 'Invoice']])" x-modelable="value" x-model="form.copies">
    <span class="label">Send copies of</span>
    <div class="option-box">
        <template x-for="[val, text] in options" :key="val">
            <label class="option"><input type="checkbox" class="checkbox" :checked="has(val)" @change="toggle(val)"> <span x-text="text"></span></label>
        </template>
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "checkboxes", name: "checkboxList", title: "Checkbox group", model: "{ copies: 'quote,invoice' }", html: html, description: "Options are <code class='code-inline'>[[value, text], ...]</code>; the model is a comma-joined string. A single yes or no is a plain <code class='code-inline'>switch</code> checkbox with <code class='code-inline'>x-model</code>, no component." }) />

        <cfsavecontent variable="html">
<div class="field" style="max-width: 16rem" x-data="dateQuick()" x-modelable="value" x-model="form.due">
    <label class="label" for="cx-due">Due date</label>
    <div class="input-group">
        <input id="cx-due" class="input" type="date" x-model="value">
        <details class="dropdown">
            <summary class="btn btn-icon" aria-label="Quick pick"><i class="fa-solid fa-calendar-days"></i></summary>
            <div class="dropdown-menu dropdown-menu-end">
                <button type="button" class="dropdown-item" @click="set(0); $el.closest('details').open = false">Today</button>
                <button type="button" class="dropdown-item" @click="set(1); $el.closest('details').open = false">Tomorrow</button>
                <button type="button" class="dropdown-item" @click="set(7); $el.closest('details').open = false">In a week</button>
                <button type="button" class="dropdown-item" @click="set(1, 'month'); $el.closest('details').open = false">In a month</button>
                <div class="dropdown-divider"></div>
                <button type="button" class="dropdown-item" @click="value = ''; $el.closest('details').open = false">Clear</button>
            </div>
        </details>
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "date", name: "dateQuick", title: "Date with quick picks", model: "{ due: '' }", html: html, description: "A native date input; <code class='code-inline'>set(n, 'day' | 'month')</code> picks a date from today. The model is a local calendar date, <code class='code-inline'>yyyy-mm-dd</code>." }) />

        <cfsavecontent variable="html">
<div class="field" style="max-width: 16rem" x-data="datetimeUtc()" x-modelable="value" x-model="form.starts_at">
    <label class="label" for="cx-starts">Starts</label>
    <input id="cx-starts" class="input" type="datetime-local" :value="toLocal()" @change="fromLocal($event.target.value)">
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "datetime", name: "datetimeUtc", title: "Date and time", model: "{ starts_at: '' }", html: html, description: "Shows the browser's local time and stores an ISO string in UTC, ready for a <code class='code-inline'>timestamptz</code> column." }) />

        <cfsavecontent variable="html">
<div class="field" x-data="comboSingle({ endpoint: 'search.customer', groupBy: 'kind', placeholder: 'Search customers…' })"
     x-modelable="selected" x-model="form.customer_id">
    <label class="label" for="cx-customer">Customer</label>
    <div class="combo" @keydown.escape.prevent="close()" @click.outside="close()">
        <div class="combo-shell" @click="$refs.input.focus()">
            <input id="cx-customer" x-ref="input" type="text" autocomplete="off" :placeholder="placeholder"
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
                         @mouseenter="active = row.index" @click="choose(row.item)">
                        <span><span x-text="row.item.label"></span><span class="combo-sub" x-text="row.item.state"></span></span>
                    </div>
                </li>
            </template>
            <li class="combo-empty" x-show="!loading && !options.length">No matches</li>
        </ul>
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "combo-single", name: "comboSingle", title: "Combobox, one", model: "{ customer_id: null }", html: html, description: "Searches as you type, with the keyboard. The model is the chosen option, <code class='code-inline'>{ id, label, ... }</code>, or null. Options: <code class='code-inline'>endpoint</code>, <code class='code-inline'>placeholder</code>, <code class='code-inline'>limit</code>, <code class='code-inline'>groupBy</code> (a path such as <code class='code-inline'>'kind'</code>) and <code class='code-inline'>request: () =&gt; ({ ... })</code> for parameters read at each search. Choosing dispatches <code class='code-inline'>model-change</code> with <code class='code-inline'>detail.selected_option</code>." }) />

        <cfsavecontent variable="html">
<div class="field" x-data="comboMany({ endpoint: 'search.tag', placeholder: 'Add a tag…' })" x-modelable="selected" x-model="form.tag_ids">
    <label class="label" for="cx-tags">Tags</label>
    <div class="combo" @keydown.escape.prevent="close()" @click.outside="close()">
        <div class="combo-shell" @click="$refs.input.focus()">
            <template x-for="item in selected" :key="item.id">
                <span class="combo-chip"><span x-text="item.label"></span><button type="button" @click.stop="remove(item)" aria-label="Remove"><i class="fa-solid fa-xmark"></i></button></span>
            </template>
            <input id="cx-tags" x-ref="input" type="text" autocomplete="off" :placeholder="placeholder" x-model="query"
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
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "combo-many", name: "comboMany", title: "Combobox, many", model: "{ tag_ids: [] }", html: html, description: "Chips. The model is an array of options; the search leaves out those already chosen (<code class='code-inline'>exclude_ids</code>). For a many-to-many field, save the array of ids with <code class='code-inline'>db.save()</code> on the parent." }) />

        <cfsavecontent variable="html">
<div class="field" x-data="sortList({ endpoint: 'search.customer' })" x-modelable="items" x-model="form.contacts">
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
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "sort-list", name: "sortList", title: "Ordered list", model: "{ contacts: [{ id: 'c2', label: 'Harbour Joinery' }, { id: 'c4', label: 'Example Pty Ltd' }] }", html: html, description: "Drag to reorder (the browser's own drag and drop, nothing to load), search to add. The model is the ordered array of <code class='code-inline'>{ id, label }</code>." }) />

        <cfsavecontent variable="html">
<div class="field" x-data="addressSearch({ endpoint: 'search.address' })" x-modelable="value" x-model="form.address">
    <label class="label" for="cx-address">Delivery address</label>
    <div class="combo" @keydown.escape.prevent="close()" @click.outside="close()">
        <div class="combo-shell" @click="$refs.input.focus()">
            <input id="cx-address" x-ref="input" type="text" autocomplete="off" placeholder="Start typing an address…"
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
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "address", name: "addressSearch", title: "Address, from your endpoint", model: "{ address: null }", html: html, description: "The page's own endpoint looks the address up (a proxy to whatever service the project uses) and returns <code class='code-inline'>{ suggestions: [{ formatted_address, ... }] }</code>. The model is the picked suggestion." }) />

        <cfsavecontent variable="html">
<div class="field" x-data="addressGoogle({ key: '#encodeForJavaScript(server.system.environment.GOOGLE_MAP_API_KEY)#', country: 'au' })"
     x-modelable="value" x-model="form.address">
    <label class="label" for="address">Address</label>
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
            <template x-for="s in options" :key="s.place_id"><li class="combo-option" @click="pick(s)"><span x-text="s.formatted_address"></span></li></template>
            <li class="combo-empty" x-show="!loading && !options.length">No matching addresses</li>
        </ul>
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "address-google", name: "addressGoogle", title: "Address, from Google Places", model: "", html: html, description: "Google Places in the browser, with the project's Maps key, so the key's referrer restrictions apply. The model is <code class='code-inline'>{ place_id, name, formatted_address, geometry: { location: { lat, lng } }, state, postcode, suburb }</code>. Options: <code class='code-inline'>key</code> (required), <code class='code-inline'>country</code> (ISO code, default <code class='code-inline'>au</code>), <code class='code-inline'>language</code>, <code class='code-inline'>bias: { lat, lng, radius }</code>. Markup only here: it calls Google." }) />

        <cfsavecontent variable="html">
<div class="field" x-data="emailRecipients()" x-modelable="value" x-model="form.to">
    <label class="label" for="cx-to">To</label>
    <div class="cluster" x-show="addresses().length">
        <template x-for="email in addresses()" :key="email">
            <span class="chip"><span x-text="email"></span><button type="button" @click="remove(email)" aria-label="Remove"><i class="fa-solid fa-xmark"></i></button></span>
        </template>
    </div>
    <input id="cx-to" class="input" x-model="query" placeholder="name@example.com"
           @keydown.enter.prevent="add()" @keydown.comma.prevent="add()" @blur="add()" @paste.prevent="add($event.clipboardData.getData('text'))">
    <span class="help text-danger" x-show="query && !valid(query)">Not an email address</span>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "email", name: "emailRecipients", title: "Email addresses", model: "{ to: 'accounts@example.com' }", html: html, description: "Chips for addresses, from typing or a pasted list (commas, semicolons or spaces). Invalid ones stay in the input; duplicates are dropped. The model is a comma-joined string." }) />

        <cfsavecontent variable="html">
<div class="field" x-data="fileUpload({ endpoint: 'uploadFileToServerWithProgress.attachments', table: 'job', field: 'attachments', parentId: 'example' })"
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
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "files", name: "fileUpload", title: "File upload", model: "{ attachments: [] }", html: html, description: "Presign, PUT to storage with progress, then finalise: the endpoint delegates to <code class='code-inline'>moo_file</code>'s <code class='code-inline'>uploadFileToServerWithProgress(request.data)</code>. The model holds finished uploads only; <code class='code-inline'>remove</code> and <code class='code-inline'>restore</code> undo, <code class='code-inline'>retry</code> and <code class='code-inline'>dismiss</code> handle a failed one. Events: <code class='code-inline'>files-uploading</code>, <code class='code-inline'>file-uploaded</code> (<code class='code-inline'>detail.file</code>), <code class='code-inline'>files-uploaded</code>. Nothing is stored from this page." }) />

        <cfsavecontent variable="html">
<!-- Once per page: <link rel="stylesheet" href="…/trix.css"> and <script src="…/trix.umd.min.js"></script> -->
<div class="field" x-data="richText()" x-modelable="value" x-model="form.message">
    <label class="label" for="message">Message</label>
    <input id="message-value" x-ref="input" type="hidden">
    <trix-editor id="message" input="message-value" x-ref="editor" class="textarea"
                 @trix-initialize="sync()" @trix-change="change()" @trix-file-accept.prevent></trix-editor>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "rich-text", name: "richText", title: "Rich text", model: "", html: html, description: "Trix, which the page loads once. Each editor needs its own input id. Only the user's edits dispatch <code class='code-inline'>model-change</code> (<code class='code-inline'>detail.value</code>); loading a value does not. Markup only here: Moopa does not ship Trix." }) />

        <cfsavecontent variable="html">
<!-- Once per page: <script src="…/Sortable.min.js"></script> -->
<tbody x-data="sortableRows({ endpoint: 'sortLines', handle: '.line-handle', row: '.line-row', enabled: () => !locked })">
    <template x-for="line in lines" :key="line.id">
        <tr class="line-row" :data-id="line.id">
            <td><button type="button" class="btn btn-ghost btn-icon btn-xs line-handle" aria-label="Move"><i class="fa-solid fa-grip-vertical"></i></button></td>
            <td x-text="line.description"></td>
        </tr>
    </template>
</tbody>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "sortable-rows", name: "sortableRows", title: "Sortable rows", model: "", html: html, description: "SortableJS, which the page loads once, on the rows' parent; each row has <code class='code-inline'>data-id</code>. With <code class='code-inline'>endpoint</code>, a drop posts <code class='code-inline'>{ ids: 'a,b,c' }</code>. With <code class='code-inline'>onMove: (oldIndex, newIndex) =&gt; ...</code> instead, the rows go back and the page moves the item in its own array, so an <code class='code-inline'>x-for</code> list keeps the order. <code class='code-inline'>enabled</code> is read reactively. Markup only here." }) />

        <cfsavecontent variable="html">
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
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "admin-list", name: "adminList", title: "Admin list", model: "", html: html, description: "A simple admin screen: filtered records, an edit dialog and a delete dialog. The route's endpoints: <code class='code-inline'>load</code> (<code class='code-inline'>body.filters</code>, returns the array), <code class='code-inline'>new</code> (a blank record, or pass <code class='code-inline'>blank</code>), optional <code class='code-inline'>read</code> (<code class='code-inline'>id</code>), <code class='code-inline'>save</code> (the record) and <code class='code-inline'>delete</code> (<code class='code-inline'>id</code>); rename any with <code class='code-inline'>endpoints: { ... }</code>. Every change to <code class='code-inline'>filters</code> reloads; <code class='code-inline'>persist</code> keeps them for the tab. A page with more behaviour spreads <code class='code-inline'>window.adminList({ ... })</code> into its own <code class='code-inline'>Alpine.data</code>. Markup only here: it needs a table." }) />

        <cfreturn out />
    </cffunction>

</cfcomponent>
