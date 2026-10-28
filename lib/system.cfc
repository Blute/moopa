<cfcomponent displayname="system" output="false" hint="Moopa's System pages (/sysadmin), which Hub serves from the framework: the menu that offers them to sysadmins.">

    <cffunction name="init" access="public" returntype="system" output="false">
        <cfreturn this />
    </cffunction>


    <cffunction name="menu" access="public" returntype="array" output="false" hint="The System menu's links (sysadmin_nav.json) for the signed-in profile: all of them for a sysadmin in Hub, none otherwise. A layout shows them as a group after the app's navs, below a dividing line.">
        <cfif NOT (application.system_routes ?: false) OR NOT application.lib.auth.isSysAdmin()>
            <cfreturn [] />
        </cfif>
        <cfreturn application.system_menu />
    </cffunction>


    <cffunction name="staticUrl" access="public" returntype="string" output="false" hint="The URL Moopa serves a file of its static/ folder at, versioned by the content of moopa.css and moopa.js so browsers keep it until Moopa changes it.">
        <cfargument name="path" type="string" required="true" hint="Under static/, e.g. moopa.css" />

        <cfif NOT structKeyExists(variables, "staticVersion")>
            <cfset variables.staticVersion = left(lCase(hash(fileRead(expandPath("/moopa/static/moopa.css")) & fileRead(expandPath("/moopa/static/moopa.js")), "MD5")), 12) />
        </cfif>
        <cfreturn "/_moopa/static/#arguments.path#?v=#variables.staticVersion#" />
    </cffunction>

</cfcomponent>
