<cfcomponent key="c67106f7-67f2-45d6-97f7-a0bc7fb0e126" open_to="security">

    <cffunction name="load">
        <cfreturn buildSummary() />
    </cffunction>

    <cffunction name="get">
        <cfset var summary = buildSummary() />

        <cfmodule template="/moopa/tags/moopa_layout.cfm" title="App summary">
            <cfoutput>
                <div class="page">
                    <div class="page-header">
                        <div>
                            <div class="eyebrow">#htmlEditFormat(summary.app_name)# runtime</div>
                            <h1>App summary</h1>
                            <p class="page-lede">Everything Moopa loaded for this app when it started: packages, routes, table services, libraries, controls, navs and tags.</p>
                        </div>
                        <div class="page-actions">
                            <a href="/sysadmin/app_summary/?X-Endpoint=load" class="btn btn-sm"><i class="fa-solid fa-code"></i> JSON</a>
                        </div>
                    </div>

                    <div class="auto-grid" style="--auto-min: 13rem">
                        <div class="card stat">
                            <div class="stat-label">App</div>
                            <div class="stat-value">#htmlEditFormat(summary.app_title)#</div>
                            <div class="stat-sub mono">#htmlEditFormat(summary.app_base_url)#</div>
                        </div>
                        <div class="card stat">
                            <div class="stat-label">Packages</div>
                            <div class="stat-value">#arrayLen(summary.packages)#</div>
                            <div class="stat-sub">Moopa, then shared, then the active app</div>
                        </div>
                        <div class="card stat">
                            <div class="stat-label">Routes</div>
                            <div class="stat-value">#summary.totals.routes#</div>
                            <div class="stat-sub">#summary.totals.static_routes# static · #summary.totals.dynamic_routes# dynamic · #summary.totals.route_endpoints# endpoints</div>
                        </div>
                        <div class="card stat">
                            <div class="stat-label">Services</div>
                            <div class="stat-value">#summary.totals.table_services#</div>
                            <div class="stat-sub">#arrayLen(summary.table_overrides)# intentional table override(s)</div>
                        </div>
                    </div>

                    <div class="split split-end">
                        <div class="stack" style="--stack-gap: var(--card-gap)">
                            <section class="card">
                                <div class="card-header"><h2 class="card-title">Loaded packages</h2></div>
                                <div class="table-wrap">
                                    <table class="table table-sm">
                                        <thead>
                                            <tr>
                                                <th>Package</th>
                                                <th>Kind</th>
                                                <th>Path</th>
                                                <th class="text-right">Routes</th>
                                                <th class="text-right">Tables</th>
                                                <th class="text-right">Lib</th>
                                                <th class="text-right">Controls</th>
                                                <th class="text-right">Navs</th>
                                                <th class="text-right">Tags</th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            <cfloop array="#summary.packages#" item="packageSummary">
                                                <tr>
                                                    <td class="cell-main">#htmlEditFormat(packageSummary.name)#</td>
                                                    <td><span class="badge">#htmlEditFormat(packageSummary.kind)#</span></td>
                                                    <td class="mono muted">#htmlEditFormat(packageSummary.path)#</td>
                                                    <td class="text-right">#packageSummary.capabilities.routes.count#</td>
                                                    <td class="text-right">#packageSummary.capabilities.tables.count#</td>
                                                    <td class="text-right">#packageSummary.capabilities.lib.count#</td>
                                                    <td class="text-right">#packageSummary.capabilities.controls.count#</td>
                                                    <td class="text-right">#packageSummary.capabilities.navs.count#</td>
                                                    <td class="text-right">#packageSummary.capabilities.tags.count#</td>
                                                </tr>
                                            </cfloop>
                                        </tbody>
                                    </table>
                                </div>
                            </section>

                            <section class="card">
                                <div class="card-header"><h2 class="card-title">Route access mix</h2></div>
                                <div class="card-body auto-grid" style="--auto-min: 9rem">
                                    <cfloop array="#summary.route_access_rows#" item="accessRow">
                                        <div class="stat" style="padding: var(--sp-3); border: 1px solid var(--hairline); border-radius: var(--radius-md); background: var(--canvas-cream)">
                                            <div class="stat-label">#htmlEditFormat(accessRow.name)#</div>
                                            <div class="stat-value">#accessRow.count#</div>
                                        </div>
                                    </cfloop>
                                </div>
                            </section>

                            <section class="card">
                                <div class="card-header"><h2 class="card-title">Table definition overrides</h2></div>
                                <cfif arrayLen(summary.table_overrides)>
                                    <div class="table-wrap">
                                        <table class="table table-sm">
                                            <thead>
                                                <tr><th>Table</th><th>Effective package</th><th>Overridden package(s)</th></tr>
                                            </thead>
                                            <tbody>
                                                <cfloop array="#summary.table_overrides#" item="overrideRow">
                                                    <tr>
                                                        <td class="mono">#htmlEditFormat(overrideRow.name)#</td>
                                                        <td><span class="badge badge-signal">#htmlEditFormat(overrideRow.effective_package)#</span></td>
                                                        <td class="muted small">#htmlEditFormat(arrayToList(overrideRow.overridden_packages, ", "))#</td>
                                                    </tr>
                                                </cfloop>
                                            </tbody>
                                        </table>
                                    </div>
                                <cfelse>
                                    <div class="card-body small muted">No table definitions are overridden in this runtime.</div>
                                </cfif>
                            </section>
                        </div>

                        <aside class="stack" style="--stack-gap: var(--card-gap)">
                            <section class="card">
                                <div class="card-header"><h2 class="card-title">Loaded scopes</h2></div>
                                <div class="card-body kv-grid">
                                    <span class="kv-label">Table services</span><span class="kv-value strong">#summary.totals.table_services#</span>
                                    <span class="kv-label">Libraries</span><span class="kv-value strong">#summary.totals.libraries#</span>
                                    <span class="kv-label">Controls</span><span class="kv-value strong">#summary.totals.controls#</span>
                                    <span class="kv-label">Navs</span><span class="kv-value strong">#summary.totals.navs#</span>
                                </div>
                            </section>

                            <section class="card">
                                <div class="card-header"><h2 class="card-title">Nav files</h2></div>
                                <div class="card-body cluster">
                                    <cfloop array="#summary.loaded.navs#" item="navName">
                                        <span class="badge">#htmlEditFormat(navName)#</span>
                                    </cfloop>
                                    <cfif NOT arrayLen(summary.loaded.navs)>
                                        <span class="muted small">None</span>
                                    </cfif>
                                </div>
                            </section>

                            <section class="card">
                                <div class="card-header"><h2 class="card-title">Libraries</h2></div>
                                <div class="card-body mono small secondary" style="max-height: 18rem; overflow: auto; line-height: 1.7">
                                    <cfloop array="#summary.loaded.libraries#" item="libName">#htmlEditFormat(libName)#<br></cfloop>
                                </div>
                            </section>
                        </aside>
                    </div>
                </div>
            </cfoutput>
        </cfmodule>
    </cffunction>

    <cffunction name="buildSummary" access="private" returntype="struct" output="false">
        <cfset var summary = {
            app_name = application.app_name ?: "",
            app_title = appSetting("app_titles", application.app_name ?: "", application.app_name ?: ""),
            app_home = appSetting("app_homes", application.app_name ?: "", "/"),
            app_base_url = appSetting("app_base_urls", application.app_name ?: "", application.base_url ?: ""),
            packages = [],
            loaded = {},
            totals = {},
            table_overrides = [],
            route_open_to_counts = {},
            route_access_rows = [],
            route_package_counts = {}
        } />
        <cfset var package = {} />
        <cfset var packageSummary = {} />
        <cfset var tableEntriesByName = {} />
        <cfset var tableName = "" />
        <cfset var tableEntries = [] />
        <cfset var routeId = "" />
        <cfset var route = {} />
        <cfset var openTo = "" />
        <cfset var routePackage = "" />
        <cfset var endpointCount = 0 />
        <cfset var accessName = "" />

        <cfloop array="#application.moopa_packages#" item="package">
            <cfset packageSummary = scanPackage(package) />
            <cfset arrayAppend(summary.packages, packageSummary) />

            <cfloop array="#packageSummary.capabilities.tables.records#" item="tableRecord">
                <cfset tableName = tableRecord.name />
                <cfif NOT structKeyExists(tableEntriesByName, tableName)>
                    <cfset tableEntriesByName[tableName] = [] />
                </cfif>
                <cfset tableRecord.package_name = packageSummary.name />
                <cfset arrayAppend(tableEntriesByName[tableName], duplicate(tableRecord)) />
            </cfloop>
        </cfloop>

        <cfloop collection="#tableEntriesByName#" item="tableName">
            <cfset tableEntries = tableEntriesByName[tableName] />
            <cfif arrayLen(tableEntries) GT 1>
                <cfset arrayAppend(summary.table_overrides, {
                    name = tableName,
                    effective_package = tableEntries[arrayLen(tableEntries)].package_name,
                    overridden_packages = overriddenPackageNames(tableEntries)
                }) />
            </cfif>
        </cfloop>

        <cfset summary.loaded.table_services = sortedStructKeys(application.service ?: {}) />
        <cfset summary.loaded.libraries = sortedStructKeys(application.lib ?: {}) />
        <!---
            Controls are CFM templates resolved at render time by package path, not
            long-lived CFC instances in application.control. Report the effective
            control templates from the loaded package stack instead of application.control.
        --->
        <cfset summary.loaded.controls = effectiveCapabilityNames(summary.packages, "controls") />
        <cfset summary.loaded.control_templates = effectiveCapabilityRecords(summary.packages, "controls") />
        <cfset summary.loaded.navs = sortedStructKeys(application.navs ?: {}) />

        <cfif structKeyExists(application, "stAllRoutes")>
            <cfloop collection="#application.stAllRoutes#" item="routeId">
                <cfset route = application.stAllRoutes[routeId] />
                <cfset openTo = route.open_to ?: "security" />
                <cfset routePackage = classifyRoutePackage(route) />
                <cfif NOT structKeyExists(summary.route_open_to_counts, openTo)>
                    <cfset summary.route_open_to_counts[openTo] = 0 />
                </cfif>
                <cfset summary.route_open_to_counts[openTo] = summary.route_open_to_counts[openTo] + 1 />
                <cfif NOT structKeyExists(summary.route_package_counts, routePackage)>
                    <cfset summary.route_package_counts[routePackage] = 0 />
                </cfif>
                <cfset summary.route_package_counts[routePackage] = summary.route_package_counts[routePackage] + 1 />
                <cfset endpointCount = endpointCount + structCount(route.endpoints ?: {}) />
            </cfloop>
        </cfif>

        <cfloop array="#sortedStructKeys(summary.route_open_to_counts)#" item="accessName">
            <cfset arrayAppend(summary.route_access_rows, { name = accessName, count = summary.route_open_to_counts[accessName] }) />
        </cfloop>

        <cfset summary.totals.routes = structCount(application.stAllRoutes ?: {}) />
        <cfset summary.totals.static_routes = structCount(application.stStaticRoutes ?: {}) />
        <cfset summary.totals.dynamic_routes = structCount(application.stDynamicRoutes ?: {}) />
        <cfset summary.totals.route_endpoints = endpointCount />
        <cfset summary.totals.table_services = arrayLen(summary.loaded.table_services) />
        <cfset summary.totals.libraries = arrayLen(summary.loaded.libraries) />
        <cfset summary.totals.controls = arrayLen(summary.loaded.controls) />
        <cfset summary.totals.navs = arrayLen(summary.loaded.navs) />

        <cfreturn summary />
    </cffunction>

    <cffunction name="scanPackage" access="private" returntype="struct" output="false">
        <cfargument name="package" type="struct" required="true" />
        <cfset var result = {
            name = arguments.package.name ?: "",
            kind = arguments.package.kind ?: "",
            path = arguments.package.path ?: "",
            physical_path = expandPath(arguments.package.path ?: "/"),
            capabilities = {}
        } />

        <cfset result.capabilities.routes = scanDirectory(arguments.package, "routes", "*.cfc", true) />
        <cfset result.capabilities.tables = scanDirectory(arguments.package, "tables", "*.cfc", true) />
        <cfset result.capabilities.lib = scanDirectory(arguments.package, "lib", "*.cfc", true) />
        <cfset result.capabilities.controls = scanDirectory(arguments.package, "controls", "*.cfm", true) />
        <cfset result.capabilities.navs = scanDirectory(arguments.package, "navs", "*.json", false) />
        <cfset result.capabilities.tags = scanDirectory(arguments.package, "tags", "*.cfm", true) />

        <cfreturn result />
    </cffunction>

    <cffunction name="scanDirectory" access="private" returntype="struct" output="false">
        <cfargument name="package" type="struct" required="true" />
        <cfargument name="capability" type="string" required="true" />
        <cfargument name="filter" type="string" required="true" />
        <cfargument name="recurse" type="boolean" required="true" />

        <cfset var virtualDirectory = (arguments.package.path ?: "") & "/" & arguments.capability />
        <cfset var physicalDirectory = expandPath(virtualDirectory) />
        <cfset var result = {
            loads = packageLoads(arguments.package, arguments.capability),
            virtual_directory = virtualDirectory,
            physical_directory = physicalDirectory,
            exists = false,
            count = 0,
            records = []
        } />
        <cfset var qFiles = queryNew("") />
        <cfset var filePath = "" />
        <cfset var relativePath = "" />
        <cfset var recordName = "" />

        <cfif NOT result.loads OR NOT directoryExists(physicalDirectory)>
            <cfreturn result />
        </cfif>

        <cfset result.exists = true />
        <cfdirectory action="list" directory="#physicalDirectory#" recurse="#arguments.recurse#" name="qFiles" filter="#arguments.filter#" />
        <cfloop query="qFiles">
            <cfset filePath = replace(qFiles.directory & "/" & qFiles.name, "\", "/", "all") />
            <cfset relativePath = replaceNoCase(filePath, replace(physicalDirectory, "\", "/", "all") & "/", "", "one") />
            <cfset recordName = listFirst(qFiles.name, ".") />
            <cfset arrayAppend(result.records, {
                name = recordName,
                relative_path = relativePath,
                path = virtualDirectory & "/" & relativePath
            }) />
        </cfloop>
        <cfset result.count = arrayLen(result.records) />

        <cfreturn result />
    </cffunction>

    <cffunction name="packageLoads" access="private" returntype="boolean" output="false">
        <cfargument name="package" type="struct" required="true" />
        <cfargument name="capability" type="string" required="true" />
        <cfset var packageKind = arguments.package.kind ?: "" />

        <cfif arguments.capability EQ "routes" OR arguments.capability EQ "navs">
            <cfif packageKind EQ "core">
                <cfreturn arguments.capability EQ "routes" AND (application.system_routes ?: false) />
            </cfif>

            <cfreturn (listFindNoCase("app,shared", packageKind) GT 0) AND (packageKind NEQ "app" OR (arguments.package.app_name ?: arguments.package.name) EQ (application.app_name ?: "")) />
        </cfif>

        <cfif listFindNoCase("tables,controls,lib,tags", arguments.capability)>
            <cfreturn (listFindNoCase("core,shared,app", packageKind) GT 0) AND (packageKind NEQ "app" OR (arguments.package.app_name ?: arguments.package.name) EQ (application.app_name ?: "")) />
        </cfif>

        <cfreturn false />
    </cffunction>

    <cffunction name="appSetting" access="private" returntype="string" output="false">
        <cfargument name="settingName" type="string" required="true" />
        <cfargument name="key" type="string" required="true" />
        <cfargument name="fallback" type="string" required="true" />

        <cfif structKeyExists(application, arguments.settingName)
            AND isStruct(application[arguments.settingName])
            AND structKeyExists(application[arguments.settingName], arguments.key)>
            <cfreturn application[arguments.settingName][arguments.key] />
        </cfif>

        <cfreturn arguments.fallback />
    </cffunction>

    <cffunction name="sortedStructKeys" access="private" returntype="array" output="false">
        <cfargument name="source" type="struct" required="true" />
        <cfset var keys = listToArray(structKeyList(arguments.source)) />
        <cfset arraySort(keys, "textnocase") />
        <cfreturn keys />
    </cffunction>

    <cffunction name="effectiveCapabilityNames" access="private" returntype="array" output="false">
        <cfargument name="packageSummaries" type="array" required="true" />
        <cfargument name="capability" type="string" required="true" />
        <cfset var recordsByName = effectiveCapabilityRecordMap(arguments.packageSummaries, arguments.capability) />

        <cfreturn sortedStructKeys(recordsByName) />
    </cffunction>

    <cffunction name="effectiveCapabilityRecords" access="private" returntype="array" output="false">
        <cfargument name="packageSummaries" type="array" required="true" />
        <cfargument name="capability" type="string" required="true" />
        <cfset var recordsByName = effectiveCapabilityRecordMap(arguments.packageSummaries, arguments.capability) />
        <cfset var names = sortedStructKeys(recordsByName) />
        <cfset var records = [] />
        <cfset var name = "" />

        <cfloop array="#names#" item="name">
            <cfset arrayAppend(records, recordsByName[name]) />
        </cfloop>

        <cfreturn records />
    </cffunction>

    <cffunction name="effectiveCapabilityRecordMap" access="private" returntype="struct" output="false">
        <cfargument name="packageSummaries" type="array" required="true" />
        <cfargument name="capability" type="string" required="true" />
        <cfset var recordsByName = {} />
        <cfset var packageSummary = {} />
        <cfset var record = {} />
        <cfset var effectiveRecord = {} />

        <cfloop array="#arguments.packageSummaries#" item="packageSummary">
            <cfif NOT structKeyExists(packageSummary.capabilities, arguments.capability)>
                <cfcontinue />
            </cfif>

            <cfloop array="#packageSummary.capabilities[arguments.capability].records#" item="record">
                <cfset effectiveRecord = duplicate(record) />
                <cfset effectiveRecord.package_name = packageSummary.name />
                <cfset recordsByName[effectiveRecord.name] = effectiveRecord />
            </cfloop>
        </cfloop>

        <cfreturn recordsByName />
    </cffunction>

    <cffunction name="overriddenPackageNames" access="private" returntype="array" output="false">
        <cfargument name="entries" type="array" required="true" />
        <cfset var names = [] />
        <cfset var i = 1 />

        <cfloop from="1" to="#arrayLen(arguments.entries) - 1#" index="i">
            <cfset arrayAppend(names, arguments.entries[i].package_name) />
        </cfloop>

        <cfreturn names />
    </cffunction>

    <cffunction name="classifyRoutePackage" access="private" returntype="string" output="false">
        <cfargument name="route" type="struct" required="true" />
        <cfset var componentPath = arguments.route.componentPath ?: arguments.route.mapping ?: "" />

        <cfif findNoCase("/shared/routes", componentPath)>
            <cfreturn "shared" />
        </cfif>
        <cfif findNoCase("/moopa/routes", componentPath)>
            <cfreturn "moopa" />
        </cfif>
        <cfif findNoCase("/apps/", componentPath)>
            <cfreturn "app" />
        </cfif>

        <cfreturn "unknown" />
    </cffunction>

</cfcomponent>
