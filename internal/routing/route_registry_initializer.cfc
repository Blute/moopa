<cfcomponent displayName="route_registry_initializer" output="false" hint="Discovers, compiles, and persists Moopa file-based routes into application scope.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfargument name="routeDescriptorBuilder" required="true" />
        <cfargument name="routeRegistryStore" required="true" />

        <cfset variables.routeDescriptorBuilder = arguments.routeDescriptorBuilder />
        <cfset variables.routeRegistryStore = arguments.routeRegistryStore />

        <cfreturn this />
    </cffunction>


    <cffunction name="initializeRoutesIntoApplicationScope">



        <cfset application.stDynamicRoutes = {} />
        <cfset application.aDynamicRoutes = [] />
        <cfset application.stStaticRoutes = {} />
        <cfset application.stAllRoutes = {} />

        <cfset aCheckNoDuplicateKeys = [] />
        <cfset routeRegistry = variables.routeRegistryStore.loadExistingRoutes() />



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

                <cfset stRoute = variables.routeRegistryStore.claimExistingRoute(stRoute, routeRegistry) />
                <cfset stRoute = variables.routeRegistryStore.syncRoute(stRoute, routeRegistry) />



                <cfif stRoute.url.reFind("\[\w+\]")>
                    <cfif structKeyExists(application.stDynamicRoutes, stRoute.md.key)>
                        <cfthrow message="Trying to process [#stRoute.path#] but a Route with the key [#stRoute.md.key#] already exists" />
                    </cfif>

                    <cfset application.stDynamicRoutes[stRoute.key] = stRoute />
                    <cfset arrayAppend(application.aDynamicRoutes, stRoute) />
                <cfelse>

                    <cfif structKeyExists(application.stStaticRoutes, stRoute.md.key)>
                        <cfthrow message="Trying to process [#stRoute.path#] but a Route with the key [#stRoute.md.key#] already exists" />
                    </cfif>

                    <cfset application.stStaticRoutes[stRoute.key] = stRoute />
                </cfif>

                <cfset application.stAllRoutes[stRoute.id] = stRoute />


            </cfloop>
        </cfloop>

        <cfset arraySort(application.aDynamicRoutes, function(leftRoute, rightRoute) {
            return compareNoCase(leftRoute.url, rightRoute.url);
        }) />

        <cfset variables.routeRegistryStore.deleteLegacyUnscopedRoutes(routeRegistry.persistenceAvailable) />

    </cffunction>




</cfcomponent>
