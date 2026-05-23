<cfcomponent displayName="route_registry_store" output="false" hint="Loads and synchronizes file-based routes with the persisted moo_route registry.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfargument name="routeIdentity" required="true" />
        <cfargument name="registryRowMerger" required="true" />

        <cfset variables.routeIdentity = arguments.routeIdentity />
        <cfset variables.registryRowMerger = arguments.registryRowMerger />

        <cfreturn this />
    </cffunction>


    <cffunction name="loadExistingRoutes" access="public" returntype="struct" output="false">
        <cfset var registry = {
            routesByIdentity = {},
            routesByUrlIdentity = {},
            routesByUrlIdentityList = {},
            legacyRoutesByKey = {},
            persistenceAvailable = true
        } />
        <cfset var aDBRoutes = [] />
        <cfset var route = {} />
        <cfset var urlIdentity = "" />

        <cftry>
            <cfquery name="local.qDBRoutes">
            SELECT COALESCE(jsonb_agg(data)::text, '[]') as data
            FROM (
                    SELECT id::text as id, key::text as key, url, mapping, app_name,
                    COALESCE((
                        SELECT json_agg(json_build_object('id', moo_route_endpoint.id::text, 'name', moo_route_endpoint.name))
                        FROM moo_route_endpoint
                        WHERE moo_route_endpoint.route_id = moo_route.id
                    ), '[]') AS endpoints
                    FROM moo_route
            ) as data
            </cfquery>

            <cfset aDBRoutes = deserializeJSON(local.qDBRoutes.data) />
            <cfcatch type="database">
                <!--- First-run/dev fallback: route tables may not exist until /sysadmin/schema has been applied. --->
                <cfset registry.persistenceAvailable = false />
                <cfset aDBRoutes = [] />
            </cfcatch>
        </cftry>

        <cfloop array="#aDBRoutes#" item="route">
            <cfif len(route.app_name ?: "")>
                <cfset urlIdentity = variables.routeIdentity.byUrl(route.url, route.app_name) />
                <cfset registry.routesByIdentity[variables.routeIdentity.byKey(route.key, route.app_name)] = route />
                <cfif NOT structKeyExists(registry.routesByUrlIdentity, urlIdentity)>
                    <cfset registry.routesByUrlIdentity[urlIdentity] = route />
                </cfif>
                <cfif NOT structKeyExists(registry.routesByUrlIdentityList, urlIdentity)>
                    <cfset registry.routesByUrlIdentityList[urlIdentity] = [] />
                </cfif>
                <cfset arrayAppend(registry.routesByUrlIdentityList[urlIdentity], route) />
            <cfelse>
                <!--- Legacy rows created before routes were app-scoped. The active app can claim them on re-init. --->
                <cfset registry.legacyRoutesByKey[route.key] = route />
            </cfif>
        </cfloop>

        <cfreturn registry />
    </cffunction>


    <cffunction name="claimExistingRoute" access="public" returntype="struct" output="false">
        <cfargument name="stRoute" type="struct" required="true" />
        <cfargument name="registry" type="struct" required="true" />

        <cfset arguments.stRoute.identity = variables.routeIdentity.byKey(arguments.stRoute.key, arguments.stRoute.app_name) />

        <cfif arguments.registry.persistenceAvailable
            AND NOT structKeyExists(arguments.registry.routesByIdentity, arguments.stRoute.identity)
            AND structKeyExists(arguments.registry.legacyRoutesByKey, arguments.stRoute.key)>
            <!--- Claim a pre-app-scoped route row for this app to preserve local permissions during the refactor. --->
            <cfset arguments.registry.routesByIdentity[arguments.stRoute.identity] = arguments.registry.legacyRoutesByKey[arguments.stRoute.key] />
        </cfif>

        <cfset arguments.stRoute.urlIdentity = variables.routeIdentity.byUrl(arguments.stRoute.url, arguments.stRoute.app_name) />
        <cfif arguments.registry.persistenceAvailable AND structKeyExists(arguments.registry.routesByIdentity, arguments.stRoute.identity)>
            <cfset mergeLoadedUrlDuplicates(arguments.stRoute, arguments.registry) />
        </cfif>

        <cfif arguments.registry.persistenceAvailable
            AND NOT structKeyExists(arguments.registry.routesByIdentity, arguments.stRoute.identity)
            AND structKeyExists(arguments.registry.routesByUrlIdentity, arguments.stRoute.urlIdentity)>
            <!--- The conventional source route is the same app URL with a new key. Claim the row by URL so re-inits update cleanly instead of violating idx_moo_route_app_name_url. --->
            <cfset arguments.registry.routesByIdentity[arguments.stRoute.identity] = arguments.registry.routesByUrlIdentity[arguments.stRoute.urlIdentity] />
        </cfif>

        <cfreturn arguments.stRoute />
    </cffunction>


    <cffunction name="mergeLoadedUrlDuplicates" access="private" returntype="void" output="false">
        <cfargument name="stRoute" type="struct" required="true" />
        <cfargument name="registry" type="struct" required="true" />
        <cfset var targetRoute = arguments.registry.routesByIdentity[arguments.stRoute.identity] />
        <cfset var routeWithSameUrl = {} />
        <cfset var retainedRoutes = [targetRoute] />

        <cfif NOT structKeyExists(arguments.registry.routesByUrlIdentityList, arguments.stRoute.urlIdentity)>
            <cfset arguments.registry.routesByUrlIdentity[arguments.stRoute.urlIdentity] = targetRoute />
            <cfset arguments.registry.routesByUrlIdentityList[arguments.stRoute.urlIdentity] = retainedRoutes />
            <cfreturn />
        </cfif>

        <cfloop array="#arguments.registry.routesByUrlIdentityList[arguments.stRoute.urlIdentity]#" item="routeWithSameUrl">
            <cfif routeWithSameUrl.id NEQ targetRoute.id>
                <!--- Canonical URL normalization can reveal stale duplicate registry rows such as /login and /login/index. Merge before updating to avoid unique-key conflicts and permission loss. --->
                <cfset variables.registryRowMerger.merge(
                    target_route_id = targetRoute.id,
                    duplicate_route_id = routeWithSameUrl.id
                ) />
            </cfif>
        </cfloop>

        <cfset arguments.registry.routesByUrlIdentity[arguments.stRoute.urlIdentity] = targetRoute />
        <cfset arguments.registry.routesByUrlIdentityList[arguments.stRoute.urlIdentity] = retainedRoutes />
    </cffunction>


    <cffunction name="syncRoute" access="public" returntype="struct" output="false">
        <cfargument name="stRoute" type="struct" required="true" />
        <cfargument name="registry" type="struct" required="true" />

        <cfif NOT arguments.registry.persistenceAvailable>
            <cfreturn assignInMemoryIds(arguments.stRoute) />
        </cfif>

        <cfif !structKeyExists(arguments.registry.routesByIdentity, arguments.stRoute.identity)>
            <cfreturn createRoute(arguments.stRoute, arguments.registry) />
        </cfif>

        <cfreturn updateRoute(arguments.stRoute, arguments.registry) />
    </cffunction>


    <cffunction name="deleteLegacyUnscopedRoutes" access="public" returntype="void" output="false">
        <cfargument name="persistenceAvailable" type="boolean" required="true" />

        <cfif NOT arguments.persistenceAvailable>
            <cfreturn />
        </cfif>

        <cfquery name="local.qDeleteLegacyUnscopedRoutes">
            DELETE FROM moo_route
            WHERE app_name IS NULL
               OR btrim(app_name) = ''
        </cfquery>
    </cffunction>


    <cffunction name="assignInMemoryIds" access="private" returntype="struct" output="false">
        <cfargument name="stRoute" type="struct" required="true" />
        <cfset var function_name = "" />

        <cfset arguments.stRoute.id = arguments.stRoute.key />
        <cfloop collection="#arguments.stRoute.endpoints#" item="function_name">
            <cfset arguments.stRoute.endpoints[function_name].id = "#arguments.stRoute.key#:#function_name#" />
        </cfloop>

        <cfreturn arguments.stRoute />
    </cffunction>


    <cffunction name="createRoute" access="private" returntype="struct" output="false">
        <cfargument name="stRoute" type="struct" required="true" />
        <cfargument name="registry" type="struct" required="true" />
        <cfset var save_moo_route = {} />
        <cfset var function_name = "" />

        <cfset save_moo_route = application.lib.db.save(
            table_name = "moo_route",
            data = {
                key = arguments.stRoute.key,
                app_name = arguments.stRoute.app_name,
                url = arguments.stRoute.url,
                mapping = arguments.stRoute.componentPath
            },
            returnFormat = "cfml"
        ) />

        <cfset arguments.stRoute.id = save_moo_route.id />
        <cfset arguments.registry.routesByIdentity[arguments.stRoute.identity] = {
            id = arguments.stRoute.id,
            key = arguments.stRoute.key,
            app_name = arguments.stRoute.app_name,
            url = arguments.stRoute.url,
            mapping = arguments.stRoute.componentPath,
            endpoints = []
        } />
        <cfset arguments.registry.routesByUrlIdentity[arguments.stRoute.urlIdentity] = arguments.registry.routesByIdentity[arguments.stRoute.identity] />

        <cfloop collection="#arguments.stRoute.endpoints#" item="function_name">
            <cfset arguments.stRoute.endpoints[function_name].id = createEndpoint(arguments.stRoute.id, function_name) />
        </cfloop>

        <cfreturn arguments.stRoute />
    </cffunction>


    <cffunction name="updateRoute" access="private" returntype="struct" output="false">
        <cfargument name="stRoute" type="struct" required="true" />
        <cfargument name="registry" type="struct" required="true" />
        <cfset var existingRoute = arguments.registry.routesByIdentity[arguments.stRoute.identity] />
        <cfset var function_name = "" />
        <cfset var stEndpoint = {} />
        <cfset var endpoint_db_id = "" />

        <cfif existingRoute.url NEQ arguments.stRoute.url
            OR existingRoute.mapping NEQ arguments.stRoute.componentPath
            OR (existingRoute.app_name ?: "") NEQ arguments.stRoute.app_name>
            <cfset application.lib.db.save(
                table_name = "moo_route",
                data = {
                    id = existingRoute.id,
                    key = arguments.stRoute.key,
                    app_name = arguments.stRoute.app_name,
                    url = arguments.stRoute.url,
                    mapping = arguments.stRoute.componentPath
                },
                returnFormat = "cfml"
            ) />
        </cfif>

        <cfset arguments.stRoute.id = existingRoute.id />

        <cfloop collection="#arguments.stRoute.endpoints#" item="function_name">
            <cfset endpoint_db_id = findEndpointId(existingRoute.endpoints, function_name) />
            <cfif !len(endpoint_db_id)>
                <cfset endpoint_db_id = createEndpoint(arguments.stRoute.id, function_name) />
            </cfif>
            <cfset arguments.stRoute.endpoints[function_name].id = endpoint_db_id />
        </cfloop>

        <cfloop array="#existingRoute.endpoints#" item="stEndpoint">
            <cfif NOT structKeyExists(arguments.stRoute.endpoints, stEndpoint.name)>
                <cfset application.lib.db.delete(
                    table_name = "moo_route_endpoint",
                    id = stEndpoint.id,
                    returnFormat = "cfml"
                ) />
            </cfif>
        </cfloop>

        <cfreturn arguments.stRoute />
    </cffunction>


    <cffunction name="findEndpointId" access="private" returntype="string" output="false">
        <cfargument name="endpoints" type="array" required="true" />
        <cfargument name="name" type="string" required="true" />
        <cfset var stEndpoint = {} />

        <cfloop array="#arguments.endpoints#" item="stEndpoint">
            <cfif stEndpoint.name EQ arguments.name>
                <cfreturn stEndpoint.id />
            </cfif>
        </cfloop>

        <cfreturn "" />
    </cffunction>


    <cffunction name="createEndpoint" access="private" returntype="string" output="false">
        <cfargument name="route_id" type="string" required="true" />
        <cfargument name="name" type="string" required="true" />
        <cfset var save_moo_route_endpoint = application.lib.db.save(
            table_name = "moo_route_endpoint",
            data = {
                route_id = arguments.route_id,
                name = arguments.name
            },
            returnFormat = "cfml"
        ) />

        <cfreturn save_moo_route_endpoint.id />
    </cffunction>

</cfcomponent>
