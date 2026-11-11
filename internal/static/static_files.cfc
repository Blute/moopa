<cfcomponent displayname="static_files" output="false" hint="Where Moopa's static/ folder (its stylesheet, script and vendored libraries) is served, and which file a request there asks for. By default each file is at /_moopa/static/{path}, versioned by the content of moopa.css and moopa.js. With this.moopa_anonymous_static_path set, each file is at {path}/{hash}.{extension} instead, named by its own content, so neither a page's source nor a file's URL says what serves them; a stylesheet's relative url()s are rewritten to those names. docs/design.md: Serving the static files.">

    <cfset variables.TYPES = {
        "css": "text/css; charset=utf-8",
        "js": "text/javascript; charset=utf-8",
        "woff2": "font/woff2",
        "svg": "image/svg+xml",
        "png": "image/png",
        "txt": "text/plain; charset=utf-8"
    } />
    <cfset variables.PLAIN_PREFIX = "/_moopa/static/" />
    <!--- A url() in a stylesheet, its target double-quoted, single-quoted or bare --->
    <cfset variables.CSS_URL = "url\(\s*(?:""([^""]*)""|'([^']*)'|([^""')\s]*))\s*\)" />


    <cffunction name="init" access="public" returntype="static_files" output="false">
        <cfargument name="root" type="string" required="true" hint="The static/ folder's absolute path." />
        <cfargument name="anonymous_path" type="string" required="true" hint="this.moopa_anonymous_static_path as validated at start (/_ui), or empty to serve at /_moopa/static/." />
        <cfargument name="development" type="boolean" required="true" hint="True re-reads the files whenever they change, so an edit reaches the browser without a restart." />

        <cfset variables.root = reReplace(arguments.root, "[\\/]+$", "") />
        <cfset variables.anonymous_path = arguments.anonymous_path />
        <cfset variables.development = arguments.development />
        <cfset variables.prefix = len(variables.anonymous_path) ? variables.anonymous_path & "/" : variables.PLAIN_PREFIX />
        <cfreturn this />
    </cffunction>


    <cffunction name="urlFor" access="public" returntype="string" output="false" hint="The URL a file of static/ is served at. Throws moopa.static.notFound for a path that isn't a file Moopa serves.">
        <cfargument name="path" type="string" required="true" hint="Under static/, e.g. moopa.css" />

        <cfset var catalog = "" />
        <cfif len(variables.anonymous_path)>
            <cfset catalog = anonymousCatalog() />
            <cfif NOT structKeyExists(catalog.by_path, arguments.path)>
                <cfthrow type="moopa.static.notFound" message="static/#arguments.path# isn't a file Moopa serves." />
            </cfif>
            <cfreturn variables.prefix & catalog.by_path[arguments.path].name />
        </cfif>

        <cfif NOT len(plainFile(arguments.path))>
            <cfthrow type="moopa.static.notFound" message="static/#arguments.path# isn't a file Moopa serves." />
        </cfif>
        <cfreturn variables.PLAIN_PREFIX & arguments.path & "?v=" & plainVersion() />
    </cffunction>


    <cffunction name="owns" access="public" returntype="boolean" output="false" hint="Whether a request's route is under the path the static files are served at, so Moopa answers it from static/ (or with a 404) before the session or database is touched.">
        <cfargument name="route" type="string" required="true" />
        <cfreturn left(arguments.route, len(variables.prefix)) EQ variables.prefix />
    </cffunction>


    <cffunction name="lookup" access="public" returntype="struct" output="false" hint="The file a route that owns() asks for: { type, immutable } with file (a path to send) or bytes (a stylesheet rewritten for its anonymous URL, as UTF-8 to send exactly), or an empty struct when there is no such file. immutable says the URL's content never changes: an anonymous name, a ?v= URL or a versioned vendor/ folder.">
        <cfargument name="route" type="string" required="true" />
        <cfargument name="versioned" type="boolean" required="true" hint="Whether the request carries ?v=." />

        <cfset var path = mid(arguments.route, len(variables.prefix) + 1, len(arguments.route)) />
        <cfset var catalog = "" />
        <cfset var entry = "" />
        <cfset var file = "" />

        <cfif len(variables.anonymous_path)>
            <cfset catalog = anonymousCatalog() />
            <cfif NOT structKeyExists(catalog.by_name, path)>
                <cfreturn {} />
            </cfif>
            <cfset entry = catalog.by_name[path] />
            <cfif structKeyExists(entry, "bytes")>
                <cfreturn { type: entry.type, bytes: entry.bytes, immutable: true } />
            </cfif>
            <cfreturn { type: entry.type, file: entry.file, immutable: true } />
        </cfif>

        <cfset file = plainFile(path) />
        <cfif NOT len(file)>
            <cfreturn {} />
        </cfif>
        <cfreturn {
            type: variables.TYPES[lCase(listLast(path, "."))],
            file: file,
            immutable: arguments.versioned OR left(path, 7) EQ "vendor/"
        } />
    </cffunction>


    <!--- The file a plain path names, or empty when it isn't one Moopa serves: a path of plain segments
          (no .., no hidden files) to an existing file with a known extension --->
    <cffunction name="plainFile" access="private" returntype="string" output="false">
        <cfargument name="path" type="string" required="true" />

        <cfset var file = variables.root & "/" & arguments.path />
        <cfif NOT reFind("^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*(/[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*)*$", arguments.path)
            OR NOT structKeyExists(variables.TYPES, lCase(listLast(arguments.path, ".")))
            OR NOT fileExists(file)>
            <cfreturn "" />
        </cfif>
        <cfreturn file />
    </cffunction>


    <!--- The plain URLs' ?v=: the content of moopa.css and moopa.js. Worked out once per start, as the files
          change only with a deploy; in development, on every call, so an edit reaches the browser without a restart --->
    <cffunction name="plainVersion" access="private" returntype="string" output="false">
        <cfif NOT structKeyExists(variables, "plain_version") OR variables.development>
            <cfset variables.plain_version = left(lCase(hash(fileRead(variables.root & "/moopa.css") & fileRead(variables.root & "/moopa.js"), "MD5")), 12) />
        </cfif>
        <cfreturn variables.plain_version />
    </cffunction>


    <!--- Every file Moopa serves, by its path under static/ (by_path) and by its anonymous name (by_name). Built
          once per start; in development, again whenever a file is added, removed or changed. --->
    <cffunction name="anonymousCatalog" access="private" returntype="struct" output="false">
        <cfset var listing = "" />
        <cfset var signature = "" />

        <cfif structKeyExists(variables, "catalog") AND NOT variables.development>
            <cfreturn variables.catalog />
        </cfif>
        <cfset listing = directoryList(variables.root, true, "query", "", "directory,name") />
        <cfloop query="listing">
            <cfset signature &= listing.directory & "/" & listing.name & "|" & listing.size & "|" & listing.dateLastModified & chr(10) />
        </cfloop>
        <cfset signature = hash(signature, "MD5") />
        <cfif NOT structKeyExists(variables, "catalog") OR variables.catalog_signature NEQ signature>
            <cfset variables.catalog = buildCatalog(listing) />
            <cfset variables.catalog_signature = signature />
        </cfif>
        <cfreturn variables.catalog />
    </cffunction>


    <cffunction name="buildCatalog" access="private" returntype="struct" output="false">
        <cfargument name="listing" type="query" required="true" />

        <cfset var catalog = { by_path: {}, by_name: {} } />
        <cfset var stylesheets = [] />
        <cfset var path = "" />
        <cfset var file = "" />
        <cfset var extension = "" />
        <cfset var bytes = "" />
        <cfset var entry = "" />

        <!--- Everything but the stylesheets first: a stylesheet's url()s are rewritten to the names of the
              files they point at, so those names must be known before it is --->
        <cfloop query="arguments.listing">
            <cfif arguments.listing.type NEQ "File">
                <cfcontinue />
            </cfif>
            <cfset file = arguments.listing.directory & "/" & arguments.listing.name />
            <cfset path = mid(replace(file, "\", "/", "all"), len(variables.root) + 2, len(file)) />
            <cfset extension = lCase(listLast(arguments.listing.name, ".")) />
            <cfif NOT find(".", arguments.listing.name) OR NOT structKeyExists(variables.TYPES, extension)>
                <cfcontinue />
            </cfif>
            <cfif extension EQ "css">
                <cfset arrayAppend(stylesheets, { path: path, file: file }) />
                <cfcontinue />
            </cfif>
            <cfset entry = { name: contentName(fileReadBinary(file), extension), type: variables.TYPES[extension], file: file } />
            <cfset catalog.by_path[path] = entry />
            <cfset catalog.by_name[entry.name] = entry />
        </cfloop>

        <cfloop array="#stylesheets#" item="local.stylesheet">
            <cfset bytes = charsetDecode(rewriteUrls(fileRead(local.stylesheet.file, "utf-8"), local.stylesheet.path, catalog), "utf-8") />
            <cfset entry = { name: contentName(bytes, "css"), type: variables.TYPES.css, bytes: bytes } />
            <cfset catalog.by_path[local.stylesheet.path] = entry />
            <cfset catalog.by_name[entry.name] = entry />
        </cfloop>

        <cfreturn catalog />
    </cffunction>


    <!--- A file's anonymous name: the start of its content's SHA-256, then its extension. Files with the same
          content share a name, and serve the same bytes. --->
    <cffunction name="contentName" access="private" returntype="string" output="false">
        <cfargument name="bytes" type="binary" required="true" />
        <cfargument name="extension" type="string" required="true" />
        <cfreturn left(lCase(hash(arguments.bytes, "SHA-256")), 16) & "." & arguments.extension />
    </cffunction>


    <!--- A stylesheet with each relative url() (../webfonts/fa-solid-900.woff2) pointing at that file's anonymous
          URL. Absolute, data: and fragment-only URLs stay as they are. A relative URL that doesn't resolve to a
          file Moopa serves throws moopa.static.unresolvedUrl, rather than leave a link that 404s. --->
    <cffunction name="rewriteUrls" access="private" returntype="string" output="false">
        <cfargument name="css" type="string" required="true" />
        <cfargument name="path" type="string" required="true" hint="The stylesheet's path under static/." />
        <cfargument name="catalog" type="struct" required="true" />

        <cfset var result = "" />
        <cfset var start = 1 />
        <cfset var found = "" />
        <cfset var target = "" />
        <cfset var group = 0 />
        <cfset var suffix = "" />
        <cfset var resolved = "" />
        <cfset var cut = 0 />

        <cfloop condition="true">
            <cfset found = reFind(variables.CSS_URL, arguments.css, start, true) />
            <cfif found.pos[1] EQ 0>
                <cfbreak />
            </cfif>
            <cfset target = "" />
            <cfloop from="2" to="4" index="group">
                <cfif arrayLen(found.pos) GTE group AND found.pos[group] GT 0>
                    <cfset target = mid(arguments.css, found.pos[group], found.len[group]) />
                </cfif>
            </cfloop>
            <cfset result &= mid(arguments.css, start, found.pos[1] - start) />
            <cfif NOT len(target) OR reFind("^([A-Za-z][A-Za-z0-9+.-]*:|/|##)", target)>
                <cfset result &= mid(arguments.css, found.pos[1], found.len[1]) />
            <cfelse>
                <cfset cut = reFind("[?##]", target) />
                <cfset suffix = cut ? mid(target, cut, len(target)) : "" />
                <cfset resolved = resolvePath(listDeleteAt(arguments.path, listLen(arguments.path, "/"), "/"), cut ? left(target, cut - 1) : target) />
                <cfif NOT len(resolved) OR NOT structKeyExists(arguments.catalog.by_path, resolved)>
                    <cfthrow type="moopa.static.unresolvedUrl"
                        message="static/#arguments.path# links url(#target#), which isn't a file Moopa serves." />
                </cfif>
                <cfset result &= 'url("' & variables.prefix & arguments.catalog.by_path[resolved].name & suffix & '")' />
            </cfif>
            <cfset start = found.pos[1] + found.len[1] />
        </cfloop>

        <cfreturn result & mid(arguments.css, start, len(arguments.css)) />
    </cffunction>


    <!--- A relative URL's path under static/, from the folder of the file that links it; empty when it climbs out --->
    <cffunction name="resolvePath" access="private" returntype="string" output="false">
        <cfargument name="folder" type="string" required="true" hint="Under static/, empty for static/ itself." />
        <cfargument name="relative" type="string" required="true" />

        <cfset var segments = listToArray(arguments.folder, "/") />
        <cfset var segment = "" />
        <cfloop list="#arguments.relative#" delimiters="/" index="segment">
            <cfif segment EQ "..">
                <cfif NOT arrayLen(segments)>
                    <cfreturn "" />
                </cfif>
                <cfset arrayDeleteAt(segments, arrayLen(segments)) />
            <cfelseif segment NEQ ".">
                <cfset arrayAppend(segments, segment) />
            </cfif>
        </cfloop>
        <cfreturn arrayToList(segments, "/") />
    </cffunction>

</cfcomponent>
