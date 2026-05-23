<cfcomponent displayName="route_matcher" output="false" hint="Matches incoming paths against compiled Moopa route registries.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfargument name="routeUrl" required="true" />
        <cfset variables.routeUrl = arguments.routeUrl />
        <cfreturn this />
    </cffunction>


    <cffunction name="parseRoute" access="public" returntype="struct" output="false">
        <cfargument name="route" required="true" hint="Usually from url.route" />
        <cfargument name="staticRoutes" type="struct" required="true" />
        <cfargument name="dynamicRoutes" type="struct" required="true" />

        <cfset var result = {
            stRoute : {},
            params : {
                route : arguments.route
            }
        } />
        <cfset var routeToParse = variables.routeUrl.canonicalize(arguments.route) />
        <cfset var static_key = "" />
        <cfset var dynamic_key = "" />
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

            <cfloop collection="#arguments.dynamicRoutes#" item="dynamic_key">
                <cfset current_route = arguments.dynamicRoutes[dynamic_key] />
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

</cfcomponent>
