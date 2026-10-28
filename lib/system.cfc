<cfcomponent displayname="system" output="false" hint="Moopa's System pages (/sysadmin), which Hub serves from the framework: the menu that offers them to sysadmins, and what every shell layout shares (solid sidebar icons, the profile picture).">

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

        <!--- Worked out once per start, as the files change only with a deploy; in development, on every
              call, so an edit to moopa.css or moopa.js reaches the browser without a restart --->
        <cfif NOT structKeyExists(variables, "staticVersion") OR (server.system.environment.APP_ENVIRONMENT ?: "") EQ "development">
            <cfset variables.staticVersion = left(lCase(hash(fileRead(expandPath("/moopa/static/moopa.css")) & fileRead(expandPath("/moopa/static/moopa.js")), "MD5")), 12) />
        </cfif>
        <cfreturn "/_moopa/static/#arguments.path#?v=#variables.staticVersion#" />
    </cffunction>


    <cffunction name="solidIcon" access="public" returntype="string" output="false" hint="A Font Awesome class list with its style made solid, for icons on the shell's dark sidebar. Any style (fat, fal, far, fad, fa-thin, fa-light, fa-regular, fa-duotone, sharp ...) becomes fa-solid; brand icons keep fa-brands; a list without a style gets fa-solid.">
        <cfargument name="icon" type="string" required="true" hint="e.g. fat fa-house" />

        <cfset var classes = [] />
        <cfset var styled = false />
        <cfloop list="#arguments.icon#" index="local.cls" delimiters=" ">
            <cfif listFindNoCase("fab,fa-brands", local.cls)>
                <cfif NOT styled><cfset arrayAppend(classes, "fa-brands") /><cfset styled = true /></cfif>
            <cfelseif listFindNoCase("fas,far,fal,fat,fad,fass,fasr,fasl,fast,fasds,fa-solid,fa-regular,fa-light,fa-thin,fa-duotone,fa-sharp,fa-sharp-duotone", local.cls)>
                <cfif NOT styled><cfset arrayAppend(classes, "fa-solid") /><cfset styled = true /></cfif>
            <cfelseif len(local.cls)>
                <cfset arrayAppend(classes, local.cls) />
            </cfif>
        </cfloop>
        <cfif NOT styled AND arrayLen(classes)>
            <cfset arrayPrepend(classes, "fa-solid") />
        </cfif>
        <cfreturn arrayToList(classes, " ") />
    </cffunction>


    <cffunction name="avatarUrl" access="public" returntype="string" output="false" hint="The signed-in profile's picture (its avatar, else its picture) as a small square image URL from the signed-assets Worker, or an empty string when it has none or files are not set up. Kept in the session for 15 minutes per profile, so a change shows without signing out.">
        <cfargument name="profileId" type="string" default="" hint="Empty: the signed-in profile, if there is one." />
        <cfargument name="size" type="numeric" default="64" hint="Pixels; the layout shows it at 2rem." />

        <cfset var cached = {} />
        <cfset var avatar = "" />
        <cfset var rows = [] />

        <!--- Signed out (or after a refused login) session.auth may be empty: look each level up safely --->
        <cfif NOT len(arguments.profileId)
              AND isDefined("session.auth") AND isStruct(session.auth)
              AND structKeyExists(session.auth, "profile") AND isStruct(session.auth.profile)
              AND structKeyExists(session.auth.profile, "id")>
            <cfset arguments.profileId = session.auth.profile.id />
        </cfif>
        <cfif NOT len(arguments.profileId)>
            <cfreturn "" />
        </cfif>
        <cfif isDefined("session.moopa_avatar") AND isStruct(session.moopa_avatar)>
            <cfset cached = session.moopa_avatar />
        </cfif>
        <cfif (cached.profile_id ?: "") EQ arguments.profileId AND (cached.size ?: 0) EQ arguments.size AND isDate(cached.fetched_at ?: "") AND dateDiff("n", cached.fetched_at, now()) LT 15>
            <cfreturn cached.url />
        </cfif>

        <!--- 'NEVER' URLs do not expire, so caching one is safe. Without moo_file, signed_asset_url() or the
              signing settings (config/init/cloudflare.sql) the query fails: no picture, initials instead. --->
        <cftry>
            <cfquery name="rows" returntype="array">
                SELECT signed_asset_url(mf.path, 'NEVER', 'i', <cfqueryparam cfsqltype="varchar" value="width=#arguments.size#&height=#arguments.size#&fit=cover" />) AS avatar_url
                FROM moo_profile p
                INNER JOIN moo_file mf ON mf.id = COALESCE(p.profile_avatar_id, p.profile_picture_id)
                WHERE p.id = <cfqueryparam cfsqltype="other" value="#arguments.profileId#" />
            </cfquery>
            <cfif arrayLen(rows)>
                <cfset avatar = rows[1].avatar_url ?: "" />
            </cfif>
            <cfcatch type="any">
                <cfset avatar = "" />
            </cfcatch>
        </cftry>

        <cfset session.moopa_avatar = { profile_id: arguments.profileId, size: arguments.size, url: avatar, fetched_at: now() } />
        <cfreturn avatar />
    </cffunction>

</cfcomponent>
