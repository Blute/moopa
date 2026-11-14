<cfcomponent displayname="signin_device" output="false"
    hint="A stay-signed-in device: the moo_profile_extended_session row and the deviceid cookie that names it. Everything that makes, reads or removes either goes through here (application.lib.signin_device).">

    <!---
        Signing in with "stay signed in" gives the browser a device: a row holding a random id, the profile
        and an expiry, and a cookie holding that id. While the row is live (expiration > now(), by the
        database's clock) the cookie signs the browser back in whenever its session has gone, and an open
        session that came from the device is ended once the row is gone. A stay lasts STAY_DAYS from the
        sign-in that made it and is never extended: using the app does not renew it.

        The session's side of this (session.auth.device_id, and how often an open session is checked) is
        application.cfc's. This library owns the row and the cookie only.
    --->

    <cfset variables.STAY_DAYS = 30 />
    <cfset variables.COOKIE_NAME = "deviceid" />


    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>


    <!--- ===================================================================================== --->
    <!--- This browser                                                                           --->
    <!--- ===================================================================================== --->

    <cffunction name="issue" access="public" returntype="string" output="false"
        hint="Make a device for the profile and give this browser its cookie. Returns the device id, which the session keeps.">
        <cfargument name="profile_id" type="string" required="true" />
        <cfargument name="place" type="string" default="" hint="Roughly where the device is (e.g. 'Brisbane, QLD, AU'), for Sign-in activity." />

        <cfset var deviceId = createUUID() />
        <cfset var expires = dateAdd("d", variables.STAY_DAYS, now()) />

        <cfset application.lib.db.save(
            table_name = "moo_profile_extended_session",
            data = {
                profile_id = arguments.profile_id,
                device_id = deviceId,
                expiration = "#expires#",
                user_agent = left(cgi.http_user_agent ?: "", 500),
                place = left(arguments.place, 120)
            },
            returnFormat = "cfml"
        ) />
        <cfset writeCookie(deviceId, expires) />

        <cfreturn deviceId />
    </cffunction>


    <cffunction name="resume" access="public" returntype="struct" output="false"
        hint="The live device this browser's cookie names, as { profile_id, device_id }, for signing it back in; an empty struct when it has none. A cookie whose device has expired or is gone signs nobody in: what is left of the device is removed and the cookie cleared.">

        <cfset var deviceId = cookieValue() />
        <cfif NOT len(deviceId)>
            <cfreturn {} />
        </cfif>

        <!--- returntype="array": the values go into the session, and a query column kept there comes back on
              the next request as an array --->
        <cfquery name="local.qDevice" returntype="array">
            SELECT profile_id::text AS profile_id, device_id, expiration > now() AS live
            FROM moo_profile_extended_session
            WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#deviceId#" />
        </cfquery>

        <cfif arrayLen(local.qDevice) EQ 1 AND local.qDevice[1].live>
            <cfreturn { "profile_id": local.qDevice[1].profile_id, "device_id": local.qDevice[1].device_id } />
        </cfif>

        <cfset forget() />
        <cfreturn {} />
    </cffunction>


    <cffunction name="forget" access="public" returntype="void" output="false"
        hint="End this browser's stay: remove the device its cookie names and clear the cookie. The session is left alone. Does nothing without the cookie.">

        <cfset var deviceId = cookieValue() />
        <cfif NOT len(deviceId)>
            <cfreturn />
        </cfif>

        <cfquery>
            DELETE FROM moo_profile_extended_session
            WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#deviceId#" />
        </cfquery>
        <cfset clearCookie() />
    </cffunction>


    <cffunction name="clearCookie" access="public" returntype="void" output="false"
        hint="Clear this browser's device cookie, for a session whose device is already gone.">
        <cfcookie name="#variables.COOKIE_NAME#" value="" path="/" expires="0" httponly="true" secure="true" samesite="Lax">
    </cffunction>


    <cffunction name="cookieValue" access="public" returntype="string" output="false"
        hint="The device id this browser's cookie carries, or empty. Not checked against the database.">
        <cfreturn cookie[variables.COOKIE_NAME] ?: "" />
    </cffunction>


    <!--- ===================================================================================== --->
    <!--- Any device                                                                             --->
    <!--- ===================================================================================== --->

    <cffunction name="isLive" access="public" returntype="boolean" output="false"
        hint="Whether the device still exists and hasn't expired: false once it is signed out from Sign-in activity or runs out. The test resume() makes.">
        <cfargument name="device_id" type="string" required="true" />

        <cfquery name="local.qDevice" returntype="array">
            SELECT 1 AS present
            FROM moo_profile_extended_session
            WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#arguments.device_id#" />
              AND expiration > now()
        </cfquery>
        <cfreturn arrayLen(local.qDevice) GT 0 />
    </cffunction>


    <cffunction name="belongsTo" access="public" returntype="boolean" output="false"
        hint="Whether the device is the profile's, live or not.">
        <cfargument name="device_id" type="string" required="true" />
        <cfargument name="profile_id" type="string" required="true" />

        <cfquery name="local.qDevice" returntype="array">
            SELECT 1 AS present
            FROM moo_profile_extended_session
            WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#arguments.device_id#" />
              AND profile_id = <cfqueryparam cfsqltype="other" value="#arguments.profile_id#" />
        </cfquery>
        <cfreturn arrayLen(local.qDevice) GT 0 />
    </cffunction>


    <!--- ===================================================================================== --->
    <!--- A profile's devices                                                                    --->
    <!--- ===================================================================================== --->

    <cffunction name="devicesFor" access="public" returntype="array" output="false"
        hint="The profile's live devices, newest first: id (the row), device_id, user_agent, place, created_at and expiration (UTC, ISO 8601).">
        <cfargument name="profile_id" type="string" required="true" />

        <cfquery name="local.qDevices" returntype="array">
            SELECT id::text AS id, device_id, user_agent, place,
                   to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at,
                   to_char(expiration AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS expiration
            FROM moo_profile_extended_session
            WHERE profile_id = <cfqueryparam cfsqltype="other" value="#arguments.profile_id#" />
              AND expiration > now()
            ORDER BY created_at DESC
        </cfquery>
        <cfreturn local.qDevices />
    </cffunction>


    <cffunction name="signOut" access="public" returntype="void" output="false"
        hint="Remove one of the profile's devices, by its row id. A session open on it ends within a minute. Does nothing when the row isn't that profile's.">
        <cfargument name="id" type="string" required="true" />
        <cfargument name="profile_id" type="string" required="true" />

        <cfquery>
            DELETE FROM moo_profile_extended_session
            WHERE id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
              AND profile_id = <cfqueryparam cfsqltype="other" value="#arguments.profile_id#" />
        </cfquery>
    </cffunction>


    <cffunction name="signOutOthers" access="public" returntype="void" output="false"
        hint="Remove every device of the profile but one; all of them when keep_device_id is empty.">
        <cfargument name="profile_id" type="string" required="true" />
        <cfargument name="keep_device_id" type="string" default="" />

        <cfquery>
            DELETE FROM moo_profile_extended_session
            WHERE profile_id = <cfqueryparam cfsqltype="other" value="#arguments.profile_id#" />
              AND device_id <> <cfqueryparam cfsqltype="varchar" value="#arguments.keep_device_id#" />
        </cfquery>
    </cffunction>


    <cffunction name="prune" access="public" returntype="void" output="false"
        hint="Remove every device whose stay has run out.">
        <cfquery>
            DELETE FROM moo_profile_extended_session WHERE expiration < now()
        </cfquery>
    </cffunction>


    <!--- ===================================================================================== --->

    <cffunction name="writeCookie" access="private" returntype="void" output="false"
        hint="Give this browser a device's cookie, lasting as long as the device.">
        <cfargument name="device_id" type="string" required="true" />
        <cfargument name="expires" type="date" required="true" />

        <cfcookie name="#variables.COOKIE_NAME#" value="#arguments.device_id#" path="/" expires="#arguments.expires#" httponly="true" secure="true" samesite="Lax">
    </cffunction>

</cfcomponent>
