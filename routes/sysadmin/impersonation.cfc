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
                FROM moo_login_grant g
                INNER JOIN moo_profile ip ON ip.id = g.impersonator_profile_id
                INNER JOIN moo_profile tp ON tp.id = g.target_profile_id
                WHERE g.kind = 'impersonation'
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
        <cfmodule template="/moopa/tags/moopa_layout.cfm" title="Impersonation">
            <div x-data="sysadmin_impersonation" x-cloak class="page">
                <div class="page-header">
                    <div>
                        <div class="eyebrow" x-text="summary()"></div>
                        <h1>Impersonation</h1>
                        <p class="page-lede">Who can create impersonation links, and recent link activity.</p>
                    </div>
                    <div class="page-actions">
                        <button type="button" class="btn btn-primary btn-sm" @click="$refs.targetModal.showModal()"><i class="fa-solid fa-mask"></i> Create link</button>
                    </div>
                </div>

                <div class="card empty" x-show="loading"><i class="fa-solid fa-spinner fa-spin"></i>Loading impersonation access…</div>

                <div class="auto-grid" style="--auto-min: 11rem" x-show="!loading">
                    <div class="card stat"><div class="stat-label">Effective impersonators</div><div class="stat-value text-signal" x-text="accessors.effective_profiles?.length || 0"></div></div>
                    <div class="card stat"><div class="stat-label">Sysadmins</div><div class="stat-value" x-text="accessors.sysadmins?.length || 0"></div></div>
                    <div class="card stat"><div class="stat-label">Direct grants</div><div class="stat-value" x-text="accessors.direct_profiles?.length || 0"></div></div>
                    <div class="card stat"><div class="stat-label">Role grants</div><div class="stat-value" x-text="accessors.roles?.length || 0"></div></div>
                </div>

                <div class="split split-end" style="--split-aside: 22rem" x-show="!loading">
                    <section class="card">
                        <div class="card-header">
                            <div>
                                <h2 class="card-title">Who can impersonate</h2>
                                <p class="card-sub">From sysadmin status, direct endpoint grants and role endpoint grants.</p>
                            </div>
                        </div>
                        <div class="table-wrap">
                            <table class="table table-sm">
                                <thead><tr><th>Person</th><th>App</th><th>Source</th></tr></thead>
                                <tbody>
                                    <template x-for="person in accessors.effective_profiles || []" :key="person.id">
                                        <tr>
                                            <td><div class="cell-main" x-text="person.full_name || 'Unnamed profile'"></div><div class="cell-sub" x-text="person.email"></div></td>
                                            <td><span class="badge mono" x-text="person.app_name || '—'"></span></td>
                                            <td>
                                                <div class="cluster" style="--cluster-gap: var(--sp-1)">
                                                    <template x-for="source in person.sources" :key="source">
                                                        <span class="badge" :class="source === 'Sysadmin' ? 'badge-signal' : ''" x-text="source"></span>
                                                    </template>
                                                </div>
                                            </td>
                                        </tr>
                                    </template>
                                    <tr x-show="!(accessors.effective_profiles || []).length"><td colspan="3" class="empty">No delegated impersonators.</td></tr>
                                </tbody>
                            </table>
                        </div>
                    </section>

                    <aside class="card">
                        <div class="card-header">
                            <div>
                                <h2 class="card-title">Grant access</h2>
                                <p class="card-sub">Sysadmins always have access. These delegate the create-link endpoint.</p>
                            </div>
                        </div>
                        <div class="card-body stack">
                            <div class="field">
                                <label class="label" for="impersonation-profile-search">Profile</label>
                                <div class="input-icon">
                                    <i class="fa-solid fa-user"></i>
                                    <input id="impersonation-profile-search" class="input input-sm" x-model="profile_search" placeholder="Search a profile to toggle" @input.debounce.300ms="searchProfiles()">
                                </div>
                                <div class="card list-rows" style="max-height: 12rem; overflow: auto; box-shadow: none" x-show="profile_results.length">
                                    <template x-for="profile in profile_results" :key="profile.id">
                                        <button type="button" class="list-row" @click="toggleProfileAccess(profile)">
                                            <span class="min0"><span class="cell-main truncate" style="display: block" x-text="profile.full_name || 'Unnamed profile'"></span><span class="cell-sub truncate" style="display: block" x-text="`${profile.email || '—'} · ${profile.app_name || '—'}`"></span></span>
                                        </button>
                                    </template>
                                </div>
                            </div>
                            <div class="field">
                                <label class="label" for="impersonation-role-search">Role</label>
                                <div class="input-icon">
                                    <i class="fa-solid fa-shield-halved"></i>
                                    <input id="impersonation-role-search" class="input input-sm" x-model="role_search" placeholder="Search a role to toggle" @input.debounce.300ms="searchRoles()">
                                </div>
                                <div class="card list-rows" style="max-height: 12rem; overflow: auto; box-shadow: none" x-show="role_results.length">
                                    <template x-for="role in role_results" :key="role.id">
                                        <button type="button" class="list-row" @click="toggleRoleAccess(role)"><span class="cell-main truncate" x-text="role.name"></span></button>
                                    </template>
                                </div>
                            </div>
                        </div>
                    </aside>
                </div>

                <section class="card" x-show="!loading">
                    <div class="card-header">
                        <div>
                            <h2 class="card-title">Recent activity</h2>
                            <p class="card-sub">The last 50 impersonation links. Their tokens are never shown.</p>
                        </div>
                    </div>
                    <div class="table-wrap">
                        <table class="table table-sm">
                            <thead><tr><th>Created</th><th>Impersonator</th><th>Target</th><th>Status</th><th>IP</th></tr></thead>
                            <tbody>
                                <template x-for="grant in activity" :key="grant.id">
                                    <tr>
                                        <td class="mono muted nowrap" x-text="compactDate(grant.created_at)"></td>
                                        <td><div class="cell-main" x-text="grant.impersonator_name"></div><div class="cell-sub" x-text="grant.impersonator_email"></div></td>
                                        <td><div class="cell-main" x-text="grant.target_name"></div><div class="cell-sub"><span x-text="grant.target_email"></span> · <span x-text="grant.target_app_name"></span></div></td>
                                        <td><span class="badge" :class="grant.status === 'consumed' ? 'badge-success' : (grant.status === 'active' ? 'badge-warning' : '')" x-text="grant.status"></span></td>
                                        <td class="mono muted"><span x-text="grant.request_ip || '—'"></span><span x-show="grant.consume_ip"> → </span><span x-text="grant.consume_ip || ''"></span></td>
                                    </tr>
                                </template>
                                <tr x-show="!activity.length"><td colspan="5" class="empty">No impersonation links yet.</td></tr>
                            </tbody>
                        </table>
                    </div>
                </section>

                <dialog x-ref="targetModal" class="modal" aria-labelledby="impersonation-target-title">
                    <div class="modal-header">
                        <div>
                            <h2 id="impersonation-target-title" class="card-title">Create an impersonation link</h2>
                            <p class="card-sub">Find the person to impersonate. Hub profiles are allowed, except the configured sysadmins. The link is copied to your clipboard and expires in 5 minutes.</p>
                        </div>
                        <button type="button" class="btn btn-ghost btn-icon btn-sm" @click="$refs.targetModal.close()" aria-label="Close"><i class="fa-solid fa-xmark"></i></button>
                    </div>
                    <div class="modal-body stack">
                        <div class="input-icon">
                            <i class="fa-solid fa-magnifying-glass"></i>
                            <input class="input" placeholder="Search name or email" x-model="target_search" @input.debounce.300ms="searchTargets()" aria-label="Search name or email">
                        </div>
                        <div class="card list-rows" style="box-shadow: none" x-show="targets.length || target_search">
                            <template x-for="target in targets" :key="target.id">
                                <button type="button" class="list-row" @click="createGrant(target)">
                                    <span class="min0"><span class="cell-main truncate" style="display: block" x-text="target.full_name || 'Unnamed profile'"></span><span class="cell-sub truncate" style="display: block" x-text="`${target.email || '—'} · ${target.app_name || '—'}`"></span></span>
                                    <i class="fa-solid fa-copy muted"></i>
                                </button>
                            </template>
                            <div class="empty" x-show="target_search && !targets.length">No matching profiles.</div>
                        </div>
                    </div>
                    <div class="modal-footer"><button type="button" class="btn btn-sm" @click="$refs.targetModal.close()">Close</button></div>
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
                        summary() { const n = this.accessors.effective_profiles?.length || 0; return `${n} ${n === 1 ? 'person' : 'people'}`; },
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
        </cfmodule>
    </cffunction>

</cfcomponent>
