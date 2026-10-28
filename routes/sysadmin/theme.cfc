<cfcomponent key="c416d453-6e43-4892-97e6-a377443edb43" open_to="security">

    <!---
        System > Theme: Moopa's design as this project sees it. Tokens shows every token in moopa.css's
        :root beside the project's value (its theme files, application.moopa_theme.css or /_static/theme.css
        and /_static/theme-<app>.css), marking what the theme overrides. Components shows each primitive
        live, with the markup to copy. docs/design.md.
    --->

    <cffunction name="get">
        <cfset var model = themeModel() />
        <cfset var sections = components() />

        <cfmodule template="/moopa/tags/moopa_layout.cfm" title="Theme">
            <style>
                /* stuck, it sits below the content's top padding: the shadow paints that strip so nothing shows through */
                .ds-tabs { position: sticky; top: 0; z-index: var(--z-raised); margin-top: calc(var(--sp-6) - var(--card-gap)); background: var(--canvas); box-shadow: 0 calc(-1 * var(--sp-6)) 0 var(--canvas); }
                .ds-group-title { display: flex; align-items: baseline; justify-content: space-between; gap: var(--sp-3); }
                .ds-tokens { table-layout: fixed; }
                .ds-tokens th:nth-child(1) { width: 28%; }
                .ds-tokens th:nth-child(2), .ds-tokens th:nth-child(3) { width: 36%; }
                .ds-tokens td { vertical-align: middle; }
                .ds-value { display: flex; align-items: center; gap: var(--sp-3); min-width: 0; }
                .ds-value .mono { color: var(--ink-secondary); font-size: var(--text-xs); overflow-wrap: anywhere; }
                .ds-swatch { flex: 0 0 auto; width: 2.25rem; height: 2.25rem; border-radius: var(--radius-md); border: 1px solid var(--hairline); box-shadow: inset 0 0 0 1px color-mix(in oklab, var(--ink) 6%, transparent); }
                .ds-radius { flex: 0 0 auto; width: 2.25rem; height: 2.25rem; border: 1.5px solid var(--ink-mute-2); background: var(--canvas-soft); }
                .ds-space { flex: 0 0 auto; height: 0.75rem; border-radius: 2px; background: var(--signal); }
                .ds-shadow { flex: 0 0 auto; width: 3rem; height: 2.25rem; border-radius: var(--radius-md); background: var(--surface); border: 1px solid var(--hairline); }
                .ds-font { flex: 0 0 auto; min-width: 2.25rem; color: var(--ink); line-height: 1; }
                .ds-inherits { color: var(--ink-mute-2); font-size: var(--text-xs); }
                .ds-split > aside { top: 4rem; }
                .ds-nav { display: flex; flex-direction: column; gap: 1px; }
                .ds-nav a { padding: 0.3rem 0.625rem; border-radius: var(--radius-sm); color: var(--ink-secondary); font-size: var(--text-sm); text-decoration: none; }
                .ds-nav a:hover { background: var(--canvas-soft); color: var(--ink); }
                @media (max-width: 1099px) { .ds-nav { flex-direction: row; flex-wrap: wrap; gap: 0.375rem; } .ds-nav a { border: 1px solid var(--hairline); border-radius: 999px; background: var(--canvas); } }
                .ds-section { scroll-margin-top: 4.5rem; }
                .ds-section + .ds-section { margin-top: var(--sp-8); }
                .ds-section h2 { font-size: var(--text-lg); }
                .ds-section > p { margin-top: 0.25rem; color: var(--ink-mute); font-size: var(--text-sm); max-width: 44rem; }
                .ds-preview {
                    position: relative; display: flex; flex-wrap: wrap; align-items: center; justify-content: center; gap: var(--sp-3);
                    min-height: 9rem; margin-top: var(--sp-3); padding: 2.5rem var(--sp-6);
                    border: 1px solid var(--hairline); border-radius: var(--radius-lg) var(--radius-lg) 0 0; background-color: var(--surface);
                    background-image: radial-gradient(color-mix(in oklab, var(--ink) 9%, transparent) 1px, transparent 1px); background-size: 14px 14px;
                }
                .ds-preview.is-block { display: block; }
                .ds-preview.is-block > * { max-width: 48rem; margin-inline: auto; }
                .ds-code { border: 1px solid var(--hairline); border-top: 0; border-radius: 0 0 var(--radius-lg) var(--radius-lg); background: var(--canvas-cream); }
                .ds-code > summary { display: flex; align-items: center; justify-content: space-between; padding: 0.5rem var(--sp-4); color: var(--ink-mute); font-size: var(--text-xs); letter-spacing: 0.06em; text-transform: uppercase; cursor: pointer; list-style: none; }
                .ds-code > summary::-webkit-details-marker { display: none; }
                .ds-code > summary:hover { color: var(--ink); }
                .ds-code .code-block { margin: 0; border-radius: 0 0 var(--radius-lg) var(--radius-lg); max-height: 22rem; }
            </style>

            <cfoutput>
            <div class="page" x-data="{ tab: 'tokens', overriddenOnly: false }">
                <div class="page-header">
                    <div>
                        <div class="eyebrow">Design</div>
                        <h1>Theme</h1>
                        <p class="page-lede">Moopa's design tokens and components, with this project's theme applied. A theme overrides tokens only (docs/design.md); everything else is Moopa's.</p>
                    </div>
                    <div class="page-actions">
                        <a class="btn btn-sm" href="#encodeForHTMLAttribute(application.lib.system.staticUrl('moopa.css'))#" target="_blank"><i class="fa-solid fa-file-code"></i> moopa.css</a>
                        <cfloop array="#model.theme_files#" index="local.themeFile">
                            <a class="btn btn-sm" href="#encodeForHTMLAttribute(local.themeFile)#" target="_blank"><i class="fa-solid fa-palette"></i> #encodeForHTML(listLast(local.themeFile, '/'))#</a>
                        </cfloop>
                    </div>
                </div>

                <div class="auto-grid" style="--auto-min: 13rem">
                    <div class="card stat">
                        <div class="stat-label">Tokens</div>
                        <div class="stat-value">#model.token_count#</div>
                        <div class="stat-sub">in moopa.css :root</div>
                    </div>
                    <div class="card stat">
                        <div class="stat-label">Overridden</div>
                        <div class="stat-value">#model.overridden_count#</div>
                        <div class="stat-sub"><cfif arrayLen(model.theme_files)>by #encodeForHTML(arrayToList(model.theme_files.map((f) => listLast(f, '/')), ', '))#<cfelse>no theme file</cfif></div>
                    </div>
                    <div class="card stat">
                        <div class="stat-label">Icons</div>
                        <div class="stat-value" style="font-size: var(--text-md)"><cfif len(model.icons)>Font Awesome kit<cfelse>Font Awesome Free</cfif></div>
                        <div class="stat-sub mono truncate">#encodeForHTML(len(model.icons) ? model.icons : 'Moopa vendored, solid · regular · brands')#</div>
                    </div>
                    <div class="card stat">
                        <div class="stat-label">Logo</div>
                        <cfif len(model.logo)>
                            <div style="margin-top: var(--sp-2); padding: var(--sp-2) var(--sp-3); border-radius: var(--radius-md); background: var(--shell-bg); display: inline-block"><img src="#encodeForHTMLAttribute(model.logo)#" alt="" style="height: 1.75rem; width: auto" /></div>
                        <cfelse>
                            <div class="stat-value" style="font-size: var(--text-md)">Project name</div>
                            <div class="stat-sub">application.moopa_theme.logo is not set</div>
                        </cfif>
                    </div>
                </div>

                <div class="tabs ds-tabs" role="tablist">
                    <button type="button" class="tab" role="tab" :aria-selected="tab === 'tokens'" @click="tab = 'tokens'">Tokens <span class="tab-count">#model.token_count#</span></button>
                    <button type="button" class="tab" role="tab" :aria-selected="tab === 'components'" @click="tab = 'components'">Components <span class="tab-count">#arrayLen(sections)#</span></button>
                </div>

                <!--- Tokens --->
                <section x-show="tab === 'tokens'" class="stack">
                    <div class="cluster cluster-between">
                        <p class="muted small">Moopa's default beside this project's value. A project value in <span class="badge badge-signal">Overridden</span> comes from its theme; the rest inherit Moopa's.</p>
                        <label class="option"><input type="checkbox" class="switch" x-model="overriddenOnly"> <span>Overridden only</span></label>
                    </div>

                    <cfloop array="#model.groups#" index="local.group">
                        <div class="card" x-show="!overriddenOnly || #local.group.overridden# > 0">
                            <div class="card-header">
                                <div class="ds-group-title">
                                    <h2 class="card-title">#encodeForHTML(local.group.title)#</h2>
                                    <cfif local.group.overridden><span class="badge badge-signal">#local.group.overridden# overridden</span></cfif>
                                </div>
                            </div>
                            <div class="table-wrap">
                                <table class="table table-sm ds-tokens">
                                    <thead><tr><th>Token</th><th>Moopa default</th><th>This project</th></tr></thead>
                                    <tbody>
                                        <cfloop array="#local.group.tokens#" index="local.token">
                                            <tr x-show="!overriddenOnly || #local.token.overridden ? 'true' : 'false'#">
                                                <td><span class="mono strong">#encodeForHTML(local.token.name)#</span></td>
                                                <td>#tokenValue(local.token, local.token.default_value)#</td>
                                                <td>
                                                    <cfif local.token.overridden>
                                                        <div class="cluster" style="gap: var(--sp-2)">#tokenValue(local.token, local.token.project_value)#<span class="badge badge-signal">Overridden</span></div>
                                                    <cfelse>
                                                        <span class="ds-inherits">inherits</span>
                                                    </cfif>
                                                </td>
                                            </tr>
                                        </cfloop>
                                    </tbody>
                                </table>
                            </div>
                        </div>
                    </cfloop>
                </section>

                <!--- Components --->
                <section x-show="tab === 'components'" x-cloak class="split ds-split" style="--split-aside: 12rem">
                    <aside>
                        <nav class="ds-nav" aria-label="Components">
                            <cfloop array="#sections#" index="local.section">
                                <a href="##ds-#local.section.id#">#encodeForHTML(local.section.title)#</a>
                            </cfloop>
                        </nav>
                    </aside>
                    <div>
                        <cfloop array="#sections#" index="local.section">
                            <section class="ds-section" id="ds-#local.section.id#">
                                <h2>#encodeForHTML(local.section.title)#</h2>
                                <p>#local.section.description#</p>
                                <div class="ds-preview#local.section.block ? ' is-block' : ''#" x-data="{}">#local.section.html#</div>
                                <details class="ds-code">
                                    <summary><span>Code</span><button type="button" class="btn btn-ghost btn-xs" @click.prevent="navigator.clipboard.writeText($el.closest('details').querySelector('pre').innerText); toast({ type: 'success', message: 'Copied' })"><i class="fa-solid fa-copy"></i> Copy</button></summary>
                                    <pre class="code-block">#encodeForHTML(trim(local.section.html))#</pre>
                                </details>
                            </section>
                        </cfloop>
                    </div>
                </section>
            </div>
            </cfoutput>
        </cfmodule>
    </cffunction>


    <!--- A token's value: a visual suited to its kind, then the value itself --->
    <cffunction name="tokenValue" access="private" returntype="string" output="false">
        <cfargument name="token" type="struct" required="true" />
        <cfargument name="value" type="string" required="true" />
        <cfset var v = encodeForHTMLAttribute(arguments.value) />
        <cfset var visual = "" />
        <cfswitch expression="#arguments.token.kind#">
            <cfcase value="colour"><cfset visual = '<span class="ds-swatch" style="background: ' & v & '"></span>' /></cfcase>
            <cfcase value="radius"><cfset visual = '<span class="ds-radius" style="border-radius: ' & v & '"></span>' /></cfcase>
            <cfcase value="space"><cfset visual = '<span class="ds-space" style="width: ' & v & '"></span>' /></cfcase>
            <cfcase value="shadow"><cfset visual = '<span class="ds-shadow" style="box-shadow: ' & v & '"></span>' /></cfcase>
            <cfcase value="font"><cfset visual = '<span class="ds-font" style="font-family: ' & v & '; font-size: 1.125rem">Aa</span>' /></cfcase>
            <cfcase value="size"><cfset visual = '<span class="ds-font" style="font-size: ' & v & '">Aa</span>' /></cfcase>
        </cfswitch>
        <cfreturn '<span class="ds-value">' & visual & '<span class="mono">' & encodeForHTML(arguments.value) & '</span></span>' />
    </cffunction>


    <!---
        The tokens, grouped as moopa.css groups them (the comment heading each run of :root), each with Moopa's
        default and this project's value, var() references resolved so each column shows its own result.
    --->
    <cffunction name="themeModel" access="private" returntype="struct" output="false">
        <cfset var parsed = parseRoot(fileRead(expandPath("/moopa/static/moopa.css"))) />
        <cfset var defaults = {} />
        <cfset var project = {} />
        <cfset var overrides = {} />
        <cfset var themeFiles = themeFiles() />
        <cfset var groups = [] />
        <cfset var total = 0 />
        <cfset var overriddenTotal = 0 />

        <cfloop array="#parsed#" index="local.token">
            <cfset defaults[local.token.name] = local.token.value />
        </cfloop>
        <cfloop array="#themeFiles#" index="local.path">
            <cfif fileExists(expandPath(local.path))>
                <cfset structAppend(overrides, declarations(fileRead(expandPath(local.path))), true) />
            </cfif>
        </cfloop>
        <cfset project = duplicate(defaults) />
        <cfset structAppend(project, overrides, true) />

        <cfloop array="#parsed#" index="local.token">
            <cfif NOT arrayLen(groups) OR groups[arrayLen(groups)].title NEQ local.token.group>
                <cfset arrayAppend(groups, { title: local.token.group, tokens: [], overridden: 0 }) />
            </cfif>
            <cfset local.isOverridden = structKeyExists(overrides, local.token.name) AND compare(overrides[local.token.name], local.token.value) NEQ 0 />
            <cfset local.defaultValue = resolve(local.token.value, defaults, 0) />
            <cfset arrayAppend(groups[arrayLen(groups)].tokens, {
                name: local.token.name,
                default_value: local.defaultValue,
                project_value: resolve(project[local.token.name], project, 0),
                overridden: local.isOverridden,
                kind: tokenKind(local.token.name, local.defaultValue)
            }) />
            <cfset total++ />
            <cfif local.isOverridden>
                <cfset groups[arrayLen(groups)].overridden++ />
                <cfset overriddenTotal++ />
            </cfif>
        </cfloop>

        <cfreturn {
            groups: groups,
            token_count: total,
            overridden_count: overriddenTotal,
            theme_files: themeFiles.filter((p) => fileExists(expandPath(p))),
            icons: application.moopa_theme.icons ?: "",
            logo: application.moopa_theme.logo ?: ""
        } />
    </cffunction>

    <!--- The theme files system.stylesheets() loads --->
    <cffunction name="themeFiles" access="private" returntype="array" output="false">
        <cfif structKeyExists(application, "moopa_theme") AND isStruct(application.moopa_theme) AND isArray(application.moopa_theme.css ?: "")>
            <cfreturn application.moopa_theme.css />
        </cfif>
        <cfreturn [ "/_static/theme.css", "/_static/theme-" & (application.app_name ?: "app") & ".css" ] />
    </cffunction>

    <!--- moopa.css's :root, in order, each declaration with the group of the comment above it --->
    <cffunction name="parseRoot" access="private" returntype="array" output="false">
        <cfargument name="css" type="string" required="true" />
        <cfset var start = find(":root {", arguments.css) />
        <cfset var finish = find(chr(10) & "}", arguments.css, start) />
        <cfset var body = mid(arguments.css, start + 7, finish - start - 7) />
        <cfset var out = [] />
        <cfset var group = "Tokens" />
        <cfset var inComment = false />
        <cfset var line = "" />

        <cfloop list="#body#" index="line" delimiters="#chr(10)#">
            <cfset line = trim(line) />
            <cfif inComment>
                <cfif find("*/", line)><cfset inComment = false /></cfif>
                <cfcontinue />
            </cfif>
            <cfif left(line, 2) EQ "/*">
                <cfset group = groupTitle(line) />
                <cfif NOT find("*/", line)><cfset inComment = true /></cfif>
                <cfcontinue />
            </cfif>
            <cfset line = reReplace(line, "/\*.*?\*/", "", "all") />
            <cfloop array="#reMatch('--[A-Za-z0-9-]+\s*:\s*[^;]+;', line)#" index="local.decl">
                <cfset arrayAppend(out, { name: trim(listFirst(local.decl, ":")), value: trim(reReplace(listRest(local.decl, ":"), ";\s*$", "")), group: group }) />
            </cfloop>
        </cfloop>
        <cfreturn out />
    </cffunction>

    <!--- "signal — the one vivid colour ..." is the group "Signal"; "code blocks (stack traces)" is "Code blocks" --->
    <cffunction name="groupTitle" access="private" returntype="string" output="false">
        <cfargument name="comment" type="string" required="true" />
        <cfset var t = trim(reReplace(arguments.comment, "^/\*\s*|\s*\*/.*$", "", "all")) />
        <cfset t = trim(listFirst(t, chr(8212))) />
        <cfset t = trim(listFirst(t, "(")) />
        <cfreturn uCase(left(t, 1)) & mid(t, 2, len(t)) />
    </cffunction>

    <!--- Every --name: value; in a stylesheet (a theme declares tokens only) --->
    <cffunction name="declarations" access="private" returntype="struct" output="false">
        <cfargument name="css" type="string" required="true" />
        <cfset var out = {} />
        <cfset var clean = reReplace(arguments.css, "/\*.*?\*/", "", "all") />
        <cfloop array="#reMatch('--[A-Za-z0-9-]+\s*:\s*[^;{}]+;', clean)#" index="local.decl">
            <cfset out[trim(listFirst(local.decl, ":"))] = trim(reReplace(listRest(local.decl, ":"), ";\s*$", "")) />
        </cfloop>
        <cfreturn out />
    </cffunction>

    <!--- var(--x) and var(--x, fallback) replaced by their values from the map, recursively --->
    <cffunction name="resolve" access="private" returntype="string" output="false">
        <cfargument name="value" type="string" required="true" />
        <cfargument name="tokens" type="struct" required="true" />
        <cfargument name="depth" type="numeric" required="true" />
        <cfset var out = arguments.value />
        <cfset var pos = 0 />
        <cfset var level = 0 />
        <cfset var i = 0 />
        <cfset var inner = "" />
        <cfset var name = "" />
        <cfset var fallback = "" />
        <cfset var resolved = "" />

        <cfif arguments.depth GT 8><cfreturn out /></cfif>
        <cfset pos = find("var(", out) />
        <cfloop condition="pos GT 0">
            <cfset level = 0 />
            <cfloop from="#pos + 3#" to="#len(out)#" index="i">
                <cfif mid(out, i, 1) EQ "("><cfset level++ /></cfif>
                <cfif mid(out, i, 1) EQ ")">
                    <cfset level-- />
                    <cfif level EQ 0><cfbreak /></cfif>
                </cfif>
            </cfloop>
            <cfset inner = mid(out, pos + 4, i - pos - 4) />
            <cfset name = trim(listFirst(inner, ",")) />
            <cfset fallback = listLen(inner, ",") GT 1 ? trim(listRest(inner, ",")) : "" />
            <cfset resolved = resolve(structKeyExists(arguments.tokens, name) ? arguments.tokens[name] : fallback, arguments.tokens, arguments.depth + 1) />
            <cfset out = left(out, pos - 1) & resolved & mid(out, i + 1, len(out)) />
            <!--- search on after the substitution: a circular token comes back still holding var() at the depth cap --->
            <cfset pos = find("var(", out, pos + len(resolved)) />
        </cfloop>
        <cfreturn out />
    </cffunction>

    <cffunction name="tokenKind" access="private" returntype="string" output="false">
        <cfargument name="name" type="string" required="true" />
        <cfargument name="value" type="string" required="true" />
        <cfif reFindNoCase("shadow|halo", arguments.name)><cfreturn "shadow" /></cfif>
        <cfif reFindNoCase("^--radius", arguments.name)><cfreturn "radius" /></cfif>
        <cfif reFindNoCase("^--sp-", arguments.name)><cfreturn "space" /></cfif>
        <cfif reFindNoCase("^--font-(sans|mono)$", arguments.name)><cfreturn "font" /></cfif>
        <cfif reFindNoCase("^--text-", arguments.name)><cfreturn "size" /></cfif>
        <cfif reFindNoCase("^(oklch|##|rgb|hsl|color-mix|transparent)", arguments.value)><cfreturn "colour" /></cfif>
        <cfreturn "value" />
    </cffunction>


    <!---
        The component gallery. Each entry's html is both the live preview and the code shown to copy, so the
        two cannot drift. Written outside cfoutput: the markup is literal.
    --->
    <cffunction name="components" access="private" returntype="array" output="false">
        <cfset var out = [] />
        <cfset var html = "" />

        <cfsavecontent variable="html">
<div class="cluster">
    <button type="button" class="btn btn-primary"><i class="fa-solid fa-plus"></i> Primary</button>
    <button type="button" class="btn btn-ink">Ink</button>
    <button type="button" class="btn">Default</button>
    <button type="button" class="btn btn-ghost">Ghost</button>
    <button type="button" class="btn btn-danger">Danger</button>
    <button type="button" class="btn btn-danger-solid">Delete</button>
</div>
<div class="cluster">
    <button type="button" class="btn btn-sm">Small</button>
    <button type="button" class="btn btn-xs">Tiny</button>
    <button type="button" class="btn btn-icon" aria-label="Settings"><i class="fa-solid fa-gear"></i></button>
    <button type="button" class="btn" disabled>Disabled</button>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "button", title: "Button", block: false, html: html, description: "<code class='code-inline'>btn</code> with <code class='code-inline'>btn-primary</code> for the one main action, <code class='code-inline'>btn-ink</code>, <code class='code-inline'>btn-ghost</code> and the danger pair. Sizes <code class='code-inline'>btn-sm</code>, <code class='code-inline'>btn-xs</code>; <code class='code-inline'>btn-icon</code> for icon-only." }) />

        <cfsavecontent variable="html">
<div class="cluster">
    <span class="badge">Neutral</span>
    <span class="badge badge-success">Paid</span>
    <span class="badge badge-warning">On hold</span>
    <span class="badge badge-danger">Void</span>
    <span class="badge badge-info">Started</span>
    <span class="badge badge-signal">Current</span>
    <span class="badge badge-solid">Accounts</span>
    <span class="badge badge-outline">Draft</span>
    <span class="cluster" style="gap: var(--sp-1)"><span class="dot dot-success"></span> <span class="small">Online</span></span>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "badge", title: "Badge", block: false, html: html, description: "A status or category: <code class='code-inline'>badge</code> with a semantic modifier. <code class='code-inline'>dot</code> for a quiet status marker." }) />

        <cfsavecontent variable="html">
<div class="cluster">
    <span class="avatar avatar-sm">MB</span>
    <span class="avatar">JD</span>
    <span class="avatar avatar-lg">RT</span>
    <span class="avatar avatar-ok">OK</span>
    <span class="avatar avatar-bad">NO</span>
    <span class="avatar avatar-ink">TM</span>
    <span class="avatar-stack"><span class="avatar">AB</span><span class="avatar">CD</span><span class="avatar">EF</span></span>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "avatar", title: "Avatar", block: false, html: html, description: "Initials or a picture (an <code class='code-inline'>img</code> inside). <code class='code-inline'>avatar-ok</code> and <code class='code-inline'>avatar-bad</code> ring it; <code class='code-inline'>avatar-stack</code> overlaps a group." }) />

        <cfsavecontent variable="html">
<div class="stack" style="width: 100%; max-width: 26rem">
    <div class="field">
        <label class="label" for="ds-name">Name</label>
        <input id="ds-name" class="input" placeholder="Full name">
        <div class="help">As it appears on invoices.</div>
    </div>
    <div class="field">
        <label class="label" for="ds-search">Search</label>
        <div class="input-icon"><i class="fa-solid fa-magnifying-glass"></i><input id="ds-search" class="input" placeholder="Search customers"></div>
    </div>
    <div class="field">
        <label class="label" for="ds-site">Website</label>
        <div class="input-group"><span class="input-addon">https://</span><input id="ds-site" class="input" placeholder="example.com.au"></div>
    </div>
    <div class="field">
        <label class="label" for="ds-email">Email</label>
        <input id="ds-email" class="input is-invalid" value="not-an-email">
        <div class="field-error">Enter a valid email address.</div>
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "input", title: "Input", block: false, html: html, description: "A <code class='code-inline'>field</code> holds a <code class='code-inline'>label</code>, the control and <code class='code-inline'>help</code> or <code class='code-inline'>field-error</code>. <code class='code-inline'>input-icon</code> leads with an icon; <code class='code-inline'>input-group</code> adds a fixed addon." }) />

        <cfsavecontent variable="html">
<div class="stack" style="width: 100%; max-width: 26rem">
    <div class="field">
        <label class="label" for="ds-filter">Filter by</label>
        <select id="ds-filter" class="select"><option>Date</option><option>Customer</option><option>Status</option></select>
    </div>
    <div class="field">
        <label class="label" for="ds-notes">Notes</label>
        <textarea id="ds-notes" class="textarea" rows="3" placeholder="Anything the next person should know"></textarea>
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "select", title: "Select and textarea", block: false, html: html, description: "Native controls, styled: <code class='code-inline'>select</code> and <code class='code-inline'>textarea</code> share the input's height, border and focus ring." }) />

        <cfsavecontent variable="html">
<div class="cluster" style="gap: var(--sp-8); align-items: flex-start">
    <div class="stack stack-xs">
        <label class="option"><input type="checkbox" class="checkbox" checked> <span>Quotes</span></label>
        <label class="option"><input type="checkbox" class="checkbox"> <span>Orders</span></label>
    </div>
    <div class="stack stack-xs">
        <label class="option"><input type="radio" class="radio" name="ds-type" checked> <span>All</span></label>
        <label class="option"><input type="radio" class="radio" name="ds-type"> <span>Open only</span></label>
    </div>
    <div class="stack stack-xs">
        <label class="option"><input type="checkbox" class="switch" checked> <span>Can sign in</span></label>
        <label class="option"><input type="checkbox" class="switch"> <span>Notify me</span></label>
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "choice", title: "Checkbox, radio and switch", block: false, html: html, description: "Wrap each in an <code class='code-inline'>option</code> label so the text toggles it too. A <code class='code-inline'>switch</code> is a checkbox that applies at once." }) />

        <cfsavecontent variable="html">
<div class="chips" x-data="{ on: 'all' }">
    <button type="button" class="chip" :class="on === 'all' && 'is-active'" @click="on = 'all'">All</button>
    <button type="button" class="chip" :class="on === 'overdue' && 'is-active'" @click="on = 'overdue'">Overdue</button>
    <button type="button" class="chip" :class="on === 'open' && 'is-active'" @click="on = 'open'">Open</button>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "chips", title: "Chips", block: false, html: html, description: "Quick filters: <code class='code-inline'>chips</code> of <code class='code-inline'>chip</code> buttons, the chosen one <code class='code-inline'>is-active</code>." }) />

        <cfsavecontent variable="html">
<div class="card">
    <div class="card-header">
        <div>
            <h2 class="card-title">Monthly report</h2>
            <p class="card-sub">Last 30 days</p>
        </div>
        <button type="button" class="btn btn-sm"><i class="fa-solid fa-download"></i> PDF</button>
    </div>
    <div class="card-body">Totals reconcile with the bank for every day in the period.</div>
    <div class="card-footer cluster cluster-end">
        <button type="button" class="btn btn-ghost">Cancel</button>
        <button type="button" class="btn btn-primary">Send</button>
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "card", title: "Card", block: true, html: html, description: "The box everything sits in: <code class='code-inline'>card-header</code> (with <code class='code-inline'>card-title</code> and <code class='code-inline'>card-sub</code>), <code class='code-inline'>card-body</code>, <code class='code-inline'>card-footer</code>. No card inside a card." }) />

        <cfsavecontent variable="html">
<div class="card">
    <div class="table-wrap">
        <table class="table table-hover">
            <thead><tr><th>Customer</th><th>Status</th><th class="text-right">Total</th><th></th></tr></thead>
            <tbody>
                <tr><td><div class="cell-main">Northwind Traders</div><div class="cell-sub">Order 2502</div></td><td><span class="badge badge-success">Paid</span></td><td class="text-right money">$31,020.00</td><td class="actions"><button type="button" class="btn btn-ghost btn-icon btn-sm" aria-label="Open"><i class="fa-solid fa-chevron-right"></i></button></td></tr>
                <tr><td><div class="cell-main">Acme Supplies</div><div class="cell-sub">Invoice 2595</div></td><td><span class="badge badge-warning">Due</span></td><td class="text-right money">$47,036.00</td><td class="actions"><button type="button" class="btn btn-ghost btn-icon btn-sm" aria-label="Open"><i class="fa-solid fa-chevron-right"></i></button></td></tr>
                <tr><td><div class="cell-main">Globex Corporation</div><div class="cell-sub">Quote 2606</div></td><td><span class="badge">Draft</span></td><td class="text-right money">$2,794.00</td><td class="actions"><button type="button" class="btn btn-ghost btn-icon btn-sm" aria-label="Open"><i class="fa-solid fa-chevron-right"></i></button></td></tr>
            </tbody>
        </table>
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "table", title: "Table", block: true, html: html, description: "<code class='code-inline'>table</code> in a <code class='code-inline'>table-wrap</code> (it scrolls, fading the edge it can still scroll to). <code class='code-inline'>cell-main</code> over <code class='code-inline'>cell-sub</code>; <code class='code-inline'>money</code> keeps figures aligned." }) />

        <cfsavecontent variable="html">
<div class="stack stack-sm">
    <div class="alert alert-info"><i class="fa-solid fa-circle-info"></i><div>Prices update overnight.</div></div>
    <div class="alert alert-success"><i class="fa-solid fa-circle-check"></i><div>Report emailed to accounts.</div></div>
    <div class="alert alert-warning"><i class="fa-solid fa-triangle-exclamation"></i><div>Three orders have no delivery address.</div></div>
    <div class="alert alert-danger"><i class="fa-solid fa-circle-exclamation"></i><div>The nightly import failed. See Jobs.</div></div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "alert", title: "Alert", block: true, html: html, description: "A message about the page, with an icon: <code class='code-inline'>alert</code> and its semantic modifier." }) />

        <cfsavecontent variable="html">
<div x-data="{ tab: 'details' }">
    <div class="tabs" role="tablist">
        <button type="button" class="tab" role="tab" :aria-selected="tab === 'details'" @click="tab = 'details'">Details</button>
        <button type="button" class="tab" role="tab" :aria-selected="tab === 'lines'" @click="tab = 'lines'">Lines <span class="tab-count">12</span></button>
        <button type="button" class="tab" role="tab" :aria-selected="tab === 'notes'" @click="tab = 'notes'">Notes <span class="tab-count is-attention">2</span></button>
    </div>
    <p class="muted small" style="padding-top: var(--sp-3)" x-text="'Showing ' + tab"></p>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "tabs", title: "Tabs", block: true, html: html, description: "<code class='code-inline'>tabs</code> of <code class='code-inline'>tab</code> buttons, the shown one <code class='code-inline'>aria-selected</code>. A <code class='code-inline'>tab-count</code> that <code class='code-inline'>is-attention</code> pulses until seen." }) />

        <cfsavecontent variable="html">
<details class="dropdown">
    <summary class="btn btn-sm">Actions <i class="fa-solid fa-chevron-down"></i></summary>
    <div class="dropdown-menu">
        <button type="button" class="dropdown-item"><i class="fa-solid fa-pen"></i> Edit</button>
        <button type="button" class="dropdown-item"><i class="fa-solid fa-copy"></i> Duplicate</button>
        <hr class="dropdown-divider">
        <button type="button" class="dropdown-item dropdown-item-danger"><i class="fa-solid fa-trash"></i> Delete</button>
    </div>
</details>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "dropdown", title: "Dropdown", block: false, html: html, description: "A native <code class='code-inline'>details</code>: no script needed, and a click outside closes it." }) />

        <cfsavecontent variable="html">
<div x-data="{ open: false }">
    <button type="button" class="btn" @click="open = true">Open dialog</button>
    <dialog class="modal modal-sm" x-effect="open ? ($el.open || $el.showModal()) : ($el.open && $el.close())" @close="open = false">
        <div class="modal-header">
            <h2 class="card-title">Delete this quote?</h2>
            <button type="button" class="btn btn-ghost btn-icon btn-sm" aria-label="Close" @click="open = false"><i class="fa-solid fa-xmark"></i></button>
        </div>
        <div class="modal-body">It is removed for everyone and cannot be undone.</div>
        <div class="modal-footer">
            <button type="button" class="btn btn-ghost" @click="open = false">Cancel</button>
            <button type="button" class="btn btn-danger-solid" @click="open = false">Delete</button>
        </div>
    </dialog>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "dialog", title: "Dialog", block: false, html: html, description: "A native <code class='code-inline'>dialog class=&quot;modal&quot;</code> following an Alpine flag, so Esc and the backdrop keep the flag in step. Sizes <code class='code-inline'>modal-sm</code>, <code class='code-inline'>modal-lg</code>, <code class='code-inline'>modal-xl</code>." }) />

        <cfsavecontent variable="html">
<div class="cluster">
    <button type="button" class="btn" @click="toast({ type: 'success', title: 'Saved', message: 'The settings are stored.' })">Success</button>
    <button type="button" class="btn" @click="toast({ type: 'error', title: 'Not saved', message: 'The store refused the key.' })">Error</button>
    <button type="button" class="btn" @click="toast({ type: 'info', message: 'Prices update overnight.' })">Info</button>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "toast", title: "Toast", block: false, html: html, description: "A passing confirmation: <code class='code-inline'>toast({ type, title, message })</code> from moopa.js. <code class='code-inline'>req()</code> raises one for a failed request on its own." }) />

        <cfsavecontent variable="html">
<div class="stack" style="width: 100%">
    <div class="auto-grid" style="--auto-min: 10rem">
        <div class="card stat"><div class="stat-label">Orders</div><div class="stat-value">108,234</div><div class="stat-sub">12 today</div></div>
        <div class="card stat"><div class="stat-label">Settled</div><div class="stat-value">$1.2m</div><div class="stat-sub">last 30 days</div></div>
        <div class="card stat"><div class="stat-label">Open</div><div class="stat-value">35</div><div class="stat-sub">awaiting approval</div></div>
    </div>
    <div class="metrics">
        <div class="metric"><div class="metric-label">Tier</div><div class="metric-value">1</div></div>
        <div class="metric"><div class="metric-label">Branches</div><div class="metric-value">3</div></div>
        <div class="metric"><div class="metric-label">YTD ordered</div><div class="metric-value money">$212,400</div></div>
        <div class="metric"><div class="metric-label">Last order</div><div class="metric-value">2 days ago</div></div>
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "stat", title: "Stat and metrics", block: true, html: html, description: "Headline numbers: a <code class='code-inline'>card stat</code> each in an <code class='code-inline'>auto-grid</code>, or a <code class='code-inline'>metrics</code> strip of <code class='code-inline'>metric</code>s." }) />

        <cfsavecontent variable="html">
<div class="card" style="width: 100%">
    <div class="empty">
        <div><i class="fa-solid fa-inbox" style="font-size: 1.5rem"></i></div>
        <div class="strong" style="margin-top: var(--sp-2); color: var(--ink)">No reports yet</div>
        <div class="small">The first one runs at the end of the month.</div>
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "empty", title: "Empty state", block: true, html: html, description: "<code class='code-inline'>empty</code> where a list or table has nothing to show: say what is missing and what to do." }) />

        <cfsavecontent variable="html">
<div class="combo" style="width: 100%; max-width: 26rem">
    <div class="combo-shell">
        <span class="combo-chip">Accounts <button type="button" aria-label="Remove"><i class="fa-solid fa-xmark"></i></button></span>
        <span class="combo-chip">Warehouse <button type="button" aria-label="Remove"><i class="fa-solid fa-xmark"></i></button></span>
        <input placeholder="Add a role">
    </div>
    <div class="combo-tools"><button type="button" aria-label="Open"><i class="fa-solid fa-chevron-down"></i></button></div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "combobox", title: "Combobox", block: false, html: html, description: "Chips in an input-looking <code class='code-inline'>combo-shell</code>, with a <code class='code-inline'>combo-list</code> of <code class='code-inline'>combo-option</code>s under it. The project's Alpine component supplies search and selection." }) />

        <cfsavecontent variable="html">
<div class="stack" style="width: 100%; max-width: 30rem">
    <label class="dropzone">
        <input type="file">
        <i class="fa-solid fa-cloud-arrow-up"></i>
        <span><strong>Drop files</strong> or click to choose</span>
        <span class="help">PDF or images, up to 10 MB</span>
    </label>
    <ul class="file-list">
        <li class="file-item">
            <span class="file-icon"><i class="fa-solid fa-file-pdf"></i></span>
            <span class="file-body"><button type="button" class="file-name">invoice-oct.pdf</button><span class="file-meta">248 KB</span></span>
            <span class="file-status"><span class="progress"><span style="width: 64%"></span></span>64%</span>
            <span class="file-actions"><button type="button" class="btn btn-ghost btn-icon btn-sm" aria-label="Remove"><i class="fa-solid fa-xmark"></i></button></span>
        </li>
    </ul>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "files", title: "Dropzone and file list", block: false, html: html, description: "A <code class='code-inline'>dropzone</code> label around a hidden file input, and a <code class='code-inline'>file-list</code> with <code class='code-inline'>progress</code> while uploading." }) />

        <cfsavecontent variable="html">
<ol class="stepper" style="width: 100%">
    <li class="is-done"><span class="stepper-dot"><i class="fa-solid fa-check"></i></span> Customer <span class="stepper-value">Acme</span></li>
    <li class="is-current"><span class="stepper-dot">2</span> Items</li>
    <li><span class="stepper-dot">3</span> Delivery</li>
    <li><span class="stepper-dot">4</span> Review</li>
</ol>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "stepper", title: "Stepper", block: true, html: html, description: "Steps through a task: <code class='code-inline'>is-done</code>, <code class='code-inline'>is-current</code>, with the chosen value shown on done steps." }) />

        <cfsavecontent variable="html">
<div class="card" style="width: 100%">
    <div class="card-body kv-grid">
        <div class="kv-label">Store</div><div class="kv-value">primary.example.com.au</div>
        <div class="kv-label">Last pull</div><div class="kv-value">10 minutes ago</div>
        <div class="kv-label">Key</div><div class="kv-value"><code class="code-inline">pk_7f3a</code> <kbd class="kbd">Ctrl</kbd> + <kbd class="kbd">K</kbd></div>
    </div>
</div>
        </cfsavecontent>
        <cfset arrayAppend(out, { id: "kv", title: "Key and value", block: true, html: html, description: "Read-only details: a <code class='code-inline'>kv-grid</code> of <code class='code-inline'>kv-label</code> and <code class='code-inline'>kv-value</code>, with <code class='code-inline'>code-inline</code> and <code class='code-inline'>kbd</code>." }) />

        <cfreturn out />
    </cffunction>

</cfcomponent>
