<cfcomponent output="false" hint="Stands in for lib/core.cfc in the published files harness: logError records what was logged.">
    <cffunction name="init" access="public" returntype="any" output="false">
        <cfset this.logged = [] />
        <cfreturn this />
    </cffunction>
    <cffunction name="logError" access="public" returntype="void" output="false">
        <cfargument name="Exception" type="any" required="true" />
        <cfargument name="EventName" type="string" required="false" default="" />
        <cfset arrayAppend(this.logged, arguments.EventName & ": " & (arguments.Exception.message ?: "")) />
    </cffunction>
</cfcomponent>
