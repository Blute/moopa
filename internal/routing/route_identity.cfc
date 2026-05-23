<cfcomponent displayName="route_identity" output="false" hint="Canonical identity keys for app-scoped route registry lookups.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfargument name="routeUrl" required="true" />
        <cfset variables.routeUrl = arguments.routeUrl />
        <cfreturn this />
    </cffunction>


    <cffunction name="byKey" access="public" returntype="string" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfargument name="app_name" type="string" required="true" />

        <cfif NOT len(trim(arguments.key))>
            <cfthrow message="Route identity requires a route key." />
        </cfif>
        <cfif NOT len(trim(arguments.app_name))>
            <cfthrow message="Route identity requires an app_name." />
        </cfif>

        <cfreturn "#lcase(trim(arguments.app_name))#:#lcase(trim(arguments.key))#" />
    </cffunction>


    <cffunction name="byUrl" access="public" returntype="string" output="false">
        <cfargument name="url" type="string" required="true" />
        <cfargument name="app_name" type="string" required="true" />

        <cfif NOT len(trim(arguments.url))>
            <cfthrow message="Route URL identity requires a route URL." />
        </cfif>
        <cfif NOT len(trim(arguments.app_name))>
            <cfthrow message="Route URL identity requires an app_name." />
        </cfif>

        <cfreturn "#lcase(trim(arguments.app_name))#:#lcase(variables.routeUrl.canonicalize(arguments.url))#" />
    </cffunction>

</cfcomponent>
