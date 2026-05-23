<cfcomponent displayName="route_registry_initializer" output="false" hint="Discovers, compiles, and persists Moopa file-based routes into application scope.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfargument name="routeUrl" required="true" />
        <cfargument name="routeIdentity" required="true" />
        <cfargument name="routeDescriptorBuilder" required="true" />
        <cfargument name="registryRowMerger" required="true" />

        <cfset variables.routeUrl = arguments.routeUrl />
        <cfset variables.routeIdentity = arguments.routeIdentity />
        <cfset variables.routeDescriptorBuilder = arguments.routeDescriptorBuilder />
        <cfset variables.registryRowMerger = arguments.registryRowMerger />

        <cfreturn this />
    </cffunction>


    <cffunction name="initializeRoutesIntoApplicationScope">



        <cfset application.stDynamicRoutes = {} />
        <cfset application.stStaticRoutes = {} />
        <cfset application.stAllRoutes = {} />

        <cfset aCheckNoDuplicateKeys = [] />



        <!--- ------------------- --->
        <!--- GET EXISTING ROUTES --->
        <!--- ------------------- --->

        <cfset stDBRoutes = {} />
        <cfset stDBRoutesByAppUrl = {} />
        <cfset stLegacyDBRoutesByKey = {} />
        <cfset routePersistenceAvailable = true />

        <cftry>
            <cfquery name="qDBRoutes">
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

            <cfset aDBRoutes = deserializeJSON(qDBRoutes.data) />
            <cfcatch type="database">
                <!--- First-run/dev fallback: route tables may not exist until /sysadmin/schema has been applied. --->
                <cfset routePersistenceAvailable = false />
                <cfset aDBRoutes = [] />
            </cfcatch>
        </cftry>

        <cfloop array="#aDBRoutes#" item="route">
            <cfif len(route.app_name ?: "")>
                <cfset stDBRoutes[variables.routeIdentity.byKey(route.key, route.app_name)] = route />
                <cfset stDBRoutesByAppUrl[variables.routeIdentity.byUrl(route.url, route.app_name)] = route />
            <cfelse>
                <!--- Legacy rows created before routes were app-scoped. The active app can claim them on re-init. --->
                <cfset stLegacyDBRoutesByKey[route.key] = route />
            </cfif>
        </cfloop>




        <!--- ------------------ --->
        <!--- PROCESS ALL ROUTES --->
        <!--- ------------------ --->
        <cfset processed_route_urls = {} />
        <cfset routePackages = [] />

        <cfif NOT (isDefined("application.moopa_packages") AND isArray(application.moopa_packages))>
            <cfthrow message="Cannot initialize routes: application.moopa_packages is not initialized." />
        </cfif>

        <cfloop array="#application.moopa_packages#" item="local.package">
            <cfset local.packageKind = local.package.kind ?: "" />
            <cfif listFindNoCase("app,shared", local.packageKind)
                AND ((local.package.kind ?: "") NEQ "app" OR (local.package.app_name ?: local.package.name) EQ application.app_name)>
                <cfset arrayAppend(routePackages, local.package) />
            </cfif>
        </cfloop>

        <cfloop array="#routePackages#" item="routePackage">
            <cfset iPackage = routePackage.path />
            <cfset packagePath = expandPath(iPackage) />
            <cfset routePath = "#packagePath#/routes" />
            <cfset componentPath = "#iPackage#/routes" />
            <cfset routeMount = "" />

            <cfif NOT directoryExists(routePath)>
                <cfcontinue />
            </cfif>

            <cfdirectory action="list" directory="#routePath#" name="qRoutes" recurse="true" filter="*.cfc">


<!---
TODO: need to check if old way works for the following and which has precedence: the url of both routes is /test
/routes/test/index.cfc *** THIS HAS PRECEDENCE
/routes/test.cfc

 --->

            <cfloop query="qRoutes">
                <cfset stRoute = variables.routeDescriptorBuilder.build(
                    location = "#qRoutes.directory#/#qRoutes.name#",
                    routePath = routePath,
                    componentPath = componentPath,
                    routeMount = routeMount,
                    appName = application.app_name
                ) />

                <!--- Need to determine if the route is already defined --->

                <cfset processed_route_url_key = lCase(stRoute.url) />
                <cfif !structKeyExists(processed_route_urls, processed_route_url_key)>
                    <cfset processed_route_urls[processed_route_url_key] = stRoute.componentPath />
                <cfelse>
                    <cfthrow message="Duplicate route URL '#stRoute.url#' loaded from #stRoute.componentPath#; already loaded from #processed_route_urls[processed_route_url_key]#. Package boundaries require unique canonical routes within an app runtime." />
                </cfif>

                <cfif ArrayFind(aCheckNoDuplicateKeys, stRoute.md.key)>
                    <cfthrow message="Key In Use. No duplicate keys allowed (#stRoute.md.key#)" />
                </cfif>

                <cfset arrayAppend(aCheckNoDuplicateKeys, stRoute.md.key) />

                <cfset stRoute.identity = variables.routeIdentity.byKey(stRoute.key, stRoute.app_name) />

                <cfif routePersistenceAvailable
                    AND NOT structKeyExists(stDBRoutes, stRoute.identity)
                    AND structKeyExists(stLegacyDBRoutesByKey, stRoute.key)>
                    <!--- Claim a pre-app-scoped route row for this app to preserve local permissions during the refactor. --->
                    <cfset stDBRoutes[stRoute.identity] = stLegacyDBRoutesByKey[stRoute.key] />
                </cfif>

                <cfset stRoute.urlIdentity = variables.routeIdentity.byUrl(stRoute.url, stRoute.app_name) />
                <cfif routePersistenceAvailable
                    AND structKeyExists(stDBRoutes, stRoute.identity)
                    AND structKeyExists(stDBRoutesByAppUrl, stRoute.urlIdentity)
                    AND stDBRoutes[stRoute.identity].id NEQ stDBRoutesByAppUrl[stRoute.urlIdentity].id>
                    <!--- Canonical URL normalization can reveal stale duplicate registry rows such as /login and /login/index. Merge before updating to avoid unique-key conflicts and permission loss. --->
                    <cfset variables.registryRowMerger.merge(
                        target_route_id = stDBRoutes[stRoute.identity].id,
                        duplicate_route_id = stDBRoutesByAppUrl[stRoute.urlIdentity].id
                    ) />
                    <cfset stDBRoutesByAppUrl[stRoute.urlIdentity] = stDBRoutes[stRoute.identity] />
                </cfif>
                <cfif routePersistenceAvailable AND structKeyExists(stDBRoutes, stRoute.identity)>
                    <cfset variables.registryRowMerger.mergeConflictsForUrl(
                        target_route_id = stDBRoutes[stRoute.identity].id,
                        app_name = stRoute.app_name,
                        url = stRoute.url
                    ) />
                </cfif>
                <cfif routePersistenceAvailable
                    AND NOT structKeyExists(stDBRoutes, stRoute.identity)
                    AND structKeyExists(stDBRoutesByAppUrl, stRoute.urlIdentity)>
                    <!--- The conventional source route is the same app URL with a new key. Claim the row by URL so re-inits update cleanly instead of violating idx_moo_route_app_name_url. --->
                    <cfset stDBRoutes[stRoute.identity] = stDBRoutesByAppUrl[stRoute.urlIdentity] />
                </cfif>


                <!--- ------------------------------------- --->
                <!--- SELF REGISTER IF NOT ALREADY EXISTING --->
                <!--- ------------------------------------- --->
                <cfif NOT routePersistenceAvailable>
                    <!--- First-run/dev fallback: keep routes in memory without writing moo_route rows. --->
                    <cfset stRoute.id = stRoute.key />
                    <cfloop collection="#stRoute.endpoints#" item="function_name">
                        <cfset stRoute.endpoints[function_name]['id'] = "#stRoute.key#:#function_name#" />
                    </cfloop>
                <cfelseif !structKeyExists(stDBRoutes, stRoute.identity)>
                    <cfset save_moo_route = application.lib.db.save(
                        table_name = "moo_route",
                        data = {
                            key="#stRoute.key#",
                            app_name="#stRoute.app_name#",
                            url="#stRoute.url#",
                            mapping="#stRoute.componentPath#"
                        },
                        returnFormat="cfml"
                    ) />


                    <cfset stRoute.id = save_moo_route.id />


                    <!--- ADD ALL THE ENDPOINTS THE THIS NEW ROUTE --->
                    <cfloop collection="#stRoute.endpoints#" item="function_name">

                        <cfset save_moo_route_endpoint = application.lib.db.save(
                            table_name = "moo_route_endpoint",
                            data = {
                                route_id="#stRoute.id#",
                                name="#function_name#"
                            },
                            returnFormat="cfml"
                        ) />


                        <cfset stRoute.endpoints[function_name]['id'] = save_moo_route_endpoint.id />

                    </cfloop>



                <cfelse>
                    <!--- JUST IN CASE IT HAS CHANGED OR BEEN RE-USED --->
                    <cfif stDBRoutes[stRoute.identity].url NEQ stRoute.url
                        OR stDBRoutes[stRoute.identity].mapping NEQ stRoute.componentPath
                        OR (stDBRoutes[stRoute.identity].app_name ?: "") NEQ stRoute.app_name>
                        <cfset save_moo_route = application.lib.db.save(
                            table_name = "moo_route",
                            data = {
                                id="#stDBRoutes[stRoute.identity].id#",
                                key="#stRoute.key#",
                                app_name="#stRoute.app_name#",
                                url="#stRoute.url#",
                                mapping="#stRoute.componentPath#"
                            },
                            returnFormat="cfml"
                        ) />
                    </cfif>


                    <cfset stRoute.id = stDBRoutes[stRoute.identity].id />


                    <!--- NOW WE CHECK TO MAKE SURE THE ENPOINTS ARE CORRENT. WE COMPARE THE stRoute with the stDBRoute --->



                    <cfloop collection="#stRoute.endpoints#" item="function_name">
                        <cfset endpoint_found = false />
                        <cfset endpoint_db_id = "" />
                        <cfloop array="#stDBRoutes[stRoute.identity].endpoints#" item="stEndpoint">
                            <cfif stEndpoint.name EQ function_name>
                                <cfset endpoint_found = true />
                                <cfset endpoint_db_id = stEndpoint.id />
                                <cfbreak />
                            </cfif>
                        </cfloop>

                        <cfif !endpoint_found>
                            <cfset save_moo_route_endpoint = application.lib.db.save(
                                table_name = "moo_route_endpoint",
                                data = {
                                    route_id="#stRoute.id#",
                                    name="#function_name#"
                                },
                                returnFormat="cfml"
                            ) />

                            <cfset endpoint_db_id = save_moo_route_endpoint.id />

                        </cfif>


                        <!--- update the endpoint ID --->
                        <cfset stRoute.endpoints[function_name]['id'] = endpoint_db_id />
                    </cfloop>

                    <cfloop array="#stDBRoutes[stRoute.identity].endpoints#" item="stEndpoint">
                        <cfif NOT structKeyExists(stRoute.endpoints, stEndpoint.name)>
                            <cfset application.lib.db.delete(
                                table_name = "moo_route_endpoint",
                                id = stEndpoint.id,
                                returnFormat = "cfml"
                            ) />
                        </cfif>
                    </cfloop>


                </cfif>



                <cfif stRoute.url.reFind("\[\w+\]")>
                    <cfif structKeyExists(application.stDynamicRoutes, stRoute.md.key)>
                        <cfthrow message="Trying to process [#stRoute.path#] but a Route with the key [#stRoute.md.key#] already exists" />
                    </cfif>

                    <cfset application.stDynamicRoutes[stRoute.key] = stRoute />
                <cfelse>

                    <cfif structKeyExists(application.stStaticRoutes, stRoute.md.key)>
                        <cfthrow message="Trying to process [#stRoute.path#] but a Route with the key [#stRoute.md.key#] already exists" />
                    </cfif>

                    <cfset application.stStaticRoutes[stRoute.key] = stRoute />
                </cfif>

                <cfset application.stAllRoutes[stRoute.id] = stRoute />


            </cfloop>
        </cfloop>

        <cfif routePersistenceAvailable>
            <!---
                Routes are now app-scoped. Any remaining rows without app_name are
                stale legacy registry rows that were not claimed by this app's
                current route files, so they must be removed before app_name can
                be enforced as NOT NULL.
            --->
            <cfquery name="qDeleteLegacyUnscopedRoutes">
                DELETE FROM moo_route
                WHERE app_name IS NULL
                   OR btrim(app_name) = ''
            </cfquery>
        </cfif>

    </cffunction>




</cfcomponent>
