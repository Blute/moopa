<cfcomponent key="073d9220-20ec-43e4-86ec-698624233385" open_to="security">

    <cffunction name="refusedUnlessSysadmin" access="private" returntype="boolean" output="false" hint="Changing who can reach a route is for sysadmins only. True, after answering 403, when the caller isn't one.">
        <cfif application.lib.auth.isSysAdmin()>
            <cfreturn false />
        </cfif>
        <cfheader statuscode="403" statustext="Forbidden" />
        <cfreturn true />
    </cffunction>


    <cffunction name="load">
        <cfset var map = application.lib.db.getService("moo_route").getRouteAccessMap() />
        <cfset map.can_apply = application.lib.auth.isSysAdmin() />
        <cfreturn map />
    </cffunction>


    <cffunction name="apply">
        <cfset var result = {} />

        <cfif refusedUnlessSysadmin()>
            <cfreturn { success: false, error: "Only sysadmins can change route access." } />
        </cfif>

        <cfif NOT isArray(request.data.changes ?: "")>
            <cfheader statuscode="400" statustext="Bad Request" />
            <cfreturn { success: false, error: "changes must be an array." } />
        </cfif>

        <cftry>
            <cfset result = application.lib.db.getService("moo_route").applyRoleRouteAccess(
                role_id = request.data.role_id ?: "",
                changes = request.data.changes
            ) />
            <cfcatch type="moopa.routeAccess.invalidRequest">
                <cfheader statuscode="400" statustext="Bad Request" />
                <cfreturn { success: false, error: cfcatch.message } />
            </cfcatch>
        </cftry>

        <cfif NOT result.success>
            <cfheader statuscode="#result.status_code#" />
        </cfif>

        <cfreturn result />
    </cffunction>


    <cffunction name="get">
        <cfmodule template="/moopa/tags/moopa_layout.cfm" title="Route Access">

            <style>
                .ra-node { display: flex; width: 100%; align-items: center; gap: 0.5rem; text-align: left; border: 1px solid var(--hairline); background: var(--surface); border-radius: var(--radius-sm); padding: 0.375rem 0.5625rem; cursor: pointer; color: var(--ink-mute); transition: box-shadow .3s, border-color .3s, background-color .3s, color .3s, opacity .3s; }
                .ra-node:hover { border-color: var(--ink-mute-2); }
                .ra-node:focus-visible { outline: 2px solid var(--focus-ring); outline-offset: 2px; }
                .ra-node .ra-dot { width: 0.5rem; height: 0.5rem; flex: none; border-radius: 50%; background: var(--hairline-strong); transition: background-color .3s, box-shadow .3s; }
                .ra-node .ra-label { min-width: 0; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: var(--text-sm); font-weight: 500; }
                .ra-node .ra-label.ra-url { font-family: var(--font-mono); font-size: var(--text-xs); white-space: normal; overflow-wrap: anywhere; }
                .ra-node.ra-off { border-style: dashed; opacity: .85; }
                .ra-node.ra-on { color: var(--ink); border-color: var(--success-border); background: var(--success-surface); box-shadow: 0 0 0 1px color-mix(in oklab, var(--success) 25%, transparent), 0 0 14px -4px color-mix(in oklab, var(--success) 55%, transparent); }
                .ra-node.ra-on .ra-dot { background: var(--success); box-shadow: 0 0 0 3px color-mix(in oklab, var(--success) 22%, transparent); }
                .ra-node.ra-pending { outline: 2px dashed var(--signal); outline-offset: 2px; }
                .ra-node.ra-issue.ra-off { opacity: 1; border-color: var(--warning-border); }
                .ra-node.ra-locked, .ra-node.ra-fixed { cursor: default; border-style: solid; }
                .ra-node.ra-selected { box-shadow: 0 0 0 2px var(--ink); }
                .ra-node.ra-on.ra-selected { box-shadow: 0 0 0 2px var(--ink), 0 0 14px -4px color-mix(in oklab, var(--success) 55%, transparent); }
                .ra-node.ra-dim { opacity: .22; }
                .ra-node.ra-peek { opacity: 1; outline: 2px solid var(--signal); outline-offset: 2px; animation: ra-pulse 1.1s ease-out infinite; }
                @keyframes ra-pulse { 0% { box-shadow: 0 0 0 0 color-mix(in oklab, var(--signal) 45%, transparent); } 100% { box-shadow: 0 0 0 12px transparent; } }
                @media (prefers-reduced-motion: reduce) { .ra-node.ra-peek { animation: none; } }
                .ra-child { position: relative; }
                .ra-child::before { content: ""; position: absolute; top: -0.25rem; left: -0.6875rem; width: 0.5625rem; height: 1.125rem; border-left: 1.5px solid var(--hairline-strong); border-bottom: 1.5px solid var(--hairline-strong); border-bottom-left-radius: 0.375rem; transition: border-color .3s; }
                .ra-child.ra-live::before { border-color: var(--success); }
                .ra-child.ra-dead::before { border-color: var(--warning); border-style: dashed; }
                .ra-section { padding: var(--sp-3); }
                .ra-section.is-complete { border-color: var(--success-border); }
                .ra-list { display: flex; flex-direction: column; gap: 0.25rem; margin: 0; padding: 0; list-style: none; }
                .ra-lane { padding: var(--sp-3); border: 1px dashed var(--hairline-strong); border-radius: var(--radius-lg); }
                .ra-meter { height: 3px; margin: var(--sp-2) 0 var(--sp-3); overflow: hidden; border-radius: 2px; background: var(--hairline); }
                .ra-meter > div { height: 100%; background: var(--success); transition: width .3s; }
                .ra-ring { display: grid; place-items: center; flex: 0 0 auto; width: 3.25rem; height: 3.25rem; border-radius: 50%; }
                .ra-ring > div { width: 2.5rem; height: 2.5rem; border-radius: 50%; background: var(--surface); }
                .ra-note { padding: 0.625rem 0.75rem; border-radius: var(--radius-md); background: var(--canvas-soft); color: var(--ink-secondary); font-size: var(--text-xs); line-height: 1.5; }
                .ra-note-warn { background: var(--warning-surface); color: var(--warning-text); }
                .ra-state { display: flex; align-items: center; gap: var(--sp-2); padding: 0.625rem 0.75rem; border-radius: var(--radius-md); font-size: var(--text-sm); font-weight: 500; background: var(--canvas-soft); color: var(--ink-secondary); }
                .ra-state.is-on { background: var(--success-surface); color: var(--success-text); }
                .ra-tray { position: fixed; left: 50%; bottom: 1.25rem; z-index: var(--z-bar); transform: translateX(-50%); display: flex; align-items: center; gap: var(--sp-3); padding: 0.5rem 0.5rem 0.5rem 1.25rem; border-radius: var(--radius-lg); background: var(--ink); color: var(--surface); box-shadow: var(--shadow-2); font-size: var(--text-sm); }
                .ra-tray .btn-ghost { color: var(--surface); }
                .ra-tray .btn-ghost:hover { background: color-mix(in oklab, var(--surface) 12%, transparent); color: var(--surface); }
                .ra-menus { display: grid; gap: 0.875rem; grid-template-columns: repeat(auto-fill, minmax(min(17rem, 100%), 1fr)); }
                .ra-picker { position: absolute; left: 0; top: calc(100% + 0.5rem); z-index: var(--z-popover); width: 20rem; padding: var(--sp-2); border: 1px solid var(--hairline); border-radius: var(--radius-lg); background: var(--surface); box-shadow: var(--shadow-2); }
            </style>

            <div x-data="route_access" x-cloak class="page" style="padding-bottom: 5rem">

                <div class="page-header">
                    <div>
                        <div class="eyebrow" x-text="summary()"></div>
                        <h1>Route Access</h1>
                        <p class="page-lede">
                            Every route, laid out the way people reach it: from a menu, through links on those pages, or not at all.
                            <span x-show="map.can_apply">Pick a role, click routes to stage grants and revokes, then review and apply them together.</span>
                            <span x-show="!loading && !map.can_apply">Pick a role to see what it can open. Only sysadmins can change access.</span>
                        </p>
                    </div>
                </div>

                <div class="card empty" x-show="loading"><i class="fa-solid fa-spinner fa-spin"></i>Loading the map…</div>

                <template x-if="!loading && map.roles.length === 0">
                    <div class="card empty">
                        <i class="fa-solid fa-shield-halved"></i>
                        <p class="strong secondary">No roles yet</p>
                        <p class="small">Create one on the <a href="/sysadmin/roles">Roles</a> page, then come back to give it access.</p>
                    </div>
                </template>

                <template x-if="!loading && map.roles.length > 0">
                    <div class="stack" style="--stack-gap: var(--card-gap)">

                        <div class="cluster">
                            <div style="position: relative" @keydown.escape="rolePickerOpen = false" @click.outside="rolePickerOpen = false">
                                <button type="button" class="btn btn-sm" style="background: var(--ink); border-color: var(--ink); color: var(--surface)" @click="openRolePicker()" aria-haspopup="listbox" :aria-expanded="rolePickerOpen">
                                    <i class="fa-solid fa-shield-halved"></i>
                                    <span x-text="currentRole()?.name"></span>
                                    <span class="badge" x-text="currentRole()?.profile_count ?? 0"></span>
                                    <span class="badge badge-signal" x-show="pendingCount(roleId) > 0" x-text="`${pendingCount(roleId)} staged`"></span>
                                    <i class="fa-solid fa-chevron-down tiny"></i>
                                </button>
                                <div class="ra-picker" x-show="rolePickerOpen" x-transition.opacity>
                                    <div class="input-icon">
                                        <i class="fa-solid fa-magnifying-glass"></i>
                                        <input class="input input-sm" type="search" placeholder="Find a role" aria-label="Find a role" x-ref="roleSearch" x-model="roleQuery" @keydown.enter.prevent="filteredRoles().length && chooseRole(filteredRoles()[0].id)" />
                                    </div>
                                    <ul class="ra-list mt-2" style="max-height: 20rem; overflow: auto" role="listbox" aria-label="Roles">
                                        <template x-for="role in filteredRoles()" :key="role.id">
                                            <li>
                                                <button type="button" role="option" :aria-selected="role.id === roleId" class="dropdown-item" :class="role.id === roleId ? 'strong' : ''" :style="role.id === roleId ? 'background: var(--canvas-soft); color: var(--ink)' : ''" @click="chooseRole(role.id)">
                                                    <span class="grow truncate" x-text="role.name"></span>
                                                    <span class="badge badge-signal" x-show="pendingCount(role.id) > 0" x-text="`${pendingCount(role.id)} staged`"></span>
                                                    <span class="tiny muted" x-text="`${role.profile_count} ${role.profile_count === 1 ? 'person' : 'people'}`"></span>
                                                </button>
                                            </li>
                                        </template>
                                        <li class="small muted" style="padding: var(--sp-2) var(--sp-3)" x-show="filteredRoles().length === 0">No role matches.</li>
                                    </ul>
                                </div>
                            </div>
                            <span class="tiny muted" x-show="otherRolesStaged().length > 0" x-text="`Staged changes in ${otherRolesStaged().length} other role${otherRolesStaged().length === 1 ? '' : 's'}: ${otherRolesStaged().map(role => role.name).join(', ')}`"></span>
                        </div>

                        <template x-if="map.problems.length > 0">
                            <div role="alert" class="alert alert-warning">
                                <i class="fa-solid fa-triangle-exclamation"></i>
                                <div class="min0">
                                    <p class="strong">The map's sources name routes this app doesn't serve</p>
                                    <ul style="margin: var(--sp-1) 0 0; padding-left: 1.25rem">
                                        <template x-for="problem in map.problems" :key="problem.message"><li x-text="problem.message"></li></template>
                                    </ul>
                                </div>
                            </div>
                        </template>

                        <div class="auto-grid" style="--auto-min: 14rem">
                            <div class="card stat row" style="gap: var(--sp-4)">
                                <div class="ra-ring" :style="`background: conic-gradient(var(--success) ${grantedPercent()}%, var(--hairline) 0)`" role="progressbar" aria-label="Share of role-gated routes this role can open" :aria-valuenow="grantedPercent()" aria-valuemin="0" aria-valuemax="100"><div></div></div>
                                <div>
                                    <div class="stat-value" x-text="grantedCount()"></div>
                                    <div class="stat-sub" x-text="`of ${gatedIds.length} role-gated routes`"></div>
                                </div>
                            </div>
                            <div class="card stat row">
                                <div class="grow">
                                    <div class="stat-value" x-text="currentRole()?.profile_count ?? 0"></div>
                                    <div class="stat-sub" x-text="(currentRole()?.profile_count ?? 0) === 1 ? 'person holds this role' : 'people hold this role'"></div>
                                </div>
                                <button type="button" class="btn btn-xs" x-show="(currentRole()?.profile_count ?? 0) > 0" @click="openPeople()">View people</button>
                            </div>
                            <div class="card stat row">
                                <div class="grow">
                                    <div class="stat-value" :class="deadEndIds().length ? 'text-warning' : ''" x-text="deadEndIds().length"></div>
                                    <div class="stat-sub">links that dead-end for this role</div>
                                </div>
                                <button type="button" class="btn btn-xs" x-show="map.can_apply && stageableDeadEnds().length > 0" @click="stageDeadEnds()">Stage linked pages</button>
                            </div>
                            <div class="card stat">
                                <div class="stat-value" x-text="map.ghosts.length"></div>
                                <div class="stat-sub">registry rows with no route file</div>
                            </div>
                        </div>

                        <div class="split split-end" style="--split-aside: 20rem">
                            <div class="stack min0">

                                <div class="cluster">
                                    <div class="input-icon" style="width: 18rem; max-width: 100%">
                                        <i class="fa-solid fa-magnifying-glass"></i>
                                        <input class="input input-sm" type="search" placeholder="Find a route" aria-label="Find a route" x-model="search" />
                                    </div>
                                    <label class="option"><input type="checkbox" class="switch" x-model="issuesOnly" /> Dead ends only</label>
                                    <div class="cluster tiny muted ml-auto" style="--cluster-gap: var(--sp-1) var(--sp-4)">
                                        <span class="row" style="gap: var(--sp-1)"><span class="dot dot-success"></span>Can open</span>
                                        <span class="row" style="gap: var(--sp-1)"><span class="dot"></span>Can't open</span>
                                        <span class="row" style="gap: var(--sp-1)"><i class="fa-solid fa-circle-exclamation text-warning"></i>Dead end</span>
                                        <span class="row" style="gap: var(--sp-1)"><i class="fa-solid fa-lock"></i>Endpoint grants</span>
                                        <span class="row" style="gap: var(--sp-1)" x-show="map.can_apply"><span style="width: 0.625rem; height: 0.625rem; border: 2px dashed var(--signal); border-radius: 2px"></span>Staged</span>
                                    </div>
                                </div>

                                <div class="cluster" style="justify-content: center" x-show="topLinkIds.length > 0">
                                    <template x-for="row in topRows" :key="row.key">
                                        <div style="width: 14rem">
                                        <button type="button" :class="nodeClasses(row.id)" :data-route-id="row.id" :title="routesById[row.id].url" :aria-pressed="map.can_apply && isToggleable(row.id) ? String(has(row.id)) : null">
                                            <span class="ra-dot"></span>
                                            <span class="ra-label" :class="menuTitles(row.id).length ? '' : 'ra-url'" x-text="nodeLabel(row.id)"></span>
                                            <i class="fa-solid fa-lock tiny" x-show="isLocked(row.id)" title="Endpoint-level grants"></i>
                                            <i class="fa-solid fa-circle-exclamation text-warning" x-show="deadEnd(row.id)" title="Dead end for this role"></i>
                                            <i class="fa-solid fa-circle-question tiny muted" x-show="!routeLinked(row.id)" title="Not in any route_links.json"></i>
                                        </button>
                                        </div>
                                    </template>
                                </div>

                                <div class="ra-menus">
                                    <template x-for="section in sections" :key="section.key">
                                        <section class="card ra-section" :class="sectionGranted(section) === section.ids.length ? 'is-complete' : ''">
                                            <div class="row">
                                                <h2 class="strong small" x-text="section.title"></h2>
                                                <span class="ml-auto tiny muted" x-text="`${sectionGranted(section)}/${section.ids.length}`"></span>
                                                <button type="button" class="btn btn-ghost btn-xs" x-show="map.can_apply && sectionToggleable(section).length > 0" @click="stageSection(section)" x-text="sectionToggleable(section).every(id => has(id)) ? 'Revoke all' : 'Grant all'"></button>
                                            </div>
                                            <div class="ra-meter"><div :style="`width:${section.ids.length ? sectionGranted(section) / section.ids.length * 100 : 0}%`"></div></div>
                                            <ul class="ra-list">
                                                <template x-for="row in section.rows" :key="row.key">
                                                    <li :class="row.depth ? 'ra-child ' + connectorClass(row) : ''" :style="`margin-left:${row.depth * 1.25}rem`">
                                        <button type="button" :class="nodeClasses(row.id)" :data-route-id="row.id" :title="routesById[row.id].url" :aria-pressed="map.can_apply && isToggleable(row.id) ? String(has(row.id)) : null">
                                            <span class="ra-dot"></span>
                                            <span class="ra-label" :class="menuTitles(row.id).length ? '' : 'ra-url'" x-text="nodeLabel(row.id)"></span>
                                            <i class="fa-solid fa-lock tiny" x-show="isLocked(row.id)" title="Endpoint-level grants"></i>
                                            <i class="fa-solid fa-circle-exclamation text-warning" x-show="deadEnd(row.id)" title="Dead end for this role"></i>
                                            <i class="fa-solid fa-circle-question tiny muted" x-show="!routeLinked(row.id)" title="Not in any route_links.json"></i>
                                        </button>
                                                    </li>
                                                </template>
                                            </ul>
                                        </section>
                                    </template>
                                </div>

                                <div class="auto-grid" style="--auto-min: 18rem; gap: 0.875rem">
                                    <div class="ra-lane">
                                        <h3 class="row strong small">Orphans <span class="badge" x-text="orphanIds.length"></span></h3>
                                        <p class="help" style="margin: var(--sp-1) 0 var(--sp-3)">Role-gated routes that no menu item, or page reached from one, links to. Reachable by URL only.</p>
                                        <div class="ra-list" x-show="orphanIds.length > 0">
                                            <template x-for="row in orphanRows" :key="row.key">
                                        <button type="button" :class="nodeClasses(row.id)" :data-route-id="row.id" :title="routesById[row.id].url" :aria-pressed="map.can_apply && isToggleable(row.id) ? String(has(row.id)) : null">
                                            <span class="ra-dot"></span>
                                            <span class="ra-label" :class="menuTitles(row.id).length ? '' : 'ra-url'" x-text="nodeLabel(row.id)"></span>
                                            <i class="fa-solid fa-lock tiny" x-show="isLocked(row.id)" title="Endpoint-level grants"></i>
                                            <i class="fa-solid fa-circle-exclamation text-warning" x-show="deadEnd(row.id)" title="Dead end for this role"></i>
                                            <i class="fa-solid fa-circle-question tiny muted" x-show="!routeLinked(row.id)" title="Not in any route_links.json"></i>
                                        </button>
                                            </template>
                                        </div>
                                        <p class="ra-note" x-show="orphanIds.length === 0">None. Every role-gated route is reachable from a menu.</p>
                                    </div>
                                    <div class="ra-lane">
                                        <h3 class="row strong small">Unmapped <span class="badge" :class="unmappedIds.length ? 'badge-warning' : ''" x-text="unmappedIds.length"></span></h3>
                                        <p class="help" style="margin: var(--sp-1) 0 var(--sp-3)">Routes missing from every route_links.json, so the pages they link to are unknown and may show here as orphans.</p>
                                        <div class="cluster" style="--cluster-gap: var(--sp-1)" x-show="unmappedIds.length > 0">
                                            <template x-for="id in unmappedIds" :key="id">
                                                <button type="button" class="badge badge-outline mono" @click="select(id)" x-text="routesById[id].url"></button>
                                            </template>
                                        </div>
                                        <p class="ra-note" x-show="unmappedIds.length === 0">None. Every route's links are recorded.</p>
                                    </div>
                                    <div class="ra-lane">
                                        <h3 class="row strong small">Outside role security <span class="badge" x-text="outsideIds.length"></span></h3>
                                        <p class="help" style="margin: var(--sp-1) 0 var(--sp-3)">Their <code class="code-inline">open_to</code> isn't <code class="code-inline">security</code>, so roles don't apply. It is set in the route file.</p>
                                        <div class="cluster" style="--cluster-gap: var(--sp-1)">
                                            <template x-for="id in outsideIds" :key="id">
                                                <button type="button" class="badge mono" @click="select(id)">
                                                    <span x-text="routesById[id].url"></span>
                                                    <span class="badge-upper muted" style="font-family: var(--font-sans)" x-text="routesById[id].open_to"></span>
                                                </button>
                                            </template>
                                        </div>
                                    </div>
                                    <div class="ra-lane">
                                        <h3 class="row strong small">Registry rows with no route file <span class="badge" :class="map.ghosts.length ? 'badge-warning' : ''" x-text="map.ghosts.length"></span></h3>
                                        <p class="help" style="margin: var(--sp-1) 0 var(--sp-3)">Left in <code class="code-inline">moo_route</code> after their file was deleted or moved. Highlighted rows still carry a grant for this role.</p>
                                        <div class="cluster" style="--cluster-gap: var(--sp-1)">
                                            <template x-for="ghost in map.ghosts" :key="ghost.id">
                                                <span class="badge mono" :class="baseHas(ghost.id) ? 'badge-warning' : ''" :title="baseHas(ghost.id) ? `Still granted to ${currentRole()?.name}` : ''" x-text="ghost.url"></span>
                                            </template>
                                        </div>
                                    </div>
                                </div>
                            </div>

                            <aside class="card card-body" aria-live="polite">
                                <template x-if="!selectedId">
                                    <p class="small muted">Hover or click a route to see who reaches it and what it links to.</p>
                                </template>
                                <template x-if="selectedId">
                                    <div class="stack stack-sm">
                                        <div>
                                            <div class="eyebrow" x-text="kindLabel(selectedId)"></div>
                                            <h3 class="card-title" style="margin-top: var(--sp-1)" x-text="title(selectedId)"></h3>
                                            <code class="mono muted tiny break" x-text="routesById[selectedId].url"></code>
                                        </div>

                                        <div class="ra-state" :class="has(selectedId) ? 'is-on' : ''">
                                            <span class="dot" :class="has(selectedId) ? 'dot-success' : ''"></span>
                                            <span x-text="stateLabel(selectedId)"></span>
                                        </div>

                                        <template x-if="isLocked(selectedId)">
                                            <div class="ra-note"><i class="fa-solid fa-lock"></i> This route has endpoint-level grants, so its access is managed endpoint by endpoint on its route security page.</div>
                                        </template>
                                        <template x-if="!isGated(selectedId)">
                                            <div class="ra-note">Open to <strong x-text="routesById[selectedId].open_to"></strong>: roles don't apply. Change <code class="code-inline">open_to</code> in the route file.</div>
                                        </template>
                                        <template x-if="deadEnd(selectedId)">
                                            <div class="ra-note ra-note-warn"><strong>Dead end.</strong> <span x-text="`${currentRole()?.name} can open ${openableSources(selectedId).map(id => title(id)).join(', ')}, which links here, but clicking through shows an access error.`"></span></div>
                                        </template>
                                        <template x-if="has(selectedId) && blockedTargets(selectedId).length > 0">
                                            <div class="ra-note ra-note-warn" x-text="`${blockedTargets(selectedId).length} page${blockedTargets(selectedId).length === 1 ? '' : 's'} this links to ${blockedTargets(selectedId).length === 1 ? 'is' : 'are'} closed to ${currentRole()?.name}.`"></div>
                                        </template>
                                        <template x-if="!routeLinked(selectedId)">
                                            <div class="ra-note">Not in any route_links.json, so the pages it links to are unknown.</div>
                                        </template>

                                        <div class="stack stack-sm">
                                            <button type="button" class="btn btn-primary btn-sm" x-show="map.can_apply && isToggleable(selectedId)" @click="toggle(selectedId)" x-text="toggleLabel(selectedId)"></button>
                                            <button type="button" class="btn btn-sm" x-show="map.can_apply && isToggleable(selectedId) && has(selectedId) && stageableTargets(selectedId).length > 0" @click="stageGrants(stageableTargets(selectedId))" x-text="`Stage ${stageableTargets(selectedId).length} linked page${stageableTargets(selectedId).length === 1 ? '' : 's'} too`"></button>
                                            <a class="btn btn-ghost btn-sm" :href="`/sysadmin/routes/${selectedId}`"><i class="fa-solid fa-shield-halved"></i> Route security</a>
                                        </div>

                                        <div class="stack stack-sm small">
                                            <div>
                                                <div class="eyebrow">Reached from</div>
                                                <p class="tiny secondary" x-show="menuTitles(selectedId).length > 0" x-text="`Menu: ${menuTitles(selectedId).join(', ')}`"></p>
                                                <ul class="ra-list mt-1">
                                                    <template x-for="id in inbound[selectedId] || []" :key="id">
                                                        <li class="row tiny">
                                                            <span class="dot" :class="openable(id) ? 'dot-success' : ''" style="width: 0.375rem; height: 0.375rem"></span>
                                                            <a href="#" class="truncate" @click.prevent="select(id)" @mouseenter="peek(id)" @mouseleave="peek(null)" @focus="peek(id)" @blur="peek(null)" x-text="title(id)"></a>
                                                        </li>
                                                    </template>
                                                </ul>
                                                <p class="tiny muted" x-show="menuTitles(selectedId).length === 0 && !(inbound[selectedId] || []).length">Nothing links here.</p>
                                            </div>
                                            <div x-show="(map.links[selectedId] || []).length > 0">
                                                <div class="eyebrow">Links to</div>
                                                <ul class="ra-list mt-1">
                                                    <template x-for="id in map.links[selectedId] || []" :key="id">
                                                        <li class="row tiny">
                                                            <span class="dot" :class="openable(id) ? 'dot-success' : ''" style="width: 0.375rem; height: 0.375rem"></span>
                                                            <a href="#" class="truncate" @click.prevent="select(id)" @mouseenter="peek(id)" @mouseleave="peek(null)" @focus="peek(id)" @blur="peek(null)" x-text="title(id)"></a>
                                                        </li>
                                                    </template>
                                                </ul>
                                            </div>
                                            <div x-show="isGated(selectedId)">
                                                <div class="eyebrow">Other roles that can open it</div>
                                                <div class="cluster mt-1" style="--cluster-gap: var(--sp-1)">
                                                    <template x-for="role in otherRoles(selectedId)" :key="role.id"><span class="badge badge-outline" x-text="role.name"></span></template>
                                                    <span class="badge" x-show="otherRoles(selectedId).length === 0">None</span>
                                                    <span class="badge">Sysadmins always</span>
                                                </div>
                                            </div>
                                        </div>
                                    </div>
                                </template>
                            </aside>
                        </div>
                    </div>
                </template>

                <div class="ra-tray" x-show="currentPending().length > 0" x-transition.opacity>
                    <span x-text="`${currentPending().length} staged change${currentPending().length === 1 ? '' : 's'} for ${currentRole()?.name}`"></span>
                    <button type="button" class="btn btn-ghost btn-sm" @click="discard()">Discard</button>
                    <button type="button" class="btn btn-primary btn-sm" @click="openReview()">Review</button>
                </div>

                <dialog class="modal" aria-labelledby="ra-people-title" x-effect="peopleOpen ? ($el.open || $el.showModal()) : ($el.open && $el.close())" @close="peopleOpen = false">
                    <div class="modal-header">
                        <div>
                            <h2 id="ra-people-title" class="card-title" x-text="`People in ${currentRole()?.name}`"></h2>
                            <p class="card-sub" x-text="`${peopleHolding()} in this app. Each opens their profile in a new tab.`"></p>
                        </div>
                        <button type="button" class="btn btn-ghost btn-icon btn-sm" @click="peopleOpen = false" aria-label="Close"><i class="fa-solid fa-xmark"></i></button>
                    </div>
                    <div class="modal-body stack">
                        <div class="input-icon">
                            <i class="fa-solid fa-magnifying-glass"></i>
                            <input class="input input-sm" type="search" placeholder="Find a person by name or email" aria-label="Find a person" x-ref="peopleSearch" x-model="peopleQuery" />
                        </div>
                        <div class="card list-rows" style="box-shadow: none">
                            <template x-for="person in filteredPeople()" :key="person.id">
                                <a class="list-row" :style="person.can_login ? '' : 'opacity: 0.6'" :href="`/sysadmin/profiles/?profile_id=${person.id}`" target="_blank" rel="noopener">
                                    <div class="min0 grow">
                                        <div class="cell-main truncate" x-text="person.full_name || person.email"></div>
                                        <div class="cell-sub truncate" x-text="person.email"></div>
                                    </div>
                                    <span class="badge" x-show="!person.can_login">can't sign in</span>
                                    <span class="tiny muted nowrap" x-text="lastSignIn(person)"></span>
                                    <i class="fa-solid fa-arrow-up-right-from-square tiny muted"></i>
                                </a>
                            </template>
                            <div class="empty" x-show="filteredPeople().length === 0">Nobody matches.</div>
                        </div>
                    </div>
                </dialog>

                <dialog class="modal" aria-labelledby="ra-review-title" x-effect="reviewOpen ? ($el.open || $el.showModal()) : ($el.open && $el.close())" @close="reviewOpen = false">
                    <div class="modal-header">
                        <div>
                            <h2 id="ra-review-title" class="card-title" x-text="`Apply ${currentPending().length} change${currentPending().length === 1 ? '' : 's'} to ${currentRole()?.name}`"></h2>
                            <p class="card-sub" x-text="`${peopleHolding()}. All of these apply together, or none do.`"></p>
                        </div>
                    </div>
                    <div class="modal-body stack">
                        <div x-show="pendingGrants().length > 0">
                            <div class="eyebrow text-success">Grant</div>
                            <ul class="ra-list mt-1">
                                <template x-for="id in pendingGrants()" :key="id">
                                    <li class="row small"><i class="fa-solid fa-plus tiny text-success"></i><span x-text="title(id)"></span><code class="mono muted tiny truncate" x-text="routesById[id].url"></code></li>
                                </template>
                            </ul>
                        </div>
                        <div x-show="pendingRevokes().length > 0">
                            <div class="eyebrow text-danger">Revoke</div>
                            <ul class="ra-list mt-1">
                                <template x-for="id in pendingRevokes()" :key="id">
                                    <li class="row small"><i class="fa-solid fa-minus tiny text-danger"></i><span x-text="title(id)"></span><code class="mono muted tiny truncate" x-text="routesById[id].url"></code></li>
                                </template>
                            </ul>
                        </div>
                        <div class="alert alert-warning" style="display: block" x-show="newDeadEnds().length > 0">
                            <p class="strong" x-text="`This leaves ${newDeadEnds().length} new dead end${newDeadEnds().length === 1 ? '' : 's'}:`"></p>
                            <ul style="margin: var(--sp-1) 0 0; padding-left: 1.25rem">
                                <template x-for="id in newDeadEnds()" :key="id">
                                    <li x-text="`${title(id)}, linked from ${openableSources(id).map(source => title(source)).join(', ')}`"></li>
                                </template>
                            </ul>
                        </div>
                        <div role="alert" class="alert alert-danger" x-show="conflict"><i class="fa-solid fa-circle-xmark"></i><p x-text="conflict"></p></div>
                    </div>
                    <div class="modal-footer">
                        <button type="button" class="btn btn-sm" @click="reviewOpen = false">Back</button>
                        <button type="button" class="btn btn-sm" x-show="conflict" @click="reloadAfterConflict()">Discard and reload</button>
                        <button type="button" class="btn btn-primary btn-sm" x-show="!conflict" :disabled="applying" @click="apply()">
                            <i class="fa-solid fa-spinner fa-spin" x-show="applying"></i> Apply
                        </button>
                    </div>
                </dialog>
            </div>

            <script>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("route_access", () => ({
                        loading: true,
                        map: { sections: [], top_links: [], routes: [], links: {}, roles: [], access: {}, locked: [], ghosts: [], problems: [], can_apply: false },
                        roleId: null,
                        pending: {},
                        selectedId: null,
                        peekId: null,
                        rolePickerOpen: false,
                        roleQuery: '',
                        peopleOpen: false,
                        peopleQuery: '',
                        search: '',
                        issuesOnly: false,
                        reviewOpen: false,
                        applying: false,
                        conflict: '',

                        routesById: {},
                        accessSets: {},
                        lockedSet: new Set(),
                        inbound: {},
                        menuTitlesById: {},
                        sections: [],
                        topLinkIds: [],
                        topRows: [],
                        gatedIds: [],
                        orphanIds: [],
                        orphanRows: [],
                        unmappedIds: [],
                        outsideIds: [],

                        async init() {
                            await this.load();
                            this.$el.addEventListener('mouseover', (event) => {
                                const node = event.target.closest('[data-route-id]');
                                if (node && window.matchMedia('(min-width: 80rem)').matches) this.selectedId = node.dataset.routeId;
                            });
                            this.$el.addEventListener('click', (event) => {
                                const node = event.target.closest('[data-route-id]');
                                if (!node) return;
                                this.selectedId = node.dataset.routeId;
                                if (this.map.can_apply && this.isToggleable(node.dataset.routeId)) this.toggle(node.dataset.routeId);
                            });
                        },

                        async load() {
                            this.loading = true;
                            try {
                                this.index(await req({ endpoint: 'load' }));
                            } finally {
                                this.loading = false;
                            }
                        },

                        index(map) {
                            this.map = map;
                            this.routesById = Object.fromEntries(map.routes.map(route => [route.id, route]));
                            this.accessSets = Object.fromEntries(map.roles.map(role => [role.id, new Set(map.access[role.id] || [])]));
                            this.lockedSet = new Set(map.locked);
                            if (!this.roleId || !this.accessSets[this.roleId]) this.roleId = map.roles[0]?.id ?? null;
                            if (this.selectedId && !this.routesById[this.selectedId]) this.selectedId = null;

                            this.inbound = {};
                            Object.entries(map.links).forEach(([source, targets]) => targets.forEach(target => {
                                (this.inbound[target] ||= []).push(source);
                            }));

                            this.menuTitlesById = {};
                            map.top_links.forEach(entry => (this.menuTitlesById[entry.route_id] ||= []).push(entry.title));
                            map.sections.forEach(section => section.items.forEach(entry => (this.menuTitlesById[entry.route_id] ||= []).push(entry.title)));

                            this.gatedIds = map.routes.filter(route => route.open_to === 'security').map(route => route.id);
                            this.outsideIds = map.routes.filter(route => route.open_to !== 'security').map(route => route.id);
                            this.unmappedIds = map.routes.filter(route => !map.links[route.id]).map(route => route.id);
                            this.topLinkIds = map.top_links.map(entry => entry.route_id);
                            this.topRows = this.topLinkIds.map(id => ({ key: id, id, parent: null }));
                            this.layout();
                        },

                        // Each role-gated page sits under the first menu item (or page reached from one)
                        // that links to it, breadth first, so it appears once at its shallowest depth.
                        layout() {
                            const placed = new Set(this.topLinkIds);
                            this.map.sections.forEach(section => section.items.forEach(entry => placed.add(entry.route_id)));
                            const childrenOf = {};
                            // Menu items claim the pages they link to before top-level pages do.
                            const queue = [...this.map.sections.flatMap(section => section.items.map(entry => entry.route_id)), ...this.topLinkIds];
                            while (queue.length) {
                                const source = queue.shift();
                                (this.map.links[source] || []).forEach(target => {
                                    if (placed.has(target) || !this.isGated(target)) return;
                                    placed.add(target);
                                    (childrenOf[source] ||= []).push(target);
                                    queue.push(target);
                                });
                            }

                            const flatten = (id, parent, depth, rows, ids, path) => {
                                rows.push({ key: `${path}/${id}`, id, parent, depth });
                                ids.push(id);
                                (childrenOf[id] || []).forEach(child => flatten(child, id, depth + 1, rows, ids, `${path}/${id}`));
                            };
                            this.sections = this.map.sections.map((section, index) => {
                                const rows = [];
                                const ids = [];
                                section.items.forEach(entry => flatten(entry.route_id, null, 0, rows, ids, `${index}`));
                                return { key: `${index}-${section.title}`, title: section.title, rows, ids: [...new Set(ids)].filter(id => this.isGated(id)) };
                            });
                            const topChildren = [];
                            this.topLinkIds.forEach(id => (childrenOf[id] || []).forEach(child => topChildren.push(child)));
                            if (topChildren.length) {
                                const rows = [];
                                const ids = [];
                                topChildren.forEach(child => flatten(child, null, 0, rows, ids, 'top'));
                                this.sections.unshift({ key: 'top', title: 'Linked from top-level pages', rows, ids: ids.filter(id => this.isGated(id)) });
                            }
                            this.orphanIds = this.gatedIds.filter(id => !placed.has(id));
                            this.orphanRows = this.orphanIds.map(id => ({ key: id, id, parent: null }));
                        },

                        // ----- state -----
                        currentRole() { return this.map.roles.find(role => role.id === this.roleId) || null; },
                        baseHas(id) { return this.accessSets[this.roleId]?.has(id) ?? false; },
                        has(id) {
                            const staged = this.pending[this.roleId]?.[id];
                            return staged === undefined ? this.baseHas(id) : staged;
                        },
                        isGated(id) { return this.routesById[id]?.open_to === 'security'; },
                        isLocked(id) { return this.lockedSet.has(id); },
                        isToggleable(id) { return this.isGated(id) && !this.isLocked(id); },
                        isStaged(id) { return this.pending[this.roleId]?.[id] !== undefined; },
                        routeLinked(id) { return Boolean(this.map.links[id]); },
                        openable(id, view = (routeId) => this.has(routeId)) {
                            const openTo = this.routesById[id]?.open_to;
                            return openTo === 'public' || openTo === 'logged_in' || (openTo === 'security' && view(id));
                        },
                        openableSources(id, view) { return (this.inbound[id] || []).filter(source => this.openable(source, view)); },
                        deadEnd(id, view = (routeId) => this.has(routeId)) {
                            return this.isGated(id) && !view(id) && this.openableSources(id, view).length > 0;
                        },
                        deadEndIds() { return this.gatedIds.filter(id => this.deadEnd(id)); },
                        newDeadEnds() {
                            const before = (routeId) => this.baseHas(routeId);
                            return this.deadEndIds().filter(id => !this.deadEnd(id, before));
                        },
                        blockedTargets(id) { return (this.map.links[id] || []).filter(target => this.isGated(target) && !this.has(target)); },
                        stageableTargets(id) { return this.blockedTargets(id).filter(target => !this.isLocked(target)); },
                        stageableDeadEnds() { return this.deadEndIds().filter(id => !this.isLocked(id)); },
                        otherRoles(id) { return this.map.roles.filter(role => role.id !== this.roleId && this.accessSets[role.id].has(id)); },
                        grantedCount() { return this.gatedIds.filter(id => this.has(id)).length; },
                        grantedPercent() { return this.gatedIds.length ? Math.round(this.grantedCount() / this.gatedIds.length * 100) : 0; },
                        sectionGranted(section) { return section.ids.filter(id => this.has(id)).length; },
                        sectionToggleable(section) { return section.ids.filter(id => this.isToggleable(id)); },
                        lastSignIn(person) {
                            if (!person.last_login_at) return 'never signed in';
                            return 'last in ' + new Date(person.last_login_at).toLocaleDateString('en-AU', { day: 'numeric', month: 'short', year: 'numeric' });
                        },
                        peopleHolding() {
                            const count = this.currentRole()?.profile_count ?? 0;
                            return count === 1 ? '1 person holds this role' : `${count} people hold this role`;
                        },
                        summary() {
                            if (this.loading) return '';
                            return `${this.map.routes.length} routes · ${this.map.roles.length} role${this.map.roles.length === 1 ? '' : 's'}`;
                        },

                        // ----- labels -----
                        menuTitles(id) { return this.menuTitlesById[id] || []; },
                        title(id) {
                            const route = this.routesById[id];
                            if (!route) return id;
                            return this.menuTitles(id)[0] || route.url;
                        },
                        // Linked pages show their whole route, allowed to wrap only after a slash.
                        nodeLabel(id) {
                            return this.menuTitles(id).length ? this.title(id) : this.title(id).replaceAll('/', '/\u200B');
                        },
                        kindLabel(id) {
                            if (this.menuTitles(id).length) return 'Menu item';
                            if (!this.isGated(id)) return 'Outside role security';
                            if (this.orphanIds.includes(id)) return 'Orphan';
                            return 'Linked page';
                        },
                        stateLabel(id) {
                            const name = this.currentRole()?.name || 'This role';
                            if (!this.isGated(id)) return `Anyone it is open to can open this`;
                            const verb = this.has(id) ? 'can open this' : "can't open this";
                            return this.isStaged(id) ? `${name} ${verb} once applied` : `${name} ${verb}`;
                        },
                        toggleLabel(id) {
                            const name = this.currentRole()?.name;
                            if (this.isStaged(id)) return 'Unstage this change';
                            return this.has(id) ? `Stage revoke from ${name}` : `Stage grant to ${name}`;
                        },
                        connectorClass(row) {
                            if (!this.has(row.parent)) return '';
                            return this.has(row.id) ? 'ra-live' : (this.isGated(row.id) ? 'ra-dead' : '');
                        },
                        nodeClasses(id) {
                            const classes = ['ra-node'];
                            if (!this.isGated(id)) classes.push('ra-fixed');
                            else classes.push(this.has(id) ? 'ra-on' : 'ra-off');
                            if (this.isLocked(id)) classes.push('ra-locked');
                            if (this.isStaged(id)) classes.push('ra-pending');
                            if (this.deadEnd(id)) classes.push('ra-issue');
                            if (id === this.selectedId) classes.push('ra-selected');
                            if (!this.matches(id)) classes.push('ra-dim');
                            if (id === this.peekId) classes.push('ra-peek');
                            return classes.join(' ');
                        },
                        matches(id) {
                            if (this.issuesOnly && !this.deadEnd(id)) return false;
                            const term = this.search.trim().toLowerCase();
                            if (!term) return true;
                            return this.title(id).toLowerCase().includes(term) || this.routesById[id].url.toLowerCase().includes(term);
                        },

                        // ----- staging -----
                        select(id) { this.peekId = null; this.selectedId = id; },
                        // Points at a route on the map from the inspector. On the wide layout the inspector
                        // stays put while the page scrolls, so an off-screen route is brought into view.
                        peek(id) {
                            this.peekId = id;
                            if (!id || !window.matchMedia('(min-width: 80rem)').matches) return;
                            const node = this.$root.querySelector(`[data-route-id="${CSS.escape(id)}"]`);
                            if (!node) return;
                            const box = node.getBoundingClientRect();
                            if (box.top < 0 || box.bottom > window.innerHeight) node.scrollIntoView({ block: 'nearest', behavior: 'smooth' });
                        },
                        selectRole(id) { this.roleId = id; this.conflict = ''; },
                        openRolePicker() {
                            this.rolePickerOpen = !this.rolePickerOpen;
                            this.roleQuery = '';
                            if (this.rolePickerOpen) this.$nextTick(() => this.$refs.roleSearch?.focus());
                        },
                        chooseRole(id) {
                            this.selectRole(id);
                            this.rolePickerOpen = false;
                        },
                        filteredRoles() {
                            const term = this.roleQuery.trim().toLowerCase();
                            return term ? this.map.roles.filter(role => role.name.toLowerCase().includes(term)) : this.map.roles;
                        },
                        otherRolesStaged() { return this.map.roles.filter(role => role.id !== this.roleId && this.pendingCount(role.id) > 0); },
                        openPeople() {
                            this.peopleQuery = '';
                            this.peopleOpen = true;
                            this.$nextTick(() => this.$refs.peopleSearch?.focus());
                        },
                        filteredPeople() {
                            const people = this.currentRole()?.profiles || [];
                            const term = this.peopleQuery.trim().toLowerCase();
                            if (!term) return people;
                            return people.filter(person => (person.full_name || '').toLowerCase().includes(term) || (person.email || '').toLowerCase().includes(term));
                        },
                        stage(id, granted) {
                            if (!this.map.can_apply || !this.isToggleable(id)) return;
                            const roleChanges = { ...(this.pending[this.roleId] || {}) };
                            if (granted === this.baseHas(id)) delete roleChanges[id];
                            else roleChanges[id] = granted;
                            this.pending = { ...this.pending, [this.roleId]: roleChanges };
                        },
                        toggle(id) { this.stage(id, !this.has(id)); },
                        stageGrants(ids) { ids.forEach(id => this.stage(id, true)); },
                        stageDeadEnds() { this.stageGrants(this.stageableDeadEnds()); },
                        stageSection(section) {
                            const ids = this.sectionToggleable(section);
                            const grant = !ids.every(id => this.has(id));
                            ids.forEach(id => this.stage(id, grant));
                        },
                        pendingCount(roleId) { return Object.keys(this.pending[roleId] || {}).length; },
                        currentPending() { return Object.keys(this.pending[this.roleId] || {}); },
                        pendingGrants() { return this.currentPending().filter(id => this.pending[this.roleId][id]); },
                        pendingRevokes() { return this.currentPending().filter(id => !this.pending[this.roleId][id]); },
                        discard() {
                            this.pending = { ...this.pending, [this.roleId]: {} };
                            this.conflict = '';
                        },
                        openReview() {
                            this.conflict = '';
                            this.reviewOpen = true;
                        },

                        // ----- apply -----
                        async apply() {
                            const roleName = this.currentRole()?.name;
                            const changes = this.currentPending().map(id => ({
                                route_id: id,
                                granted: this.pending[this.roleId][id],
                                was_granted: this.baseHas(id)
                            }));
                            this.applying = true;
                            try {
                                await req({ endpoint: 'apply', body: { role_id: this.roleId, changes }, toastOnError: false });
                                this.pending = { ...this.pending, [this.roleId]: {} };
                                this.reviewOpen = false;
                                await this.load();
                                window.toast?.({ type: 'success', message: `Applied ${changes.length} change${changes.length === 1 ? '' : 's'} to ${roleName}` });
                            } catch (error) {
                                const failure = this.parseError(error);
                                if (failure.status === 409) {
                                    this.conflict = failure.message;
                                } else {
                                    window.toast?.({ type: 'error', message: failure.message || 'The changes could not be applied.' });
                                }
                            } finally {
                                this.applying = false;
                            }
                        },
                        parseError(error) {
                            try {
                                return JSON.parse(error.message);
                            } catch {
                                return { message: error.message };
                            }
                        },
                        async reloadAfterConflict() {
                            this.pending = { ...this.pending, [this.roleId]: {} };
                            this.conflict = '';
                            this.reviewOpen = false;
                            await this.load();
                        }
                    }));
                });
            </script>

        </cfmodule>
    </cffunction>

</cfcomponent>
