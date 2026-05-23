<cfcomponent displayName="route_matcher" output="false" hint="Matches incoming paths against compiled Moopa route registries.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfargument name="routeUrl" required="true" />
        <cfset variables.routeUrl = arguments.routeUrl />
        <cfreturn this />
    </cffunction>


    <cffunction name="parseRoute" access="public" returntype="struct" output="false">
        <cfargument name="route" required="true" hint="Usually from url.route" />
        <cfargument name="staticRoutes" type="struct" required="true" />
        <cfargument name="dynamicRoutes" type="any" required="true" />

        <cfset var result = {
            stRoute : {},
            params : {
                route : arguments.route
            }
        } />
        <cfset var routeToParse = variables.routeUrl.canonicalize(arguments.route) />
        <cfset var static_key = "" />
        <cfset var dynamic_key = "" />
        <cfset var dynamicRouteList = normalizeDynamicRoutes(arguments.dynamicRoutes) />
        <cfset var current_route = {} />
        <cfset var matcher = "" />
        <cfset var oRegex = "" />
        <cfset var group = "" />
        <cfset var i = 0 />

        <cfif !len(routeToParse)>
            <cfabort showerror="MUST INCLUDE A route" />
        </cfif>

        <cfloop collection="#arguments.staticRoutes#" item="static_key">
            <cfif arguments.staticRoutes[static_key].url EQ routeToParse>
                <cfset result.stRoute = arguments.staticRoutes[static_key] />
                <cfbreak />
            </cfif>
        </cfloop>

        <cfif structIsEmpty(result.stRoute)>
            <cfset oRegex = createObject("java", "java.util.regex.Pattern") />

            <cfloop array="#dynamicRouteList#" item="current_route">
                <cfset matcher = oRegex
                    .compile(javaCast("string", current_route.pattern))
                    .matcher(javaCast("string", routeToParse)) />

                <cfif matcher.find()>
                    <cfloop array="#current_route.groups#" item="group" index="i">
                        <cfset result.params[group] = matcher.group(i) />
                    </cfloop>

                    <cfset result.stRoute = current_route />
                    <cfbreak />
                </cfif>
            </cfloop>
        </cfif>

        <cfreturn result />
    </cffunction>


    <cffunction name="normalizeDynamicRoutes" access="private" returntype="array" output="false">
        <cfargument name="dynamicRoutes" type="any" required="true" />
        <cfset var routeList = [] />
        <cfset var routeKey = "" />

        <cfif isArray(arguments.dynamicRoutes)>
            <cfreturn arguments.dynamicRoutes />
        </cfif>

        <cfloop collection="#arguments.dynamicRoutes#" item="routeKey">
            <cfset arrayAppend(routeList, arguments.dynamicRoutes[routeKey]) />
        </cfloop>

        <cfset arraySort(routeList, function(leftRoute, rightRoute) {
            return compareNoCase(leftRoute.url, rightRoute.url);
        }) />

        <cfreturn routeList />
    </cffunction>

</cfcomponent>
