<cfcomponent extends="moopa.application" output="false" hint="Moopa's application component with its private local-mode check made callable, for the local mode harness.">

    <cffunction name="check" access="public" returntype="void" output="false">
        <cfset _assertModernLocalMode() />
    </cffunction>

</cfcomponent>
