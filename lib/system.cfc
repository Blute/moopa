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


    <cffunction name="staticUrl" access="public" returntype="string" output="false" hint="The URL Moopa serves a file of its static/ folder at: /_moopa/static/{path}, versioned by the content of moopa.css and moopa.js so browsers keep it until Moopa changes it, or, with this.moopa_anonymous_static_path, a name made from the file's own content (docs/design.md: Serving the static files). Throws moopa.static.notFound for a path that isn't a file Moopa serves.">
        <cfargument name="path" type="string" required="true" hint="Under static/, e.g. moopa.css" />
        <cfreturn application.moopa_static.urlFor(arguments.path) />
    </cffunction>


    <cffunction name="stylesheets" access="public" returntype="string" output="false" hint="The <link> tags every Moopa page loads, in order: the icon CSS, moopa.css, then the project's theme. A Moopa layout and a project's own layout both put this in their <head>, so the System pages and the project's pages share one design. docs/design.md: Theming.">
        <cfset var theme = application.moopa_theme ?: {} />
        <cfset var links = [] />
        <cfset var icons = theme.icons ?: "" />
        <cfset var css = [] />

        <!--- Icons: the project's (e.g. a Font Awesome Pro kit) or Moopa's vendored Font Awesome Free --->
        <cfif len(icons)>
            <cfset arrayAppend(links, '<link rel="stylesheet" href="' & encodeForHTMLAttribute(icons) & '" crossorigin="anonymous" />') />
        <cfelse>
            <cfloop list="fontawesome,solid,regular,brands" index="local.part">
                <cfset arrayAppend(links, '<link rel="stylesheet" href="' & staticUrl("vendor/fontawesome-free-7.3.1/css/" & local.part & ".min.css") & '" />') />
            </cfloop>
        </cfif>

        <cfset arrayAppend(links, '<link rel="stylesheet" href="' & staticUrl("moopa.css") & '" />') />

        <!--- The project's theme: token overrides (and its own extras), after moopa.css so they win.
              application.moopa_theme.css lists them; unset, Moopa uses /_static/theme.css and
              /_static/theme-<app>.css when they exist. --->
        <cfif isArray(theme.css ?: "")>
            <cfset css = theme.css />
        <cfelse>
            <cfset local.conventional = [ "/_static/theme.css", "/_static/theme-" & (application.app_name ?: "app") & ".css" ] />
            <cfloop array="#local.conventional#" index="local.path">
                <cfif fileExists(expandPath(local.path))><cfset arrayAppend(css, local.path) /></cfif>
            </cfloop>
        </cfif>
        <cfloop array="#css#" index="local.path">
            <cfset arrayAppend(links, '<link rel="stylesheet" href="' & encodeForHTMLAttribute(versioned(local.path)) & '" />') />
        </cfloop>

        <cfreturn arrayToList(links, chr(10) & "    ") />
    </cffunction>


    <cffunction name="banner" access="public" returntype="string" output="false" hint="The project's banner (application.moopa_theme.banner): a template rendered as the first thing in <body> on every Moopa page, for a strip each page carries, such as one naming a test environment. Empty when the project sets none. moopa_layout (except in a frame, chrome=false, where the page around it shows it) and moopa_bare render it, and a project's own shell layout may too. docs/design.md: Configuring the theme.">
        <cfset var theme = application.moopa_theme ?: {} />
        <cfset var template = theme.banner ?: "" />
        <cfset var html = "" />
        <cfif NOT len(template)>
            <cfreturn "" />
        </cfif>
        <cfsavecontent variable="html"><cfmodule template="#template#"></cfsavecontent>
        <cfreturn html />
    </cffunction>


    <!--- A project file's URL with ?v= from its content, so browsers keep it until it changes. Worked out once per
          start, and on every call in development, as Moopa's own static files are. A URL that is not a local file is returned as is. --->
    <cffunction name="versioned" access="private" returntype="string" output="false">
        <cfargument name="path" type="string" required="true" />
        <cfset var file = "" />
        <cfif NOT structKeyExists(variables, "fileVersions") OR (server.system.environment.APP_ENVIRONMENT ?: "") EQ "development">
            <cfset variables.fileVersions = {} />
        </cfif>
        <cfif NOT structKeyExists(variables.fileVersions, arguments.path)>
            <cfset file = left(arguments.path, 1) EQ "/" AND NOT find("//", arguments.path) ? expandPath(arguments.path) : "" />
            <cfset variables.fileVersions[arguments.path] = len(file) AND fileExists(file) ? left(lCase(hash(fileRead(file), "MD5")), 12) : "" />
        </cfif>
        <cfif NOT len(variables.fileVersions[arguments.path])>
            <cfreturn arguments.path />
        </cfif>
        <cfreturn arguments.path & (find("?", arguments.path) ? "&" : "?") & "v=" & variables.fileVersions[arguments.path] />
    </cffunction>


    <cffunction name="currentRoute" access="public" returntype="string" output="false" hint="The route a shell marks current in its menus: the given one, else this request's, as a path without a query or trailing slash. Pass the result to navHtml().">
        <cfargument name="route" type="string" default="" hint="Empty: this request's route." />

        <cfset var current = trim(len(arguments.route) ? arguments.route : (url.route ?: "/")) />
        <cfset current = listFirst(current, "?") />
        <cfif NOT len(current)><cfset current = "/" /></cfif>
        <cfif left(current, 1) NEQ "/"><cfset current = "/" & current /></cfif>
        <cfif len(current) GT 1 AND right(current, 1) EQ "/"><cfset current = left(current, len(current) - 1) /></cfif>
        <cfreturn current />
    </cffunction>


    <cffunction name="navHtml" access="public" returntype="string" output="false" hint="Nav items (a nav file's, as moo_profile.buildNavs() gives them, or the System menu as one group) as the shell sidebar's rows: icons made solid for the dark panel, the current route marked and the groups holding it open. An item is a title, icon and route, or a group with items; an item with section is a heading over the rows after it, one with divider a line. An item's own current (true or false) overrides matching its route, for a layout that knows the current page better than the route (a detail page under its list's row). moopa_layout renders its menus with it, and so does a project's own shell layout, inside its moo-shell-nav, so every shell's menus match. docs/design.md: The layout.">
        <cfargument name="items" type="array" required="true" />
        <cfargument name="current" type="string" required="true" hint="The route to mark current, from currentRoute()." />

        <cfset var html = "" />
        <cfset var item = {} />
        <cfloop array="#arguments.items#" item="item">
            <cfset html &= navRow(item, 0, arguments.current) />
        </cfloop>
        <cfreturn html />
    </cffunction>


    <!--- A nav item and its children as sidebar rows --->
    <cffunction name="navRow" access="private" returntype="string" output="false">
        <cfargument name="item" type="struct" required="true" />
        <cfargument name="depth" type="numeric" required="true" />
        <cfargument name="current" type="string" required="true" />

        <cfset var html = "" />
        <cfset var child = {} />
        <cfset var isCurrent = isItemCurrent(arguments.item, arguments.current) />
        <cfset var hasCurrentChild = false />
        <cfset var depthClass = arguments.depth GTE 2 ? " is-depth-2" : (arguments.depth EQ 1 ? " is-depth-1" : "") />
        <!--- The sidebar is dark, so every icon is solid (Font Awesome Free has solid for every free icon) --->
        <cfset var icon = len(arguments.item.icon ?: "") ? solidIcon(arguments.item.icon) : "" />
        <cfset var title = encodeForHTML(arguments.item.title ?: "") />
        <cfset var subId = "" />

        <cfif structKeyExists(arguments.item, "divider")>
            <cfreturn '<div class="moo-shell-menu-divider"></div>' />
        </cfif>
        <cfif structKeyExists(arguments.item, "section")>
            <cfreturn '<div class="moo-shell-section-title">#encodeForHTML(arguments.item.section)#</div>' />
        </cfif>

        <cfif structKeyExists(arguments.item, "items") AND arrayLen(arguments.item.items)>
            <cfset hasCurrentChild = containsCurrent(arguments.item.items, arguments.current) />
            <cfset subId = "moo-shell-sub-" & lCase(left(hash(serializeJSON(arguments.item) & arguments.depth, "MD5"), 10)) />
            <cfset html &= '<div class="moo-shell-nav-row-wrap" data-moo-shell-submenu#hasCurrentChild ? ' data-open="true"' : ''#>' />
            <cfset html &= '<button type="button" class="moo-shell-nav-row#hasCurrentChild ? ' moo-shell-nav-row-parent-current' : ''##depthClass#" data-moo-shell-toggle-submenu aria-expanded="#hasCurrentChild ? 'true' : 'false'#" aria-controls="#subId#">' />
            <cfif arguments.depth EQ 0>
                <cfset html &= '<span class="moo-shell-nav-icon"><i class="#encodeForHTMLAttribute(len(icon) ? icon : 'fa-solid fa-folder')#"></i></span>' />
            </cfif>
            <cfset html &= '<span class="moo-shell-label">#title#</span><span class="moo-shell-chevron"><i class="fa-solid fa-chevron-right"></i></span></button>' />
            <cfset html &= '<span class="moo-shell-nav-tooltip">#title#</span>' />
            <cfset html &= '<div id="#subId#" class="moo-shell-sub-nav"><div class="moo-shell-sub-inner">' />
            <cfloop array="#arguments.item.items#" item="child">
                <cfset html &= navRow(child, arguments.depth + 1, arguments.current) />
            </cfloop>
            <cfset html &= '</div></div></div>' />
            <cfreturn html />
        </cfif>

        <cfif NOT len(arguments.item.route ?: "")>
            <cfreturn "" />
        </cfif>
        <cfset html &= '<div class="moo-shell-nav-row-wrap"><a href="#encodeForHTMLAttribute(arguments.item.route)#" class="moo-shell-nav-row#isCurrent ? ' moo-shell-nav-row-current' : ''##depthClass#"#isCurrent ? ' aria-current="page"' : ''#>' />
        <cfif arguments.depth EQ 0>
            <cfset html &= '<span class="moo-shell-nav-icon">#len(icon) ? '<i class="#encodeForHTMLAttribute(icon)#"></i>' : ''#</span>' />
        </cfif>
        <cfset html &= '<span class="moo-shell-label">#title#</span></a><span class="moo-shell-nav-tooltip">#title#</span></div>' />
        <cfreturn html />
    </cffunction>


    <!--- Whether the current route is anywhere under a nav item, at any depth --->
    <!--- An item is current when it says so (current: true or false), else when its route is the current one --->
    <cffunction name="isItemCurrent" access="private" returntype="boolean" output="false">
        <cfargument name="item" type="struct" required="true" />
        <cfargument name="current" type="string" required="true" />
        <cfif structKeyExists(arguments.item, "current")>
            <cfif NOT isBoolean(arguments.item.current)>
                <cfset var itemName = arguments.item.title ?: (arguments.item.route ?: "") />
                <cfthrow type="moopa.nav.badCurrent" message="Nav item '#itemName#' has a current that isn't true or false." />
            </cfif>
            <cfreturn arguments.item.current />
        </cfif>
        <cfreturn len(arguments.item.route ?: "") AND (arguments.item.route EQ arguments.current) />
    </cffunction>


    <cffunction name="containsCurrent" access="private" returntype="boolean" output="false">
        <cfargument name="items" type="array" required="true" />
        <cfargument name="current" type="string" required="true" />
        <cfset var child = {} />
        <cfloop array="#arguments.items#" item="child">
            <cfif isItemCurrent(child, arguments.current)
                OR (structKeyExists(child, "items") AND isArray(child.items) AND containsCurrent(child.items, arguments.current))>
                <cfreturn true />
            </cfif>
        </cfloop>
        <cfreturn false />
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


    <cffunction name="forgetAvatar" access="public" returntype="void" output="false" hint="Drop this session's cached picture URL, so the next page looks it up again. Call it after a profile's picture changes.">
        <cfset structDelete(session, "moopa_avatar") />
    </cffunction>

</cfcomponent>
