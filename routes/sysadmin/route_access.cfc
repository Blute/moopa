<cfcomponent key="073d9220-20ec-43e4-86ec-698624233385" open_to="security">

    <cffunction name="load">
        <cfreturn application.lib.db.getService("moo_route").getRouteAccessMap() />
    </cffunction>


    <cffunction name="apply">
        <cfset var result = {} />

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
        <cf_layout_default title="Route Access">

            <style>
                .ra-node { display: flex; width: 100%; align-items: center; gap: 0.5rem; text-align: left; border: 1px solid var(--color-base-300); background: var(--color-base-100); border-radius: var(--radius-field); padding: 0.375rem 0.5625rem; cursor: pointer; color: color-mix(in oklch, var(--color-base-content) 55%, transparent); transition: box-shadow .3s, border-color .3s, background-color .3s, color .3s, opacity .3s; }
                .ra-node:hover { border-color: color-mix(in oklch, var(--color-base-content) 45%, transparent); }
                .ra-node:focus-visible { outline: 2px solid var(--color-primary); outline-offset: 2px; }
                .ra-node .ra-dot { width: 0.5rem; height: 0.5rem; flex: none; border-radius: 9999px; background: var(--color-base-300); transition: background-color .3s, box-shadow .3s; }
                .ra-node .ra-label { min-width: 0; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 0.8125rem; font-weight: 500; }
                .ra-node.ra-off { border-style: dashed; opacity: .8; }
                .ra-node.ra-on { color: var(--color-base-content); border-color: color-mix(in oklch, var(--color-success) 65%, white); background: color-mix(in oklch, var(--color-success) 9%, var(--color-base-100)); box-shadow: 0 0 0 1px color-mix(in oklch, var(--color-success) 30%, transparent), 0 0 16px -3px color-mix(in oklch, var(--color-success) 55%, transparent); }
                .ra-node.ra-on .ra-dot { background: var(--color-success); box-shadow: 0 0 0 3px color-mix(in oklch, var(--color-success) 22%, transparent); }
                .ra-node.ra-pending { outline: 2px dashed var(--color-primary); outline-offset: 2px; }
                .ra-node.ra-issue.ra-off { opacity: 1; border-color: color-mix(in oklch, var(--color-warning) 70%, var(--color-base-300)); }
                .ra-node.ra-locked, .ra-node.ra-fixed { cursor: default; border-style: solid; }
                .ra-node.ra-selected { box-shadow: 0 0 0 2px var(--color-base-content); }
                .ra-node.ra-on.ra-selected { box-shadow: 0 0 0 2px var(--color-base-content), 0 0 16px -3px color-mix(in oklch, var(--color-success) 55%, transparent); }
                .ra-node.ra-dim { opacity: .22; }
                .ra-child { position: relative; }
                .ra-child::before { content: ""; position: absolute; top: -0.25rem; left: -0.6875rem; width: 0.5625rem; height: 1.125rem; border-left: 1.5px solid var(--color-base-300); border-bottom: 1.5px solid var(--color-base-300); border-bottom-left-radius: 0.375rem; transition: border-color .3s; }
                .ra-child.ra-live::before { border-color: var(--color-success); }
                .ra-child.ra-dead::before { border-color: var(--color-warning); border-style: dashed; }
            </style>

            <div x-data="route_access" x-cloak class="flex flex-col gap-4 lg:gap-5 pb-24">

                <!-- Header -->
                <div class="flex items-center gap-3">
                    <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-box border border-base-300 bg-base-100 text-primary">
                        <i class="fa-solid fa-sitemap text-base"></i>
                    </div>
                    <div class="min-w-0">
                        <div class="flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
                            <h1 class="text-[1.625rem] font-semibold leading-none tracking-[-0.03em]">Route Access</h1>
                            <span class="text-[0.6875rem] font-medium uppercase tracking-[0.11em] text-base-content/42" x-text="summary()"></span>
                        </div>
                        <p class="mt-1 max-w-[70ch] text-sm leading-5 text-base-content/62">Every route, laid out the way people reach it: from a menu, through links on those pages, or not at all. Pick a role, click routes to stage grants and revokes, then review and apply them together.</p>
                    </div>
                </div>

                <div x-show="loading" class="flex justify-center py-16">
                    <span class="loading loading-spinner loading-md"></span>
                </div>

                <template x-if="!loading && map.roles.length === 0">
                    <div class="rounded-box border border-base-300 bg-base-100 p-10 text-center">
                        <i class="fa-solid fa-shield-halved mb-3 block text-3xl text-base-content/30"></i>
                        <p class="font-medium">No roles yet</p>
                        <p class="mt-1 text-sm text-base-content/60">Create a role on the <a class="link" href="/sysadmin/roles">Roles</a> page, then come back to give it access.</p>
                    </div>
                </template>

                <template x-if="!loading && map.roles.length > 0">
                    <div class="flex flex-col gap-4 lg:gap-5">

                        <!-- Roles -->
                        <div class="flex flex-wrap gap-2" role="group" aria-label="Role">
                            <template x-for="role in map.roles" :key="role.id">
                                <button type="button" class="btn btn-sm gap-2 rounded-full" :class="role.id === roleId ? 'btn-neutral' : 'btn-outline border-base-300'" :aria-pressed="role.id === roleId" @click="selectRole(role.id)">
                                    <span x-text="role.name"></span>
                                    <span class="badge badge-sm badge-ghost" x-text="role.profile_count" :title="`${role.profile_count} people in this app hold ${role.name}`"></span>
                                    <span x-show="pendingCount(role.id) > 0" class="badge badge-sm badge-primary" x-text="`${pendingCount(role.id)} staged`"></span>
                                </button>
                            </template>
                        </div>

                        <!-- Problems -->
                        <template x-if="map.problems.length > 0">
                            <div role="alert" class="alert alert-warning items-start">
                                <i class="fa-solid fa-triangle-exclamation mt-0.5"></i>
                                <div class="min-w-0">
                                    <p class="font-medium">The map's sources name routes this app doesn't serve</p>
                                    <ul class="mt-1 list-disc pl-5 text-sm">
                                        <template x-for="problem in map.problems" :key="problem.message">
                                            <li x-text="problem.message"></li>
                                        </template>
                                    </ul>
                                </div>
                            </div>
                        </template>

                        <!-- Stats -->
                        <div class="grid grid-cols-2 gap-3 xl:grid-cols-4">
                            <div class="flex items-center gap-4 rounded-box border border-base-300 bg-base-100 px-5 py-4">
                                <div class="grid h-13 w-13 shrink-0 place-items-center rounded-full" :style="`background: conic-gradient(var(--color-success) ${grantedPercent()}%, var(--color-base-300) 0)`" role="progressbar" aria-label="Share of role-gated routes this role can open" :aria-valuenow="grantedPercent()" aria-valuemin="0" aria-valuemax="100">
                                    <div class="h-10 w-10 rounded-full bg-base-100"></div>
                                </div>
                                <div>
                                    <p class="text-[1.75rem] font-bold leading-none tracking-[-0.04em]" x-text="grantedCount()"></p>
                                    <p class="mt-1 text-xs text-base-content/55" x-text="`of ${gatedIds.length} role-gated routes`"></p>
                                </div>
                            </div>
                            <div class="rounded-box border border-base-300 bg-base-100 px-5 py-4">
                                <p class="text-[1.75rem] font-bold leading-none tracking-[-0.04em]" x-text="currentRole()?.profile_count ?? 0"></p>
                                <p class="mt-1 text-xs text-base-content/55" x-text="(currentRole()?.profile_count ?? 0) === 1 ? 'person holds this role' : 'people hold this role'"></p>
                            </div>
                            <div class="flex items-center gap-3 rounded-box border border-base-300 bg-base-100 px-5 py-4">
                                <div class="min-w-0">
                                    <p class="text-[1.75rem] font-bold leading-none tracking-[-0.04em]" :class="deadEndIds().length ? 'text-warning' : ''" x-text="deadEndIds().length"></p>
                                    <p class="mt-1 text-xs text-base-content/55">links that dead-end for this role</p>
                                </div>
                                <button type="button" class="btn btn-xs btn-outline ml-auto shrink-0" x-show="stageableDeadEnds().length > 0" @click="stageDeadEnds()">Stage linked pages</button>
                            </div>
                            <div class="rounded-box border border-base-300 bg-base-100 px-5 py-4">
                                <p class="text-[1.75rem] font-bold leading-none tracking-[-0.04em]" x-text="map.ghosts.length"></p>
                                <p class="mt-1 text-xs text-base-content/55">registry rows with no route file</p>
                            </div>
                        </div>

                        <div class="grid grid-cols-1 items-start gap-5 xl:grid-cols-[minmax(0,1fr)_20rem]">
                            <div class="flex min-w-0 flex-col gap-4">

                                <!-- Toolbar -->
                                <div class="flex flex-col gap-3 sm:flex-row sm:items-center">
                                    <label class="input input-sm w-full focus-within:outline-primary/55 focus-within:outline-offset-2 sm:w-80">
                                        <i class="fa-solid fa-magnifying-glass text-base-content/40"></i>
                                        <input type="search" placeholder="Find a route" aria-label="Find a route" x-model="search" />
                                    </label>
                                    <label class="flex shrink-0 cursor-pointer items-center gap-2 whitespace-nowrap text-sm text-base-content/70">
                                        <input type="checkbox" class="toggle toggle-sm" x-model="issuesOnly" />
                                        Dead ends only
                                    </label>
                                    <div class="flex flex-wrap gap-x-4 gap-y-1 text-xs text-base-content/55 sm:ml-auto">
                                        <span class="flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-full bg-success"></span>Can open</span>
                                        <span class="flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-full bg-base-300"></span>Can't open</span>
                                        <span class="flex items-center gap-1.5"><i class="fa-solid fa-circle-exclamation text-warning"></i>Dead end</span>
                                        <span class="flex items-center gap-1.5"><i class="fa-solid fa-lock"></i>Endpoint grants</span>
                                        <span class="flex items-center gap-1.5"><span class="h-2.5 w-2.5 rounded-sm border-2 border-dashed border-primary"></span>Staged</span>
                                    </div>
                                </div>

                                <!-- Top-level links -->
                                <div class="flex flex-wrap justify-center gap-2" x-show="topLinkIds.length > 0">
                                    <template x-for="row in topRows" :key="row.key">
                                        <div class="w-56">
                                        <button type="button" :class="nodeClasses(row.id)" :data-route-id="row.id" :title="routesById[row.id].url" :aria-pressed="isToggleable(row.id) ? String(has(row.id)) : null">
                                            <span class="ra-dot"></span>
                                            <span class="ra-label" x-text="rowLabel(row.id, row.parent)"></span>
                                            <i class="fa-solid fa-lock text-xs" x-show="isLocked(row.id)" title="Endpoint-level grants"></i>
                                            <i class="fa-solid fa-circle-exclamation text-warning" x-show="deadEnd(row.id)" title="Dead end for this role"></i>
                                            <i class="fa-solid fa-circle-question text-xs text-base-content/40" x-show="!routeLinked(row.id)" title="Not in any route_links.json"></i>
                                        </button>
                                        </div>
                                    </template>
                                </div>

                                <!-- Menus -->
                                <div class="grid grid-cols-1 gap-3.5 md:grid-cols-2 2xl:grid-cols-3">
                                    <template x-for="section in sections" :key="section.key">
                                        <section class="rounded-box border bg-base-100 p-3" :class="sectionGranted(section) === section.ids.length ? 'border-success/50' : 'border-base-300'">
                                            <div class="mb-2 flex items-center gap-2 px-0.5">
                                                <h2 class="text-sm font-semibold" x-text="section.title"></h2>
                                                <span class="ml-auto text-xs tabular-nums text-base-content/50" x-text="`${sectionGranted(section)}/${section.ids.length}`"></span>
                                                <button type="button" class="btn btn-ghost btn-xs" x-show="sectionToggleable(section).length > 0" @click="stageSection(section)" x-text="sectionToggleable(section).every(id => has(id)) ? 'Revoke all' : 'Grant all'"></button>
                                            </div>
                                            <div class="mx-0.5 mb-2.5 h-[3px] overflow-hidden rounded bg-base-300">
                                                <div class="h-full bg-success transition-all duration-300" :style="`width:${section.ids.length ? sectionGranted(section) / section.ids.length * 100 : 0}%`"></div>
                                            </div>
                                            <ul class="flex flex-col gap-1">
                                                <template x-for="row in section.rows" :key="row.key">
                                                    <li :class="row.depth ? 'ra-child ' + connectorClass(row) : ''" :style="`margin-left:${row.depth * 1.25}rem`">
                                        <button type="button" :class="nodeClasses(row.id)" :data-route-id="row.id" :title="routesById[row.id].url" :aria-pressed="isToggleable(row.id) ? String(has(row.id)) : null">
                                            <span class="ra-dot"></span>
                                            <span class="ra-label" x-text="rowLabel(row.id, row.parent)"></span>
                                            <i class="fa-solid fa-lock text-xs" x-show="isLocked(row.id)" title="Endpoint-level grants"></i>
                                            <i class="fa-solid fa-circle-exclamation text-warning" x-show="deadEnd(row.id)" title="Dead end for this role"></i>
                                            <i class="fa-solid fa-circle-question text-xs text-base-content/40" x-show="!routeLinked(row.id)" title="Not in any route_links.json"></i>
                                        </button>
                                                    </li>
                                                </template>
                                            </ul>
                                        </section>
                                    </template>
                                </div>

                                <!-- Lanes -->
                                <div class="grid grid-cols-1 gap-3.5 md:grid-cols-2">
                                    <div class="rounded-box border border-dashed border-base-300 p-3">
                                        <h3 class="flex items-center gap-2 text-sm font-semibold">Orphans <span class="badge badge-sm badge-ghost" x-text="orphanIds.length"></span></h3>
                                        <p class="mb-2.5 text-xs text-base-content/55">Role-gated routes that no menu item, or page reached from one, links to. Reachable by URL only.</p>
                                        <div class="flex flex-col gap-1" x-show="orphanIds.length > 0">
                                            <template x-for="row in orphanRows" :key="row.key">
                                        <button type="button" :class="nodeClasses(row.id)" :data-route-id="row.id" :title="routesById[row.id].url" :aria-pressed="isToggleable(row.id) ? String(has(row.id)) : null">
                                            <span class="ra-dot"></span>
                                            <span class="ra-label" x-text="rowLabel(row.id, row.parent)"></span>
                                            <i class="fa-solid fa-lock text-xs" x-show="isLocked(row.id)" title="Endpoint-level grants"></i>
                                            <i class="fa-solid fa-circle-exclamation text-warning" x-show="deadEnd(row.id)" title="Dead end for this role"></i>
                                            <i class="fa-solid fa-circle-question text-xs text-base-content/40" x-show="!routeLinked(row.id)" title="Not in any route_links.json"></i>
                                        </button>
                                            </template>
                                        </div>
                                        <p class="rounded-field bg-base-200 px-3 py-2 text-xs text-base-content/55" x-show="orphanIds.length === 0">None. Every role-gated route is reachable from a menu.</p>
                                    </div>
                                    <div class="rounded-box border border-dashed border-base-300 p-3">
                                        <h3 class="flex items-center gap-2 text-sm font-semibold">Unmapped <span class="badge badge-sm" :class="unmappedIds.length ? 'badge-warning' : 'badge-ghost'" x-text="unmappedIds.length"></span></h3>
                                        <p class="mb-2.5 text-xs text-base-content/55">Routes missing from every route_links.json, so the pages they link to are unknown and may show here as orphans.</p>
                                        <div class="flex flex-wrap gap-1.5" x-show="unmappedIds.length > 0">
                                            <template x-for="id in unmappedIds" :key="id">
                                                <button type="button" class="badge badge-outline font-mono text-[0.6875rem]" @click="select(id)" x-text="routesById[id].url"></button>
                                            </template>
                                        </div>
                                        <p class="rounded-field bg-base-200 px-3 py-2 text-xs text-base-content/55" x-show="unmappedIds.length === 0">None. Every route's links are recorded.</p>
                                    </div>
                                    <div class="rounded-box border border-dashed border-base-300 p-3">
                                        <h3 class="flex items-center gap-2 text-sm font-semibold">Outside role security <span class="badge badge-sm badge-ghost" x-text="outsideIds.length"></span></h3>
                                        <p class="mb-2.5 text-xs text-base-content/55">Their <code>open_to</code> isn't <code>security</code>, so roles don't apply. It is set in the route file.</p>
                                        <div class="flex flex-wrap gap-1.5">
                                            <template x-for="id in outsideIds" :key="id">
                                                <button type="button" class="badge badge-ghost gap-1.5 font-mono text-[0.6875rem]" @click="select(id)">
                                                    <span x-text="routesById[id].url"></span>
                                                    <span class="font-sans uppercase tracking-wide text-base-content/50" x-text="routesById[id].open_to"></span>
                                                </button>
                                            </template>
                                        </div>
                                    </div>
                                    <div class="rounded-box border border-dashed border-base-300 p-3">
                                        <h3 class="flex items-center gap-2 text-sm font-semibold">Registry rows with no route file <span class="badge badge-sm" :class="map.ghosts.length ? 'badge-warning' : 'badge-ghost'" x-text="map.ghosts.length"></span></h3>
                                        <p class="mb-2.5 text-xs text-base-content/55">Left in <code>moo_route</code> after their file was deleted or moved. Highlighted rows still carry a grant for this role.</p>
                                        <div class="flex flex-wrap gap-1.5">
                                            <template x-for="ghost in map.ghosts" :key="ghost.id">
                                                <span class="badge font-mono text-[0.6875rem]" :class="baseHas(ghost.id) ? 'badge-warning' : 'badge-ghost'" :title="baseHas(ghost.id) ? `Still granted to ${currentRole()?.name}` : ''" x-text="ghost.url"></span>
                                            </template>
                                        </div>
                                    </div>
                                </div>
                            </div>

                            <!-- Inspector -->
                            <aside class="rounded-box border border-base-300 bg-base-100 p-5 xl:sticky xl:top-4" aria-live="polite">
                                <template x-if="!selectedId">
                                    <p class="text-sm text-base-content/55">Hover or click a route to see who reaches it and what it links to.</p>
                                </template>
                                <template x-if="selectedId">
                                    <div>
                                        <p class="text-[0.6875rem] uppercase tracking-[0.11em] text-base-content/50" x-text="kindLabel(selectedId)"></p>
                                        <h3 class="mt-1.5 text-lg font-semibold leading-tight tracking-[-0.02em]" x-text="title(selectedId)"></h3>
                                        <code class="break-all text-xs text-base-content/60" x-text="routesById[selectedId].url"></code>

                                        <div class="mt-3.5 flex items-center gap-2 rounded-field px-3 py-2.5 text-sm font-medium" :class="has(selectedId) ? 'bg-success/10 text-success' : 'bg-base-200 text-base-content/70'">
                                            <span class="h-2 w-2 rounded-full" :class="has(selectedId) ? 'bg-success' : 'bg-base-content/40'"></span>
                                            <span x-text="stateLabel(selectedId)"></span>
                                        </div>

                                        <template x-if="isLocked(selectedId)">
                                            <div class="mt-2 rounded-field bg-base-200 px-3 py-2.5 text-xs leading-5 text-base-content/70">
                                                <i class="fa-solid fa-lock mr-1"></i>This route has endpoint-level grants, so its access is managed endpoint by endpoint on its route security page.
                                            </div>
                                        </template>
                                        <template x-if="!isGated(selectedId)">
                                            <div class="mt-2 rounded-field bg-base-200 px-3 py-2.5 text-xs leading-5 text-base-content/70">
                                                Open to <strong x-text="routesById[selectedId].open_to"></strong>: roles don't apply. Change <code>open_to</code> in the route file.
                                            </div>
                                        </template>
                                        <template x-if="deadEnd(selectedId)">
                                            <div class="mt-2 rounded-field bg-warning/15 px-3 py-2.5 text-xs leading-5">
                                                <strong>Dead end.</strong> <span x-text="`${currentRole()?.name} can open ${openableSources(selectedId).map(id => title(id)).join(', ')}, which links here, but clicking through shows an access error.`"></span>
                                            </div>
                                        </template>
                                        <template x-if="has(selectedId) && blockedTargets(selectedId).length > 0">
                                            <div class="mt-2 rounded-field bg-warning/15 px-3 py-2.5 text-xs leading-5" x-text="`${blockedTargets(selectedId).length} page${blockedTargets(selectedId).length === 1 ? '' : 's'} this links to ${blockedTargets(selectedId).length === 1 ? 'is' : 'are'} closed to ${currentRole()?.name}.`"></div>
                                        </template>
                                        <template x-if="!routeLinked(selectedId)">
                                            <div class="mt-2 rounded-field bg-base-200 px-3 py-2.5 text-xs leading-5 text-base-content/70">Not in any route_links.json, so the pages it links to are unknown.</div>
                                        </template>

                                        <div class="mt-3 flex flex-col gap-2">
                                            <button type="button" class="btn btn-primary btn-sm" x-show="isToggleable(selectedId)" @click="toggle(selectedId)" x-text="toggleLabel(selectedId)"></button>
                                            <button type="button" class="btn btn-outline btn-sm" x-show="isToggleable(selectedId) && has(selectedId) && stageableTargets(selectedId).length > 0" @click="stageGrants(stageableTargets(selectedId))" x-text="`Stage ${stageableTargets(selectedId).length} linked page${stageableTargets(selectedId).length === 1 ? '' : 's'} too`"></button>
                                            <a class="btn btn-ghost btn-sm" :href="`/sysadmin/routes/${selectedId}`">
                                                <i class="fa-solid fa-shield-halved"></i>
                                                Route security
                                            </a>
                                        </div>

                                        <dl class="mt-4 flex flex-col gap-3.5 text-sm">
                                            <div>
                                                <dt class="mb-1 text-[0.6875rem] uppercase tracking-[0.09em] text-base-content/50">Reached from</dt>
                                                <dd>
                                                    <p class="text-xs text-base-content/70" x-show="menuTitles(selectedId).length > 0" x-text="`Menu: ${menuTitles(selectedId).join(', ')}`"></p>
                                                    <ul class="mt-1 flex flex-col gap-1">
                                                        <template x-for="id in inbound[selectedId] || []" :key="id">
                                                            <li class="flex items-center gap-1.5 text-xs">
                                                                <span class="h-1.5 w-1.5 shrink-0 rounded-full" :class="openable(id) ? 'bg-success' : 'bg-base-300'"></span>
                                                                <button type="button" class="link link-hover truncate text-left" @click="select(id)" x-text="title(id)"></button>
                                                            </li>
                                                        </template>
                                                    </ul>
                                                    <p class="text-xs text-base-content/50" x-show="menuTitles(selectedId).length === 0 && !(inbound[selectedId] || []).length">Nothing links here.</p>
                                                </dd>
                                            </div>
                                            <div x-show="(map.links[selectedId] || []).length > 0">
                                                <dt class="mb-1 text-[0.6875rem] uppercase tracking-[0.09em] text-base-content/50">Links to</dt>
                                                <dd>
                                                    <ul class="flex flex-col gap-1">
                                                        <template x-for="id in map.links[selectedId] || []" :key="id">
                                                            <li class="flex items-center gap-1.5 text-xs">
                                                                <span class="h-1.5 w-1.5 shrink-0 rounded-full" :class="openable(id) ? 'bg-success' : 'bg-base-300'"></span>
                                                                <button type="button" class="link link-hover truncate text-left" @click="select(id)" x-text="title(id)"></button>
                                                            </li>
                                                        </template>
                                                    </ul>
                                                </dd>
                                            </div>
                                            <div x-show="isGated(selectedId)">
                                                <dt class="mb-1 text-[0.6875rem] uppercase tracking-[0.09em] text-base-content/50">Other roles that can open it</dt>
                                                <dd class="flex flex-wrap gap-1">
                                                    <template x-for="role in otherRoles(selectedId)" :key="role.id">
                                                        <span class="badge badge-sm badge-outline" x-text="role.name"></span>
                                                    </template>
                                                    <span class="badge badge-sm badge-ghost" x-show="otherRoles(selectedId).length === 0">None</span>
                                                    <span class="badge badge-sm badge-ghost">Sysadmins always</span>
                                                </dd>
                                            </div>
                                        </dl>
                                    </div>
                                </template>
                            </aside>
                        </div>
                    </div>
                </template>

                <!-- Staged changes tray -->
                <div class="fixed bottom-5 left-1/2 z-40 -translate-x-1/2" x-show="currentPending().length > 0" x-transition>
                    <div class="flex items-center gap-3 rounded-box bg-neutral py-2.5 pl-5 pr-2.5 text-sm text-neutral-content shadow-xl">
                        <span x-text="`${currentPending().length} staged change${currentPending().length === 1 ? '' : 's'} for ${currentRole()?.name}`"></span>
                        <button type="button" class="btn btn-ghost btn-sm text-neutral-content" @click="discard()">Discard</button>
                        <button type="button" class="btn btn-primary btn-sm" @click="openReview()">Review</button>
                    </div>
                </div>

                <!-- Review -->
                <dialog class="modal" :class="{ 'modal-open': reviewOpen }">
                    <div class="modal-box max-w-xl">
                        <h3 class="text-lg font-semibold" x-text="`Apply ${currentPending().length} change${currentPending().length === 1 ? '' : 's'} to ${currentRole()?.name}`"></h3>
                        <p class="mt-1 text-sm text-base-content/60" x-text="`${peopleHolding()}. All of these apply together, or none do.`"></p>

                        <div class="mt-4 flex flex-col gap-4">
                            <div x-show="pendingGrants().length > 0">
                                <p class="mb-1.5 text-xs font-medium uppercase tracking-[0.09em] text-success">Grant</p>
                                <ul class="flex flex-col gap-1">
                                    <template x-for="id in pendingGrants()" :key="id">
                                        <li class="flex items-center gap-2 text-sm"><i class="fa-solid fa-plus text-xs text-success"></i><span x-text="title(id)"></span><code class="truncate text-xs text-base-content/50" x-text="routesById[id].url"></code></li>
                                    </template>
                                </ul>
                            </div>
                            <div x-show="pendingRevokes().length > 0">
                                <p class="mb-1.5 text-xs font-medium uppercase tracking-[0.09em] text-error">Revoke</p>
                                <ul class="flex flex-col gap-1">
                                    <template x-for="id in pendingRevokes()" :key="id">
                                        <li class="flex items-center gap-2 text-sm"><i class="fa-solid fa-minus text-xs text-error"></i><span x-text="title(id)"></span><code class="truncate text-xs text-base-content/50" x-text="routesById[id].url"></code></li>
                                    </template>
                                </ul>
                            </div>
                            <div class="rounded-field bg-warning/15 px-3 py-2.5 text-sm" x-show="newDeadEnds().length > 0">
                                <p class="font-medium" x-text="`This leaves ${newDeadEnds().length} new dead end${newDeadEnds().length === 1 ? '' : 's'}:`"></p>
                                <ul class="mt-1 list-disc pl-5 text-xs">
                                    <template x-for="id in newDeadEnds()" :key="id">
                                        <li x-text="`${title(id)}, linked from ${openableSources(id).map(source => title(source)).join(', ')}`"></li>
                                    </template>
                                </ul>
                            </div>
                            <div role="alert" class="alert alert-error items-start text-sm" x-show="conflict">
                                <i class="fa-solid fa-circle-xmark mt-0.5"></i>
                                <p x-text="conflict"></p>
                            </div>
                        </div>

                        <div class="modal-action">
                            <button type="button" class="btn btn-ghost" @click="reviewOpen = false">Back</button>
                            <button type="button" class="btn btn-outline" x-show="conflict" @click="reloadAfterConflict()">Discard and reload</button>
                            <button type="button" class="btn btn-primary" x-show="!conflict" :disabled="applying" @click="apply()">
                                <span class="loading loading-spinner loading-xs" x-show="applying"></span>
                                Apply
                            </button>
                        </div>
                    </div>
                    <form method="dialog" class="modal-backdrop">
                        <button @click="reviewOpen = false">close</button>
                    </form>
                </dialog>
            </div>

            <script>
                document.addEventListener("alpine:init", () => {
                    Alpine.data("route_access", () => ({
                        loading: true,
                        map: { sections: [], top_links: [], routes: [], links: {}, roles: [], access: {}, locked: [], ghosts: [], problems: [] },
                        roleId: null,
                        pending: {},
                        selectedId: null,
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
                                if (this.isToggleable(node.dataset.routeId)) this.toggle(node.dataset.routeId);
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
                        // A linked page shows its URL with the part it shares with the page above trimmed off.
                        rowLabel(id, parent) {
                            if (this.menuTitles(id).length || !parent) return this.title(id);
                            const url = this.routesById[id].url;
                            const parentParts = this.routesById[parent].url.split('/');
                            const parts = url.split('/');
                            let shared = 0;
                            while (shared < parts.length - 1 && parts[shared] === parentParts[shared]) shared++;
                            return shared > 1 ? '…/' + parts.slice(shared).join('/') : url;
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
                            return classes.join(' ');
                        },
                        matches(id) {
                            if (this.issuesOnly && !this.deadEnd(id)) return false;
                            const term = this.search.trim().toLowerCase();
                            if (!term) return true;
                            return this.title(id).toLowerCase().includes(term) || this.routesById[id].url.toLowerCase().includes(term);
                        },

                        // ----- staging -----
                        select(id) { this.selectedId = id; },
                        selectRole(id) { this.roleId = id; this.conflict = ''; },
                        stage(id, granted) {
                            if (!this.isToggleable(id)) return;
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

        </cf_layout_default>
    </cffunction>

</cfcomponent>
