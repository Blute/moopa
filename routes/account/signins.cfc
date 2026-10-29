<cfcomponent key="b369223b-70fe-4112-9826-839b843c38a2" open_to="logged_in">

    <!---
        Sign-in activity: the devices a profile is signed in on (each stays signed in for 30 days) and its sign-in
        requests of the last 90 days (lib/signin.cfc keeps no more). Everyone sees their own, from the profile menu;
        a sysadmin sees anyone's with ?profile=<id> (System > Profiles links here). Signing a device out removes its
        stay, and its session ends within a minute (application.cfc checks the device).
    --->

    <cffunction name="get">
        <cfset var who = target(url.profile ?: "") />
        <cfset var own = who.id EQ session.auth.profile.id />
        <cfset var devices = devicesFor(who.id) />
        <cfset var requests = requestsFor(who) />
        <cfset var thisDevice = own ? (session.auth.device_id ?: "") : "" />
        <cfset var signin = application.lib.signin />
        <cfset var others = 0 />
        <cfloop array="#devices#" item="local.d"><cfif local.d.device_id NEQ thisDevice><cfset others++ /></cfif></cfloop>

        <cfmodule template="/moopa/tags/moopa_layout.cfm" title="Sign-in activity">
        <cfoutput>
            <div class="page" x-data="signinActivity()">
                <div class="page-header">
                    <div>
                        <div class="eyebrow">#own ? "Your account" : encodeForHTML(who.email)#</div>
                        <h1>Sign-in activity</h1>
                        <p class="page-lede">#own ? "Where you're" : encodeForHTML(len(who.full_name) ? who.full_name : who.email) & " is"# signed in, and every sign-in of the last 90 days. Sign out a device you don't recognise; it's signed out within a minute.</p>
                    </div>
                    <cfif others>
                        <div class="page-actions">
                            <button type="button" class="btn btn-sm btn-danger" @click="signOutOthers()" :disabled="busy"><i class="fa-solid fa-right-from-bracket"></i> #own ? "Sign out everywhere else" : "Sign out everywhere"#</button>
                        </div>
                    </cfif>
                </div>

                <section class="card">
                    <div class="card-header"><h2 class="card-title">Signed-in devices</h2><span class="card-sub">Each stays signed in for 30 days, until it signs out or is signed out here.</span></div>
                    <cfif arrayLen(devices)>
                        <div class="table-wrap">
                            <table class="table">
                                <thead><tr><th>Device</th><th>Near</th><th>Signed in</th><th>Until</th><th></th></tr></thead>
                                <tbody>
                                    <cfloop array="#devices#" item="local.d">
                                        <tr>
                                            <td>#encodeForHTML(len(local.d.user_agent ?: "") ? signin.describeDevice(local.d.user_agent) : "A browser")#<cfif local.d.device_id EQ thisDevice> <span class="badge badge-signal">This device</span></cfif></td>
                                            <td>#encodeForHTML(local.d.place ?: "")#</td>
                                            <td class="nowrap"><time datetime="#local.d.created_at#"></time></td>
                                            <td class="nowrap"><time datetime="#local.d.expiration#" data-date></time></td>
                                            <td class="nowrap" style="text-align: right">
                                                <button type="button" class="btn btn-xs" @click="signOut('#local.d.id#', #local.d.device_id EQ thisDevice ? 'true' : 'false'#)" :disabled="busy">Sign out</button>
                                            </td>
                                        </tr>
                                    </cfloop>
                                </tbody>
                            </table>
                        </div>
                    <cfelse>
                        <div class="card-body muted small">Not signed in on any device.</div>
                    </cfif>
                </section>

                <section class="card">
                    <div class="card-header"><h2 class="card-title">Sign-ins</h2><span class="card-sub">The last 90 days, newest first. An emailed link was asked for on one device and approved from the email, perhaps on another; Google signs in on the device itself.</span></div>
                    <cfif arrayLen(requests)>
                        <div class="table-wrap">
                            <table class="table">
                                <thead><tr><th>When</th><th>Asked from</th><th>Near</th><th>Result</th><th>Approved from</th></tr></thead>
                                <tbody>
                                    <cfloop array="#requests#" item="local.r">
                                        <cfset local.result = outcome(local.r) />
                                        <tr>
                                            <td class="nowrap"><time datetime="#local.r.created_at#"></time></td>
                                            <td>#encodeForHTML(signin.describeDevice(local.r.request_user_agent ?: ""))#</td>
                                            <td>#encodeForHTML(local.r.request_place ?: "")#</td>
                                            <td><span class="badge #local.result.tone#">#local.result.label#</span></td>
                                            <td><cfif (local.r.method ?: "") EQ "google">Google account<cfelseif len(local.r.decide_user_agent ?: "")>#encodeForHTML(signin.describeDevice(local.r.decide_user_agent))#</cfif></td>
                                        </tr>
                                    </cfloop>
                                </tbody>
                            </table>
                        </div>
                    <cfelse>
                        <div class="card-body muted small">No sign-ins in the last 90 days.</div>
                    </cfif>
                </section>
            </div>

            <script>
                // Times in the viewer's own zone
                document.querySelectorAll('time[datetime]').forEach(function (el) {
                    var d = new Date(el.getAttribute('datetime'));
                    el.textContent = el.hasAttribute('data-date')
                        ? d.toLocaleDateString(undefined, { day: 'numeric', month: 'short' })
                        : d.toLocaleString(undefined, { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
                    el.title = d.toLocaleString();
                });
                function signinActivity() {
                    var profile = '#own ? "" : who.id#';
                    return {
                        busy: false,
                        async signOut(id, isThisDevice) {
                            if (isThisDevice) { window.location.href = '/logout/'; return; }
                            this.busy = true;
                            try { await req({ endpoint: 'sign_out_device', body: { id: id, profile: profile } }); window.location.reload(); }
                            finally { this.busy = false; }
                        },
                        async signOutOthers() {
                            this.busy = true;
                            try { await req({ endpoint: 'sign_out_others', body: { profile: profile } }); window.location.reload(); }
                            finally { this.busy = false; }
                        }
                    };
                }
            </script>
        </cfoutput>
        </cfmodule>
    </cffunction>


    <cffunction name="sign_out_device" hint="Remove one of the profile's signed-in devices. Its session ends within a minute.">
        <cfset var who = target(request.data.profile ?: "") />
        <cfquery>
            DELETE FROM moo_profile_extended_session
            WHERE id = <cfqueryparam cfsqltype="other" value="#request.data.id ?: ''#" />
              AND profile_id = <cfqueryparam cfsqltype="other" value="#who.id#" />
        </cfquery>
        <cfreturn { "ok": true } />
    </cffunction>


    <cffunction name="sign_out_others" hint="Remove every signed-in device of the profile but this one (all of them, for someone else's).">
        <cfset var who = target(request.data.profile ?: "") />
        <!--- This device: the session's own, else (a session older than that) its stay-signed-in cookie's --->
        <cfset var keep = who.id EQ session.auth.profile.id ? (len(session.auth.device_id ?: "") ? session.auth.device_id : (cookie.deviceid ?: "")) : "" />
        <cfquery>
            DELETE FROM moo_profile_extended_session
            WHERE profile_id = <cfqueryparam cfsqltype="other" value="#who.id#" />
              AND device_id <> <cfqueryparam cfsqltype="varchar" value="#keep#" />
        </cfquery>
        <cfreturn { "ok": true } />
    </cffunction>


    <!--- ===================================================================================== --->

    <cffunction name="target" access="private" returntype="struct" output="false"
        hint="The profile to show: the asked-for one for a sysadmin, else the signed-in person's own.">
        <cfargument name="profileId" type="string" required="true" />

        <cfset var id = session.auth.profile.id />
        <cfif len(arguments.profileId) AND application.lib.auth.isSysAdmin()
              AND reFindNoCase("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", arguments.profileId)>
            <cfset id = arguments.profileId />
        </cfif>
        <cfquery name="local.qProfile" returntype="array">
            SELECT id::text AS id, COALESCE(full_name, '') AS full_name, COALESCE(email, '') AS email, app_name
            FROM moo_profile
            WHERE id = <cfqueryparam cfsqltype="other" value="#id#" />
        </cfquery>
        <cfif NOT arrayLen(local.qProfile)>
            <cfthrow type="moopa.signinActivity.noProfile" message="No profile #id#." />
        </cfif>
        <cfreturn local.qProfile[1] />
    </cffunction>


    <cffunction name="devicesFor" access="private" returntype="array" output="false">
        <cfargument name="profileId" type="string" required="true" />
        <cfquery name="local.qDevices" returntype="array">
            SELECT id::text AS id, device_id, user_agent, place,
                   to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at,
                   to_char(expiration AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS expiration
            FROM moo_profile_extended_session
            WHERE profile_id = <cfqueryparam cfsqltype="other" value="#arguments.profileId#" />
              AND expiration > now()
            ORDER BY created_at DESC
        </cfquery>
        <cfreturn local.qDevices />
    </cffunction>


    <cffunction name="requestsFor" access="private" returntype="array" output="false"
        hint="The profile's sign-in requests of the last 90 days: its own, and any for its email before it had a profile.">
        <cfargument name="profile" type="struct" required="true" />
        <cfquery name="local.qRequests" returntype="array">
            SELECT status, COALESCE(method, '') AS method, expires_at > now() AS live, request_user_agent, request_place, decide_user_agent,
                   to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"') AS created_at
            FROM moo_signin_request
            WHERE (profile_id = <cfqueryparam cfsqltype="other" value="#arguments.profile.id#" />
                   OR (profile_id IS NULL
                       AND email = <cfqueryparam cfsqltype="varchar" value="#lCase(arguments.profile.email)#" />
                       AND app_name = <cfqueryparam cfsqltype="varchar" value="#arguments.profile.app_name#" />))
              AND created_at > now() - interval '90 days'
            ORDER BY created_at DESC
            LIMIT 200
        </cfquery>
        <cfreturn local.qRequests />
    </cffunction>


    <cffunction name="outcome" access="private" returntype="struct" output="false" hint="A request's result, as a label and a badge tone.">
        <cfargument name="row" type="struct" required="true" />
        <cfswitch expression="#arguments.row.status#">
            <cfcase value="used"><cfreturn { label: "Signed in", tone: "badge-success" } /></cfcase>
            <cfcase value="denied"><cfreturn { label: "Turned down", tone: "badge-danger" } /></cfcase>
            <cfcase value="approved">
                <cfreturn arguments.row.live ? { label: "Approved", tone: "badge-info" } : { label: "Approved, not continued", tone: "badge-outline" } />
            </cfcase>
        </cfswitch>
        <cfreturn arguments.row.live ? { label: "Waiting", tone: "badge-warning" } : { label: "Expired", tone: "badge-outline" } />
    </cffunction>

</cfcomponent>
