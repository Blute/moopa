<cfcomponent displayName="access_policy" output="false" hint="Evaluates access for resolved Moopa routes and endpoints.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>


    <cffunction name="checkAccess" access="public" returntype="boolean" output="false">
        <cfargument name="route_data" required="true" />
        <cfargument name="endpoint" required="true" />
        <cfargument name="sysadmin_has_access" required="false" default="true" />

        <cfset var has_custom_access = false />
        <cfset var open_to = "" />
        <cfset var bearer_access = {} />
        <cfset var signature_access = false />
        <cfset var start_time = 0 />

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
            <cfquery name="local.qSecurityCheck">
            select *
            from moo_route_permission
            where moo_route_permission.route_id = <cfqueryparam cfsqltype="other" value="#arguments.route_data.stRoute.id#" />
            AND moo_route_permission.is_granted = true
            AND (
                moo_route_permission.endpoint_id = <cfqueryparam cfsqltype="other" value="#arguments.route_data.stRoute.endpoints[arguments.endpoint].id#" />
                OR moo_route_permission.endpoint_id is null
            )
            AND (
                moo_route_permission.profile_id = <cfqueryparam cfsqltype="other" value="#session.auth.profile.id#" />
                <cfif arrayLen(session.auth.role_id_array)>
                    OR moo_route_permission.role_id IN (<cfqueryparam cfsqltype="other" list=true value="#session.auth.role_id_array#" />)
                </cfif>
            )
            AND (
                moo_route_permission.role_id IN (
                    SELECT foreign_id
                    FROM moo_route_roles
                    WHERE primary_id = <cfqueryparam cfsqltype="other" value="#arguments.route_data.stRoute.id#" />
                )
                OR moo_route_permission.profile_id IN (
                    SELECT foreign_id
                    FROM moo_route_profiles
                    WHERE primary_id = <cfqueryparam cfsqltype="other" value="#arguments.route_data.stRoute.id#" />
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

        <cfif local.qSecurityCheck.recordcount>
            <cfreturn true />
        </cfif>
        <cfreturn false />
    </cffunction>


    <cffunction name="checkBearerToken" access="private" returntype="struct" output="false">
        <cfset var response = {} />
        <cfset var routeHeaders = GetHttpRequestData().headers />
        <cfset var authToken = "" />
        <cfset var token = "" />

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

</cfcomponent>
