<cfcomponent displayName="route_access_map" output="false" hint="Assembles the Route Access page: the app's menus, its live routes, the links between them, and what each role can open.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfargument name="routeUrl" required="true" />
        <cfargument name="routeLinks" required="true" />
        <cfargument name="roleRouteAccess" required="true" />
        <cfset variables.routeUrl = arguments.routeUrl />
        <cfset variables.routeLinks = arguments.routeLinks />
        <cfset variables.roleRouteAccess = arguments.roleRouteAccess />
        <cfreturn this />
    </cffunction>


    <cffunction name="build" access="public" returntype="struct" output="false">
        <cfargument name="app_name" type="string" required="true" />
        <cfargument name="live_routes" type="struct" required="true" hint="application.stAllRoutes" />
        <cfargument name="navs" type="struct" required="true" hint="application.navs" />
        <cfargument name="packages" type="array" required="true" hint="application.moopa_packages" />

        <cfset var routes = [] />
        <cfset var idByUrl = {} />
        <cfset var routeUrls = [] />
        <cfset var routeId = "" />
        <cfset var liveRoute = {} />
        <cfset var menus = {} />
        <cfset var problems = [] />
        <cfset var linkData = {} />
        <cfset var links = {} />
        <cfset var sourceUrl = "" />
        <cfset var target = "" />
        <cfset var state = {} />
        <cfset var registryRow = {} />
        <cfset var ghosts = [] />

        <cfloop collection="#arguments.live_routes#" item="routeId">
            <cfset liveRoute = arguments.live_routes[routeId] />
            <cfif (liveRoute.app_name ?: "") NEQ arguments.app_name>
                <cfcontinue />
            </cfif>
            <cfset idByUrl[liveRoute.url] = routeId />
            <cfset arrayAppend(routeUrls, liveRoute.url) />
            <cfset arrayAppend(routes, { id: routeId, url: liveRoute.url, open_to: liveRoute.open_to ?: "security" }) />
        </cfloop>
        <cfset arraySort(routes, function(a, b) { return compare(a.url, b.url); }) />

        <cfset menus = buildMenus(arguments.navs, idByUrl, problems) />

        <cfset linkData = variables.routeLinks.load(sources = linkSources(arguments.packages), route_urls = routeUrls) />
        <cfset arrayAppend(problems, linkData.problems, true) />
        <cfloop collection="#linkData.links#" item="sourceUrl">
            <cfif NOT structKeyExists(idByUrl, sourceUrl)>
                <cfcontinue />
            </cfif>
            <cfset links[idByUrl[sourceUrl]] = [] />
            <cfloop array="#linkData.links[sourceUrl]#" item="target">
                <cfif structKeyExists(idByUrl, target)>
                    <cfset arrayAppend(links[idByUrl[sourceUrl]], idByUrl[target]) />
                </cfif>
            </cfloop>
        </cfloop>

        <cfset state = variables.roleRouteAccess.getState(app_name = arguments.app_name) />

        <cfloop array="#state.registry#" item="registryRow">
            <cfif NOT structKeyExists(arguments.live_routes, registryRow.id)>
                <cfset arrayAppend(ghosts, registryRow) />
            </cfif>
        </cfloop>

        <cfreturn {
            sections: menus.sections,
            top_links: menus.top_links,
            routes: routes,
            links: links,
            roles: state.roles,
            access: state.access,
            locked: state.locked,
            ghosts: ghosts,
            problems: problems
        } />
    </cffunction>


    <cffunction name="buildMenus" access="private" returntype="struct" output="false" hint="Each nav file's top-level menus become sections of their links (nested menus flattened, dividers dropped); top-level links stand alone. Nav files are taken in name order.">
        <cfargument name="navs" type="struct" required="true" />
        <cfargument name="idByUrl" type="struct" required="true" />
        <cfargument name="problems" type="array" required="true" />

        <cfset var sections = [] />
        <cfset var topLinks = [] />
        <cfset var navNames = structKeyArray(arguments.navs) />
        <cfset var navName = "" />
        <cfset var item = {} />
        <cfset var entry = {} />
        <cfset var section = {} />

        <cfset arraySort(navNames, "textnocase") />

        <cfloop array="#navNames#" item="navName">
            <cfloop array="#arguments.navs[navName]#" item="item">
                <cfif structKeyExists(item, "items")>
                    <cfset section = { title: item.title ?: navName, items: [] } />
                    <cfset collectLinks(item.items, section.items, arguments.idByUrl, arguments.problems, navName) />
                    <cfif arrayLen(section.items)>
                        <cfset arrayAppend(sections, section) />
                    </cfif>
                <cfelseif structKeyExists(item, "route")>
                    <cfset entry = menuEntry(item, arguments.idByUrl, arguments.problems, navName) />
                    <cfif NOT structIsEmpty(entry)>
                        <cfset arrayAppend(topLinks, entry) />
                    </cfif>
                </cfif>
            </cfloop>
        </cfloop>

        <cfreturn { sections: sections, top_links: topLinks } />
    </cffunction>


    <cffunction name="collectLinks" access="private" returntype="void" output="false">
        <cfargument name="items" type="array" required="true" />
        <cfargument name="into" type="array" required="true" />
        <cfargument name="idByUrl" type="struct" required="true" />
        <cfargument name="problems" type="array" required="true" />
        <cfargument name="navName" type="string" required="true" />

        <cfset var item = {} />
        <cfset var entry = {} />

        <cfloop array="#arguments.items#" item="item">
            <cfif structKeyExists(item, "items")>
                <cfset collectLinks(item.items, arguments.into, arguments.idByUrl, arguments.problems, arguments.navName) />
            <cfelseif structKeyExists(item, "route")>
                <cfset entry = menuEntry(item, arguments.idByUrl, arguments.problems, arguments.navName) />
                <cfif NOT structIsEmpty(entry)>
                    <cfset arrayAppend(arguments.into, entry) />
                </cfif>
            </cfif>
        </cfloop>
    </cffunction>


    <cffunction name="menuEntry" access="private" returntype="struct" output="false">
        <cfargument name="item" type="struct" required="true" />
        <cfargument name="idByUrl" type="struct" required="true" />
        <cfargument name="problems" type="array" required="true" />
        <cfargument name="navName" type="string" required="true" />

        <cfset var menuUrl = variables.routeUrl.canonicalize(arguments.item.route) />

        <cfif NOT structKeyExists(arguments.idByUrl, menuUrl)>
            <cfset arrayAppend(arguments.problems, {
                kind: "unknown_menu_route",
                source: arguments.navName,
                route: menuUrl,
                message: "The #arguments.navName# menu's #arguments.item.title ?: menuUrl# item points to #menuUrl#, which is not a route in this app."
            }) />
            <cfreturn {} />
        </cfif>

        <cfreturn { title: arguments.item.title ?: menuUrl, route_id: arguments.idByUrl[menuUrl] } />
    </cffunction>


    <cffunction name="linkSources" access="private" returntype="array" output="false" hint="Each loaded package's route_links.json that exists, in package load order.">
        <cfargument name="packages" type="array" required="true" />

        <cfset var sources = [] />
        <cfset var package = {} />
        <cfset var file = "" />

        <cfloop array="#arguments.packages#" item="package">
            <cfset file = expandPath("#package.path#/route_links.json") />
            <cfif fileExists(file)>
                <cfset arrayAppend(sources, { package: package.name, file: file }) />
            </cfif>
        </cfloop>

        <cfreturn sources />
    </cffunction>

</cfcomponent>
