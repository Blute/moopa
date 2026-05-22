<cfcomponent key="ba297912-e9f9-4f5a-939a-2851c1c18a6e" open_to="security">

    <cffunction name="getImpersonationRouteData" access="private" returntype="struct" output="false">
        <cfset var mooRoute = application.lib.db.getService("moo_route") />
        <cfset var routeData = mooRoute.parseRoute("/sysadmin/impersonation/") />
        <cfif structIsEmpty(routeData.stRoute ?: {})>
            <cfthrow type="moopa.impersonation.routeMissing" message="The impersonation sysadmin route is not registered. Re-initialise the application." />
        </cfif>
        <cfif NOT structKeyExists(routeData.stRoute.endpoints, "create_grant")>
            <cfthrow type="moopa.impersonation.endpointMissing" message="The create_grant endpoint is not registered. Re-initialise the application." />
        </cfif>
        <cfreturn routeData />
    </cffunction>


    <cffunction name="load">
        <cfset var routeData = getImpersonationRouteData() />
        <cfset var mooRoute = application.lib.db.getService("moo_route") />
        <cfset var accessors = mooRoute.getEffectiveAccessors(route="/sysadmin/impersonation/", endpoint="create_grant") />

        <cfquery name="qActivity">
            SELECT COALESCE(json_agg(row_to_json(data) ORDER BY created_at DESC)::text, '[]') AS recordset
            FROM (
                SELECT g.id::text,
                       g.created_at,
                       g.expires_at,
                       g.consumed_at,
                       g.request_ip,
                       g.consume_ip,
                       ip.id::text AS impersonator_id,
                       ip.full_name AS impersonator_name,
                       ip.email AS impersonator_email,
                       tp.id::text AS target_id,
                       tp.full_name AS target_name,
                       tp.email AS target_email,
                       tp.app_name AS target_app_name,
                       CASE
                           WHEN g.consumed_at IS NOT NULL THEN 'consumed'
                           WHEN g.expires_at <= now() THEN 'expired'
                           ELSE 'active'
                       END AS status
                FROM moo_impersonation_grant g
                INNER JOIN moo_profile ip ON ip.id = g.impersonator_profile_id
                INNER JOIN moo_profile tp ON tp.id = g.target_profile_id
                ORDER BY g.created_at DESC
                LIMIT 50
            ) data
        </cfquery>

        <cfreturn {
            accessors = accessors,
            route_id = routeData.stRoute.id,
            endpoint_id = routeData.stRoute.endpoints.create_grant.id,
            activity = deserializeJSON(qActivity.recordset)
        } />
    </cffunction>


    <cffunction name="create_grant">
        <cfset var profileId = request.data.profile_id ?: '' />

        <cfif NOT len(profileId)>
            <cfreturn { success = false, error = "profile_id is required" } />
        </cfif>

        <cftry>
            <cfset var result = application.lib.impersonate.createGrant(profileId) />
            <cfreturn result />
            <cfcatch>
                <cfreturn { success = false, error = cfcatch.message } />
            </cfcatch>
        </cftry>
    </cffunction>


    <cffunction name="search.targets">
        <cfset var term = trim(url.q ?: "") />
        <cfquery name="qTargets">
            SELECT COALESCE(json_agg(row_to_json(data) ORDER BY full_name)::text, '[]') AS recordset
            FROM (
                SELECT id::text, full_name, email, app_name
                FROM moo_profile
                WHERE can_login = true
                  AND NOT (app_name = 'hub' AND lower(coalesce(email, '')) IN (<cfqueryparam cfsqltype="varchar" value="#getSysadminEmailList()#" list="true" />))
                  <cfif len(term)>
                    AND (full_name ILIKE <cfqueryparam cfsqltype="varchar" value="%#term#%" />
                         OR email ILIKE <cfqueryparam cfsqltype="varchar" value="%#term#%" />)
                  </cfif>
                ORDER BY full_name
                LIMIT 20
            ) data
        </cfquery>
        <cfreturn qTargets.recordset />
    </cffunction>


    <cffunction name="search.profiles">
        <cfset var term = trim(url.q ?: "") />
        <cfquery name="qProfiles">
            SELECT COALESCE(json_agg(row_to_json(data) ORDER BY full_name)::text, '[]') AS recordset
            FROM (
                SELECT id::text, full_name, email, app_name
                FROM moo_profile
                WHERE can_login = true
                  AND app_name = 'hub'
                  <cfif len(term)>
                    AND (full_name ILIKE <cfqueryparam cfsqltype="varchar" value="%#term#%" />
                         OR email ILIKE <cfqueryparam cfsqltype="varchar" value="%#term#%" />)
                  </cfif>
                ORDER BY full_name
                LIMIT 20
            ) data
        </cfquery>
        <cfreturn qProfiles.recordset />
    </cffunction>


    <cffunction name="search.roles">
        <cfset var term = trim(url.q ?: "") />
        <cfquery name="qRoles">
            SELECT COALESCE(json_agg(row_to_json(data) ORDER BY name)::text, '[]') AS recordset
            FROM (
                SELECT id::text, name
                FROM moo_role
                WHERE 1 = 1
                  <cfif len(term)>
                    AND name ILIKE <cfqueryparam cfsqltype="varchar" value="%#term#%" />
                  </cfif>
                ORDER BY name
                LIMIT 20
            ) data
        </cfquery>
        <cfreturn qRoles.recordset />
    </cffunction>


    <cffunction name="toggleProfileAccess">
        <cfif NOT application.lib.auth.isSysAdmin()>
            <cfthrow type="moopa.impersonation.sysadminRequired" message="Only sysadmins can change impersonation access." />
        </cfif>
        <cfset var profileId = request.data.profile_id ?: "" />
        <cfset var routeData = getImpersonationRouteData() />
        <cfset var routeId = routeData.stRoute.id />
        <cfset var endpointId = routeData.stRoute.endpoints.create_grant.id />

        <cfif NOT len(profileId)>
            <cfthrow type="moopa.impersonation.missingProfile" message="profile_id is required." />
        </cfif>

        <cfquery name="qProfile" returntype="array">
            SELECT id::text
            FROM moo_profile
            WHERE id = <cfqueryparam cfsqltype="other" value="#profileId#" />
              AND app_name = 'hub'
              AND can_login = true
        </cfquery>
        <cfif NOT arrayLen(qProfile)>
            <cfthrow type="moopa.impersonation.invalidProfile" message="Impersonation access can only be granted to login-enabled Hub profiles." />
        </cfif>

        <cfquery name="qExisting" returntype="array">
            SELECT id::text
            FROM moo_route_permission
            WHERE route_id = <cfqueryparam cfsqltype="other" value="#routeId#" />
              AND endpoint_id = <cfqueryparam cfsqltype="other" value="#endpointId#" />
              AND profile_id = <cfqueryparam cfsqltype="other" value="#profileId#" />
        </cfquery>

        <cfif arrayLen(qExisting)>
            <cfset application.lib.db.delete(table_name="moo_route_permission", id=qExisting[1].id) />
        <cfelse>
            <cfquery name="qEnsureProfileBridge">
                INSERT INTO moo_route_profiles (primary_id, foreign_id)
                VALUES (
                    <cfqueryparam cfsqltype="other" value="#routeId#" />,
                    <cfqueryparam cfsqltype="other" value="#profileId#" />
                )
                ON CONFLICT DO NOTHING
            </cfquery>
            <cfset application.lib.db.save(table_name="moo_route_permission", data={
                route_id = routeId,
                endpoint_id = endpointId,
                profile_id = profileId,
                is_granted = true
            }) />
        </cfif>

        <cfreturn { success = true } />
    </cffunction>


    <cffunction name="toggleRoleAccess">
        <cfif NOT application.lib.auth.isSysAdmin()>
            <cfthrow type="moopa.impersonation.sysadminRequired" message="Only sysadmins can change impersonation access." />
        </cfif>
        <cfset var roleId = request.data.role_id ?: "" />
        <cfset var routeData = getImpersonationRouteData() />
        <cfset var routeId = routeData.stRoute.id />
        <cfset var endpointId = routeData.stRoute.endpoints.create_grant.id />

        <cfif NOT len(roleId)>
            <cfthrow type="moopa.impersonation.missingRole" message="role_id is required." />
        </cfif>

        <cfquery name="qExisting" returntype="array">
            SELECT id::text
            FROM moo_route_permission
            WHERE route_id = <cfqueryparam cfsqltype="other" value="#routeId#" />
              AND endpoint_id = <cfqueryparam cfsqltype="other" value="#endpointId#" />
              AND role_id = <cfqueryparam cfsqltype="other" value="#roleId#" />
        </cfquery>

        <cfif arrayLen(qExisting)>
            <cfset application.lib.db.delete(table_name="moo_route_permission", id=qExisting[1].id) />
        <cfelse>
            <cfquery name="qEnsureRoleBridge">
                INSERT INTO moo_route_roles (primary_id, foreign_id)
                VALUES (
                    <cfqueryparam cfsqltype="other" value="#routeId#" />,
                    <cfqueryparam cfsqltype="other" value="#roleId#" />
                )
                ON CONFLICT DO NOTHING
            </cfquery>
            <cfset application.lib.db.save(table_name="moo_route_permission", data={
                route_id = routeId,
                endpoint_id = endpointId,
                role_id = roleId,
                is_granted = true
            }) />
        </cfif>

        <cfreturn { success = true } />
    </cffunction>


    <cffunction name="getSysadminEmailList" access="private" returntype="string" output="false">
        <cfset var emails = "" />
        <cfset var email = "" />
        <cfloop list="#server.system.environment.SYSADMIN_EMAIL ?: ''#" item="email">
            <cfset email = lCase(trim(email)) />
            <cfif len(email)>
                <cfset emails = listAppend(emails, email) />
            </cfif>
        </cfloop>
        <cfif NOT len(emails)>
            <cfreturn "__moopa_no_configured_sysadmin_email__" />
        </cfif>
        <cfreturn emails />
    </cffunction>


    <cffunction name="get">
        <cf_layout_default>
            <div x-data="sysadmin_impersonation" x-cloak class="flex flex-col gap-4 lg:gap-5">
                <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                    <div class="min-w-0">
                        <div class="flex items-center gap-3">
                            <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-box border border-base-300 bg-base-100 text-primary">
                                <i class="fa-solid fa-user-secret text-base"></i>
                            </div>
                            <div class="min-w-0">
                                <div class="flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
                                    <h1 class="text-[1.625rem] font-semibold leading-none tracking-[-0.03em]">Impersonation</h1>
                                    <span class="text-[0.6875rem] font-medium uppercase tracking-[0.11em] text-base-content/42" x-text="summary()"></span>
                                </div>
                                <p class="mt-1 max-w-[68ch] text-sm leading-5 text-base-content/62">Manage who can create impersonation links and review recent grant activity.</p>
                            </div>
                        </div>
                    </div>
                    <button class="btn btn-primary btn-sm gap-2" @click="$refs.targetModal.showModal()">
                        <i class="fa-solid fa-mask"></i>
                        Create link
                    </button>
                </div>

                <template x-if="loading">
                    <div class="rounded-lg border border-base-300 bg-base-100 p-8 text-center text-base-content/60">
                        <span class="loading loading-spinner loading-md"></span>
                        <p class="mt-2">Loading impersonation access…</p>
                    </div>
                </template>

                <div x-show="!loading" class="grid gap-4 md:grid-cols-4">
                    <div class="stats rounded-lg border border-base-300 bg-base-100 shadow-none md:col-span-4">
                        <div class="stat">
                            <div class="stat-title">Effective impersonators</div>
                            <div class="stat-value text-primary" x-text="accessors.effective_profiles?.length || 0"></div>
                        </div>
                        <div class="stat">
                            <div class="stat-title">Sysadmins</div>
                            <div class="stat-value" x-text="accessors.sysadmins?.length || 0"></div>
                        </div>
                        <div class="stat">
                            <div class="stat-title">Direct grants</div>
                            <div class="stat-value" x-text="accessors.direct_profiles?.length || 0"></div>
                        </div>
                        <div class="stat">
                            <div class="stat-title">Role grants</div>
                            <div class="stat-value" x-text="accessors.roles?.length || 0"></div>
                        </div>
                    </div>
                </div>

                <div x-show="!loading" class="grid gap-4 xl:grid-cols-[minmax(0,1fr)_24rem]">
                    <section class="overflow-hidden rounded-lg border border-base-300 bg-base-100">
                        <div class="border-b border-base-300 px-4 py-3 flex items-center justify-between gap-3">
                            <div>
                                <h2 class="font-semibold">Who can impersonate</h2>
                                <p class="text-sm text-base-content/58">Resolved from sysadmin status, direct endpoint grants, and role endpoint grants.</p>
                            </div>
                        </div>
                        <div class="overflow-auto">
                            <table class="table table-sm w-full">
                                <thead><tr><th>Person</th><th>App</th><th>Source</th></tr></thead>
                                <tbody>
                                    <template x-for="person in accessors.effective_profiles || []" :key="person.id">
                                        <tr>
                                            <td>
                                                <div class="font-medium" x-text="person.full_name || 'Unnamed profile'"></div>
                                                <div class="text-xs text-base-content/55" x-text="person.email"></div>
                                            </td>
                                            <td><span class="badge badge-ghost badge-sm font-mono" x-text="person.app_name || '—'"></span></td>
                                            <td>
                                                <div class="flex flex-wrap gap-1">
                                                    <template x-for="source in person.sources" :key="source">
                                                        <span class="badge badge-sm" :class="source === 'Sysadmin' ? 'badge-primary' : 'badge-soft badge-neutral'" x-text="source"></span>
                                                    </template>
                                                </div>
                                            </td>
                                        </tr>
                                    </template>
                                    <tr x-show="!(accessors.effective_profiles || []).length"><td colspan="3" class="py-8 text-center text-base-content/50">No delegated impersonators found.</td></tr>
                                </tbody>
                            </table>
                        </div>
                    </section>

                    <aside class="space-y-4">
                        <section class="rounded-lg border border-base-300 bg-base-100 p-4">
                            <h2 class="font-semibold">Grant access</h2>
                            <p class="mt-1 text-sm text-base-content/58">Sysadmins always have access. These controls delegate the create-grant endpoint.</p>
                            <div class="mt-4 space-y-4">
                                <div>
                                    <label class="input input-sm input-bordered flex items-center gap-2">
                                        <i class="fa-solid fa-user text-base-content/40"></i>
                                        <input class="grow" x-model="profile_search" placeholder="Search profile to toggle" @input.debounce.300ms="searchProfiles()">
                                    </label>
                                    <div class="mt-2 max-h-48 overflow-auto divide-y divide-base-300 rounded-lg border border-base-300" x-show="profile_results.length">
                                        <template x-for="profile in profile_results" :key="profile.id">
                                            <button type="button" class="w-full px-3 py-2 text-left hover:bg-base-200/60" @click="toggleProfileAccess(profile)">
                                                <span class="block truncate text-sm font-medium" x-text="profile.full_name || 'Unnamed profile'"></span>
                                                <span class="block truncate text-xs text-base-content/55" x-text="`${profile.email || '—'} · ${profile.app_name || '—'}`"></span>
                                            </button>
                                        </template>
                                    </div>
                                </div>
                                <div>
                                    <label class="input input-sm input-bordered flex items-center gap-2">
                                        <i class="fa-solid fa-shield-halved text-base-content/40"></i>
                                        <input class="grow" x-model="role_search" placeholder="Search role to toggle" @input.debounce.300ms="searchRoles()">
                                    </label>
                                    <div class="mt-2 max-h-48 overflow-auto divide-y divide-base-300 rounded-lg border border-base-300" x-show="role_results.length">
                                        <template x-for="role in role_results" :key="role.id">
                                            <button type="button" class="w-full px-3 py-2 text-left hover:bg-base-200/60" @click="toggleRoleAccess(role)">
                                                <span class="block truncate text-sm font-medium" x-text="role.name"></span>
                                            </button>
                                        </template>
                                    </div>
                                </div>
                            </div>
                        </section>
                    </aside>
                </div>

                <section x-show="!loading" class="overflow-hidden rounded-lg border border-base-300 bg-base-100">
                    <div class="border-b border-base-300 px-4 py-3">
                        <h2 class="font-semibold">Recent activity</h2>
                        <p class="text-sm text-base-content/58">Last 50 impersonation grants. Tokens are intentionally never displayed.</p>
                    </div>
                    <div class="overflow-auto">
                        <table class="table table-sm w-full">
                            <thead><tr><th>Created</th><th>Impersonator</th><th>Target</th><th>Status</th><th>IP</th></tr></thead>
                            <tbody>
                                <template x-for="grant in activity" :key="grant.id">
                                    <tr>
                                        <td class="font-mono text-xs" x-text="compactDate(grant.created_at)"></td>
                                        <td><div x-text="grant.impersonator_name"></div><div class="text-xs text-base-content/55" x-text="grant.impersonator_email"></div></td>
                                        <td><div x-text="grant.target_name"></div><div class="text-xs text-base-content/55"><span x-text="grant.target_email"></span> · <span x-text="grant.target_app_name"></span></div></td>
                                        <td><span class="badge badge-sm" :class="grant.status === 'consumed' ? 'badge-success' : (grant.status === 'active' ? 'badge-warning' : 'badge-ghost')" x-text="grant.status"></span></td>
                                        <td class="font-mono text-xs"><span x-text="grant.request_ip || '—'"></span><span x-show="grant.consume_ip"> → </span><span x-text="grant.consume_ip || ''"></span></td>
                                    </tr>
                                </template>
                                <tr x-show="!activity.length"><td colspan="5" class="py-8 text-center text-base-content/50">No impersonation grants yet.</td></tr>
                            </tbody>
                        </table>
                    </div>
                </section>

                <dialog x-ref="targetModal" class="modal">
                    <div class="modal-box max-w-2xl">
                        <h3 class="text-lg font-semibold">Create impersonation link</h3>
                        <p class="mt-1 text-sm text-base-content/60">Search for the user you want to impersonate. Hub profiles are allowed, except configured sysadmins. The link is copied to your clipboard and expires in 5 minutes.</p>
                        <label class="input input-bordered mt-4 flex items-center gap-2">
                            <i class="fa-solid fa-magnifying-glass text-base-content/40"></i>
                            <input class="grow" placeholder="Search name or email" x-model="target_search" @input.debounce.300ms="searchTargets()">
                        </label>
                        <div class="mt-3 max-h-80 overflow-auto divide-y divide-base-300 rounded-lg border border-base-300">
                            <template x-for="target in targets" :key="target.id">
                                <button type="button" class="flex w-full items-center justify-between gap-3 px-3 py-2 text-left hover:bg-base-200/60" @click="createGrant(target)">
                                    <span class="min-w-0"><span class="block truncate font-medium" x-text="target.full_name || 'Unnamed profile'"></span><span class="block truncate text-xs text-base-content/55" x-text="`${target.email || '—'} · ${target.app_name || '—'}`"></span></span>
                                    <i class="fa-solid fa-copy text-base-content/45"></i>
                                </button>
                            </template>
                            <div x-show="target_search && !targets.length" class="px-3 py-6 text-center text-sm text-base-content/50">No matching profiles.</div>
                        </div>
                        <div class="modal-action"><form method="dialog"><button class="btn">Close</button></form></div>
                    </div>
                    <form method="dialog" class="modal-backdrop"><button>close</button></form>
                </dialog>

                <script>
                document.addEventListener('alpine:init', () => {
                    Alpine.data('sysadmin_impersonation', () => ({
                        loading: true,
                        accessors: {},
                        activity: [],
                        profile_search: '',
                        profile_results: [],
                        role_search: '',
                        role_results: [],
                        target_search: '',
                        targets: [],
                        async init() { await this.load(); },
                        async load() {
                            this.loading = true;
                            const data = await req({ endpoint: 'load' });
                            this.accessors = data.accessors || {};
                            this.activity = data.activity || [];
                            this.loading = false;
                        },
                        summary() { return `${this.accessors.effective_profiles?.length || 0} people`; },
                        compactDate(value) { return value ? new Date(value).toLocaleString() : '—'; },
                        async searchProfiles() {
                            const q = this.profile_search.trim();
                            this.profile_results = q ? await req({ endpoint: 'search.profiles', q }) : [];
                        },
                        async searchRoles() {
                            const q = this.role_search.trim();
                            this.role_results = q ? await req({ endpoint: 'search.roles', q }) : [];
                        },
                        async toggleProfileAccess(profile) {
                            await req({ endpoint: 'toggleProfileAccess', body: { profile_id: profile.id } });
                            this.profile_search = '';
                            this.profile_results = [];
                            await this.load();
                            window.toast?.({ type: 'success', message: 'Profile access updated', duration: 2000 });
                        },
                        async toggleRoleAccess(role) {
                            await req({ endpoint: 'toggleRoleAccess', body: { role_id: role.id } });
                            this.role_search = '';
                            this.role_results = [];
                            await this.load();
                            window.toast?.({ type: 'success', message: 'Role access updated', duration: 2000 });
                        },
                        async searchTargets() {
                            const q = this.target_search.trim();
                            this.targets = q ? await req({ endpoint: 'search.targets', q }) : [];
                        },
                        async createGrant(target) {
                            const result = await req({ endpoint: 'create_grant', body: { profile_id: target.id } });
                            if (result?.success) {
                                await navigator.clipboard.writeText(result.url);
                                this.$refs.targetModal.close();
                                this.target_search = '';
                                this.targets = [];
                                await this.load();
                                window.toast?.({ type: 'success', title: 'Impersonation URL copied', description: 'Paste into an incognito/private window. Link expires in 5 minutes.', duration: 8000, icon: 'fa-mask' });
                            } else {
                                window.toast?.({ type: 'error', title: 'Impersonation failed', description: result?.error || 'Unknown error', duration: 5000, icon: 'fa-triangle-exclamation' });
                            }
                        }
                    }));
                });
                </script>
            </div>
        </cf_layout_default>
    </cffunction>

</cfcomponent>
