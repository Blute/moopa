<cfcomponent displayName="route_url" output="false" hint="Canonical URL handling for Moopa file-based routes.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>


    <cffunction name="canonicalize" access="public" returntype="string" output="false">
        <cfargument name="url" type="string" required="true" />

        <cfset var routeUrl = replace(trim(arguments.url), chr(92), "/", "all") />
        <cfset routeUrl = reReplace(routeUrl, "\.cfc$", "", "one") />
        <cfset routeUrl = reReplace("/#routeUrl#", "/+", "/", "all") />
        <cfset routeUrl = reReplace(routeUrl, "/+$", "", "one") />

        <cfif NOT len(routeUrl)>
            <cfset routeUrl = "/" />
        </cfif>

        <cfif routeUrl EQ "/index">
            <cfreturn "/" />
        </cfif>

        <cfif right(routeUrl, 6) EQ "/index">
            <cfset routeUrl = left(routeUrl, len(routeUrl) - 6) />
        </cfif>

        <cfreturn routeUrl />
    </cffunction>

</cfcomponent>
