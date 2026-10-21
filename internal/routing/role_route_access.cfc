<cfcomponent displayName="role_route_access" output="false" hint="Route-wide role access: what each role can open, and applying a reviewed batch of grants and revokes for one role.">

    <!---
        A role can open a route when both hold, as access_policy checks them:
          - the role is one of the route's subjects (moo_route_roles), and
          - a granted moo_route_permission row names the role for that route, route-wide
            (endpoint_id null) or for the route's get endpoint.
        A route with any granted endpoint-level permission is locked: its access is
        managed endpoint by endpoint on the route's own security page, never here.
    --->

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>


    <cffunction name="getState" access="public" returntype="struct" output="false" hint="Roles, the app's registry rows, which routes each role can open, and which routes are locked.">
        <cfargument name="app_name" type="string" required="true" />

        <cfquery name="local.qState">
            WITH app_routes AS (
                SELECT id, url
                FROM moo_route
                WHERE app_name = <cfqueryparam cfsqltype="varchar" value="#arguments.app_name#" />
            ), can_open AS (
                #preserveSingleQuotes(canOpenSql())#
            )
            SELECT row_to_json(payload)::text AS data
            FROM (
                SELECT
                    COALESCE((
                        SELECT json_agg(json_build_object(
                            'id', moo_role.id,
                            'name', moo_role.name,
                            'profile_count', (
                                SELECT count(*)
                                FROM moo_profile_roles
                                INNER JOIN moo_profile ON moo_profile.id = moo_profile_roles.primary_id
                                WHERE moo_profile_roles.foreign_id = moo_role.id
                                  AND moo_profile.app_name = <cfqueryparam cfsqltype="varchar" value="#arguments.app_name#" />
                            ),
                            'profiles', COALESCE((
                                SELECT json_agg(json_build_object(
                                    'id', moo_profile.id,
                                    'full_name', moo_profile.full_name,
                                    'email', moo_profile.email,
                                    'can_login', COALESCE(moo_profile.can_login, false),
                                    'last_login_at', moo_profile.last_login_at
                                ) ORDER BY moo_profile.can_login DESC NULLS LAST, lower(COALESCE(NULLIF(moo_profile.full_name, ''), moo_profile.email)), moo_profile.id)
                                FROM moo_profile_roles
                                INNER JOIN moo_profile ON moo_profile.id = moo_profile_roles.primary_id
                                WHERE moo_profile_roles.foreign_id = moo_role.id
                                  AND moo_profile.app_name = <cfqueryparam cfsqltype="varchar" value="#arguments.app_name#" />
                            ), '[]'::json)
                        ) ORDER BY moo_role.name)
                        FROM moo_role
                    ), '[]'::json) AS roles,
                    COALESCE((
                        SELECT json_agg(json_build_object('id', app_routes.id, 'url', app_routes.url) ORDER BY app_routes.url)
                        FROM app_routes
                    ), '[]'::json) AS registry,
                    COALESCE((
                        SELECT json_object_agg(role_id, route_ids)
                        FROM (
                            SELECT role_id, json_agg(route_id ORDER BY route_id) AS route_ids
                            FROM can_open
                            GROUP BY role_id
                        ) by_role
                    ), '{}'::json) AS access,
                    COALESCE((
                        SELECT json_agg(DISTINCT moo_route_permission.route_id)
                        FROM moo_route_permission
                        WHERE moo_route_permission.route_id IN (SELECT id FROM app_routes)
                          AND moo_route_permission.endpoint_id IS NOT NULL
                          AND moo_route_permission.is_granted
                    ), '[]'::json) AS locked
            ) payload
        </cfquery>

        <cfreturn deserializeJSON(local.qState.data) />
    </cffunction>


    <cffunction name="apply" access="public" returntype="struct" output="false" hint="Apply one role's reviewed changes in a single transaction, or none of them. Each change carries the state the reviewer saw; a route that has moved on since, is locked, is not role-gated or is not a live route of this app rejects the whole batch with 409.">
        <cfargument name="role_id" type="string" required="true" />
        <cfargument name="changes" type="array" required="true" hint="[{route_id, granted, was_granted}]" />
        <cfargument name="app_name" type="string" required="true" />
        <cfargument name="live_routes" type="struct" required="true" hint="The runtime registry: route id to route descriptor (application.stAllRoutes)." />

        <cfset var routeIds = [] />
        <cfset var change = {} />
        <cfset var current = {} />
        <cfset var conflicts = [] />
        <cfset var liveRoute = {} />
        <cfset var routeUrl = "" />

        <cfset assertRequest(arguments.role_id, arguments.changes) />

        <cfloop array="#arguments.changes#" item="change">
            <cfset arrayAppend(routeIds, change.route_id) />
        </cfloop>

        <cftransaction>
            <!--- Serialise concurrent batches touching the same routes. --->
            <cfquery name="local.qLock">
                SELECT id
                FROM moo_route
                WHERE id IN (<cfqueryparam cfsqltype="other" list="true" value="#arrayToList(routeIds)#" />)
                ORDER BY id
                FOR UPDATE
            </cfquery>

            <cfset current = getRouteStates(arguments.role_id, routeIds, arguments.app_name) />

            <cfloop array="#arguments.changes#" item="change">
                <cfset liveRoute = structKeyExists(arguments.live_routes, change.route_id) ? arguments.live_routes[change.route_id] : {} />
                <cfset routeUrl = structKeyExists(current, change.route_id) ? current[change.route_id].url : change.route_id />

                <cfif NOT structKeyExists(current, change.route_id) OR structIsEmpty(liveRoute) OR (liveRoute.app_name ?: "") NEQ arguments.app_name>
                    <cfset arrayAppend(conflicts, { route_id: change.route_id, url: routeUrl, reason: "is not a live route of this app" }) />
                <cfelseif (liveRoute.open_to ?: "security") NEQ "security">
                    <cfset arrayAppend(conflicts, { route_id: change.route_id, url: routeUrl, reason: "is open to #liveRoute.open_to#, so roles do not apply" }) />
                <cfelseif current[change.route_id].locked>
                    <cfset arrayAppend(conflicts, { route_id: change.route_id, url: routeUrl, reason: "has endpoint-level grants; manage it on its route security page" }) />
                <cfelseif current[change.route_id].can_open NEQ change.was_granted>
                    <cfset arrayAppend(conflicts, { route_id: change.route_id, url: routeUrl, reason: "changed since you loaded the page" }) />
                </cfif>
            </cfloop>

            <cfif arrayLen(conflicts)>
                <cftransaction action="rollback" />
                <cfreturn {
                    success: false,
                    status_code: 409,
                    error: "Nothing was applied. " & arrayToList(arrayMap(conflicts, function(conflict) { return "#conflict.url# #conflict.reason#."; }), " ") & " Reload to see the current access.",
                    conflicts: conflicts
                } />
            </cfif>

            <cfloop array="#arguments.changes#" item="change">
                <cfif change.granted>
                    <cfset grant(arguments.role_id, change.route_id, current[change.route_id]) />
                <cfelse>
                    <cfset revoke(arguments.role_id, change.route_id, current[change.route_id]) />
                </cfif>
            </cfloop>
        </cftransaction>

        <cfreturn { success: true, applied: arrayLen(arguments.changes) } />
    </cffunction>


    <cffunction name="assertRequest" access="private" returntype="void" output="false" hint="Reject a malformed batch before touching the database.">
        <cfargument name="role_id" type="string" required="true" />
        <cfargument name="changes" type="array" required="true" />

        <cfset var seen = {} />
        <cfset var change = {} />

        <cfif NOT isUuid(arguments.role_id)>
            <cfthrow type="moopa.routeAccess.invalidRequest" message="role_id must be a role id." />
        </cfif>

        <cfquery name="local.qRole">
            SELECT id FROM moo_role WHERE id = <cfqueryparam cfsqltype="other" value="#arguments.role_id#" />
        </cfquery>
        <cfif NOT local.qRole.recordCount>
            <cfthrow type="moopa.routeAccess.invalidRequest" message="Role #arguments.role_id# does not exist." />
        </cfif>

        <cfif NOT arrayLen(arguments.changes)>
            <cfthrow type="moopa.routeAccess.invalidRequest" message="There are no changes to apply." />
        </cfif>

        <cfloop array="#arguments.changes#" item="change">
            <cfif NOT isStruct(change)
                  OR NOT isUuid(change.route_id ?: "")
                  OR NOT isBoolean(change.granted ?: "")
                  OR NOT isBoolean(change.was_granted ?: "")>
                <cfthrow type="moopa.routeAccess.invalidRequest" message="Each change needs route_id, granted and was_granted." />
            </cfif>
            <cfif change.granted EQ change.was_granted>
                <cfthrow type="moopa.routeAccess.invalidRequest" message="Route #change.route_id# is not a change: granted equals was_granted." />
            </cfif>
            <cfif structKeyExists(seen, change.route_id)>
                <cfthrow type="moopa.routeAccess.invalidRequest" message="Route #change.route_id# appears twice in one batch." />
            </cfif>
            <cfset seen[change.route_id] = true />
        </cfloop>
    </cffunction>


    <cffunction name="isUuid" access="private" returntype="boolean" output="false">
        <cfargument name="value" type="any" required="true" />
        <cfreturn isSimpleValue(arguments.value) AND reFind("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", arguments.value) GT 0 />
    </cffunction>


    <cffunction name="getRouteStates" access="private" returntype="struct" output="false" hint="For one role, each of the given routes of this app: its url, whether it is locked, whether the role can open it, and the rows a change touches.">
        <cfargument name="role_id" type="string" required="true" />
        <cfargument name="route_ids" type="array" required="true" />
        <cfargument name="app_name" type="string" required="true" />

        <cfquery name="local.qStates">
            WITH app_routes AS (
                SELECT id, url
                FROM moo_route
                WHERE app_name = <cfqueryparam cfsqltype="varchar" value="#arguments.app_name#" />
                  AND id IN (<cfqueryparam cfsqltype="other" list="true" value="#arrayToList(arguments.route_ids)#" />)
            ), can_open AS (
                #preserveSingleQuotes(canOpenSql())#
            )
            SELECT COALESCE(json_object_agg(app_routes.id, json_build_object(
                'url', app_routes.url,
                'locked', EXISTS (
                    SELECT 1 FROM moo_route_permission
                    WHERE moo_route_permission.route_id = app_routes.id
                      AND moo_route_permission.endpoint_id IS NOT NULL
                      AND moo_route_permission.is_granted
                ),
                'can_open', EXISTS (
                    SELECT 1 FROM can_open
                    WHERE can_open.route_id = app_routes.id
                      AND can_open.role_id = <cfqueryparam cfsqltype="other" value="#arguments.role_id#" />
                ),
                'role_ids', COALESCE((
                    SELECT json_agg(moo_route_roles.foreign_id ORDER BY moo_route_roles.sequence, moo_route_roles.foreign_id)
                    FROM moo_route_roles
                    WHERE moo_route_roles.primary_id = app_routes.id
                ), '[]'::json),
                'route_wide_permission_ids', COALESCE((
                    SELECT json_agg(moo_route_permission.id ORDER BY moo_route_permission.id)
                    FROM moo_route_permission
                    WHERE moo_route_permission.route_id = app_routes.id
                      AND moo_route_permission.role_id = <cfqueryparam cfsqltype="other" value="#arguments.role_id#" />
                      AND moo_route_permission.endpoint_id IS NULL
                ), '[]'::json)
            ))::text, '{}') AS data
            FROM app_routes
        </cfquery>

        <cfreturn deserializeJSON(local.qStates.data) />
    </cffunction>


    <cffunction name="grant" access="private" returntype="void" output="false" hint="Make the role a subject of the route and hold exactly one granted route-wide permission row for it.">
        <cfargument name="role_id" type="string" required="true" />
        <cfargument name="route_id" type="string" required="true" />
        <cfargument name="state" type="struct" required="true" />

        <cfset var roleIds = duplicate(arguments.state.role_ids) />
        <cfset var permissionIds = arguments.state.route_wide_permission_ids />
        <cfset var index = 0 />

        <cfif NOT arrayFindNoCase(roleIds, arguments.role_id)>
            <cfset arrayAppend(roleIds, arguments.role_id) />
            <cfset application.lib.db.save(table_name = "moo_route", data = { id: arguments.route_id, roles: roleIds }) />
        </cfif>

        <cfif NOT arrayLen(permissionIds)>
            <cfset application.lib.db.save(table_name = "moo_route_permission", data = {
                route_id: arguments.route_id,
                role_id: arguments.role_id,
                is_granted: true
            }) />
            <cfreturn />
        </cfif>

        <cfset application.lib.db.save(table_name = "moo_route_permission", data = { id: permissionIds[1], is_granted: true }) />
        <cfloop from="2" to="#arrayLen(permissionIds)#" index="index">
            <cfset application.lib.db.delete(table_name = "moo_route_permission", id = permissionIds[index]) />
        </cfloop>
    </cffunction>


    <cffunction name="revoke" access="private" returntype="void" output="false" hint="Remove the role's route-wide permission rows and drop it as a subject of the route. Only reached for unlocked routes, which have no endpoint-level grants to keep the subject for.">
        <cfargument name="role_id" type="string" required="true" />
        <cfargument name="route_id" type="string" required="true" />
        <cfargument name="state" type="struct" required="true" />

        <cfset var roleIds = [] />
        <cfset var roleId = "" />
        <cfset var permissionId = "" />

        <cfloop array="#arguments.state.route_wide_permission_ids#" item="permissionId">
            <cfset application.lib.db.delete(table_name = "moo_route_permission", id = permissionId) />
        </cfloop>

        <cfloop array="#arguments.state.role_ids#" item="roleId">
            <cfif roleId NEQ arguments.role_id>
                <cfset arrayAppend(roleIds, roleId) />
            </cfif>
        </cfloop>
        <cfset application.lib.db.save(table_name = "moo_route", data = { id: arguments.route_id, roles: roleIds }) />
    </cffunction>


    <cffunction name="canOpenSql" access="private" returntype="string" output="false" hint="SELECT route_id, role_id for every role that can open a route in app_routes (a CTE the caller defines).">
        <cfreturn "
            SELECT moo_route_roles.primary_id AS route_id, moo_route_roles.foreign_id AS role_id
            FROM moo_route_roles
            WHERE moo_route_roles.primary_id IN (SELECT id FROM app_routes)
              AND EXISTS (
                  SELECT 1
                  FROM moo_route_permission
                  LEFT JOIN moo_route_endpoint ON moo_route_endpoint.id = moo_route_permission.endpoint_id
                  WHERE moo_route_permission.route_id = moo_route_roles.primary_id
                    AND moo_route_permission.role_id = moo_route_roles.foreign_id
                    AND moo_route_permission.is_granted
                    AND (moo_route_permission.endpoint_id IS NULL OR lower(moo_route_endpoint.name) = 'get')
              )
        " />
    </cffunction>

</cfcomponent>
