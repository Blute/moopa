<cfcomponent displayName="device_session" hint="Owns the deviceid extended-session lifecycle: issue on login, resume on request, revoke on logout.">


    <cffunction name="init">
        <cfreturn this />
    </cffunction>


    <cffunction name="issue" hint="Mint a device row and cookie so the profile can auto-login after the in-memory session ends">
        <cfargument name="profile_id" required="true" />

        <cfset var device_id = createUUID() />
        <cfset var expiration = dateAdd("d", _sessionDays(), now()) />

        <cfset application.lib.db.save(
            table_name = "moo_profile_extended_session",
            data = {
                profile_id = "#arguments.profile_id#",
                device_id = "#device_id#",
                expiration = "#expiration#"
            },
            returnFormat = "cfml"
        ) />

        <cfset _writeCookie(device_id, expiration) />
    </cffunction>


    <cffunction name="resume" hint="Auto-login from the deviceid cookie when no session is active; safe to call on every request">

        <cfif application.lib.auth.isLoggedIn() OR NOT len(cookie.deviceid ?: '')>
            <cfreturn />
        </cfif>

        <cfquery name="local.qDevice">
        SELECT profile_id::text as profile_id,
               device_id,
               expiration
        FROM moo_profile_extended_session
        WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#cookie.deviceid#" />
        </cfquery>

        <cfif local.qDevice.recordcount NEQ 1>
            <cfreturn />
        </cfif>

        <cfif dateDiff('d', now(), local.qDevice.expiration) LT 0>
            <cfset revoke() />
            <cfreturn />
        </cfif>

        <cfset application.lib.db.getService("moo_profile").login(profile_id = local.qDevice.profile_id, auto_login = true) />

        <!--- Sliding renewal: without this, stay-logged-in is a hard cliff from the
              last INTERACTIVE login, so daily-active users still get dumped to the
              login screen when the original window closes. The token is deliberately
              NOT rotated: parallel requests from the same browser both auto-login,
              and rotating on the first would invalidate the second's cookie mid-flight. --->
        <cfset var renewed_expiration = dateAdd("d", _sessionDays(), now()) />
        <cfquery>
        UPDATE moo_profile_extended_session
        SET expiration = <cfqueryparam cfsqltype="timestamp" value="#renewed_expiration#" />
        WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#local.qDevice.device_id#" />
          AND profile_id = <cfqueryparam cfsqltype="other" value="#local.qDevice.profile_id#" />
        </cfquery>
        <cfset _writeCookie(local.qDevice.device_id, renewed_expiration) />
    </cffunction>


    <cffunction name="revoke" hint="Delete the device row and expire the cookie without ending the active session">

        <cfif NOT len(cookie.deviceid ?: '')>
            <cfreturn />
        </cfif>

        <cfquery>
        DELETE FROM moo_profile_extended_session
        WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#cookie.deviceid#" />
        </cfquery>

        <cfcookie name="deviceid" value="" expires="0" path="/" httponly="true" secure="true" samesite="Lax">
    </cffunction>


    <cffunction name="logout" hint="Revoke device persistence and end the active session">

        <cfset revoke() />
        <cfset structDelete(session, "auth") />

        <!--- The write-behind session flush is mutation-gated and skipped when the
              request ends in a cflocation redirect, so without a synchronous commit
              the cleared session may never reach the session store. --->
        <cfset sessionCommit() />
    </cffunction>


    <cffunction name="_sessionDays" access="private" returntype="numeric">
        <cfset var configured = trim(server.system.environment.DEVICE_SESSION_DAYS ?: "") />

        <cfif isNumeric(configured) AND configured GT 0>
            <cfreturn configured />
        </cfif>

        <cfreturn 30 />
    </cffunction>


    <cffunction name="_writeCookie" access="private">
        <cfargument name="device_id" required="true" />
        <cfargument name="expiration" required="true" />

        <!--- path="/" so auto-relogin sees deviceid on every route, not just the
              login directory (RustCFML defaults cfcookie path to the request
              directory, unlike Lucee). --->
        <cfcookie name="deviceid" value="#arguments.device_id#" path="/" expires="#arguments.expiration#" httponly="true" secure="true" samesite="Lax">
    </cffunction>


</cfcomponent>
