<cfcomponent extends="moopa.application" output="false" hint="Moopa's application component with _moopa() replaced by a recorder, for the front door harness: it notes the route onRequest would run instead of running it.">

    <cffunction name="_moopa" access="private" returntype="void" output="false">
        <cfset request.front_door_route = url.route />
    </cffunction>

</cfcomponent>
