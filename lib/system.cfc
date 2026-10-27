<cfcomponent displayname="system" output="false" hint="Moopa's System pages (/sysadmin), which Hub serves from the framework: the menu that offers them to sysadmins.">

    <cffunction name="init" access="public" returntype="system" output="false">
        <cfreturn this />
    </cffunction>


    <cffunction name="menu" access="public" returntype="array" output="false" hint="The System menu's links (sysadmin_nav.json) for the signed-in profile: all of them for a sysadmin in Hub, none otherwise. A layout shows them in the profile menu; they are never part of a nav.">
        <cfif NOT (application.system_routes ?: false) OR NOT application.lib.auth.isSysAdmin()>
            <cfreturn [] />
        </cfif>
        <cfreturn application.system_menu />
    </cffunction>

</cfcomponent>
