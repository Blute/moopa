<cfcomponent displayname="Application" output="true" hint="Handle the application.">



    <cfset THIS.datasource = 'project' />

    <cfset this.tag.cflocation.addtoken = false />


    <!--- S3 --->
    <cfset this.s3.accesskeyid = server.system.environment.S3_accesskeyid />
    <cfset this.s3.awssecretkey = server.system.environment.S3_awssecretkey />
    <!--- <cfset this.s3.host = server.system.environment.S3_host /> --->






	<cffunction name="OnApplicationStart" access="public" returntype="boolean" output="true" hint="Fires when the application is first created.">


        <!--- LET THE TEMPLATE KNOW WE HAVE INITIALIZE IN CASE WE WANT TO ALERT THE USER --->
        <cfset request.application_initialized = true />

        <cfset application.lib = {} />
        <cfset application.path = {} />
        <cfset application.path.project =  expandPath('/project') />


        <cfset _setupLibs() />
        <cfset _setupControls() />
        <cfset _setupServices() />
        <!--- <cfset application.lib.db.getService("moo_route").initializeRoutesIntoApplicationScope() /> --->

        <cfset application.service.moo_route.initializeRoutesIntoApplicationScope() />

        <cfset _setupNavs() />



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


        <cfif !structKeyExists(cookie, "s3p_token")>
            <!--- Calculate explicit expiration date --->
            <cfset expire_date = dateAdd("d", 30, now()) />
            <cfset token_value = createUUID() />

            <!--- Set cookie manually with cfheader to bypass setdomaincookies=false restriction --->
            <cfset cookie_expires = dateFormat(expire_date, "ddd, dd-mmm-yyyy") & " " & timeFormat(expire_date, "HH:mm:ss") & " GMT" />
            <cfheader name="Set-Cookie" value="s3p_token=#token_value#; Domain=.blute.com.au; Expires=#cookie_expires#; Path=/; SameSite=None; Secure" />
        </cfif>



        <cfif (application.about_to_initialize?:false)>
            <cflocation url="/restarting/index.html?redirect=#url.route?:'/'#" />
        </cfif>

		<!--- Return out. --->
		<cfreturn bReturn />

	</cffunction>


	<cffunction name="OnRequest" access="public" returntype="void" output="true" hint="Fires after pre page processing is complete.">

        <cfargument name="TargetPage" type="string" required="true" />

        <!--- DETERMINE IF WE ARE IN THE MOOPA FRAMEWORK. This is the result of the nginx rewrite rule --->
        <cfif arguments.TargetPage EQ "/_moopa.cfm">
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



    <cffunction name="_moopa" access="private" returntype="void" output="true" hint="THIS IS THE MOOPA FRAMEWORK">

        <cfif ( url.keyExists( "init" ) )>
            <cftry>

                <cfset application.about_to_initialize = true />

                <!--- Give other requests 1 second to finish processing on production --->
                <cfif (server.system.environment.IS_PRODUCTION?:false)>
                    <cfset delay_init = 1000 />

                    <cfsleep time="#delay_init#" />
                </cfif>

                <cfset applicationStop() />

                <cfcatch>
                    <!--- IGNORE. Someone else got here --->
                </cfcatch>
            </cftry>
            <cflocation url = '#url.route#' />

        </cfif>


        <cfif !structKeyExists(application, "lib")>
            <h1>Application not initialized correctly</h1>
            <cfset applicationStop() /><cfabort>
            <!--- NOT INITIALIZED CORRECTLY --->
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
                    <cfset application.lib.db.getService("moo_profile").login(profile_id="#qCheckDevice.profile_id#", auto_login=true) />

                <cfelse>
                    <cfquery name="qCleanupExtendedSession">
                    DELETE FROM moo_profile_extended_session
                    WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#cookie.deviceid#" />
                    </cfquery>
                    <cfcookie name="deviceid" value="" expires="0" httponly="true" secure="true" samesite="Lax">

                </cfif>
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




    <cffunction name="_get500" access="private" returntype="void" output="true">

		<cfargument name="Exception" type="any" required="true" />
		<cfargument name="EventName" type="string" required="false" default="" />



        <cfset error_line = "From: Unknown Line" />
        <cfif arrayLen(arguments.Exception.tagContext?:[])>
            <cfset error_line = "#replaceNoCase(arguments.Exception.tagContext[1].template,"/var/www","")#:#arguments.Exception.tagContext[1].line#" />
        </cfif>


        <cfthread Exception="#arguments.Exception#" error_line="#error_line#">


            <cfset new_error_log = application.lib.db.save(
                    table_name = "moo_error_log",
                    data = {
                        message = "#arguments.Exception.message#",
                        line = "#error_line#",
                        tag = "500 Error",
                        exception = "#serializeJSON(arguments.Exception)#",
                        current_auth = "#serializeJSON(session.auth?:{})#",
                        cgi_scope = "#serializeJSON(cgi?:{})#",
                        form_scope = "#serializeJSON(form?:{})#",
                        request_scope = "#serializeJSON(request?:{})#",
                        url_scope = "#serializeJSON(url?:{})#",
                        session_scope = "#serializeJSON(session?:{})#"
                    },
                    returnAsCFML=true
                ) />

            <cfif (server.system.environment.IS_PRODUCTION?:false)>
                <cfset email_subject = "MOOPA FRAMEWORK 500 ERROR [#dateFormat(now(),'ddd dd-mmm-yyyy')#]"/>

                <cfsavecontent variable="email_body">
                    <cfoutput>
                    #error_line# <br>
                    #arguments.exception.message?:''# <br>
                    <a href="#server.system.environment.base_url#/moo_error_log">Error Log</a>
                    </cfoutput>
                </cfsavecontent>

                <cfset result = application.lib.postmark.sendEmail(
                    to="#server.system.environment.SYSADMIN_EMAIL#",
                    subject="#email_subject#",
                    htmlBody="#email_body#",
                    tag="500 Error"
                ) />
            </cfif>

        </cfthread>


        <cfif structKeyExists(getHttpRequestData().headers, "X-Fetch-Request") AND getHttpRequestData().headers["X-Fetch-Request"] EQ "true">


            <cfheader statuscode="500" statustext="Server Error">
            <cfcontent type="application/json" reset="true">


            <cfif !(server.system.environment.IS_PRODUCTION?:false) OR (url.debug?:'') EQ 9>
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
                    "error": "An error occurred. Administrators have been notififed"
                }
                </cfoutput>
            </cfif>

        <cfelse>


            <cfheader statuscode="500" statustext="Server Error">
            <cfcontent type="text/html" reset="true">


            <cf_layout_system>
                <h1 class="display-1 fw-bold">Whoops!</h1>



                <p class="h2 fw-normal mt-3 mb-4">Administrators have been notififed.</p>
                <p class="h2 fw-normal mt-3 mb-4">You could try again or wait for us to get in touch.</p>
                <div class="">
                    <a href="#url.route?:''#" class="btn btn-outline-primary btn-lg" id="try-again-button">Try Again</a>

                    <a href="/" class="btn btn-primary btn-lg" id="try-again-button">Return home</a>
                </div>

                <cfif !(server.system.environment.IS_PRODUCTION?:false) OR (url.debug?:'') EQ 9>
                    <hr>

                    <p class="h1">#arguments.exception.message?:''#.</p>
                    <hr>
                    <cfif arrayLen(arguments.exception.tagContext?:[])>
                        <cfloop array="#arguments.exception.tagContext#" item="item">
                            <h4 class="text-lg text-start">From: #item.template#:#item.line# </h4>
                        </cfloop>
                    </cfif>

                    <hr>


                    <cfdump var="#arguments.exception#" label="arguments.exception" expand="true">
                </cfif>
            </cf_layout_system>
        </cfif>
    </cffunction>



    <cffunction name="_setupLibs" access="private" returntype="void" output="true">


        <!--- lib.db first --->
        <cfset application.lib['db'] = CreateObject('component', "/moopa/lib/db").init() />



        <cfif len(server.system.environment.deploy_key?:'') AND len(url.deploy?:'') AND url.deploy EQ server.system.environment.deploy_key>
            <cfset local.statements = application.lib.db.compareDatabaseSchema(application.lib.db.codeSchema) />
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




        <!--- MOOPA LIBS --->
        <cfdirectory action="list" directory="/moopa/lib" recurse="true" name="qLibs" filter="*.cfc" />
        <cfloop query="qLibs">
            <cfset iName = listFirst(qLibs.name,'.') />
            <cfset application.lib['#iName#'] = CreateObject('component', "/moopa/lib/#iName#").init() />
        </cfloop>

        <!--- PROJECT LIBS --->
        <cfdirectory action="list" directory="/project/lib" recurse="true" name="qLibs" filter="*.cfc" />
        <cfloop query="qLibs">
            <cfset iName = listFirst(qLibs.name,'.') />
            <cfset application.lib['#iName#'] = CreateObject('component', "/project/lib/#iName#").init() />
        </cfloop>

    </cffunction>



    <cffunction name="_setupControls" access="private" returntype="void" output="true">

        <cfset application.control = {} />

        <!--- CORE TABLES --->
        <cfdirectory action="list" directory="/moopa/controls" recurse="true" name="qControls" filter="*.cfc" />
        <cfloop query="qControls">
            <cfset iName = listFirst(qControls.name,'.') />
            <cfset application.control['#iName#'] = CreateObject('component', "/moopa/controls/#iName#").init() />
        </cfloop>

        <!--- PROJECT TABLES --->
        <cfdirectory action="list" directory="/project/controls" recurse="true" name="qControls" filter="*.cfc" />
        <cfloop query="qControls">
            <cfset iName = listFirst(qControls.name,'.') />
            <cfset application.control['#iName#'] = CreateObject('component', "/project/controls/#iName#").init() />
        </cfloop>

    </cffunction>



    <cffunction name="_setupServices" access="private" returntype="void" output="true">

        <cfset application.service = {} />

        <!--- CORE TABLES --->
        <cfdirectory action="list" directory="/moopa/tables" recurse="true" name="qTables" filter="*.cfc" />
        <cfloop query="qTables">
            <cfset iName = listFirst(qTables.name,'.') />
            <cfset application.service['#iName#'] = CreateObject('component', "/moopa/tables/#iName#").init() />
        </cfloop>

        <!--- PROJECT TABLES --->
        <cfdirectory action="list" directory="/project/tables" recurse="true" name="qTables" filter="*.cfc" />
        <cfloop query="qTables">
            <cfset iName = listFirst(qTables.name,'.') />
            <cfset application.service['#iName#'] = CreateObject('component', "/project/tables/#iName#").init() />
        </cfloop>

    </cffunction>


    <cffunction name="_setupNavs" access="private" returntype="void" output="true">

        <!--- Initialize the application.navs structure --->
        <cfset application.navs = {} />
        <cfset application.nav_id = createUUID() />


        <!--- Get all JSON files in the navs directory --->
        <cfdirectory action="list" directory="/moopa/navs" filter="*.json" name="qNavFiles" />

        <!--- Loop through each JSON file and add it to application.navs --->
        <cfloop query="qNavFiles">
            <cfset var fileName = listFirst(qNavFiles.name, ".") />
            <cfset var filePath = "/moopa/navs/#qNavFiles.name#" />

            <cffile action="read" file="#filePath#" variable="jsonContent" />

            <cfif !isJSON(jsonContent)>
                <cfthrow message="Error parsing JSON file #qNavFiles.name#" />
            </cfif>

            <cfset application.navs[fileName] = deserializeJSON(jsonContent) />

        </cfloop>



        <!--- Get all JSON files in the navs directory --->
        <cfdirectory action="list" directory="/project/navs" filter="*.json" name="qNavFiles" />

        <!--- Loop through each JSON file and add it to application.navs --->
        <cfloop query="qNavFiles">
            <cfset var fileName = listFirst(qNavFiles.name, ".") />
            <cfset var filePath = "/project/navs/#qNavFiles.name#" />

            <cffile action="read" file="#filePath#" variable="jsonContent" />

            <cfif !isJSON(jsonContent)>
                <cfthrow message="Error parsing JSON file #qNavFiles.name#" />
            </cfif>

            <cfset application.navs[fileName] = deserializeJSON(jsonContent) />

        </cfloop>


    </cffunction>









</cfcomponent>
