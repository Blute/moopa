<cfcomponent displayName="route_descriptor_builder" output="false" hint="Builds compiled route descriptors from route CFC files.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfargument name="routeUrl" required="true" />
        <cfset variables.routeUrl = arguments.routeUrl />
        <cfreturn this />
    </cffunction>


    <cffunction name="build" access="public" returntype="struct" output="false">
        <cfargument name="location" type="string" required="true" />
        <cfargument name="routePath" type="string" required="true" />
        <cfargument name="componentPath" type="string" required="true" />
        <cfargument name="routeMount" type="string" required="false" default="" />
        <cfargument name="appName" type="string" required="true" />

        <cfset var stRoute = {} />

        <cfset stRoute.key = "" />
        <cfset stRoute.location = arguments.location />
        <cfset stRoute.path = replaceNoCase(stRoute.location, ".cfc", "") />
        <cfset stRoute.localUrl = replaceNoCase(stRoute.path, arguments.routePath, "") />
        <cfset stRoute.url = variables.routeUrl.canonicalize("#arguments.routeMount##stRoute.localUrl#") />
        <cfset stRoute.componentPath = "#arguments.componentPath##stRoute.localUrl#" />
        <cfset stRoute.app_name = arguments.appName />
        <cfset stRoute.docs = {} />
        <cfset stRoute.endpoints = {} />
        <cfset stRoute.md = duplicate(getMetaData(createObject("component", stRoute.componentPath))) />
        <cfset stRoute.open_to = stRoute.md.open_to ?: "security" />

        <cfset addEndpoints(stRoute) />
        <cfset assertRouteKey(stRoute) />

        <cfset stRoute.key = stRoute.md.key />

        <cfif stRoute.url.reFind("\[\w+\]")>
            <cfset addDynamicPattern(stRoute) />
        </cfif>

        <cfreturn stRoute />
    </cffunction>


    <cffunction name="addEndpoints" access="private" returntype="void" output="false">
        <cfargument name="stRoute" type="struct" required="true" />
        <cfset var fn = {} />

        <cfloop array="#arguments.stRoute.md.functions#" item="fn">
            <cfif lCase(fn.access ?: "public") EQ "private">
                <cfcontinue />
            </cfif>
            <cfset arguments.stRoute.endpoints[fn.name] = fn />
            <cfset arguments.stRoute.endpoints[fn.name].open_to = arguments.stRoute.endpoints[fn.name].open_to ?: arguments.stRoute.open_to />
        </cfloop>
    </cffunction>


    <cffunction name="assertRouteKey" access="private" returntype="void" output="false">
        <cfargument name="stRoute" type="struct" required="true" />

        <cfif !len(arguments.stRoute.md.key ?: "")>
            <cfthrow message="No Key Defined for #arguments.stRoute.url#" />
        </cfif>
    </cffunction>


    <cffunction name="addDynamicPattern" access="private" returntype="void" output="false">
        <cfargument name="stRoute" type="struct" required="true" />

        <cfset var route_string = arguments.stRoute.url />
        <cfset var route_parts = [] />
        <cfset var route_groups = [] />
        <cfset var iPart = "" />
        <cfset var iPattern = "" />

        <cfloop list="#route_string#" delimiters="/" item="iPart">
            <cfif left(iPart, 1) EQ "[" AND right(iPart, 1) EQ "]">
                <cfset arrayAppend(route_parts, "([0-9A-Za-z\s\-_]+)") />
                <cfset arrayAppend(route_groups, mid(iPart, 2, len(iPart) - 2)) />
            <cfelse>
                <cfset arrayAppend(route_parts, iPart) />
            </cfif>
        </cfloop>

        <cfset iPattern = route_parts.toList("\/") />
        <cfset arguments.stRoute.pattern = "^\/#iPattern#$" />
        <cfset arguments.stRoute.parts = route_parts />
        <cfset arguments.stRoute.groups = route_groups />
    </cffunction>

</cfcomponent>
