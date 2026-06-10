<cfcomponent key="c67106f7-67f2-45d6-97f7-a0bc7fb0e126" open_to="security">

    <cffunction name="load">
        <cfreturn buildSummary() />
    </cffunction>

    <cffunction name="get">
        <cfset var summary = buildSummary() />

        <cf_layout_default>
            <cfoutput>
                <div class="flex flex-col gap-5">
                    <div class="flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
                        <div class="min-w-0">
                            <div class="flex items-center gap-3">
                                <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-box border border-base-300 bg-base-100 text-primary">
                                    <i class="fa-solid fa-gear text-base"></i>
                                </div>
                                <div class="min-w-0">
                                    <div class="flex flex-wrap items-baseline gap-x-2.5 gap-y-1">
                                        <h1 class="text-[1.625rem] font-semibold leading-none tracking-[-0.03em]">App Summary</h1>
                                        <span class="text-[0.6875rem] font-medium uppercase tracking-[0.11em] text-base-content/42">#htmlEditFormat(summary.app_name)# runtime</span>
                                    </div>
                                    <p class="mt-1 max-w-[68ch] text-sm leading-5 text-base-content/62">Everything Moopa loaded for this app at application start: packages, routes, table services, libraries, controls, navs, and tags.</p>
                                </div>
                            </div>
                        </div>
                        <a href="/sysadmin/app_summary/?X-Endpoint=load" class="btn btn-ghost btn-sm gap-2">
                            <i class="fa-solid fa-code text-sm"></i>
                            JSON
                        </a>
                    </div>

                    <div class="grid gap-3 md:grid-cols-2 xl:grid-cols-4">
                        <div class="rounded-lg border border-base-300 bg-base-100 p-4">
                            <div class="text-xs font-medium uppercase tracking-[0.11em] text-base-content/45">App</div>
                            <div class="mt-2 text-xl font-semibold tracking-[-0.03em]">#htmlEditFormat(summary.app_title)#</div>
                            <div class="mt-1 font-mono text-xs text-base-content/55">#htmlEditFormat(summary.app_base_url)#</div>
                        </div>
                        <div class="rounded-lg border border-base-300 bg-base-100 p-4">
                            <div class="text-xs font-medium uppercase tracking-[0.11em] text-base-content/45">Packages</div>
                            <div class="mt-2 text-xl font-semibold tracking-[-0.03em]">#arrayLen(summary.packages)#</div>
                            <div class="mt-1 text-xs text-base-content/55">Moopa → shared → active app</div>
                        </div>
                        <div class="rounded-lg border border-base-300 bg-base-100 p-4">
                            <div class="text-xs font-medium uppercase tracking-[0.11em] text-base-content/45">Routes</div>
                            <div class="mt-2 text-xl font-semibold tracking-[-0.03em]">#summary.totals.routes#</div>
                            <div class="mt-1 text-xs text-base-content/55">#summary.totals.static_routes# static · #summary.totals.dynamic_routes# dynamic · #summary.totals.route_endpoints# endpoints</div>
                        </div>
                        <div class="rounded-lg border border-base-300 bg-base-100 p-4">
                            <div class="text-xs font-medium uppercase tracking-[0.11em] text-base-content/45">Services</div>
                            <div class="mt-2 text-xl font-semibold tracking-[-0.03em]">#summary.totals.table_services#</div>
                            <div class="mt-1 text-xs text-base-content/55">#arrayLen(summary.table_overrides)# intentional table override(s)</div>
                        </div>
                    </div>

                    <div class="grid gap-5 xl:grid-cols-[minmax(0,1fr)_22rem]">
                        <div class="flex flex-col gap-5">
                            <section class="overflow-hidden rounded-lg border border-base-300 bg-base-100">
                                <div class="border-b border-base-300 px-4 py-3">
                                    <h2 class="font-semibold tracking-[-0.02em]">Loaded packages</h2>
                                </div>
                                <div class="overflow-x-auto">
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
                                                    <td class="font-medium">#htmlEditFormat(packageSummary.name)#</td>
                                                    <td><span class="badge badge-ghost badge-sm">#htmlEditFormat(packageSummary.kind)#</span></td>
                                                    <td class="font-mono text-xs text-base-content/60">#htmlEditFormat(packageSummary.path)#</td>
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

                            <section class="overflow-hidden rounded-lg border border-base-300 bg-base-100">
                                <div class="border-b border-base-300 px-4 py-3">
                                    <h2 class="font-semibold tracking-[-0.02em]">Route access mix</h2>
                                </div>
                                <div class="grid gap-3 p-4 sm:grid-cols-2 lg:grid-cols-4">
                                    <cfloop array="#summary.route_access_rows#" item="accessRow">
                                        <div class="rounded-box border border-base-300 bg-base-200/25 p-3">
                                            <div class="text-xs font-medium uppercase tracking-[0.11em] text-base-content/45">#htmlEditFormat(accessRow.name)#</div>
                                            <div class="mt-1 text-2xl font-semibold tracking-[-0.04em]">#accessRow.count#</div>
                                        </div>
                                    </cfloop>
                                </div>
                            </section>

                            <section class="overflow-hidden rounded-lg border border-base-300 bg-base-100">
                                <div class="border-b border-base-300 px-4 py-3">
                                    <h2 class="font-semibold tracking-[-0.02em]">Table definition overrides</h2>
                                </div>
                                <cfif arrayLen(summary.table_overrides)>
                                    <div class="overflow-x-auto">
                                        <table class="table table-sm">
                                            <thead>
                                                <tr>
                                                    <th>Table</th>
                                                    <th>Effective package</th>
                                                    <th>Overridden package(s)</th>
                                                </tr>
                                            </thead>
                                            <tbody>
                                                <cfloop array="#summary.table_overrides#" item="overrideRow">
                                                    <tr>
                                                        <td class="font-mono text-xs">#htmlEditFormat(overrideRow.name)#</td>
                                                        <td><span class="badge badge-primary badge-sm">#htmlEditFormat(overrideRow.effective_package)#</span></td>
                                                        <td class="text-xs text-base-content/65">#htmlEditFormat(arrayToList(overrideRow.overridden_packages, ", "))#</td>
                                                    </tr>
                                                </cfloop>
                                            </tbody>
                                        </table>
                                    </div>
                                <cfelse>
                                    <div class="p-4 text-sm text-base-content/62">No table definitions are overridden in this runtime.</div>
                                </cfif>
                            </section>
                        </div>

                        <aside class="flex flex-col gap-5">
                            <section class="rounded-lg border border-base-300 bg-base-100 p-4">
                                <h2 class="font-semibold tracking-[-0.02em]">Loaded scopes</h2>
                                <dl class="mt-3 grid grid-cols-2 gap-3 text-sm">
                                    <div><dt class="text-base-content/50">Table services</dt><dd class="font-semibold">#summary.totals.table_services#</dd></div>
                                    <div><dt class="text-base-content/50">Libraries</dt><dd class="font-semibold">#summary.totals.libraries#</dd></div>
                                    <div><dt class="text-base-content/50">Controls</dt><dd class="font-semibold">#summary.totals.controls#</dd></div>
                                    <div><dt class="text-base-content/50">Navs</dt><dd class="font-semibold">#summary.totals.navs#</dd></div>
                                </dl>
                            </section>

                            <section class="rounded-lg border border-base-300 bg-base-100 p-4">
                                <h2 class="font-semibold tracking-[-0.02em]">Nav files</h2>
                                <div class="mt-3 flex flex-wrap gap-2">
                                    <cfloop array="#summary.loaded.navs#" item="navName">
                                        <span class="badge badge-ghost badge-sm">#htmlEditFormat(navName)#</span>
                                    </cfloop>
                                    <cfif NOT arrayLen(summary.loaded.navs)>
                                        <span class="text-sm text-base-content/60">None</span>
                                    </cfif>
                                </div>
                            </section>

                            <section class="rounded-lg border border-base-300 bg-base-100 p-4">
                                <h2 class="font-semibold tracking-[-0.02em]">Libraries</h2>
                                <div class="mt-3 max-h-72 overflow-auto rounded-box border border-base-300 bg-base-200/25 p-3 font-mono text-xs leading-5 text-base-content/68">
                                    <cfloop array="#summary.loaded.libraries#" item="libName">#htmlEditFormat(libName)#<br></cfloop>
                                </div>
                            </section>
                        </aside>
                    </div>
                </div>
            </cfoutput>
        </cf_layout_default>
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
                <cfreturn sysadminRoutesEnabled() />
            </cfif>

            <cfreturn (listFindNoCase("app,shared", packageKind) GT 0) AND (packageKind NEQ "app" OR (arguments.package.app_name ?: arguments.package.name) EQ (application.app_name ?: "")) />
        </cfif>

        <cfif listFindNoCase("tables,controls,lib,tags", arguments.capability)>
            <cfreturn (listFindNoCase("core,shared,app", packageKind) GT 0) AND (packageKind NEQ "app" OR (arguments.package.app_name ?: arguments.package.name) EQ (application.app_name ?: "")) />
        </cfif>

        <cfreturn false />
    </cffunction>

    <cffunction name="sysadminRoutesEnabled" access="private" returntype="boolean" output="false">
        <cfset var enabled = trim(server.system.environment.MOOPA_ENABLE_SYSADMIN ?: "") />

        <cfreturn listFindNoCase("true,yes,1,on", enabled) GT 0 />
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
