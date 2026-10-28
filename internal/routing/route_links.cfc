<cfcomponent displayName="route_links" output="false" hint="Reads packages' route_links.json files: which routes each route's page links to. See docs/route-links.md.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>


    <cffunction name="load" access="public" returntype="struct" output="false" hint="Merge route links files in package load order (a later package's entry for the same route wins, as with navs) and report entries that name routes this runtime does not serve.">
        <cfargument name="sources" type="array" required="true" hint="Ordered [{package, file}], file being the physical path of a route_links.json that exists." />
        <cfargument name="route_urls" type="array" required="true" hint="Every route URL this runtime serves." />

        <cfset var served = {} />
        <cfset var links = structNew("ordered") />
        <cfset var owners = {} />
        <cfset var problems = [] />
        <cfset var source = {} />
        <cfset var fileLinks = {} />
        <cfset var routeUrl = "" />
        <cfset var target = "" />

        <cfloop array="#arguments.route_urls#" item="routeUrl">
            <cfset served[routeUrl] = true />
        </cfloop>

        <cfloop array="#arguments.sources#" item="source">
            <cfset fileLinks = readFile(source.file) />
            <cfloop collection="#fileLinks#" item="routeUrl">
                <cfset links[routeUrl] = fileLinks[routeUrl] />
                <cfset owners[routeUrl] = source.package />
            </cfloop>
        </cfloop>

        <cfloop collection="#links#" item="routeUrl">
            <cfif NOT structKeyExists(served, routeUrl)>
                <cfset arrayAppend(problems, {
                    kind: "unknown_route",
                    source: owners[routeUrl],
                    route: routeUrl,
                    message: "#owners[routeUrl]# lists #routeUrl#, which is not a route in this app."
                }) />
                <cfcontinue />
            </cfif>
            <cfloop array="#links[routeUrl]#" item="target">
                <cfif NOT structKeyExists(served, target)>
                    <cfset arrayAppend(problems, {
                        kind: "unknown_target",
                        source: owners[routeUrl],
                        route: routeUrl,
                        target: target,
                        message: "#routeUrl# links to #target#, which is not a route in this app."
                    }) />
                </cfif>
            </cfloop>
        </cfloop>

        <cfreturn { links: links, problems: problems } />
    </cffunction>


    <cffunction name="readFile" access="private" returntype="struct" output="false" hint="Parse one route_links.json, failing loudly on anything that is not an object of route URL to array of route URLs.">
        <cfargument name="file" type="string" required="true" />

        <cfset var content = fileRead(arguments.file, "utf-8") />
        <cfset var parsed = {} />
        <cfset var routeUrl = "" />
        <cfset var target = "" />

        <cfif NOT isJSON(content)>
            <cfthrow type="moopa.routeLinks.invalid" message="#arguments.file# is not valid JSON." />
        </cfif>

        <cfset parsed = deserializeJSON(content) />

        <cfif NOT isStruct(parsed)>
            <cfthrow type="moopa.routeLinks.invalid" message="#arguments.file# must be an object of route URL to linked route URLs." />
        </cfif>

        <cfloop collection="#parsed#" item="routeUrl">
            <cfif NOT isArray(parsed[routeUrl])>
                <cfthrow type="moopa.routeLinks.invalid" message="#arguments.file#: #routeUrl# must map to an array of route URLs." />
            </cfif>
            <cfloop array="#parsed[routeUrl]#" item="target">
                <cfif NOT isSimpleValue(target) OR left(target, 1) NEQ "/">
                    <cfthrow type="moopa.routeLinks.invalid" message="#arguments.file#: #routeUrl# has a link that is not a route URL." />
                </cfif>
            </cfloop>
        </cfloop>

        <cfreturn parsed />
    </cffunction>

</cfcomponent>
