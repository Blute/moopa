<cfcomponent displayname="login_grant" output="false"
    hint="Single-use, short-lived grants that sign a browser in as a profile (table moo_login_grant). One issue path and one consume path for every kind of grant. Callers decide who may get a grant of their kind and what happens around the sign-in; this owns the token, its lifetime, the table's invariant and the session switch.">

    <cfset variables.IMPERSONATION = "impersonation" />
    <cfset variables.TTL_MINUTES = 5 />

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>


    <cffunction name="issue" access="public" returntype="struct" output="false"
        hint="Record a new grant and return { token, expires_at }. The token is URL-safe and comes from a secure random source.">
        <cfargument name="kind" type="string" required="true" hint="'impersonation', or one of the project's own kinds (a lower-case slug)." />
        <cfargument name="target_profile_id" type="string" required="true" />
        <cfargument name="impersonator_profile_id" type="string" required="false" default=""
                    hint="Who is impersonating: required for an impersonation grant, not allowed for any other kind." />

        <cfset assertKind(arguments.kind) />
        <cfif (arguments.kind EQ variables.IMPERSONATION) NEQ (len(arguments.impersonator_profile_id) GT 0)>
            <cfthrow type="loginGrant.invalid"
                message="An impersonator_profile_id is required for an impersonation grant and not allowed for a #arguments.kind# grant." />
        </cfif>

        <cfset var token = application.lib.core.generateSecureToken(32) />
        <cfset var expiresAt = dateAdd("n", variables.TTL_MINUTES, now()) />
        <cfset var data = {
            kind = arguments.kind,
            token = token,
            target_profile_id = arguments.target_profile_id,
            expires_at = expiresAt,
            request_ip = cgi.remote_addr ?: ""
        } />
        <cfif len(arguments.impersonator_profile_id)>
            <cfset data.impersonator_profile_id = arguments.impersonator_profile_id />
        </cfif>

        <cfset application.lib.db.save(table_name = "moo_login_grant", data = data) />

        <cfreturn { token = token, expires_at = expiresAt } />
    </cffunction>


    <cffunction name="consume" access="public" returntype="struct" output="false"
        hint="Use a grant of this kind and sign the browser in as its target. Throws loginGrant.unusable unless the token is of this kind, unused and unexpired. Returns { target_profile_id, impersonator_profile_id, app_name, auth_type } with app_name and auth_type the target's.">
        <cfargument name="token" type="string" required="true" />
        <cfargument name="kind" type="string" required="true" />

        <cfset assertKind(arguments.kind) />

        <!--- Atomic: only one request can use a grant, and only while it's live --->
        <cfquery name="local.qConsume" returntype="array">
        UPDATE moo_login_grant
        SET consumed_at = now(),
            consume_ip = <cfqueryparam cfsqltype="varchar" value="#cgi.remote_addr ?: ''#" />,
            user_agent = <cfqueryparam cfsqltype="varchar" value="#left(cgi.http_user_agent ?: '', 500)#" />
        WHERE token = <cfqueryparam cfsqltype="varchar" value="#arguments.token#" />
          AND kind = <cfqueryparam cfsqltype="varchar" value="#arguments.kind#" />
          AND consumed_at IS NULL
          AND expires_at > now()
        RETURNING target_profile_id::text, COALESCE(impersonator_profile_id::text, '') AS impersonator_profile_id
        </cfquery>

        <cfif NOT arrayLen(local.qConsume)>
            <cfthrow type="loginGrant.unusable" message="This sign-in link is invalid, expired, or already used." />
        </cfif>

        <cfset var grant = local.qConsume[1] />

        <cfset var target = application.lib.db.read(
            table_name = "moo_profile",
            id = grant.target_profile_id,
            field_list = "id,app_name,auth_type",
            returnFormat = "cfml"
        ) />

        <!--- Sever any remember-me on this browser. Without this, the previous
              user's deviceid cookie survives and, when the granted session
              expires, auto-login silently switches the browser back to them
              mid-flow. A granted session ending (explicitly or by expiry) should
              land signed out. --->
        <cfif len(cookie.deviceid ?: '')>
            <cfquery>
            DELETE FROM moo_profile_extended_session
            WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#cookie.deviceid#" />
            </cfquery>
            <cfcookie name="deviceid" value="" path="/" expires="0" httponly="true" secure="true" samesite="Lax">
        </cfif>

        <!--- stay_logged_in=false: closing the browser (or private window) ends the session --->
        <cfset application.lib.db.getService("moo_profile").login(
            profile_id = grant.target_profile_id,
            stay_logged_in = false
        ) />

        <cfreturn {
            target_profile_id = grant.target_profile_id,
            impersonator_profile_id = grant.impersonator_profile_id,
            app_name = target.app_name ?: "",
            auth_type = target.auth_type
        } />
    </cffunction>


    <cffunction name="assertKind" access="private" returntype="void" output="false">
        <cfargument name="kind" type="string" required="true" />
        <cfif NOT reFind("^[a-z][a-z0-9_]*$", arguments.kind)>
            <cfthrow type="loginGrant.invalid" message="Login grant kind '#arguments.kind#' must be a lower-case slug, such as 'impersonation'." />
        </cfif>
    </cffunction>

</cfcomponent>
