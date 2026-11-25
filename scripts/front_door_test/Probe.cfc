<cfcomponent extends="moopa.application" output="false" hint="Moopa's application component with _moopa() and _requestStarted() replaced by recorders, for the front door harness: it notes the route OnRequest would run, and the route OnRequestStart would count or send to /restarting/, instead of acting on them.">

    <cffunction name="_moopa" access="private" returntype="void" output="false">
        <cfset request.front_door_route = url.route />
    </cffunction>

    <cffunction name="_requestStarted" access="private" returntype="boolean" output="false">
        <cfset request.front_door_started_route = url.route ?: "" />
        <cfreturn true />
    </cffunction>

</cfcomponent>
