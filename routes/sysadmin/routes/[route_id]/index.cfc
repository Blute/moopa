<cfcomponent key="2befa9ac-1cc6-483f-bde1-1cca8cc1a818" open_to="security">


    <cffunction name="assertRouteInCurrentApp" access="private" returntype="void" output="false">
        <cfargument name="route_id" type="string" required="true" />

        <cfquery name="qRouteScope">
            SELECT id
            FROM moo_route
            WHERE id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
              AND app_name = <cfqueryparam cfsqltype="varchar" value="#application.app_name#" />
        </cfquery>

        <cfif qRouteScope.recordcount NEQ 1>
            <cfthrow type="moopa.security.routeWrongApp" message="Route '#arguments.route_id#' does not belong to app '#application.app_name#'." />
        </cfif>
    </cffunction>


    <cffunction name="refusedUnlessSysadmin" access="private" returntype="boolean" output="false" hint="Changing who can reach a route is for sysadmins only. True, after answering 403, when the caller isn't one.">
        <cfif application.lib.auth.isSysAdmin()>
            <cfreturn false />
        </cfif>
        <cfheader statuscode="403" statustext="Forbidden" />
        <cfreturn true />
    </cffunction>


    <cffunction name="getRouteAccessSubjects" access="private" returntype="struct" output="false">
        <cfargument name="route_id" type="string" required="true" />

        <cfset var qSubjects = "" />

        <cfquery name="qSubjects">
            WITH profile_subjects AS (
                SELECT
                    moo_route_profiles.sequence,
                    moo_profile.id::text AS id,
                    'profile' AS type,
                    COALESCE(NULLIF(moo_profile.full_name, ''), NULLIF(moo_profile.preferred_name, ''), moo_profile.email, moo_profile.id::text) AS label,
                    moo_profile.full_name,
                    moo_profile.preferred_name,
                    moo_profile.email
                FROM moo_route_profiles
                INNER JOIN moo_profile ON moo_profile.id = moo_route_profiles.foreign_id
                WHERE moo_route_profiles.primary_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
            ), role_subjects AS (
                SELECT
                    moo_route_roles.sequence,
                    moo_role.id::text AS id,
                    'role' AS type,
                    moo_role.name AS label,
                    moo_role.name
                FROM moo_route_roles
                INNER JOIN moo_role ON moo_role.id = moo_route_roles.foreign_id
                WHERE moo_route_roles.primary_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
            ), subjects AS (
                SELECT 1 AS sort_group, sequence, id, type, label FROM profile_subjects
                UNION ALL
                SELECT 2 AS sort_group, sequence, id, type, label FROM role_subjects
            )
            SELECT row_to_json(payload)::text AS data
            FROM (
                SELECT
                    COALESCE((
                        SELECT jsonb_agg(to_jsonb(profile_subjects) - 'sequence' ORDER BY sequence)
                        FROM profile_subjects
                    ), '[]'::jsonb) AS profiles,
                    COALESCE((
                        SELECT jsonb_agg(to_jsonb(role_subjects) - 'sequence' ORDER BY sequence)
                        FROM role_subjects
                    ), '[]'::jsonb) AS roles,
                    COALESCE((
                        SELECT jsonb_agg(to_jsonb(subjects) - 'sort_group' - 'sequence' ORDER BY sort_group, sequence)
                        FROM subjects
                    ), '[]'::jsonb) AS subjects
            ) payload
        </cfquery>

        <cfreturn deserializeJSON(qSubjects.data) />
    </cffunction>


    <cffunction name="getRouteEffectiveAccessors" access="private" returntype="array" output="false">
        <cfargument name="route_id" type="string" required="true" />

        <cfset var qAccessors = "" />
        <cfset var sysadminEmails = application.lib.signin.sysadminEmails() />

        <cfif NOT len(sysadminEmails)>
            <cfset sysadminEmails = "__moopa_no_configured_sysadmin_email__" />
        </cfif>

        <cfquery name="qAccessors">
            WITH direct_profiles AS (
                SELECT DISTINCT
                    moo_profile.id::text AS profile_id,
                    COALESCE(NULLIF(moo_profile.full_name, ''), NULLIF(moo_profile.preferred_name, ''), moo_profile.email, moo_profile.id::text) AS label,
                    moo_profile.email,
                    moo_profile.can_login,
                    'Direct profile' AS source
                FROM moo_route_permission
                INNER JOIN moo_profile ON moo_profile.id = moo_route_permission.profile_id
                WHERE moo_route_permission.route_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
                  AND moo_route_permission.is_granted = true
                  AND moo_profile.app_name = <cfqueryparam cfsqltype="varchar" value="#application.app_name#" />
                  AND moo_route_permission.profile_id IN (
                      SELECT foreign_id
                      FROM moo_route_profiles
                      WHERE primary_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
                  )
            ), role_profiles AS (
                SELECT DISTINCT
                    moo_profile.id::text AS profile_id,
                    COALESCE(NULLIF(moo_profile.full_name, ''), NULLIF(moo_profile.preferred_name, ''), moo_profile.email, moo_profile.id::text) AS label,
                    moo_profile.email,
                    moo_profile.can_login,
                    'Role: ' || moo_role.name AS source
                FROM moo_route_permission
                INNER JOIN moo_role ON moo_role.id = moo_route_permission.role_id
                INNER JOIN moo_profile_roles on moo_profile_roles.foreign_id = moo_role.id
                INNER JOIN moo_profile on moo_profile.id = moo_profile_roles.primary_id
                WHERE moo_route_permission.route_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
                  AND moo_route_permission.is_granted = true
                  AND moo_profile.app_name = <cfqueryparam cfsqltype="varchar" value="#application.app_name#" />
                  AND moo_route_permission.role_id IN (
                      SELECT foreign_id
                      FROM moo_route_roles
                      WHERE primary_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
                  )
            ), sysadmins AS (
                SELECT DISTINCT
                    moo_profile.id::text AS profile_id,
                    COALESCE(NULLIF(moo_profile.full_name, ''), NULLIF(moo_profile.preferred_name, ''), moo_profile.email, moo_profile.id::text) AS label,
                    moo_profile.email,
                    moo_profile.can_login,
                    'Sysadmin' AS source
                FROM moo_profile
                WHERE moo_profile.app_name = <cfqueryparam cfsqltype="varchar" value="#application.app_name#" />
                  AND <cfqueryparam cfsqltype="varchar" value="#application.app_name#" /> = 'hub'
                  AND moo_profile.can_login = true
                  AND lower(moo_profile.email) IN (<cfqueryparam cfsqltype="varchar" value="#sysadminEmails#" list="true" />)
            ), effective AS (
                SELECT profile_id, label, email, can_login, source FROM direct_profiles
                UNION ALL
                SELECT profile_id, label, email, can_login, source FROM role_profiles
                UNION ALL
                SELECT profile_id, label, email, can_login, source FROM sysadmins
            )
            SELECT COALESCE(jsonb_agg(accessor ORDER BY label)::text, '[]') AS data
            FROM (
                SELECT
                    effective.profile_id,
                    effective.label,
                    effective.email,
                    bool_or(effective.can_login) AS can_login,
                    jsonb_agg(DISTINCT effective.source ORDER BY effective.source) AS sources,
                    profile_picture.thumbnail AS avatar_url
                FROM effective
                INNER JOIN moo_profile ON moo_profile.id::text = effective.profile_id
                LEFT JOIN moo_file profile_picture ON profile_picture.id = moo_profile.profile_picture_id
                GROUP BY effective.profile_id, effective.label, effective.email, profile_picture.thumbnail
            ) accessor
        </cfquery>

        <cfreturn deserializeJSON(qAccessors.data) />
    </cffunction>


    <cffunction name="load">
        <cfargument name="route_id" type="string" required="true" />

        <cfset assertRouteInCurrentApp(arguments.route_id) />
        <cfset var accessSubjects = getRouteAccessSubjects(arguments.route_id) />
        <cfset stResult = {} />
        <cfset stResult.current_route = application.lib.db.read(table_name='moo_route', id="#arguments.route_id#", field_list="*", returnFormat="cfml") />
        <cfset stResult.route_open_to = application.stAllRoutes[arguments.route_id].open_to />
        <cfset stResult.endpoint_access = {} />
        <cfset stResult.current_route.profiles = accessSubjects.profiles />
        <cfset stResult.current_route.roles = accessSubjects.roles />
        <cfset stResult.access_subjects = accessSubjects.subjects />

        <!--- The endpoints relation reads back as {id, label} with no name; the matrix rows need the name --->
        <cfquery name="local.qEndpoints">
            SELECT id::text AS id, name
            FROM moo_route_endpoint
            WHERE route_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
            ORDER BY name
        </cfquery>
        <cfset stResult.current_route.endpoints = [] />
        <cfloop query="local.qEndpoints">
            <cfset arrayAppend(stResult.current_route.endpoints, { id: local.qEndpoints.id, name: local.qEndpoints.name }) />
        </cfloop>


        <!--- Initialize endpoint access --->
        <cfloop array="#stResult.current_route.profiles#" item="profile">
            <cfif !structKeyExists(stResult.endpoint_access, profile.id)>
                <cfset stResult.endpoint_access[profile.id] = {'_full_route_access_':false, endpoints:{}} />
            </cfif>
        </cfloop>

        <cfloop array="#stResult.current_route.roles#" item="role">
            <cfif !structKeyExists(stResult.endpoint_access, role.id)>
                <cfset stResult.endpoint_access[role.id] = {'_full_route_access_':false, endpoints:{}} />
            </cfif>
        </cfloop>


        <cfquery name="qRoutePermissions">
            SELECT
            moo_route.id AS route_id,
            moo_route.url AS route_url,
            moo_route_permission.profile_id AS profile_id,
            moo_route_permission.role_id as role_id,
            moo_route_permission.is_granted as is_granted
            FROM moo_route
            LEFT JOIN moo_route_endpoint ON moo_route.id = moo_route_endpoint.route_id
            LEFT JOIN moo_route_permission ON moo_route_permission.route_id = moo_route.id AND moo_route_permission.endpoint_id is null
            WHERE moo_route.id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
        </cfquery>

        <cfquery name="qEndpointPermissions">
            SELECT
            moo_route.id AS route_id,
            moo_route.url AS route_url,
            moo_route_endpoint.id AS endpoint_id,
            moo_route_endpoint.name AS endpoint_name,
            moo_route_permission.profile_id AS profile_id,
            moo_route_permission.role_id as role_id,
            moo_route_permission.is_granted as is_granted
            FROM moo_route
            LEFT JOIN moo_route_endpoint ON moo_route.id = moo_route_endpoint.route_id
            LEFT JOIN moo_route_permission ON moo_route_permission.route_id = moo_route.id AND moo_route_permission.endpoint_id = moo_route_endpoint.id
            WHERE moo_route.id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
        </cfquery>



        <cfloop query="qRoutePermissions">
            <cfif len(qRoutePermissions.profile_id)>
                <cfset stResult.endpoint_access[qRoutePermissions.profile_id]['_full_route_access_'] = qRoutePermissions.is_granted?true:false />
            <cfelseif len(qRoutePermissions.role_id)>
                <cfset stResult.endpoint_access[qRoutePermissions.role_id]['_full_route_access_'] = qRoutePermissions.is_granted?true:false />
            </cfif>
        </cfloop>

        <cfloop query="qEndpointPermissions">
            <cfif len(qEndpointPermissions.profile_id)>
                <cfset stResult.endpoint_access[qEndpointPermissions.profile_id]['endpoints'][qEndpointPermissions.endpoint_id] = qEndpointPermissions.is_granted?true:false />
            <cfelseif len(qEndpointPermissions.role_id)>
                <cfset stResult.endpoint_access[qEndpointPermissions.role_id]['endpoints'][qEndpointPermissions.endpoint_id] = qEndpointPermissions.is_granted?true:false />
            </cfif>
        </cfloop>

        <cfset stResult.who_has_access = getRouteEffectiveAccessors(arguments.route_id) />


        <cfreturn stResult />

    </cffunction>

    <cffunction name="toggleProfileAccess">
        <cfargument name="route_id" type="string" required="true" />

        <cfif refusedUnlessSysadmin()>
            <cfreturn { success: false, error: "Only sysadmins can change route access." } />
        </cfif>

        <cfset assertRouteInCurrentApp(arguments.route_id) />

        <cfquery name="qCheckExists">
        SELECT *
        FROM moo_route_permission
        WHERE route_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
        AND profile_id = <cfqueryparam cfsqltype="other" value="#request.data.profileId#" />
        <cfif len(request.data.endpointId?:'')>
            AND endpoint_id = <cfqueryparam cfsqltype="other" value="#request.data.endpointId#" />
        <cfelse>
            AND endpoint_id is null
        </cfif>
        </cfquery>

        <cfif qCheckExists.recordcount EQ 1>
            <cfreturn application.lib.db.delete(
                table_name = "moo_route_permission",
                id="#qCheckExists.id#"
            ) />
        <cfelse>
            <cfreturn application.lib.db.save(
                table_name = "moo_route_permission",
                data = {
                    route_id="#arguments.route_id#",
                    profile_id="#request.data.profileId#",
                    endpoint_id="#request.data.endpointId?:''#",
                    is_granted=true,

                }
            ) />
        </cfif>
    </cffunction>

    <cffunction name="toggleRoleAccess">
        <cfargument name="route_id" type="string" required="true" />

        <cfif refusedUnlessSysadmin()>
            <cfreturn { success: false, error: "Only sysadmins can change route access." } />
        </cfif>

        <cfset assertRouteInCurrentApp(arguments.route_id) />

        <cfquery name="qCheckExists">
        SELECT *
        FROM moo_route_permission
        WHERE route_id = <cfqueryparam cfsqltype="other" value="#arguments.route_id#" />
        AND role_id = <cfqueryparam cfsqltype="other" value="#request.data.roleId#" />
        <cfif len(request.data.endpointId?:'')>
            AND endpoint_id = <cfqueryparam cfsqltype="other" value="#request.data.endpointId#" />
        <cfelse>
            AND endpoint_id is null
        </cfif>
        </cfquery>

        <cfif qCheckExists.recordcount EQ 1>
            <cfreturn application.lib.db.delete(
                table_name = "moo_route_permission",
                id="#qCheckExists.id#"
            ) />
        <cfelse>
            <cfreturn application.lib.db.save(
                table_name = "moo_route_permission",
                data = {
                    route_id="#arguments.route_id#",
                    role_id="#request.data.roleId#",
                    endpoint_id="#request.data.endpointId?:''#",
                    is_granted=true,

                }
            ) />
        </cfif>
    </cffunction>


    <cffunction name="search.roles">
        <cfreturn application.lib.db.search(table_name='moo_role', q="#url.q?:''#", exclude_ids="#url.exclude_ids?:''#") />
    </cffunction>
    <cffunction name="search.profiles">
        <!--- Route grants only make sense for profiles that can log into this app. --->
        <cfreturn application.lib.db.search(table_name='moo_profile', q="#url.q?:''#", exclude_ids="#url.exclude_ids?:''#", where={"app_name": application.app_name}) />
    </cffunction>



    <cffunction name="save_route">

        <cfif refusedUnlessSysadmin()>
            <cfreturn { success: false, error: "Only sysadmins can change route access." } />
        </cfif>
        <cfparam name="request.data.id" />
        <cfset assertRouteInCurrentApp(request.data.id) />
        <cfset request.data.app_name = application.app_name />

        <cfreturn application.lib.db.save(
            table_name = "moo_route",
            data = request.data
        ) />
    </cffunction>




    <cffunction name="get" output="true">
        <cfargument name="route_id" />

        <cfmodule template="/moopa/tags/moopa_layout.cfm" title="Route security" chrome="false">

        <style>
            .route-matrix th.subject { vertical-align: bottom; padding: 0; width: 3rem; background: var(--surface); text-transform: none; letter-spacing: 0; }
            /* rotated subject names take no width: the 7rem box keeps them clear of the content above */
            .route-matrix .rotated { position: relative; height: 7rem; }
            /* anchored at the column's centre and leaning left, over the wide first column, so names never leave the table */
            .route-matrix .rotated > span { position: absolute; right: 50%; bottom: 0.75rem; transform-origin: right center; transform: rotate(45deg); white-space: nowrap; color: var(--ink); font-size: var(--text-sm); font-weight: 500; }
            .route-matrix td.cell { width: 3rem; padding: 0; text-align: center; border-left: 1px solid var(--hairline); }
            .route-matrix td.cell > button { width: 100%; min-height: 2.5rem; color: var(--ink-mute-2); }
            .route-matrix td.cell > button:hover { background: var(--canvas-soft); }
            .route-matrix .is-on { color: var(--success); }
            .route-matrix .is-inherited { color: var(--success); opacity: 0.45; }
            .route-matrix .is-off { color: var(--danger); opacity: 0.55; }
            .route-matrix .is-unset { opacity: 0.3; }
            .picker-results { max-height: 12rem; overflow: auto; box-shadow: none; }
        </style>

        <div x-data="xxx" class="page">

            <cfif session.auth.is_sysadmin?:false>
                <div x-cloak x-show="showEditRoute" class="card" style="max-width: 44rem">
                    <div class="card-header"><h2 class="card-title">Edit route access</h2></div>
                    <div class="card-body stack">
                        <template x-for="field in ['roles', 'profiles']" :key="field">
                            <div class="field">
                                <span class="label" x-text="field === 'roles' ? 'Roles' : 'People'"></span>
                                <div class="cluster" style="--cluster-gap: var(--sp-1)">
                                    <template x-for="item in (route_to_edit[field] || [])" :key="item.id">
                                        <span class="badge badge-signal">
                                            <span x-text="item.label"></span>
                                            <button type="button" @click="removePicked(field, item.id)" :aria-label="`Remove ${item.label}`"><i class="fa-solid fa-xmark"></i></button>
                                        </span>
                                    </template>
                                    <span class="muted small" x-show="!(route_to_edit[field] || []).length">None</span>
                                </div>
                                <div class="input-icon">
                                    <i class="fa-solid fa-magnifying-glass"></i>
                                    <input class="input input-sm" type="search" :placeholder="field === 'roles' ? 'Add a role' : 'Add a person'" :aria-label="field === 'roles' ? 'Add a role' : 'Add a person'"
                                        x-model="picker[field].q" @input.debounce.250ms="searchPicker(field)" @focus="searchPicker(field)">
                                </div>
                                <div class="card list-rows picker-results" x-show="picker[field].results.length">
                                    <template x-for="item in picker[field].results" :key="item.id">
                                        <button type="button" class="list-row" @click="addPicked(field, item)">
                                            <span class="cell-main truncate" x-text="item.label"></span>
                                            <i class="fa-solid fa-plus muted"></i>
                                        </button>
                                    </template>
                                </div>
                            </div>
                        </template>
                    </div>
                    <div class="card-footer cluster cluster-end">
                        <button type="button" class="btn btn-sm" @click="showEditRoute=false">Cancel</button>
                        <button type="button" class="btn btn-primary btn-sm" @click="save_route" :disabled="loadingState === 'loading'"><i class="fa-solid fa-floppy-disk"></i> Save</button>
                    </div>
                </div>
            </cfif>

            <div class="split split-end" style="--split-aside: 20rem" x-show="!showEditRoute" x-cloak>

                <section class="card">
                    <div class="card-header card-header-fixed">
                        <div>
                            <h2 class="card-title"><i class="fa-solid fa-check text-signal"></i> Permission matrix</h2>
                            <p class="card-sub">Grant the whole route, or single endpoints, to the people and roles in the columns.</p>
                        </div>
                        <cfif session.auth.is_sysadmin?:false>
                            <button type="button" class="btn btn-primary btn-sm" @click="edit_route"><i class="fa-solid fa-pen-to-square"></i> Edit access</button>
                        </cfif>
                    </div>

                    <template x-if="access_subjects.length > 0">
                        <div class="table-wrap">
                            <table class="table table-sm route-matrix">
                                <thead>
                                    <tr>
                                        <th style="min-width: 14rem; vertical-align: bottom; text-transform: none; letter-spacing: 0; font-weight: 400">Each row is the route or endpoint a tick grants.</th>
                                        <template x-for="subject in access_subjects" :key="subjectKey(subject)">
                                            <th class="subject"><div class="rotated"><span x-text="subject.label"></span></div></th>
                                        </template>
                                    </tr>
                                </thead>
                                <tbody>
                                    <tr>
                                        <th scope="row" style="background: var(--surface); text-transform: none; letter-spacing: 0">
                                            <div class="cluster">
                                                <code class="code-inline strong" x-text="current_route.url"></code>
                                                <span x-show="route_open_to === 'public'" class="badge badge-success">Public</span>
                                                <span x-show="route_open_to === 'bearer'" class="badge badge-success">Bearer</span>
                                                <span x-show="route_open_to === 'logged_in'" class="badge badge-success">Signed in</span>
                                            </div>
                                            <div class="mono muted tiny mt-1" x-show="routeSourcePath()" x-text="routeSourcePath()"></div>
                                        </th>
                                        <template x-for="subject in access_subjects" :key="subjectKey(subject)">
                                            <td class="cell">
                                                <button type="button" @click="toggleSubjectAccess(subject)" :aria-pressed="isSubjectAccessSet(subject)" :aria-label="`${subject.label}: whole route`">
                                                    <i class="fa-solid fa-check" :class="isSubjectAccessSet(subject) ? 'is-on' : 'is-unset'"></i>
                                                </button>
                                            </td>
                                        </template>
                                    </tr>
                                    <template x-for="endpoint in current_route.endpoints" :key="endpoint.id">
                                        <tr>
                                            <th scope="row" class="secondary" style="background: var(--surface); text-transform: none; letter-spacing: 0; font-size: var(--text-sm); font-weight: 400" x-text="endpointLabel(endpoint)"></th>
                                            <template x-for="subject in access_subjects" :key="subjectKey(subject)">
                                                <td class="cell">
                                                    <button type="button" @click="toggleSubjectAccess(subject, endpoint.id)" :aria-label="`${subject.label}: ${endpointLabel(endpoint)}`">
                                                        <i class="fa-solid" :class="isSubjectAccessSet(subject) ? 'fa-check is-inherited' : (isSubjectAccessSet(subject, endpoint.id) ? 'fa-check is-on' : 'fa-xmark is-off')"></i>
                                                    </button>
                                                </td>
                                            </template>
                                        </tr>
                                    </template>
                                </tbody>
                            </table>
                        </div>
                    </template>

                    <template x-if="access_subjects.length === 0">
                        <div class="empty">
                            <i class="fa-solid fa-user-shield"></i>
                            <p class="strong secondary">No people or roles are on this route.</p>
                            <p class="small">Use Edit access to add them.</p>
                        </div>
                    </template>
                </section>

                <aside class="card">
                    <div class="card-header"><h2 class="card-title"><i class="fa-solid fa-users text-signal"></i> People with access</h2></div>
                    <div class="list-rows" style="max-height: 18rem; overflow: auto" x-show="activeAccessors().length > 0">
                        <template x-for="person in activeAccessors()" :key="person.profile_id">
                            <div class="list-row" style="justify-content: flex-start">
                                <span class="avatar">
                                    <template x-if="person.avatar_url"><img :src="person.avatar_url" :alt="person.label" /></template>
                                    <template x-if="!person.avatar_url"><span x-text="profileInitials(person)"></span></template>
                                </span>
                                <div class="min0">
                                    <div class="cell-main truncate" x-text="person.label"></div>
                                    <div class="cell-sub truncate">via <span x-text="accessSources(person)"></span></div>
                                </div>
                            </div>
                        </template>
                    </div>
                    <div class="card-body small muted" x-show="activeAccessors().length === 0 && inactiveAccessors().length > 0">No one who can sign in has access.</div>
                    <template x-if="inactiveAccessors().length > 0">
                        <div class="card-footer stack stack-sm">
                            <div class="cluster cluster-between"><span class="eyebrow">Sign-in disabled</span><span class="badge" x-text="inactiveAccessors().length"></span></div>
                            <template x-for="person in inactiveAccessors()" :key="person.profile_id">
                                <div class="row" style="opacity: 0.75">
                                    <span class="avatar avatar-sm">
                                        <template x-if="person.avatar_url"><img :src="person.avatar_url" :alt="person.label" /></template>
                                        <template x-if="!person.avatar_url"><span x-text="profileInitials(person)"></span></template>
                                    </span>
                                    <div class="min0 small">
                                        <div class="truncate secondary" x-text="person.label"></div>
                                        <div class="truncate muted tiny" x-text="accessSources(person)"></div>
                                    </div>
                                </div>
                            </template>
                        </div>
                    </template>
                    <div class="empty" x-show="who_has_access.length === 0"><i class="fa-solid fa-user-slash"></i>No one has access.</div>
                </aside>

            </div>
        </div>

        <script>
            document.addEventListener("alpine:init", () => {
                Alpine.data("xxx", () => ({
                    loadingState: 'idle',
                    showEditRoute: false,
                    current_route: {},
                    route_to_edit: {},
                    endpoint_access: {},
                    access_subjects: [],
                    who_has_access:[],
                    route_open_to: 'security',

                    subjectKey(subject) {
                        return `${subject.type}:${subject.id}`;
                    },

                    accessSources(person) {
                        return person.sources.join(', ');
                    },

                    activeAccessors() {
                        return this.who_has_access.filter((person) => person.can_login !== false);
                    },

                    inactiveAccessors() {
                        return this.who_has_access.filter((person) => person.can_login === false);
                    },

                    routeSourcePath() {
                        const mapping = this.current_route?.mapping || '';
                        if (!mapping) return '';
                        return mapping.endsWith('.cfc') ? mapping : `${mapping}.cfc`;
                    },

                    endpointName(endpoint) {
                        return String(endpoint?.name || '').trim();
                    },

                    endpointLabel(endpoint) {
                        const name = this.endpointName(endpoint);

                        return name || 'get';
                    },

                    profileInitials(person) {
                        const name = person.label;
                        const initials = name
                            .split(/\s+/)
                            .filter(Boolean)
                            .map((part) => part[0])
                            .join('')
                            .slice(0, 2)
                            .toUpperCase();

                        return initials || '?';
                    },

                    edit_route() {
                        this.route_to_edit = JSON.parse(JSON.stringify(this.current_route))
                        this.picker = { roles: { q: '', results: [] }, profiles: { q: '', results: [] } };
                        this.showEditRoute = true;
                    },

                    // The roles/profiles pickers on the edit card: search.roles / search.profiles return [{ id, label }]
                    picker: { roles: { q: '', results: [] }, profiles: { q: '', results: [] } },

                    async searchPicker(field) {
                        const chosen = (this.route_to_edit[field] || []).map(item => item.id);
                        this.picker[field].results = await req({ endpoint: `search.${field}`, q: this.picker[field].q.trim(), exclude_ids: chosen, limit: 10 });
                    },

                    addPicked(field, item) {
                        this.route_to_edit[field] = [...(this.route_to_edit[field] || []), { id: item.id, label: item.label }];
                        this.picker[field] = { q: '', results: [] };
                    },

                    removePicked(field, id) {
                        this.route_to_edit[field] = (this.route_to_edit[field] || []).filter(item => item.id !== id);
                    },

                    async save_route() {
                        this.loadingState = 'loading';

                        await req({
                            method: 'POST',
                            endpoint: 'save_route',
                            body: this.route_to_edit
                        });

                        await this.load();
                        this.loadingState = 'idle';
                        this.showEditRoute = false;
                    },

                    isSubjectAccessSet(subject, endpointId) {
                        const subjectAccess = this.endpoint_access[subject.id];
                        if (subjectAccess) {
                            if (typeof endpointId === 'undefined' || endpointId === null) {
                                return subjectAccess._full_route_access_ === true;
                            }

                            return subjectAccess.endpoints && subjectAccess.endpoints[endpointId] === true;
                        }

                        return false;
                    },

                    async toggleSubjectAccess(subject, endpointId) {
                        if (subject.type === 'profile') {
                            await this.toggleProfileAccess(subject.id, endpointId);
                        } else if (subject.type === 'role') {
                            await this.toggleRoleAccess(subject.id, endpointId);
                        } else {
                            throw new Error(`Unknown access subject type: ${subject.type}`);
                        }
                    },

                    async toggleProfileAccess(profileId, endpointId) {
                        // Handle the checkbox click event to set access
                        <cfif session.auth.is_sysadmin?:false>
                            await req({
                                method: 'POST',
                                endpoint: 'toggleProfileAccess',
                                body: {
                                    profileId: profileId,
                                    endpointId: endpointId
                                }
                            });

                            this.loadingState = 'idle';
                            await this.load();
                        </cfif>

                    },

                    async toggleRoleAccess(roleId, endpointId) {
                        // Handle the checkbox click event to set access

                        <cfif session.auth.is_sysadmin?:false>
                            await req({
                                method: 'POST',
                                endpoint: 'toggleRoleAccess',
                                body: {
                                    roleId: roleId,
                                    endpointId: endpointId
                                }
                            });

                            this.loadingState = 'idle';
                            await this.load();
                        </cfif>
                    },

                    async load() {
                        const data = await req({ endpoint: 'load' });

                        this.route_to_edit = {};
                        this.current_route = data.current_route;
                        this.endpoint_access = data.endpoint_access;
                        this.access_subjects = data.access_subjects;
                        this.route_open_to = data.route_open_to;
                        this.who_has_access = data.who_has_access;
                    },

                    init() {
                        this.load()
                    }
                }))
            })
        </script>


        </cfmodule>
    </cffunction>


</cfcomponent>
