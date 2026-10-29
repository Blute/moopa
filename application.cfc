<cfcomponent displayname="Application" output="true" hint="Handle the application.">



    <cfset THIS.datasource = 'project' />

    <cfset this.tag.cflocation.addtoken = false />

    <!--- Sessions must be explicitly enabled (CFML spec default is false; Lucee
          installs often enable it admin-side, which masked this). RustCFML
          follows the spec default, so without this no session scope persists
          (memcached is never written) and logins never stick. --->
    <cfset this.sessionManagement = true />

    <cfset this.sessioncookie = {
        secure: true,
        httponly: true,
        samesite: "Lax"
    } />

    <!--- S3 --->
    <!--- TODO: REMOVE THIS BLOCK WHEN WE HAVE SWITCHED TO CLOUDFLARE R2 --->
    <!--- <cfset this.s3.accesskeyid = server.system.environment.S3_accesskeyid />
    <cfset this.s3.awssecretkey = server.system.environment.S3_awssecretkey /> --->

    
    <!--- <cfset this.s3.host = server.system.environment.S3_host /> --->






	<cffunction name="OnApplicationStart" access="public" returntype="boolean" output="true" hint="Fires when the application is first created.">


        <!--- LET THE TEMPLATE KNOW WE HAVE INITIALIZE IN CASE WE WANT TO ALERT THE USER --->
        <cfset request.application_initialized = true />

        <!---
            App resolution order:
            1. this.moopa_app_name - set by the project Application.cfc pseudo-constructor
               (runs every request), e.g. resolved from the request host. This lets one
               Lucee instance serve several apps, each with its own application scope,
               when this.name is derived from the same resolution.
            2. APP_NAME environment variable - the one-app-per-container default.
        --->
        <cfset application.app_name = trim(this.moopa_app_name ?: (server.system.environment.APP_NAME ?: "")) />
        <cfif NOT len(application.app_name)>
            <cfthrow message="APP_NAME is required. Set APP_NAME to the app directory name under code/apps/ (or set this.moopa_app_name in Application.cfc for host-resolved multi-app runtimes)." />
        </cfif>
        <!--- Hub always serves Moopa's own System routes and menu (/sysadmin) from the framework; no other app does, and no project may define them. --->
        <cfset application.system_routes = (application.app_name EQ "hub") />
        <cfset application.moopa_packages = _getMoopaPackages() />
        <cfset application.path = {} />
        <cfloop array="#application.moopa_packages#" item="local.package">
            <cfset application.path[local.package.name] = expandPath(local.package.path) />
        </cfloop>

        <cfset application.lib = {} />


        <cfset _setupLibs() />
        <cfset _setupControls() />
        <cfset _setupServices() />
        <!--- <cfset application.lib.db.getService("moo_route").initializeRoutesIntoApplicationScope() /> --->

        <cfset application.service.moo_route.initializeRoutesIntoApplicationScope() />

        <cfset _setupNavs() />
        <!--- The System menu: Moopa's own pages, shown to sysadmins after the app's navs, below a dividing line --->
        <cfset application.system_menu = application.system_routes ? deserializeJSON(fileRead(expandPath("/moopa/sysadmin_nav.json"))) : [] />



		<cfreturn true />

	</cffunction>



	<cffunction name="OnSessionStart" access="public" returntype="void" output="false" hint="Fires when the session is first created.">
		<!--- Call the main farcry Application.cfc --->

        <!--- Return out. --->
		<cfreturn />

	</cffunction>


	<cffunction name="OnRequestStart" access="public" returntype="boolean" output="true" hint="Fires at first part of page processing.">
		<cfargument name="TargetPage" type="string" required="true" />



		<cfset var bReturn = true />



        <cfif (application.about_to_initialize?:false)>
            <cflocation url="/restarting/index.html?redirect=#encodeForURL(_localPath(url.route ?: '/'))#" />
        </cfif>

		<!--- Return out. --->
		<cfreturn bReturn />

	</cffunction>


	<cffunction name="OnRequest" access="public" returntype="void" output="true" hint="Fires after pre page processing is complete.">

        <cfargument name="TargetPage" type="string" required="true" />

        <!--- No page at all: RustCFML running inline code from the web root (the image's start-up
              extension check, `rustcfml -c ...`). There is nothing to serve, and including an empty
              path would read this folder and log a 500 on every container start. --->
        <cfif NOT len(arguments.TargetPage)>
            <cfreturn />
        </cfif>

        <cfset local.targetPage = replace(arguments.TargetPage, "\", "/", "all") />

        <!--- DETERMINE IF WE ARE IN THE MOOPA FRAMEWORK. This is the result of the nginx rewrite rule --->
        <cfif local.targetPage EQ "/_moopa.cfm" OR local.targetPage EQ "/index.cfm" OR right(local.targetPage, 10) EQ "/index.cfm" OR right(local.targetPage, 11) EQ "/_moopa.cfm">
            <!--- A direct index.cfm entry (nginx directory index for "/") carries no ?route= param,
                  and bypassing the include of code/www/index.cfm skips the url.route it used to set --->
            <cfparam name="url.route" default="/" />
            <cfset _moopa() />
        <cfelse>
            <!--- OTHERWISE WE ARE OUTSIDE THE MOOPA FRAMEWORK --->
            <cfinclude template="#arguments.TargetPage#" />
        </cfif>

		<!--- Return out. --->
		<cfreturn />

	</cffunction>


	<cffunction name="OnRequestEnd" access="public" returntype="void" output="true" hint="Fires after the page processing is complete.">

		<!--- Return out. --->
		<cfreturn />

	</cffunction>


	<cffunction name="OnSessionEnd" access="public" returntype="void" output="false" hint="Fires when the session is terminated.">
		<cfargument name="SessionScope" type="struct" required="true" />
		<cfargument name="ApplicationScope" type="struct" required="false" default="#StructNew()#" />

		<!--- Return out. --->
		<cfreturn />

	</cffunction>


	<cffunction name="OnApplicationEnd" access="public" returntype="void" output="false" hint="Fires when the application is terminated.">
		<cfargument name="ApplicationScope" type="struct" required="false" default="#StructNew()#" />

		<!--- Return out. --->
		<cfreturn />

	</cffunction>


	<cffunction name="OnError" access="public" returntype="void" output="true" hint="Fires when an exception occures that is not caught by a try/catch.">
		<cfargument name="Exception" type="any" required="true" />
		<cfargument name="EventName" type="string" required="false" default="" />

        <cfset _get500(Exception,EventName) >

		<!--- Return out. --->
		<cfreturn />

	</cffunction>



    <!---
        RE-INITIALISING (?init). Restarting the application is allowed only in development (bare
        ?init, so local tooling keeps working), to a sysadmin signed in to this app, through req()
        (a POST carrying X-Fetch-Request, which a cross-site page cannot send), or to an operator
        POSTing the init key (PROJECT_INIT_KEY) in the X-Moopa-Init-Key header. The key is never
        read from the query string, which lands in access logs. Anything else is refused with 403.
    --->
    <cffunction name="_reinitialize" access="private" returntype="void" output="true" hint="Answers a ?init request: restarts the application when _reinitAllowed says so, else refuses with 403. A GET is answered with a redirect back to the page, a POST with JSON.">
        <cfset var isFetch = (getHttpRequestData().headers["X-Fetch-Request"] ?: "") EQ "true" />

        <cfif NOT _reinitAllowed()>
            <cfheader statuscode="403" statustext="Forbidden" />
            <cfheader name="Cache-Control" value="no-store" />
            <cfif isFetch>
                <cfcontent type="application/json" reset="true" />
                <cfoutput>#serializeJSON({ "success": false, "error": "Only a sysadmin can re-initialise the application.", "status": 403 })#</cfoutput>
            <cfelse>
                <cfcontent type="text/plain" reset="true" />
                <cfoutput>Re-initialising the application needs a sysadmin or the init key.</cfoutput>
            </cfif>
            <cfabort />
        </cfif>

        <!--- Requests arriving from here on are sent to /restarting/ (OnRequestStart) --->
        <cfset application.about_to_initialize = true />

        <cftry>
            <!--- Give other requests 1 second to finish processing on production --->
            <cfif (server.system.environment.APP_ENVIRONMENT ?: 'production') EQ 'production'>
                <cfsleep time="1000" />
            </cfif>

            <cfset applicationStop() />

            <cfcatch>
                <!--- The application is still running: stop sending requests to /restarting/ --->
                <cfset application.about_to_initialize = false />
                <cfrethrow />
            </cfcatch>
        </cftry>

        <cfif cgi.request_method EQ "POST">
            <cfheader name="Cache-Control" value="no-store" />
            <cfcontent type="application/json" reset="true" />
            <cfoutput>#serializeJSON({ "success": true })#</cfoutput>
            <cfabort />
        </cfif>

        <cflocation url="#_localPath(url.route ?: '/')#" addtoken="false" />
    </cffunction>


    <cffunction name="_reinitAllowed" access="private" returntype="boolean" output="false" hint="Whether this request may restart the application: always in development; otherwise only a POST, carrying the init key or made through req() by a sysadmin signed in to this app.">
        <cfset var headers = getHttpRequestData().headers />

        <cfif compare(server.system.environment.APP_ENVIRONMENT ?: "", "development") EQ 0>
            <cfreturn true />
        </cfif>

        <cfif cgi.request_method NEQ "POST">
            <cfreturn false />
        </cfif>

        <cfif len(headers["X-Moopa-Init-Key"] ?: "")>
            <cfreturn application.lib.core.isInitKey(headers["X-Moopa-Init-Key"]) />
        </cfif>

        <cfif (headers["X-Fetch-Request"] ?: "") NEQ "true">
            <cfreturn false />
        </cfif>

        <!--- The same session checks the route access policy makes before its sysadmin bypass --->
        <cfreturn application.lib.auth.isLoggedIn()
            AND (session.auth.profile.app_name ?: "") EQ application.app_name
            AND application.lib.auth.isSysAdmin() />
    </cffunction>


    <cffunction name="_showErrorDetail" access="private" returntype="boolean" output="false" hint="Whether an error's details (message, stack, exception) may be shown: only to a sysadmin signed in to this app, in every environment. False if the session can't be read, since the error may be the session's.">
        <cftry>
            <cfreturn application.lib.auth.isLoggedIn()
                AND (session.auth.profile.app_name ?: "") EQ application.app_name
                AND application.lib.auth.isSysAdmin() />
            <cfcatch>
                <cfreturn false />
            </cfcatch>
        </cftry>
    </cffunction>


    <cffunction name="_localPath" access="private" returntype="string" output="false" hint="The path when it is a path on this site (one leading slash, no backslashes or control characters), else /. Keeps redirects built from url.route on this site.">
        <cfargument name="path" type="string" required="true" />

        <cfif left(arguments.path, 1) NEQ "/"
                OR left(arguments.path, 2) EQ "//"
                OR find("\", arguments.path)
                OR reFind("[\x00-\x1F\x7F]", arguments.path)>
            <cfreturn "/" />
        </cfif>

        <cfreturn arguments.path />
    </cffunction>



    <cffunction name="_moopa" access="private" returntype="void" output="true" hint="THIS IS THE MOOPA FRAMEWORK">

        <!--- Moopa's own CSS, JS and fonts (static/), served before anything touches the session or the database --->
        <cfif left(url.route, 15) EQ "/_moopa/static/">
            <cfset _serveStatic(mid(url.route, 16, len(url.route))) />
            <cfreturn />
        </cfif>

        <cfif !structKeyExists(application, "lib")>
            <h1>Application not initialized correctly</h1>
            <cfset applicationStop() /><cfabort>
            <!--- NOT INITIALIZED CORRECTLY --->
        </cfif>


        <cfif url.keyExists("init")>
            <cfset _reinitialize() />
        </cfif>


        <!--- --------------------------------- --->
        <!--- LETS SEE IF WE NEED TO AUTO LOGIN --->
        <!--- --------------------------------- --->
        <cfif !application.lib.auth.isLoggedIn() AND (len(cookie.deviceid?:''))>

            <cfquery name="qCheckDevice">
            SELECT id::text as id,
            profile_id::text as profile_id,
            device_id,
            expiration
            FROM moo_profile_extended_session
            WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#cookie.deviceid#" />
            </cfquery>

            <cfif qCheckDevice.recordcount EQ 1>

                <cfif dateDiff('d', now(), qCheckDevice.expiration) GTE 0>
                    <!--- AUTO LOGIN --->
                    <cfset application.lib.db.getService("moo_profile").login(profile_id="#qCheckDevice.profile_id#", auto_login=true, device_id=qCheckDevice.device_id) />

                <cfelse>
                    <cfquery name="qCleanupExtendedSession">
                    DELETE FROM moo_profile_extended_session
                    WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#cookie.deviceid#" />
                    </cfquery>
                    <cfcookie name="deviceid" value="" expires="0" httponly="true" secure="true" samesite="Lax">

                </cfif>
            </cfif>
        </cfif>


        <!--- A session signed in before sessions knew their device: take the stay-signed-in cookie's device as its
              own, once, when that device is this person's --->
        <cfif application.lib.auth.isLoggedIn() AND NOT len(session.auth.device_id ?: "") AND len(cookie.deviceid ?: "")
              AND NOT (session.auth.device_adopted ?: false)>
            <cfset session.auth.device_adopted = true />
            <cfquery name="local.qOwnDevice" returntype="array">
                SELECT 1 AS present
                FROM moo_profile_extended_session
                WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#cookie.deviceid#" />
                  AND profile_id = <cfqueryparam cfsqltype="other" value="#session.auth.profile.id#" />
            </cfquery>
            <cfif arrayLen(local.qOwnDevice)>
                <cfset session.auth.device_id = cookie.deviceid />
            </cfif>
        </cfif>

        <!--- A device signed out from Sign-in activity (/account/signins) ends its session too: a signed-in
              session from a stay-signed-in device checks, at most once a minute, that the device is still there --->
        <cfif application.lib.auth.isLoggedIn() AND len(session.auth.device_id ?: "")
              AND dateDiff("s", session.auth.device_checked_at ?: createDateTime(2000, 1, 1, 0, 0, 0), now()) GTE 60>
            <cfquery name="local.qDevice" returntype="array">
                SELECT 1 AS present
                FROM moo_profile_extended_session
                WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#session.auth.device_id#" />
                  AND expiration > now()
            </cfquery>
            <cfif arrayLen(local.qDevice)>
                <cfset session.auth.device_checked_at = now() />
            <cfelse>
                <cfset structDelete(session, "auth") />
                <cfcookie name="deviceid" value="" path="/" expires="0" httponly="true" secure="true" samesite="Lax">
            </cfif>
        </cfif>


        <!---
        REQUEST['data']
        The Moopa Framework uses request['data'] instead of the form scope.

        The getHTTPRequestData().content method returns the raw HTTP request body as a string, regardless of the content type.
        This means that if the request is sent with a JSON payload or any other non-form format, the data will not be automatically parsed into the request['data'] variable.

        In ColdFusion, the form scope contains the parsed form data from a POST request with a Content-Type of application/x-www-form-urlencoded.
        If the request has a different content type, such as JSON, then the data will not be automatically parsed into the form scope and must be handled separately.

        That's why in the code provided, the request['data'] variable is used to store the request data, whether it's in the form format or in JSON format.
        The code first checks whether the request contains form data and, if not, it assumes that the request contains JSON data and attempts to deserialize it into a ColdFusion structure.
        --->

        <cfset httpRequestData = GetHttpRequestData() />

        <cfset request['data'] = {} />

        <cfif !structIsEmpty(form)>
            <cfset structAppend(request.data, form, true)>
        <cfelse>
            <cfset request_content = ToString(httpRequestData.content) />

            <cfif isJSON(request_content)>
                <cfset structAppend(request.data, deserializeJSON(request_content), true)>
            </cfif>
        </cfif>



        <!------------------------------------------------
        DETERMINE ROUTE STUFF
        -------------------------------------------------->
        <cfif structKeyExists(httpRequestData.headers, "X-Endpoint")>
            <cfset local.endpoint = httpRequestData.headers["X-Endpoint"] />
        <cfelseif structKeyExists(url, "X-Endpoint")>
            <cfset local.endpoint = url[ "X-Endpoint"] />
        <cfelse>
            <cfset local.endpoint = cgi.REQUEST_METHOD />
        </cfif>

        <!--- PROCESS THE ROUTE --->
        <cf_route route="#url.route#" endpoint="#local.endpoint#" returnContentVariable="routeContent" ignore_security=false />




        <!--- RETURN RESPONSE --->
        <cfcontent reset="true" />


        <cfif isJSON(routeContent)>
            <!---
            JSON
             --->
            <cfcontent type="application/json" reset="true">
            <cfoutput>#routeContent#</cfoutput>
        <cfelseif !IsSimpleValue(routeContent)>
            <!---
            ARRAY OR STRUCT
             --->
            <cfset routeContent = serializeJSON(routeContent) />

            <cfcontent type="application/json" reset="true">
            <cfoutput>#routeContent#</cfoutput>
        <cfelse>
            <!---
            PLAIN TEXT
             --->
            <cfcontent type="text/html" reset="true">
            <cfoutput>#trim(routeContent)#</cfoutput>
        </cfif>
    </cffunction>


    <cffunction name="_serveStatic" access="private" returntype="void" output="true" hint="Serves a file from Moopa's static/ folder at /_moopa/static/{path}: the System pages' stylesheet, script and vendored libraries. Versioned URLs (?v=, or a versioned vendor/ folder) are cached for a year.">
        <cfargument name="path" type="string" required="true" hint="The path under static/, e.g. moopa.css" />

        <cfset var types = {
            "css": "text/css; charset=utf-8",
            "js": "text/javascript; charset=utf-8",
            "woff2": "font/woff2",
            "svg": "image/svg+xml",
            "png": "image/png",
            "txt": "text/plain; charset=utf-8"
        } />
        <cfset var extension = lCase(listLast(arguments.path, ".")) />
        <cfset var file = expandPath("/moopa/static/") & arguments.path />

        <cfif NOT reFind("^[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*(/[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)*)*$", arguments.path)
            OR NOT structKeyExists(types, extension)
            OR NOT fileExists(file)>
            <cfheader statuscode="404" statustext="Not Found" />
            <cfheader name="Cache-Control" value="no-store" />
            <cfcontent type="text/plain" reset="true" />
            <cfoutput>Not found</cfoutput>
            <cfreturn />
        </cfif>

        <cfif len(url.v ?: "") OR left(arguments.path, 7) EQ "vendor/">
            <cfheader name="Cache-Control" value="public, max-age=31536000, immutable" />
        <cfelse>
            <cfheader name="Cache-Control" value="public, max-age=300" />
        </cfif>
        <cfheader name="X-Content-Type-Options" value="nosniff" />
        <cfcontent type="#types[extension]#" file="#file#" reset="true" />
    </cffunction>





    <cffunction name="_get500" access="private" returntype="void" output="true">

		<cfargument name="Exception" type="any" required="true" />
		<cfargument name="EventName" type="string" required="false" default="" />



        <cfset error_line = "From: Unknown Line" />
        <cfif arrayLen(arguments.Exception.tagContext?:[])>
            <cfset error_line = "#replaceNoCase(arguments.Exception.tagContext[1].template,"/var/www","")#:#arguments.Exception.tagContext[1].line#" />
        </cfif>


        <!--- Redacted auth, request data, url and session, gathered here on the request thread --->
        <cfset error_context = {} />
        <cfif structKeyExists(application, "lib") AND structKeyExists(application.lib, "core")>
            <cfset error_context = application.lib.core.errorLogContext() />
        </cfif>


        <!--- The thread body reads only its attributes: the arguments scope isn't visible inside cfthread on RustCFML --->
        <cfthread Exception="#arguments.Exception#" error_line="#error_line#" error_context="#error_context#">

            <cfset error_data = {
                message = "#attributes.Exception.message#",
                line = "#attributes.error_line#",
                tag = "500 Error",
                exception = "#serializeJSON(attributes.Exception)#"
            } />
            <cfset structAppend(error_data, attributes.error_context, true) />

            <cfset new_error_log = application.lib.db.save(
                    table_name = "moo_error_log",
                    data = error_data,
                    returnFormat="cfml"
                ) />

            <!--- Only send email in production environment --->
            <cfif (server.system.environment.APP_ENVIRONMENT?:'production') EQ 'production'>
                <cfset email_subject = "MOOPA FRAMEWORK 500 ERROR [#dateFormat(now(),'ddd dd-mmm-yyyy')#]"/>

                <cfsavecontent variable="email_body">
                    <cfoutput>
                    #attributes.error_line# <br>
                    #attributes.Exception.message?:''# <br>
                    <a href="#server.system.environment.base_url#/sysadmin/error_log">Error Log</a>
                    </cfoutput>
                </cfsavecontent>

                <cfset result = application.lib.core.sendFrameworkEmail(
                    to = server.system.environment.SYSADMIN_EMAIL,
                    subject = email_subject,
                    html = email_body,
                    tag = "500 Error"
                ) />
            </cfif>

        </cfthread>


        <cfif structKeyExists(getHttpRequestData().headers, "X-Fetch-Request") AND getHttpRequestData().headers["X-Fetch-Request"] EQ "true">


            <cfheader statuscode="500" statustext="Server Error">
            <cfcontent type="application/json" reset="true">


            <!--- The error's details only for a sysadmin signed in to this app; anyone else gets the plain message --->
            <cfif _showErrorDetail()>
                <cfset error_response = {
                    error: arguments.Exception.message,
                    line: error_line,
                    exception: arguments.Exception
                } />
                <cfoutput>
                    #serializeJSON(error_response)#
                </cfoutput>
            <cfelse>
                <cfoutput>
                {
                    "error": "An error occurred. It has been logged for the administrators."
                }
                </cfoutput>
            </cfif>

        <cfelse>


            <!--- Moopa's status page; for a sysadmin signed in to this app, the error's details under it --->
            <cfset local.errorRoute = url.route ?: "" />
            <cfif len(local.errorRoute) AND left(local.errorRoute, 1) NEQ "/"><cfset local.errorRoute = "/" & local.errorRoute /></cfif>
            <cfmodule template="/moopa/tags/moopa_status.cfm" code="500" route="#local.errorRoute#">
                <cfif _showErrorDetail()>
                    <div class="card">
                        <div class="card-header"><h2 class="card-title"><cfoutput>#encodeForHTML(arguments.exception.message?:'')#</cfoutput></h2></div>
                        <div class="card-body stack-sm">
                            <cfloop array="#arguments.exception.tagContext?:[]#" item="item">
                                <cfoutput><div><code class="code-inline">#encodeForHTML(item.template?:'')#:#encodeForHTML(item.line?:'')#</code></div></cfoutput>
                            </cfloop>
                            <div><cfdump var="#arguments.exception#" label="arguments.exception" expand="false"></div>
                        </div>
                    </div>
                </cfif>
            </cfmodule>
        </cfif>
    </cffunction>



    <cffunction name="_getMoopaPackages" access="private" returntype="array" output="false">
        <cfset var appPath = "/apps/#application.app_name#" />
        <cfset var physicalAppPath = expandPath(appPath) />

        <cfif NOT directoryExists(physicalAppPath)>
            <cfthrow message="APP_NAME '#application.app_name#' does not match an app directory at #appPath#." />
        </cfif>

        <cfreturn [
            { name: "moopa", path: "/moopa", kind: "core" },
            { name: "shared", path: "/shared", kind: "shared" },
            { name: application.app_name, path: appPath, kind: "app", app_name: application.app_name }
        ] />
    </cffunction>


    <cffunction name="_packageLoads" access="private" returntype="boolean" output="false">
        <cfargument name="package" type="struct" required="true" />
        <cfargument name="capability" type="string" required="true" />

        <cfset var packageKind = arguments.package.kind ?: "" />

        <cfif arguments.capability EQ "routes">
            <!--- Core routes are the System pages, which only Hub serves. --->
            <cfreturn listFindNoCase("shared,app", packageKind) GT 0 OR (packageKind EQ "core" AND application.system_routes) />
        </cfif>

        <cfif arguments.capability EQ "navs">
            <!--- Menus are the project's. The System menu is not a nav: it is sysadmin_nav.json, which a layout shows sysadmins below the app's menus. --->
            <cfreturn listFindNoCase("shared,app", packageKind) GT 0 />
        </cfif>

        <cfif listFindNoCase("tables,controls,lib", arguments.capability)>
            <!--- Framework, shared project, and active app tables/controls/libs are globally available. --->
            <cfreturn listFindNoCase("core,shared,app", packageKind) GT 0 />
        </cfif>

        <cfreturn false />
    </cffunction>


    <cffunction name="_packagePrecedence" access="private" returntype="numeric" output="false">
        <cfargument name="package" type="struct" required="true" />

        <cfset var packageKind = arguments.package.kind ?: "" />

        <cfif packageKind EQ "app">
            <cfreturn 30 />
        </cfif>

        <cfif packageKind EQ "shared">
            <cfreturn 20 />
        </cfif>

        <cfif packageKind EQ "core">
            <cfreturn 10 />
        </cfif>

        <cfreturn 0 />
    </cffunction>


    <cffunction name="_getPackagesFor" access="private" returntype="array" output="false">
        <cfargument name="capability" type="string" required="true" />

        <cfset var packages = [] />

        <cfloop array="#application.moopa_packages#" item="local.package">
            <cfif _packageLoads(local.package, arguments.capability)>
                <!--- App packages are mutually exclusive at runtime: APP_NAME chooses the active app. --->
                <cfif (local.package.kind ?: "") NEQ "app" OR (local.package.app_name ?: local.package.name) EQ application.app_name>
                    <cfset arrayAppend(packages, local.package) />
                </cfif>
            </cfif>
        </cfloop>

        <cfreturn packages />
    </cffunction>


    <cffunction name="_loadCfcDirectory" access="private" returntype="void" output="true">
        <cfargument name="target" type="struct" required="true" />
        <cfargument name="capability" type="string" required="true" />
        <cfargument name="label" type="string" required="true" />
        <cfargument name="skip" type="string" required="false" default="" />

        <cfloop array="#_getPackagesFor(arguments.capability)#" item="local.package">
            <cfset local.virtualDirectory = "#local.package.path#/#arguments.capability#" />
            <cfset local.physicalDirectory = expandPath(local.virtualDirectory) />

            <cfif NOT directoryExists(local.physicalDirectory)>
                <cfcontinue />
            </cfif>

            <cfdirectory action="list" directory="#local.physicalDirectory#" recurse="true" name="local.qComponents" filter="*.cfc" />
            <cfloop query="local.qComponents">
                <cfset local.componentName = listFirst(local.qComponents.name, ".") />
                <cfset local.relativeDirectory = replaceNoCase(local.qComponents.directory, local.physicalDirectory, "") />
                <cfset local.relativeDirectory = replace(local.relativeDirectory, "\", "/", "all") />
                <cfset local.componentPath = local.virtualDirectory & local.relativeDirectory & "/" & local.componentName />

                <cfif listFindNoCase(arguments.skip, local.componentName)>
                    <cfcontinue />
                </cfif>

                <cfif structKeyExists(arguments.target, local.componentName) AND arguments.capability NEQ "tables">
                    <cfthrow message="Duplicate #arguments.label# '#local.componentName#' loaded from #local.componentPath#. Package boundaries require unique component names." />
                </cfif>

                <cfset arguments.target[local.componentName] = CreateObject("component", local.componentPath).init() />
            </cfloop>
        </cfloop>
    </cffunction>


    <cffunction name="_setupLibs" access="private" returntype="void" output="true">

        <!--- lib.db first because later libs and services depend on the shared table metadata/runtime data API. --->
        <cfset application.lib["db"] = CreateObject("component", "/moopa/lib/db").init() />

        <cfset _loadCfcDirectory(application.lib, "lib", "library", "db") />

        <cfif len(server.system.environment.deploy_key?:"") AND len(url.deploy?:"") AND url.deploy EQ server.system.environment.deploy_key>
            <cfif (application.app_name ?: "") NEQ "hub" OR NOT structKeyExists(application.lib, "schemaSync")>
                <cfthrow type="moopa.schemaSync.unavailable" message="Schema deployment is only available from the Hub app." />
            </cfif>

            <cfset local.statements = application.lib.schemaSync.compareDatabaseSchema(application.lib.db.codeSchema) />
            <cfif arrayLen(local.statements)>
                <cfloop array="#local.statements#" item="local.statement">
                    <div>#local.statement.statement#;</div>
                </cfloop>
                <cfabort>
            <cfelse>
                <cfoutput>NOTHING TO DEPLOY</cfoutput>
                <cfabort>
            </cfif>
        </cfif>

    </cffunction>



    <cffunction name="_setupControls" access="private" returntype="void" output="true">

        <cfset application.control = {} />
        <cfset _loadCfcDirectory(application.control, "controls", "control") />

    </cffunction>



    <cffunction name="_setupServices" access="private" returntype="void" output="true">

        <cfset application.service = {} />
        <cfset _loadCfcDirectory(application.service, "tables", "table service") />

    </cffunction>


    <cffunction name="_setupNavs" access="private" returntype="void" output="true">

        <cfset var navs = {} />
        <cfset var navSources = {} />
        <cfset var navPrecedence = {} />
        <cfset application.nav_overrides = [] />

        <cfloop array="#_getPackagesFor('navs')#" item="local.package">
            <cfset local.packagePrecedence = _packagePrecedence(local.package) />
            <cfset local.virtualDirectory = "#local.package.path#/navs" />
            <cfset local.physicalDirectory = expandPath(local.virtualDirectory) />

            <cfif NOT directoryExists(local.physicalDirectory)>
                <cfcontinue />
            </cfif>

            <cfdirectory action="list" directory="#local.physicalDirectory#" filter="*.json" name="local.qNavFiles" />
            <cfloop query="local.qNavFiles">
                <cfset local.fileName = listFirst(local.qNavFiles.name, ".") />
                <cfset local.filePath = "#local.physicalDirectory#/#local.qNavFiles.name#" />

                <cfif local.fileName EQ "sysadmin" AND (local.package.kind ?: "") NEQ "core">
                    <cfthrow type="moopa.systemRoutes.reserved" message="The sysadmin menu is Moopa's: delete #local.filePath# (a copy of, or link to, Moopa's System menu). Moopa shows sysadmins its own System menu below the app's; put project admin pages in a menu of the project's own. See moopa/docs/packages.md." />
                </cfif>

                <cffile action="read" file="#local.filePath#" variable="local.jsonContent" />

                <cfif NOT isJSON(local.jsonContent)>
                    <cfthrow message="Error parsing JSON file #local.qNavFiles.name#" />
                </cfif>

                <cfif structKeyExists(navs, local.fileName)>
                    <cfif local.packagePrecedence EQ navPrecedence[local.fileName]>
                        <cfset local.duplicateNav = {
                            nav: local.fileName,
                            new_file: local.filePath,
                            existing_file: navSources[local.fileName],
                            package: local.package.name,
                            package_kind: local.package.kind,
                            row: local.qNavFiles.currentRow,
                            record_count: local.qNavFiles.recordCount
                        } />
                        <cfset local.duplicateNavMessage = serializeJSON(local.duplicateNav) />
                        <cfthrow message="#local.duplicateNavMessage#" />
                    </cfif>

                    <cfif local.packagePrecedence LT navPrecedence[local.fileName]>
                        <cfcontinue />
                    </cfif>

                    <cfset arrayAppend(application.nav_overrides, {
                        nav: local.fileName,
                        selected_file: local.filePath,
                        overridden_file: navSources[local.fileName]
                    }) />
                </cfif>

                <cfset navs[local.fileName] = deserializeJSON(local.jsonContent) />
                <cfset navSources[local.fileName] = local.filePath />
                <cfset navPrecedence[local.fileName] = local.packagePrecedence />
            </cfloop>
        </cfloop>

        <cfset application.navs = navs />
        <cfset application.nav_id = createUUID() />

    </cffunction>









</cfcomponent>
