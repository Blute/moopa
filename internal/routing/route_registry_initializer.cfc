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
        <cfset routePackages = [] />
        <cfset routeCandidates = {} />
        <cfset routeCandidateKeys = [] />
        <cfset application.route_overrides = [] />

        <cfif NOT (isDefined("application.moopa_packages") AND isArray(application.moopa_packages))>
            <cfthrow message="Cannot initialize routes: application.moopa_packages is not initialized." />
        </cfif>

        <cfloop array="#application.moopa_packages#" item="local.package">
            <cfif routePackageLoads(local.package)>
                <cfset arrayAppend(routePackages, local.package) />
            </cfif>
        </cfloop>

        <cfloop array="#routePackages#" item="routePackage">
            <cfset packagePrecedence = routePackagePrecedence(routePackage) />
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

                <cfif !structKeyExists(routeCandidates, processed_route_url_key)>
                    <cfset routeCandidates[processed_route_url_key] = {
                        route: stRoute,
                        precedence: packagePrecedence,
                        package_name: routePackage.name,
                        package_kind: routePackage.kind,
                        source: stRoute.componentPath
                    } />
                    <cfset arrayAppend(routeCandidateKeys, processed_route_url_key) />
                <cfelse>
                    <cfset existingCandidate = routeCandidates[processed_route_url_key] />

                    <cfif packagePrecedence EQ existingCandidate.precedence>
                        <cfset duplicateRoute = {
                            route: stRoute.url,
                            new_source: stRoute.componentPath,
                            existing_source: existingCandidate.source,
                            package: routePackage.name,
                            package_kind: routePackage.kind
                        } />
                        <cfset duplicateRouteMessage = serializeJSON(duplicateRoute) />
                        <cfthrow message="#duplicateRouteMessage#" />
                    </cfif>

                    <cfif packagePrecedence GT existingCandidate.precedence>
                        <cfset arrayAppend(application.route_overrides, {
                            route: stRoute.url,
                            selected_source: stRoute.componentPath,
                            overridden_source: existingCandidate.source
                        }) />
                        <cfset routeCandidates[processed_route_url_key] = {
                            route: stRoute,
                            precedence: packagePrecedence,
                            package_name: routePackage.name,
                            package_kind: routePackage.kind,
                            source: stRoute.componentPath
                        } />
                    </cfif>
                </cfif>
            </cfloop>
        </cfloop>

        <cfloop array="#routeCandidateKeys#" item="processed_route_url_key">
            <cfset stRoute = routeCandidates[processed_route_url_key].route />

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

        <cfset arraySort(application.aDynamicRoutes, function(leftRoute, rightRoute) {
            return compareNoCase(leftRoute.url, rightRoute.url);
        }) />

        <cfset variables.routeRegistryStore.deleteLegacyUnscopedRoutes(routeRegistry.persistenceAvailable) />

    </cffunction>


    <cffunction name="routePackageLoads" access="private" returntype="boolean" output="false">
        <cfargument name="package" type="struct" required="true" />

        <cfset var packageKind = arguments.package.kind ?: "" />

        <cfif packageKind EQ "core">
            <cfreturn sysadminRoutesEnabled() />
        </cfif>

        <cfif packageKind EQ "shared">
            <cfreturn true />
        </cfif>

        <cfif packageKind EQ "app">
            <cfreturn (arguments.package.app_name ?: arguments.package.name) EQ (application.app_name ?: "") />
        </cfif>

        <cfreturn false />
    </cffunction>


    <cffunction name="sysadminRoutesEnabled" access="private" returntype="boolean" output="false">
        <cfset var enabled = trim(server.system.environment.MOOPA_ENABLE_SYSADMIN ?: "") />

        <cfreturn listFindNoCase("true,yes,1,on", enabled) GT 0 />
    </cffunction>


    <cffunction name="routePackagePrecedence" access="private" returntype="numeric" output="false">
        <cfargument name="package" type="struct" required="true" />

        <cfset var packageKind = arguments.package.kind ?: "" />

        <cfif packageKind EQ "app">
            <cfreturn 30 />
        </cfif>

        <cfif packageKind EQ "shared">
            <cfreturn 20 />
        </cfif>

        <cfif packageKind EQ "core">
            <cfreturn 10 />
        </cfif>

        <cfreturn 0 />
    </cffunction>




</cfcomponent>
