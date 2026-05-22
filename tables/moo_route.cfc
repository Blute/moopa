<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "title": "Route",
            "title_plural": "Routes",
            "searchable_fields": "url,app_name,mapping",
            "fields": {
                "key": {
                    "type"="uuid",
                    "index":true,
                    "html": {
                        "type": "input_text"
                    }
                },
                "url": {},
                "mapping": {},
                "app_name": {
                    "type": "varchar",
                    "nullable": false,
                    "html": {
                        "type": "text"
                    }
                },
                "is_secure_by_referrer": {"type": "bool", "default": false},


                "referrers": {
                  "type": "many_to_many",
                  "foreign_key_table": "moo_route",
                  "foreign_key_field": "id"
                },
                "profiles": {
                  "type": "many_to_many",
                  "foreign_key_table": "moo_profile",
                  "foreign_key_field": "id",
                  "foreign_key_onDelete" : "CASCADE"
                },
                "roles": {
                  "type": "many_to_many",
                  "foreign_key_table": "moo_role",
                  "foreign_key_field": "id"
                },
                "endpoints": {
                  "type": "relation",
                  "foreign_key_table": "moo_route_endpoint",
                  "foreign_key_field": "route_id"
                },
                "screenshot": {}
            },
            "indexes": {
                "idx_moo_route_key_app_name": {
                    "type": "btree",
                    "fields": "key,app_name",
                    "unique": true
                },
                "idx_moo_route_app_name_url": {
                    "type": "btree",
                    "fields": "app_name,url",
                    "unique": true
                }
            }
          }

        />

        <cfreturn this>
    </cffunction>


    <cffunction name="routeIdentity" access="private" returntype="string" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfargument name="app_name" type="string" required="true" />

        <cfif NOT len(trim(arguments.key))>
            <cfthrow message="Route identity requires a route key." />
        </cfif>
        <cfif NOT len(trim(arguments.app_name))>
            <cfthrow message="Route identity requires an app_name." />
        </cfif>

        <cfreturn "#lcase(trim(arguments.app_name))#:#lcase(trim(arguments.key))#" />
    </cffunction>

    <cffunction name="routeUrlIdentity" access="private" returntype="string" output="false">
        <cfargument name="url" type="string" required="true" />
        <cfargument name="app_name" type="string" required="true" />

        <cfif NOT len(trim(arguments.url))>
            <cfthrow message="Route URL identity requires a route URL." />
        </cfif>
        <cfif NOT len(trim(arguments.app_name))>
            <cfthrow message="Route URL identity requires an app_name." />
        </cfif>

        <cfreturn "#lcase(trim(arguments.app_name))#:#lcase(trim(arguments.url))#" />
    </cffunction>



    <cffunction name="initializeRoutesIntoApplicationScope">



        <cfset application.stDynamicRoutes = {} />
        <cfset application.stStaticRoutes = {} />
        <cfset application.stAllRoutes = {} />
        <cfset application.routes = {} />

        <cfset aCheckNoDuplicateKeys = [] />



        <!--- ------------------- --->
        <!--- GET EXISTING ROUTES --->
        <!--- ------------------- --->

        <cfset stDBRoutes = {} />
        <cfset stDBRoutesByAppUrl = {} />
        <cfset stLegacyDBRoutesByKey = {} />
        <cfset routePersistenceAvailable = true />

        <cftry>
            <cfquery name="qDBRoutes">
            SELECT COALESCE(jsonb_agg(data)::text, '[]') as data
            FROM (
                    SELECT id::text as id, key::text as key, url, mapping, app_name,
                    COALESCE((
                        SELECT json_agg(json_build_object('id', moo_route_endpoint.id::text, 'name', moo_route_endpoint.name))
                        FROM moo_route_endpoint
                        WHERE moo_route_endpoint.route_id = moo_route.id
                    ), '[]') AS endpoints
                    FROM moo_route
            ) as data
            </cfquery>

            <cfset aDBRoutes = deserializeJSON(qDBRoutes.data) />
            <cfcatch type="database">
                <!--- First-run/dev fallback: route tables may not exist until /sysadmin/schema has been applied. --->
                <cfset routePersistenceAvailable = false />
                <cfset aDBRoutes = [] />
            </cfcatch>
        </cftry>

        <cfloop array="#aDBRoutes#" item="route">
            <cfif len(route.app_name ?: "")>
                <cfset stDBRoutes[routeIdentity(route.key, route.app_name)] = route />
                <cfset stDBRoutesByAppUrl[routeUrlIdentity(route.url, route.app_name)] = route />
            <cfelse>
                <!--- Legacy rows created before routes were app-scoped. The active app can claim them on re-init. --->
                <cfset stLegacyDBRoutesByKey[route.key] = route />
            </cfif>
        </cfloop>




        <!--- ------------------ --->
        <!--- PROCESS ALL ROUTES --->
        <!--- ------------------ --->
        <cfset processed_route_urls = '' />
        <cfset routePackages = [] />

        <cfif NOT (isDefined("application.moopa_packages") AND isArray(application.moopa_packages))>
            <cfthrow message="Cannot initialize routes: application.moopa_packages is not initialized." />
        </cfif>

        <cfloop array="#application.moopa_packages#" item="local.package">
            <cfset local.packageKind = local.package.kind ?: "" />
            <cfif listFindNoCase("app,shared", local.packageKind)
                AND ((local.package.kind ?: "") NEQ "app" OR (local.package.app_name ?: local.package.name) EQ application.app_name)>
                <cfset arrayAppend(routePackages, local.package) />
            </cfif>
        </cfloop>

        <cfloop array="#routePackages#" item="routePackage">
            <cfset iPackage = routePackage.path />
            <cfset packagePath = expandPath(iPackage) />
            <cfset routePath = "#packagePath#/routes" />
            <cfset componentPath = "#iPackage#/routes" />
            <cfset routeMount = "" />

            <cfif NOT directoryExists(routePath)>
                <cfcontinue />
            </cfif>

            <cfdirectory action="list" directory="#routePath#" name="qRoutes" recurse="true" filter="*.cfc">


<!---
TODO: need to check if old way works for the following and which has precedence: the url of both routes is /test
/routes/test/index.cfc *** THIS HAS PRECEDENCE
/routes/test.cfc

 --->

            <cfloop query="qRoutes">
                <cfset stRoute = {} />
                <cfset stRoute.key = "" /> <!--- set shortly via component metadata --->
                <cfset stRoute.location = "#qRoutes.directory#/#qRoutes.name#" />
                <cfset stRoute.path = replaceNoCase(stRoute.location,".cfc",'') />
                <cfset stRoute.localUrl = replaceNoCase(stRoute.path,"#routePath#",'') />
                <cfset stRoute.url = reReplace("#routeMount##stRoute.localUrl#", "/+", "/", "all") />
                <cfset stRoute.componentPath = "#componentPath##stRoute.localUrl#" />
                <cfset stRoute.app_name = application.app_name />
                <cfset stRoute.docs = {} />
                <cfset stRoute.endpoints = {} />
                <cfset stRoute.md = duplicate(getMetaData(createObject("component", "#stRoute.componentPath#"))) />
                <cfset stRoute['open_to'] = stRoute.md['open_to']?:'security' /> <!--- public,bearer,logged_in,security --->

                <!--- Need to determine if the route is already defined --->

                <cfif !listFindNoCase(processed_route_urls, stRoute.url)>
                    <cfset processed_route_urls = listAppend(processed_route_urls, stRoute.url) />
                <cfelse>
                    <cfthrow message="Duplicate route URL '#stRoute.url#' loaded from #stRoute.componentPath#. Package boundaries require unique routes within an app runtime." />
                </cfif>

                <cfloop array="#stRoute.md.functions#" item="fn">
                    <cfset stRoute.endpoints[fn.name] = fn />
                    <cfset stRoute.endpoints[fn.name]['open_to'] = stRoute.endpoints[fn.name]['open_to']?:stRoute['open_to'] /> <!--- public,bearer,logged_in,security --->
                </cfloop>


                <cfif !len(stRoute.md.key?:'')>
                    <cfthrow message="No Key Defined for #stRoute.url#" />
                </cfif>


                <cfif ArrayFind(aCheckNoDuplicateKeys, stRoute.md.key)>
                    <cfthrow message="Key In Use. No duplicate keys allowed (#stRoute.md.key#)" />
                </cfif>

                <cfset arrayAppend(aCheckNoDuplicateKeys, stRoute.md.key) />

                <cfset stRoute.key = stRoute.md.key /> <!--- Told you --->
                <cfset stRoute.identity = routeIdentity(stRoute.key, stRoute.app_name) />

                <cfif routePersistenceAvailable
                    AND NOT structKeyExists(stDBRoutes, stRoute.identity)
                    AND structKeyExists(stLegacyDBRoutesByKey, stRoute.key)>
                    <!--- Claim a pre-app-scoped route row for this app to preserve local permissions during the refactor. --->
                    <cfset stDBRoutes[stRoute.identity] = stLegacyDBRoutesByKey[stRoute.key] />
                </cfif>

                <cfset stRoute.urlIdentity = routeUrlIdentity(stRoute.url, stRoute.app_name) />
                <cfif routePersistenceAvailable
                    AND NOT structKeyExists(stDBRoutes, stRoute.identity)
                    AND structKeyExists(stDBRoutesByAppUrl, stRoute.urlIdentity)>
                    <!--- The conventional source route is the same app URL with a new key. Claim the row by URL so re-inits update cleanly instead of violating idx_moo_route_app_name_url. --->
                    <cfset stDBRoutes[stRoute.identity] = stDBRoutesByAppUrl[stRoute.urlIdentity] />
                </cfif>


                <!--- ------------------------------------- --->
                <!--- SELF REGISTER IF NOT ALREADY EXISTING --->
                <!--- ------------------------------------- --->
                <cfif NOT routePersistenceAvailable>
                    <!--- First-run/dev fallback: keep routes in memory without writing moo_route rows. --->
                    <cfset stRoute.id = stRoute.key />
                    <cfloop collection="#stRoute.endpoints#" item="function_name">
                        <cfset stRoute.endpoints[function_name]['id'] = "#stRoute.key#:#function_name#" />
                    </cfloop>
                <cfelseif !structKeyExists(stDBRoutes, stRoute.identity)>
                    <cfset save_moo_route = application.lib.db.save(
                        table_name = "moo_route",
                        data = {
                            key="#stRoute.key#",
                            app_name="#stRoute.app_name#",
                            url="#stRoute.url#",
                            mapping="#stRoute.componentPath#"
                        },
                        returnFormat="cfml"
                    ) />


                    <cfset stRoute.id = save_moo_route.id />


                    <!--- ADD ALL THE ENDPOINTS THE THIS NEW ROUTE --->
                    <cfloop collection="#stRoute.endpoints#" item="function_name">

                        <cfset save_moo_route_endpoint = application.lib.db.save(
                            table_name = "moo_route_endpoint",
                            data = {
                                route_id="#stRoute.id#",
                                name="#function_name#"
                            },
                            returnFormat="cfml"
                        ) />


                        <cfset stRoute.endpoints[function_name]['id'] = save_moo_route_endpoint.id />

                    </cfloop>



                <cfelse>
                    <!--- JUST IN CASE IT HAS CHANGED OR BEEN RE-USED --->
                    <cfif stDBRoutes[stRoute.identity].url NEQ stRoute.url
                        OR stDBRoutes[stRoute.identity].mapping NEQ stRoute.componentPath
                        OR (stDBRoutes[stRoute.identity].app_name ?: "") NEQ stRoute.app_name>
                        <cfset save_moo_route = application.lib.db.save(
                            table_name = "moo_route",
                            data = {
                                id="#stDBRoutes[stRoute.identity].id#",
                                key="#stRoute.key#",
                                app_name="#stRoute.app_name#",
                                url="#stRoute.url#",
                                mapping="#stRoute.componentPath#"
                            },
                            returnFormat="cfml"
                        ) />
                    </cfif>


                    <cfset stRoute.id = stDBRoutes[stRoute.identity].id />


                    <!--- NOW WE CHECK TO MAKE SURE THE ENPOINTS ARE CORRENT. WE COMPARE THE stRoute with the stDBRoute --->



                    <cfloop collection="#stRoute.endpoints#" item="function_name">
                        <cfset endpoint_found = false />
                        <cfset endpoint_db_id = "" />
                        <cfloop array="#stDBRoutes[stRoute.identity].endpoints#" item="stEndpoint">
                            <cfif stEndpoint.name EQ function_name>
                                <cfset endpoint_found = true />
                                <cfset endpoint_db_id = stEndpoint.id />
                                <cfbreak />
                            </cfif>
                        </cfloop>

                        <cfif !endpoint_found>
                            <cfset save_moo_route_endpoint = application.lib.db.save(
                                table_name = "moo_route_endpoint",
                                data = {
                                    route_id="#stRoute.id#",
                                    name="#function_name#"
                                },
                                returnFormat="cfml"
                            ) />

                            <cfset endpoint_db_id = save_moo_route_endpoint.id />

                        </cfif>


                        <!--- update the endpoint ID --->
                        <cfset stRoute.endpoints[function_name]['id'] = endpoint_db_id />
                    </cfloop>


                </cfif>



                <cfif stRoute.url.reFind("\[\w+\]")>
                    <cfif structKeyExists(application.stDynamicRoutes, stRoute.md.key)>
                        <cfthrow message="Trying to process [#stRoute.path#] but a Route with the key [#stRoute.md.key#] already exists" />
                    </cfif>

                    <cfset route_string = stRoute.url />
                    <cfset route_string = replaceNoCase(route_string, "/index", "") />
                    <cfset route_string = replaceNoCase(route_string, ".cfc", "") />
                    <cfset route_parts = [] />
                    <cfset route_groups = [] />
                    <cfloop list="#route_string#" delimiters="/" item="iPart">
                        <cfif left(iPart,1) EQ "[" AND right(iPart,1) EQ "]">
                            <cfset arrayAppend(route_parts,'([0-9A-Za-z\s\-_]+)') />
                            <cfset arrayAppend(route_groups, mid(iPart,2,len(iPart)-2) )/>
                        <cfelse>
                            <cfset arrayAppend(route_parts,'#iPart#') />
                        </cfif>
                    </cfloop>
                    <cfset iPattern = route_parts.toList("\/") />
                    <cfset iPattern = "^\/#iPattern#$" />
                    <cfset stRoute.pattern = iPattern />
                    <cfset stRoute.parts = route_parts />
                    <cfset stRoute.groups = route_groups />
                    <cfset application.stDynamicRoutes[stRoute.key] = stRoute />
                <cfelse>

                    <cfif structKeyExists(application.stStaticRoutes, stRoute.md.key)>
                        <cfthrow message="Trying to process [#stRoute.path#] but a Route with the key [#stRoute.md.key#] already exists" />
                    </cfif>

                    <cfset application.stStaticRoutes[stRoute.key] = stRoute />
                </cfif>

                <!--- Setup route component in application.routes --->
                <cfset setupRouteComponentInApplication(stRoute) />

                <cfset application.stAllRoutes[stRoute.id] = stRoute />


            </cfloop>
        </cfloop>

        <cfif routePersistenceAvailable>
            <!---
                Routes are now app-scoped. Any remaining rows without app_name are
                stale legacy registry rows that were not claimed by this app's
                current route files, so they must be removed before app_name can
                be enforced as NOT NULL.
            --->
            <cfquery name="qDeleteLegacyUnscopedRoutes">
                DELETE FROM moo_route
                WHERE app_name IS NULL
                   OR btrim(app_name) = ''
            </cfquery>
        </cfif>

    </cffunction>



    <cffunction name="parseRoute">

        <cfargument name="route" hint="Usually from url.route" />

        <!--- Initialize the return struct --->
        <cfset result = {
            stRoute : {},
            params : {
                route : arguments.route
            }
        } />
        <!--- Set the route to parse from the attributes.route value --->
        <cfset routeToParse = trim(arguments.route) />

        <!--- Check if a route is provided, if not, abort and show an error message --->
        <cfif !len(routeToParse)>
            <cfabort showerror="MUST INCLUDE A route" />
        </cfif>

        <!--- Remove the trailing slash from the routeToParse, if present --->
        <cfif right(routeToParse,1) EQ "/">
            <cfset routeToParse = routeToParse.RemoveChars(len(routeToParse),1) />
        </cfif>






        <!--- Loop through the collection of static routes to find a match --->
        <cfloop collection="#application.stStaticRoutes#" item="static_key">
            <cfif application.stStaticRoutes[static_key]['url'] EQ "#routeToParse#" OR application.stStaticRoutes[static_key]['url'] EQ "#routeToParse#/index">
                <cfset result.stRoute = application.stStaticRoutes[static_key] />

                <cfbreak>
            </cfif>
        </cfloop>


        <!--- If no static route is found, proceed to search for a dynamic route --->
        <cfif structIsEmpty(result.stRoute)>
            <!--- Create a regex pattern object --->
            <cfset oRegex = createObject( "java", "java.util.regex.Pattern" ) />

            <!--- Loop through the collection of dynamic routes to find a match --->
            <cfloop collection="#application.stDynamicRoutes#" item="dynamic_key">

                <!--- Get the current dynamic route from the application scope --->
                <cfset current_route = application.stDynamicRoutes[dynamic_key] />

                <!--- Compile the regex pattern and match it against the routeToParse --->
                <cfset matcher = oRegex
                                    .compile( javaCast( "string", "#current_route.pattern#" ) )
                                    .matcher( javaCast( "string", '#routeToParse#' ) ) />

                <!--- If a match is found, proceed to process the groups and store the matched route --->
                <cfif matcher.find()>

                    <!--- Loop through the groups, and store the matched values in the URL scope --->
                    <cfloop array="#current_route.groups#" item="group" index="i">
                        <cfset result.params[group] = matcher.group( i ) />
                    </cfloop>

                    <!--- Store the matched dynamic route in the stRoute struct --->
                    <cfset result.stRoute = application.stDynamicRoutes[dynamic_key] />
                    <cfbreak>
                </cfif>

            </cfloop>

        </cfif>


        <cfreturn result />

    </cffunction>



    <cffunction name="extractDocumentationMetadata" access="private" returntype="struct" output="false">
        <cfargument name="filePath" type="string" required="true">

        <cfset var fileContent = "">
        <cfset var commentBlockStart = 0>
        <cfset var commentBlocks = []>
        <cfset var commentBlock = "">
        <cfset var lines = []>
        <cfset var metadata = {}>
        <cfset var currentKey = "">

        <!--- Read file content --->
        <cffile action="read" file="#arguments.filePath#" variable="fileContent">

        <!--- Find the position of the first comment block containing at least one metadata key (@@) --->
        <cfset commentBlockStart = reFind("<!-{3}([\w\W\s\S]*?@@[\w\W\s\S]*?)-{3}>", fileContent)>

        <!--- If a comment block is found, extract it using reMatch --->
        <cfif commentBlockStart gt 0>
            <cfset commentBlocks = reMatch("<!-{3}([\w\W\s\S]*?@@[\w\W\s\S]*?)-{3}>", fileContent)>
            <cfset commentBlock = commentBlocks[1]>
            <cfset commentBlock = reReplaceNoCase(commentBlock, "<!-{3}|-{3}>", "", "all")>
            <cfset lines = listToArray(commentBlock, chr(10))>

            <!--- Iterate over the lines and extract metadata keys and values --->
            <cfloop index="i" from="1" to="#arrayLen(lines)#">
                <cfset var line = trim(lines[i])>

                <cfif left(line, 2) eq "@@">
                    <cfset currentKey = trim(listFirst(line, ":"))>
                    <cfset currentKey = reReplaceNoCase(currentKey, "@@", "", "one")>
                    <cfset metadata[currentKey] = trim(listRest(line, ":"))>
                <cfelseif structKeyExists(metadata, currentKey) and currentKey neq "" and line neq "">
                    <cfset metadata[currentKey] &= " " & line>
                </cfif>
            </cfloop>
        </cfif>

        <cfreturn metadata>
    </cffunction>


    <cffunction name="checkBearerToken">

        <cfset routeHeaders = GetHttpRequestData().headers />

        <cfif !structKeyExists(routeHeaders, "authorization")>
            <cfset response.success = false>
            <cfset response.message = "Unauthorized: Missing authorization header.">
            <cfreturn response>
        </cfif>


        <cfset authToken = routeHeaders['authorization']>

        <!--- Check if the authorization header is present and valid --->
        <cfif NOT REFind("^Bearer\s+.+$", authToken)>
            <cfset response.success = false>
            <cfset response.message = "Unauthorized: Invalid authorization header.">
            <cfreturn response>
        </cfif>


        <!--- Validate the Bearer token (replace 'YourSecretTokenHere' with your actual token) --->
        <cfset token = ListLast(authToken, " ")>
        <cfif token NEQ server.system.environment.BEARER_TOKEN>
            <cfset response.success = false>
            <cfset response.message = "Forbidden: Invalid token.">
            <cfreturn response>
        </cfif>

        <cfset response.success = true>
        <cfset response.message = "Valid token.">
        <cfreturn response>
    </cffunction>

    <cffunction name="checkAccess">

        <cfargument name="route_data" />
        <cfargument name="endpoint" />
        <cfargument name="sysadmin_has_access" default=true />


        <!--- If we get this far and the endpoint is not available, we need to throw an error. Generally this would be caught by <cf_route> 404 page --->
        <cfif !structKeyExists(arguments.route_data.stRoute.endpoints, arguments.endpoint)>
            <cfthrow message="#arguments.endpoint# not available" />
        </cfif>



        <cfif structKeyExists(arguments.route_data.stRoute.endpoints, "checkAccess")>
            <cfset has_custom_access = CreateObject('component', "#arguments.route_data.stRoute.componentPath#").checkAccess(argumentCollection = arguments.route_data.params) />
            <cfif !has_custom_access>
                <cfreturn false />
            </cfif>
        </cfif>

        <cfset open_to  =   arguments.route_data.stRoute.endpoints[arguments.endpoint]['open_to'] ?:
                            arguments.route_data.stRoute.md.open_to ?:
                            'security' />

        <!--- Public routes are always accessible --->
        <cfif open_to EQ "public">
            <cfreturn true />
        </cfif>


        <!--- Bearer token check --->
        <cfif open_to EQ "bearer">
            <cfset bearer_access = checkBearerToken() />

            <cfif bearer_access.success>
                <cfreturn true />
            </cfif>
        </cfif>



        <!--- Must be logged in for remaining checks --->
        <cfif !application.lib.auth.isLoggedIn()>
            <cfreturn false />
        </cfif>


        <!--- Profiles are app-scoped. A profile from one app cannot access another app runtime. --->
        <cfif (session.auth.profile.app_name ?: '') NEQ (application.app_name ?: '')>
            <cfreturn false />
        </cfif>


        <!--- sysadmin bypass --->
        <cfif arguments.sysadmin_has_access AND application.lib.auth.isSysAdmin()>
            <cfreturn true />
        </cfif>


        <!--- Logged in only check --->
        <cfif open_to EQ 'logged_in'>
            <cfreturn true />
        </cfif>


        <!--- Customer check --->
        <cfif open_to EQ "validated" AND application.lib.auth.isValidated()>
            <cfreturn true />
        </cfif>





        <!--- if we have an x-signature header, this will override the access --->
        <cfif structKeyExists(GetHttpRequestData().headers, "x-signature") AND structKeyExists(GetHttpRequestData().headers, "x-signed-route")>
            <cfset signature_access = application.lib.auth.verifyEndpointSignature(route="#arguments.route_data.stRoute.url#", endpoint="#arguments.endpoint#", signature="#GetHttpRequestData().headers['x-signature']#", signed_route="#GetHttpRequestData().headers['x-signed-route']#") />

            <cfif signature_access>
                <cfreturn true />
            </cfif>
        </cfif>


        <!--- Regular security check --->

        <cftry>

            <cfset start_time = getTickCount()>
            <cfquery name="qSecurityCheck">
            select *
            from moo_route_permission
            where moo_route_permission.route_id = '#arguments.route_data.stRoute.id#'
            AND moo_route_permission.is_granted = true
            AND (
                moo_route_permission.endpoint_id = '#arguments.route_data.stRoute.endpoints[arguments.endpoint].id#'
                OR moo_route_permission.endpoint_id is null
            )
            AND (
                moo_route_permission.profile_id = '#session.auth.profile.id#'
                <cfif arrayLen(session.auth.role_id_array)>
                    OR moo_route_permission.role_id IN (<cfqueryparam cfsqltype="other" list=true value="#session.auth.role_id_array#" />)
                </cfif>
            )
            AND (
                moo_route_permission.role_id IN (
                    SELECT foreign_id
                    FROM moo_route_roles
                    WHERE primary_id = '#arguments.route_data.stRoute.id#'
                )
                OR moo_route_permission.profile_id IN (
                    SELECT foreign_id
                    FROM moo_route_profiles
                    WHERE primary_id = '#arguments.route_data.stRoute.id#'
                )
            )
            </cfquery>

            <!--- Only log security check in development environment --->
            <cfif (server.system.environment.APP_ENVIRONMENT?:'production') EQ "development">
                <cflog type="information" file="security_check"  text="Security check for route #arguments.route_data.stRoute.url# and endpoint #arguments.endpoint# took #getTickCount() - start_time#ms">
            </cfif>

            <cfcatch type="any">
                <cfcontent reset="true" />
                <cfdump var="#cfcatch#"><cfabort>
                <cfreturn false />
            </cfcatch>
        </cftry>

        <cfif qSecurityCheck.recordcount>
            <cfreturn true />
        </cfif>
        <cfreturn false />
    </cffunction>

    <!--- Get profiles by route access --->
    <cffunction name="getProfilesByRouteAccess" access="public" returntype="array" output="false">
        <cfargument name="route" type="string" required="false" default="" hint="The route path (e.g. '/po_reference/new_company')">
        <cfargument name="endpoint" type="string" required="false" default="" hint="The endpoint name (e.g. 'get')">
        <cfargument name="route_id" type="string" required="false" default="" hint="Alternative: direct route UUID">
        <cfargument name="endpoint_id" type="string" required="false" default="" hint="Alternative: direct endpoint UUID">
        <cfargument name="returnFormat" type="string" required="false" default="cfml">

        <cfif NOT listFindNoCase("json,cfml", arguments.returnFormat)>
            <cfthrow type="moopa.mooRoute.invalidReturnFormat" message="Invalid returnFormat '#arguments.returnFormat#'. Use 'json' or 'cfml'." />
        </cfif>

        <!--- Resolve route and endpoint IDs if path is provided --->
        <cfset var resolved_route_id = arguments.route_id>
        <cfset var resolved_endpoint_id = arguments.endpoint_id>

        <cfset var moo_route = application.lib.db.getService("moo_route") />
        <cfif len(arguments.route)>
            <cfset var route_data = moo_route.parseRoute(arguments.route)>
            <cfset resolved_route_id = route_data.stRoute.id>

            <cfif len(arguments.endpoint)>
                <cfif structKeyExists(route_data.stRoute.endpoints, arguments.endpoint)>
                    <cfset resolved_endpoint_id = route_data.stRoute.endpoints[arguments.endpoint].id>
                <cfelse>
                    <cfthrow message="Endpoint '#arguments.endpoint#' not found for route '#arguments.route#'">
                </cfif>
            </cfif>
        </cfif>

        <!--- Validate we have at least a route ID --->
        <cfif !len(resolved_route_id)>
            <cfthrow message="Either route path or route_id must be provided">
        </cfif>

        <cfquery name="qProfiles">
            SELECT COALESCE(jsonb_agg(DISTINCT profile_data)::text, '[]') as profiles
            FROM (
                SELECT #application.lib.db.select(
                    table_name="moo_profile",
                    field_list="id,full_name,email",
                    sql_type="expanded"
                )#
                FROM moo_profile
                WHERE (
                    /* Direct profile permissions */
                    moo_profile.id IN (
                        SELECT profile_id
                        FROM moo_route_permission
                        WHERE route_id = <cfqueryparam cfsqltype="other" value="#resolved_route_id#">
                        AND is_granted = true
                        <cfif len(resolved_endpoint_id)>
                            AND (
                                endpoint_id = <cfqueryparam cfsqltype="other" value="#resolved_endpoint_id#">
                                OR endpoint_id IS NULL
                            )
                        </cfif>
                    )
                    /* Role-based permissions */
                    OR moo_profile.id IN (
                        SELECT moo_profile_roles.primary_id
                        FROM moo_profile_roles
                        INNER JOIN moo_route_permission ON
                            moo_route_permission.role_id = moo_profile_roles.foreign_id
                        WHERE moo_route_permission.route_id = <cfqueryparam cfsqltype="other" value="#resolved_route_id#">
                        AND moo_route_permission.is_granted = true
                        <cfif len(resolved_endpoint_id)>
                            AND (
                                moo_route_permission.endpoint_id = <cfqueryparam cfsqltype="other" value="#resolved_endpoint_id#">
                                OR moo_route_permission.endpoint_id IS NULL
                            )
                        </cfif>
                    )
                )
                /* Route-specific access control */
                AND (
                    moo_profile.id IN (
                        SELECT foreign_id
                        FROM moo_route_profiles
                        WHERE primary_id = <cfqueryparam cfsqltype="other" value="#resolved_route_id#">
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM moo_profile_roles
                        WHERE moo_profile_roles.primary_id = moo_profile.id
                        AND moo_profile_roles.foreign_id IN (
                            SELECT foreign_id
                            FROM moo_route_roles
                            WHERE primary_id = <cfqueryparam cfsqltype="other" value="#resolved_route_id#">
                        )
                    )
                )
                #application.lib.db.orderby(table_name="moo_profile")#
            ) as profile_data
        </cfquery>

        <cfif lCase(trim(arguments.returnFormat)) EQ "cfml">
            <cfreturn deserializeJSON(qProfiles.profiles)>
        </cfif>

        <cfreturn qProfiles.profiles>
    </cffunction>



    <cffunction name="getConfiguredSysadminEmailList" access="private" returntype="string" output="false">
        <cfset var emails = "" />
        <cfset var email = "" />
        <cfloop list="#server.system.environment.SYSADMIN_EMAIL ?: ''#" item="email">
            <cfset email = lCase(trim(email)) />
            <cfif len(email)>
                <cfset emails = listAppend(emails, email) />
            </cfif>
        </cfloop>
        <cfif NOT len(emails)>
            <cfreturn "__moopa_no_configured_sysadmin_email__" />
        </cfif>
        <cfreturn emails />
    </cffunction>


    <cffunction name="getEffectiveAccessors" access="public" returntype="struct" output="false">
        <cfargument name="route" type="string" required="false" default="" />
        <cfargument name="endpoint" type="string" required="false" default="" />
        <cfargument name="route_id" type="string" required="false" default="" />
        <cfargument name="endpoint_id" type="string" required="false" default="" />

        <cfset var resolvedRouteId = arguments.route_id />
        <cfset var resolvedEndpointId = arguments.endpoint_id />
        <cfset var routeData = {} />
        <cfset var result = {} />

        <cfif len(arguments.route)>
            <cfset routeData = parseRoute(arguments.route) />
            <cfif structIsEmpty(routeData.stRoute ?: {})>
                <cfthrow type="moopa.route.notFound" message="Route '#arguments.route#' was not found." />
            </cfif>
            <cfset resolvedRouteId = routeData.stRoute.id />
            <cfif len(arguments.endpoint)>
                <cfif NOT structKeyExists(routeData.stRoute.endpoints, arguments.endpoint)>
                    <cfthrow type="moopa.route.endpointNotFound" message="Endpoint '#arguments.endpoint#' was not found for route '#arguments.route#'." />
                </cfif>
                <cfset resolvedEndpointId = routeData.stRoute.endpoints[arguments.endpoint].id />
            </cfif>
        </cfif>

        <cfif NOT len(resolvedRouteId)>
            <cfthrow type="moopa.route.missingRoute" message="A route or route_id is required." />
        </cfif>

        <cfquery name="qRoute" returntype="array">
            SELECT id::text, url, app_name
            FROM moo_route
            WHERE id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />
        </cfquery>
        <cfif NOT arrayLen(qRoute)>
            <cfthrow type="moopa.route.notFound" message="Route '#resolvedRouteId#' was not found." />
        </cfif>

        <cfquery name="qEndpoint" returntype="array">
            SELECT id::text, name
            FROM moo_route_endpoint
            WHERE route_id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />
            <cfif len(resolvedEndpointId)>
                AND id = <cfqueryparam cfsqltype="other" value="#resolvedEndpointId#" />
            <cfelseif len(arguments.endpoint)>
                AND name = <cfqueryparam cfsqltype="varchar" value="#arguments.endpoint#" />
            <cfelse>
                AND 1 = 0
            </cfif>
            LIMIT 1
        </cfquery>

        <cfif len(arguments.endpoint) AND NOT arrayLen(qEndpoint)>
            <cfthrow type="moopa.route.endpointNotFound" message="Endpoint '#arguments.endpoint#' was not found." />
        </cfif>
        <cfif arrayLen(qEndpoint) AND NOT len(resolvedEndpointId)>
            <cfset resolvedEndpointId = qEndpoint[1].id />
        </cfif>

        <cfquery name="qAccess">
            WITH direct_profiles AS (
                SELECT DISTINCT p.id, p.full_name, p.email, p.app_name, p.can_login
                FROM moo_route_permission rp
                INNER JOIN moo_profile p ON p.id = rp.profile_id
                WHERE rp.route_id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />
                  AND rp.is_granted = true
                  AND p.can_login = true
                  AND p.app_name = 'hub'
                  <cfif len(resolvedEndpointId)>
                    AND (rp.endpoint_id = <cfqueryparam cfsqltype="other" value="#resolvedEndpointId#" /> OR rp.endpoint_id IS NULL)
                  <cfelse>
                    AND rp.endpoint_id IS NULL
                  </cfif>
                  AND p.id IN (
                    SELECT foreign_id FROM moo_route_profiles WHERE primary_id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />
                  )
            ), role_profiles AS (
                SELECT DISTINCT r.id AS role_id, r.name AS role_name, p.id, p.full_name, p.email, p.app_name, p.can_login
                FROM moo_route_permission rp
                INNER JOIN moo_role r ON r.id = rp.role_id
                INNER JOIN moo_profile_roles pr ON pr.foreign_id = r.id
                INNER JOIN moo_profile p ON p.id = pr.primary_id
                WHERE rp.route_id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />
                  AND rp.is_granted = true
                  AND p.can_login = true
                  AND p.app_name = 'hub'
                  <cfif len(resolvedEndpointId)>
                    AND (rp.endpoint_id = <cfqueryparam cfsqltype="other" value="#resolvedEndpointId#" /> OR rp.endpoint_id IS NULL)
                  <cfelse>
                    AND rp.endpoint_id IS NULL
                  </cfif>
                  AND r.id IN (
                    SELECT foreign_id FROM moo_route_roles WHERE primary_id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />
                  )
            ), sysadmins AS (
                SELECT DISTINCT p.id, p.full_name, p.email, p.app_name, p.can_login
                FROM moo_profile p
                WHERE p.app_name = 'hub'
                  AND p.can_login = true
                  AND lower(p.email) IN (<cfqueryparam cfsqltype="varchar" value="#getConfiguredSysadminEmailList()#" list="true" />)
            ), effective AS (
                SELECT id, full_name, email, app_name, can_login, 'Direct grant' AS source FROM direct_profiles
                UNION ALL
                SELECT id, full_name, email, app_name, can_login, 'Role: ' || role_name AS source FROM role_profiles
                UNION ALL
                SELECT id, full_name, email, app_name, can_login, 'Sysadmin' AS source FROM sysadmins
            )
            SELECT row_to_json(payload)::text AS data
            FROM (
                SELECT
                    (SELECT row_to_json(r) FROM (SELECT id, url, app_name FROM moo_route WHERE id = <cfqueryparam cfsqltype="other" value="#resolvedRouteId#" />) r) AS route,
                    <cfif len(resolvedEndpointId)>
                    (SELECT COALESCE(row_to_json(e), '{}'::json) FROM (SELECT id, name FROM moo_route_endpoint WHERE id = <cfqueryparam cfsqltype="other" value="#resolvedEndpointId#" />) e) AS endpoint,
                    <cfelse>
                    '{}'::json AS endpoint,
                    </cfif>
                    COALESCE((SELECT json_agg(row_to_json(s) ORDER BY full_name) FROM sysadmins s), '[]'::json) AS sysadmins,
                    COALESCE((SELECT json_agg(row_to_json(d) ORDER BY full_name) FROM direct_profiles d), '[]'::json) AS direct_profiles,
                    COALESCE((
                        SELECT json_agg(row_to_json(role_data) ORDER BY name)
                        FROM (
                            SELECT role_id AS id, role_name AS name,
                                json_agg(json_build_object('id', id, 'full_name', full_name, 'email', email, 'app_name', app_name, 'can_login', can_login) ORDER BY full_name) AS profiles
                            FROM role_profiles
                            GROUP BY role_id, role_name
                        ) role_data
                    ), '[]'::json) AS roles,
                    COALESCE((
                        SELECT json_agg(row_to_json(effective_profile) ORDER BY full_name)
                        FROM (
                            SELECT id, full_name, email, app_name, can_login, json_agg(DISTINCT source ORDER BY source) AS sources
                            FROM effective
                            GROUP BY id, full_name, email, app_name, can_login
                        ) effective_profile
                    ), '[]'::json) AS effective_profiles
            ) payload
        </cfquery>

        <cfreturn deserializeJSON(qAccess.data) />
    </cffunction>


    <cffunction name="renderMoopaPage" output="true">
        <!--- MOOPA PAGE JS --->

        <script>
            document.addEventListener("alpine:init", () => {
                Alpine.data("moopa_page", () => ({
                    isFileUploading: false,
                    moo_iframe_modal_src: '',
                    moo_iframe_modal_show: false,

                    moo_iframe_modal_open(src) {
                        console.log("moo_iframe_modal_open");
                        this.moo_iframe_modal_show = true;
                        this.moo_iframe_modal_src = src;
                    },
                    moo_iframe_modal_close() {
                        console.log("moo_iframe_modal_close");
                        this.moo_iframe_modal_show = false;
                    },
                    moo_iframe_modal_close_this() {
                        console.log("moo_iframe_modal_close_this");
                        // this will close the modal from the parent window from within the iframe
                        window.parent.dispatchEvent(new CustomEvent('moo_iframe_modal_close'));
                    },


                }))
            })
            </script>
    </cffunction>

    <cffunction name="renderSecurityModal" output="true">

        <cfif application.lib.auth.isSysAdmin() OR application.lib.auth.hasARole("Hub Admin")>
            <style>
             .security-icon {
                 position: fixed;
                 bottom: 2px; /* Adjust based on desired spacing from the bottom */
                 right: 5px; /* Adjust based on desired spacing from the right */
                 cursor: pointer;
                 z-index: 1100; /* Ensure it floats above other content, including modals */
             }
             </style>

            <div class="security-icon" @click="moo_iframe_modal_open('/sysadmin/routes/#request.route_id#')">
                <i class="fa-solid fa-key"></i>
            </div>


         </cfif>
    </cffunction>


    <!--- --------------------------------------------------------------------------------------------------
        This function is used to setup the route components in the application scope.
        This has to be complicated because we need to handle the fact that routes can be defined in the routes.cfc file in a few different ways
        and we need to make sure we do not overwrite existing routes under the same path.
    -------------------------------------------------------------------------------------------------- --->
    <cffunction name="setupRouteComponentInApplication">
        <cfargument name="stRoute" required="true" />

        <cfset local.routeStructPath = rereplace(arguments.stRoute.url, "^\\/|\\/index$", "", "all") />
        <cfset local.routeStructPathParts = listToArray(local.routeStructPath, "/") />

        <cfset local.currentStruct = application.routes />
        <cfset local.finalKey = "" />
        <cfset local.isIndexRoute = (right(arguments.stRoute.url, 6) EQ "/index" OR arguments.stRoute.url EQ "/index" OR arguments.stRoute.url EQ "") />

        <cfloop index="local.i" from="1" to="#arrayLen(local.routeStructPathParts)#">
            <cfset local.pathPart = local.routeStructPathParts[local.i] />
            <cfset local.structKey = rereplace(local.pathPart, "\[|\]", "", "all") /> <!--- Remove brackets --->

            <cfif len(local.structKey)>
                <cfif local.i EQ arrayLen(local.routeStructPathParts)> <!--- Last part --->
                    <cfset local.finalKey = local.structKey />
                <cfelse>
                    <!--- Ensure intermediate path exists and is a struct --->
                    <cfif !structKeyExists(local.currentStruct, local.structKey) OR !isStruct(local.currentStruct[local.structKey])>
                        <!--- If it exists but isn't a struct (likely overwritten by an index route processed earlier), force it back to a struct --->
                        <cfset local.currentStruct[local.structKey] = {} />
                    </cfif>
                    <cfset local.currentStruct = local.currentStruct[local.structKey] />
                </cfif>
            </cfif>
        </cfloop>

        <!--- Instantiate the component --->
        <cfset local.componentInstance = CreateObject('component', "#arguments.stRoute.componentPath#") />

        <!--- Handle assignment --->
        <cfif len(local.finalKey)> <!--- Not the root route --->
            <cfif local.isIndexRoute>
                <!--- Assign index component. Check if target key exists and is a struct (created by children) --->
                <cfif structKeyExists(local.currentStruct, local.finalKey) AND isStruct(local.currentStruct[local.finalKey])>
                     <!--- Assign to _index to avoid overwriting --->
                     <cfset local.currentStruct[local.finalKey]['_index'] = local.componentInstance />
                <cfelse>
                     <!--- Target doesn't exist or isn't a struct, assign directly --->
                     <cfset local.currentStruct[local.finalKey] = local.componentInstance />
                </cfif>
            <cfelse>
                 <!--- Not an index route, assign directly. Check for conflicts. --->
                 <cfif structKeyExists(local.currentStruct, local.finalKey) AND isStruct(local.currentStruct[local.finalKey])>
                      <cfthrow message="Routing conflict: Component '#arguments.stRoute.componentPath#' conflicts with existing structure at '#local.finalKey#'" />
                     <!--- Decide how to handle: throw error, log, or ignore? For now, log error. --->
                      <!--- Potentially assign to a different key? Or maybe this indicates a route definition error --->
                 <cfelse>
                      <cfset local.currentStruct[local.finalKey] = local.componentInstance />
                 </cfif>
            </cfif>
        <cfelseif local.isIndexRoute> <!--- Must be the root index route --->
             <!--- Check if root index already exists as struct (unlikely but possible) --->
             <cfif structKeyExists(application.routes, 'index') AND isStruct(application.routes['index'])>
                  <cfset application.routes['index']['_index'] = local.componentInstance />
             <cfelse>
                 <cfset application.routes['index'] = local.componentInstance />
             </cfif>
        </cfif>
    </cffunction>

</cfcomponent>
