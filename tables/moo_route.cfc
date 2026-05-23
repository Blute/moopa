<cfcomponent>

    <cffunction name="init">

        <cfset variables.routeUrl = CreateObject("component", "/moopa/internal/routing/route_url").init() />
        <cfset variables.routeMatcher = CreateObject("component", "/moopa/internal/routing/route_matcher").init(variables.routeUrl) />
        <cfset variables.registryRowMerger = CreateObject("component", "/moopa/internal/routing/registry_row_merger").init() />
        <cfset variables.routeRegistryInitializer = CreateObject("component", "/moopa/internal/routing/route_registry_initializer").init(
            routeUrl = variables.routeUrl,
            registryRowMerger = variables.registryRowMerger
        ) />
        <cfset variables.accessPolicy = CreateObject("component", "/moopa/internal/routing/access_policy").init() />

        <cfset this.definition =
        {
            "title": "Route",
            "title_plural": "Routes",
            "searchable_fields": "url,app_name,mapping",
            "fields": {
                "key": {
                    "type"="uuid",
                    "index":true,
                    "html": {
                        "type": "input_text"
                    }
                },
                "url": {},
                "mapping": {},
                "app_name": {
                    "type": "varchar",
                    "nullable": false,
                    "html": {
                        "type": "text"
                    }
                },
                "is_secure_by_referrer": {"type": "bool", "default": false},


                "referrers": {
                  "type": "many_to_many",
                  "foreign_key_table": "moo_route",
                  "foreign_key_field": "id"
                },
                "profiles": {
                  "type": "many_to_many",
                  "foreign_key_table": "moo_profile",
                  "foreign_key_field": "id",
                  "foreign_key_onDelete" : "CASCADE"
                },
                "roles": {
                  "type": "many_to_many",
                  "foreign_key_table": "moo_role",
                  "foreign_key_field": "id"
                },
                "endpoints": {
                  "type": "relation",
                  "foreign_key_table": "moo_route_endpoint",
                  "foreign_key_field": "route_id"
                },
                "screenshot": {}
            },
            "indexes": {
                "idx_moo_route_key_app_name": {
                    "type": "btree",
                    "fields": "key,app_name",
                    "unique": true
                },
                "idx_moo_route_app_name_url": {
                    "type": "btree",
                    "fields": "app_name,url",
                    "unique": true
                }
            }
          }

        />

        <cfreturn this>
    </cffunction>


    <cffunction name="initializeRoutesIntoApplicationScope">
        <cfreturn variables.routeRegistryInitializer.initializeRoutesIntoApplicationScope() />
    </cffunction>



    <cffunction name="parseRoute" returntype="struct" output="false">
        <cfargument name="route" hint="Usually from url.route" />

        <cfreturn variables.routeMatcher.parseRoute(
            route = arguments.route,
            staticRoutes = application.stStaticRoutes,
            dynamicRoutes = application.stDynamicRoutes
        ) />
    </cffunction>



    <cffunction name="checkAccess" returntype="boolean" output="false">
        <cfargument name="route_data" />
        <cfargument name="endpoint" />
        <cfargument name="sysadmin_has_access" default=true />

        <cfreturn variables.accessPolicy.checkAccess(
            route_data = arguments.route_data,
            endpoint = arguments.endpoint,
            sysadmin_has_access = arguments.sysadmin_has_access
        ) />
    </cffunction>

    <!--- Get profiles by route access --->
    <cffunction name="getProfilesByRouteAccess" access="public" returntype="array" output="false">
        <cfargument name="route" type="string" required="false" default="" hint="The route path (e.g. '/po_reference/new_company')">
        <cfargument name="endpoint" type="string" required="false" default="" hint="The endpoint name (e.g. 'get')">
        <cfargument name="route_id" type="string" required="false" default="" hint="Alternative: direct route UUID">
        <cfargument name="endpoint_id" type="string" required="false" default="" hint="Alternative: direct endpoint UUID">
        <cfargument name="returnFormat" type="string" required="false" default="cfml">

        <cfif NOT listFindNoCase("json,cfml", arguments.returnFormat)>
            <cfthrow type="moopa.mooRoute.invalidReturnFormat" message="Invalid returnFormat '#arguments.returnFormat#'. Use 'json' or 'cfml'." />
        </cfif>

        <!--- Resolve route and endpoint IDs if path is provided --->
        <cfset var resolved_route_id = arguments.route_id>
        <cfset var resolved_endpoint_id = arguments.endpoint_id>

        <cfset var moo_route = application.lib.db.getService("moo_route") />
        <cfif len(arguments.route)>
            <cfset var route_data = moo_route.parseRoute(arguments.route)>
            <cfset resolved_route_id = route_data.stRoute.id>

            <cfif len(arguments.endpoint)>
                <cfif structKeyExists(route_data.stRoute.endpoints, arguments.endpoint)>
                    <cfset resolved_endpoint_id = route_data.stRoute.endpoints[arguments.endpoint].id>
                <cfelse>
                    <cfthrow message="Endpoint '#arguments.endpoint#' not found for route '#arguments.route#'">
                </cfif>
            </cfif>
        </cfif>

        <!--- Validate we have at least a route ID --->
        <cfif !len(resolved_route_id)>
            <cfthrow message="Either route path or route_id must be provided">
        </cfif>

        <cfquery name="qProfiles">
            SELECT COALESCE(jsonb_agg(DISTINCT profile_data)::text, '[]') as profiles
            FROM (
                SELECT #application.lib.db.select(
                    table_name="moo_profile",
                    field_list="id,full_name,email",
                    sql_type="expanded"
                )#
                FROM moo_profile
                WHERE (
                    /* Direct profile permissions */
                    moo_profile.id IN (
                        SELECT profile_id
                        FROM moo_route_permission
                        WHERE route_id = <cfqueryparam cfsqltype="other" value="#resolved_route_id#">
                        AND is_granted = true
                        <cfif len(resolved_endpoint_id)>
                            AND (
                                endpoint_id = <cfqueryparam cfsqltype="other" value="#resolved_endpoint_id#">
                                OR endpoint_id IS NULL
                            )
                        </cfif>
                    )
                    /* Role-based permissions */
                    OR moo_profile.id IN (
                        SELECT moo_profile_roles.primary_id
                        FROM moo_profile_roles
                        INNER JOIN moo_route_permission ON
                            moo_route_permission.role_id = moo_profile_roles.foreign_id
                        WHERE moo_route_permission.route_id = <cfqueryparam cfsqltype="other" value="#resolved_route_id#">
                        AND moo_route_permission.is_granted = true
                        <cfif len(resolved_endpoint_id)>
                            AND (
                                moo_route_permission.endpoint_id = <cfqueryparam cfsqltype="other" value="#resolved_endpoint_id#">
                                OR moo_route_permission.endpoint_id IS NULL
                            )
                        </cfif>
                    )
                )
                /* Route-specific access control */
                AND (
                    moo_profile.id IN (
                        SELECT foreign_id
                        FROM moo_route_profiles
                        WHERE primary_id = <cfqueryparam cfsqltype="other" value="#resolved_route_id#">
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM moo_profile_roles
                        WHERE moo_profile_roles.primary_id = moo_profile.id
                        AND moo_profile_roles.foreign_id IN (
                            SELECT foreign_id
                            FROM moo_route_roles
                            WHERE primary_id = <cfqueryparam cfsqltype="other" value="#resolved_route_id#">
                        )
                    )
                )
                #application.lib.db.orderby(table_name="moo_profile")#
            ) as profile_data
        </cfquery>

        <cfif lCase(trim(arguments.returnFormat)) EQ "cfml">
            <cfreturn deserializeJSON(qProfiles.profiles)>
        </cfif>

        <cfreturn qProfiles.profiles>
    </cffunction>



    <cffunction name="getConfiguredSysadminEmailList" access="private" returntype="string" output="false">
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


    <cffunction name="getEffectiveAccessors" access="public" returntype="struct" output="false">
        <cfargument name="route" type="string" required="false" default="" />
        <cfargument name="endpoint" type="string" required="false" default="" />
        <cfargument name="route_id" type="string" required="false" default="" />
        <cfargument name="endpoint_id" type="string" required="false" default="" />

        <cfset var resolvedRouteId = arguments.route_id />
        <cfset var resolvedEndpointId = arguments.endpoint_id />
        <cfset var routeData = {} />
        <cfset var result = {} />

        <cfif len(arguments.route)>
            <cfset routeData = parseRoute(arguments.route) />
            <cfif structIsEmpty(routeData.stRoute ?: {})>
                <cfthrow type="moopa.route.notFound" message="Route '#arguments.route#' was not found." />
            </cfif>
            <cfset resolvedRouteId = routeData.stRoute.id />
            <cfif len(arguments.endpoint)>
                <cfif NOT structKeyExists(routeData.stRoute.endpoints, arguments.endpoint)>
                    <cfthrow type="moopa.route.endpointNotFound" message="Endpoint '#arguments.endpoint#' was not found for route '#arguments.route#'." />
                </cfif>
                <cfset resolvedEndpointId = routeData.stRoute.endpoints[arguments.endpoint].id />
            </cfif>
        </cfif>

        <cfif NOT len(resolvedRouteId)>
            <cfthrow type="moopa.route.missingRoute" message="A route or route_id is required." />
        </cfif>

        <cfquery name="qRoute" returntype="array">
            SELECT id::text, url, app_name
            FROM moo_route
            WHERE id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />
        </cfquery>
        <cfif NOT arrayLen(qRoute)>
            <cfthrow type="moopa.route.notFound" message="Route '#resolvedRouteId#' was not found." />
        </cfif>

        <cfquery name="qEndpoint" returntype="array">
            SELECT id::text, name
            FROM moo_route_endpoint
            WHERE route_id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />
            <cfif len(resolvedEndpointId)>
                AND id = <cfqueryparam cfsqltype="other" value="#resolvedEndpointId#" />
            <cfelseif len(arguments.endpoint)>
                AND name = <cfqueryparam cfsqltype="varchar" value="#arguments.endpoint#" />
            <cfelse>
                AND 1 = 0
            </cfif>
            LIMIT 1
        </cfquery>

        <cfif len(arguments.endpoint) AND NOT arrayLen(qEndpoint)>
            <cfthrow type="moopa.route.endpointNotFound" message="Endpoint '#arguments.endpoint#' was not found." />
        </cfif>
        <cfif arrayLen(qEndpoint) AND NOT len(resolvedEndpointId)>
            <cfset resolvedEndpointId = qEndpoint[1].id />
        </cfif>

        <cfquery name="qAccess">
            WITH direct_profiles AS (
                SELECT DISTINCT p.id, p.full_name, p.email, p.app_name, p.can_login
                FROM moo_route_permission rp
                INNER JOIN moo_profile p ON p.id = rp.profile_id
                WHERE rp.route_id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />
                  AND rp.is_granted = true
                  AND p.can_login = true
                  AND p.app_name = 'hub'
                  <cfif len(resolvedEndpointId)>
                    AND (rp.endpoint_id = <cfqueryparam cfsqltype="other" value="#resolvedEndpointId#" /> OR rp.endpoint_id IS NULL)
                  <cfelse>
                    AND rp.endpoint_id IS NULL
                  </cfif>
                  AND p.id IN (
                    SELECT foreign_id FROM moo_route_profiles WHERE primary_id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />
                  )
            ), role_profiles AS (
                SELECT DISTINCT r.id AS role_id, r.name AS role_name, p.id, p.full_name, p.email, p.app_name, p.can_login
                FROM moo_route_permission rp
                INNER JOIN moo_role r ON r.id = rp.role_id
                INNER JOIN moo_profile_roles pr ON pr.foreign_id = r.id
                INNER JOIN moo_profile p ON p.id = pr.primary_id
                WHERE rp.route_id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />
                  AND rp.is_granted = true
                  AND p.can_login = true
                  AND p.app_name = 'hub'
                  <cfif len(resolvedEndpointId)>
                    AND (rp.endpoint_id = <cfqueryparam cfsqltype="other" value="#resolvedEndpointId#" /> OR rp.endpoint_id IS NULL)
                  <cfelse>
                    AND rp.endpoint_id IS NULL
                  </cfif>
                  AND r.id IN (
                    SELECT foreign_id FROM moo_route_roles WHERE primary_id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />
                  )
            ), sysadmins AS (
                SELECT DISTINCT p.id, p.full_name, p.email, p.app_name, p.can_login
                FROM moo_profile p
                WHERE p.app_name = 'hub'
                  AND p.can_login = true
                  AND lower(p.email) IN (<cfqueryparam cfsqltype="varchar" value="#getConfiguredSysadminEmailList()#" list="true" />)
            ), effective AS (
                SELECT id, full_name, email, app_name, can_login, 'Direct grant' AS source FROM direct_profiles
                UNION ALL
                SELECT id, full_name, email, app_name, can_login, 'Role: ' || role_name AS source FROM role_profiles
                UNION ALL
                SELECT id, full_name, email, app_name, can_login, 'Sysadmin' AS source FROM sysadmins
            )
            SELECT row_to_json(payload)::text AS data
            FROM (
                SELECT
                    (SELECT row_to_json(r) FROM (SELECT id, url, app_name FROM moo_route WHERE id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />) r) AS route,
                    <cfif len(resolvedEndpointId)>
                    (SELECT COALESCE(row_to_json(e), '{}'::json) FROM (SELECT id, name FROM moo_route_endpoint WHERE id = <cfqueryparam cfsqltype="other" value="#resolvedEndpointId#" />) e) AS endpoint,
                    <cfelse>
                    '{}'::json AS endpoint,
                    </cfif>
                    COALESCE((SELECT json_agg(row_to_json(s) ORDER BY full_name) FROM sysadmins s), '[]'::json) AS sysadmins,
                    COALESCE((SELECT json_agg(row_to_json(d) ORDER BY full_name) FROM direct_profiles d), '[]'::json) AS direct_profiles,
                    COALESCE((
                        SELECT json_agg(row_to_json(role_data) ORDER BY name)
                        FROM (
                            SELECT role_id AS id, role_name AS name,
                                json_agg(json_build_object('id', id, 'full_name', full_name, 'email', email, 'app_name', app_name, 'can_login', can_login) ORDER BY full_name) AS profiles
                            FROM role_profiles
                            GROUP BY role_id, role_name
                        ) role_data
                    ), '[]'::json) AS roles,
                    COALESCE((
                        SELECT json_agg(row_to_json(effective_profile) ORDER BY full_name)
                        FROM (
                            SELECT id, full_name, email, app_name, can_login, json_agg(DISTINCT source ORDER BY source) AS sources
                            FROM effective
                            GROUP BY id, full_name, email, app_name, can_login
                        ) effective_profile
                    ), '[]'::json) AS effective_profiles
            ) payload
        </cfquery>

        <cfreturn deserializeJSON(qAccess.data) />
    </cffunction>



</cfcomponent>
