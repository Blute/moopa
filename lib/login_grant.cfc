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

        <!--- Expiry comes from the database clock, the same clock consume() checks it against --->
        <cfquery name="local.qExpiry" returntype="array">
            SELECT now() + make_interval(mins => <cfqueryparam cfsqltype="integer" value="#variables.TTL_MINUTES#" />) AS expires_at
        </cfquery>
        <cfset var expiresAt = local.qExpiry[1].expires_at />
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
        hint="Use a grant of this kind and sign the browser in as its target. Throws loginGrant.unusable unless the token is of this kind, unused and unexpired. Returns { target_profile_id, impersonator_profile_id, app_name } with app_name the target's (empty when it has none).">
        <cfargument name="token" type="string" required="true" />
        <cfargument name="kind" type="string" required="true" />

        <cfset assertKind(arguments.kind) />

        <!--- Atomic: only one request can use a grant, and only while it's live. The
              target's app comes back from the same statement, so nothing is read after
              the grant is spent. --->
        <cfquery name="local.qConsume" returntype="array">
        UPDATE moo_login_grant
        SET consumed_at = now(),
            consume_ip = <cfqueryparam cfsqltype="varchar" value="#cgi.remote_addr ?: ''#" />,
            user_agent = <cfqueryparam cfsqltype="varchar" value="#left(cgi.http_user_agent ?: '', 500)#" />
        FROM moo_profile target
        WHERE target.id = moo_login_grant.target_profile_id
          AND moo_login_grant.token = <cfqueryparam cfsqltype="varchar" value="#arguments.token#" />
          AND moo_login_grant.kind = <cfqueryparam cfsqltype="varchar" value="#arguments.kind#" />
          AND moo_login_grant.consumed_at IS NULL
          AND moo_login_grant.expires_at > now()
        RETURNING moo_login_grant.target_profile_id::text AS target_profile_id,
                  COALESCE(moo_login_grant.impersonator_profile_id::text, '') AS impersonator_profile_id,
                  COALESCE(target.app_name, '') AS app_name
        </cfquery>

        <cfif NOT arrayLen(local.qConsume)>
            <cfthrow type="loginGrant.unusable" message="This sign-in link is invalid, expired, or already used." />
        </cfif>

        <cfset var grant = local.qConsume[1] />

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
            app_name = grant.app_name
        } />
    </cffunction>


    <cffunction name="assertKind" access="private" returntype="void" output="false">
        <cfargument name="kind" type="string" required="true" />
        <cfif NOT reFind("^[a-z][a-z0-9_]*$", arguments.kind)>
            <cfthrow type="loginGrant.invalid" message="Login grant kind '#arguments.kind#' must be a lower-case slug, such as 'impersonation'." />
        </cfif>
    </cffunction>

</cfcomponent>
