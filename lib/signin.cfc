<cfcomponent displayname="signin" output="false"
    hint="Passwordless sign-in by emailed link, approved from any device (table moo_signin_request). A project's /login route hands its get and post to get() and post(), and its /logout route to logout(). docs/signin.md.">

    <!---
        The asking browser enters an email and waits on /login/. If someone can sign in with that email, a
        link is emailed to them. Opening it (on a phone, say) shows which device is asking, with Approve and
        Not me; only the button approves, never the opening, as mail scanners open links. The waiting page
        notices within a couple of seconds and offers Continue, which signs that browser in.

        The asking browser is bound to its request by a secret kept in its session; the emailed link carries a
        second secret. Only their SHA-256 hashes are stored. Nothing on the asking page says whether the email
        has an account. In development the waiting page shows the link, as email is redirected there.
    --->

    <cfset variables.TTL_MINUTES = 15 />
    <cfset variables.MAX_PER_EMAIL = 5 />  <!--- requests per email address per TTL_MINUTES --->
    <cfset variables.MAX_PER_IP = 20 />    <!--- requests per IP address per TTL_MINUTES --->
    <cfset variables.PATH = "/login/" />

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>


    <!--- ===================================================================================== --->
    <!--- The route's handlers                                                                   --->
    <!--- ===================================================================================== --->

    <cffunction name="get" access="public" returntype="string" output="false"
        hint="GET /login/: the approve page for an emailed link (?t=), else the asking browser's current step.">

        <cfif len(url.t ?: "")>
            <cfreturn approvePage(url.t) />
        </cfif>

        <cfif application.lib.auth.isLoggedIn()>
            <cflocation url="#application.lib.core.getRedirectUrl(clear=true, fallback='/')#" addtoken="false" />
        </cfif>

        <cfif NOT structKeyExists(session, "signin")>
            <cfreturn emailPage() />
        </cfif>

        <cfswitch expression="#status()#">
            <cfcase value="approved"><cfreturn approvedPage() /></cfcase>
            <cfcase value="denied"><cfreturn endedPage("denied") /></cfcase>
            <cfcase value="pending"><cfreturn waitingPage() /></cfcase>
            <cfdefaultcase><cfreturn endedPage("expired") /></cfdefaultcase>
        </cfswitch>
    </cffunction>


    <cffunction name="post" access="public" returntype="string" output="false"
        hint="POST /login/: action is start (email), status (JSON, polled by the waiting page), continue, restart, approve or deny (token).">

        <cfset var action = request.data.action ?: "" />

        <cfswitch expression="#action#">
            <cfcase value="start">
                <cfset var problem = start(request.data.email ?: "") />
                <cfif len(problem)>
                    <cfreturn emailPage(email = request.data.email ?: "", error = problem) />
                </cfif>
                <cflocation url="#variables.PATH#" addtoken="false" />
            </cfcase>

            <cfcase value="status">
                <cfheader name="Cache-Control" value="no-store" />
                <cfcontent type="application/json" reset="true" />
                <cfreturn serializeJSON({ "status": status() }) />
            </cfcase>

            <cfcase value="continue">
                <cfset complete() />
                <!--- Not approved (or no longer): back to the page, which says where things stand --->
                <cflocation url="#variables.PATH#" addtoken="false" />
            </cfcase>

            <cfcase value="restart">
                <cfset structDelete(session, "signin") />
                <cflocation url="#variables.PATH#" addtoken="false" />
            </cfcase>

            <cfcase value="approve,deny">
                <cfreturn decide(token = request.data.t ?: "", approve = (action EQ "approve")) />
            </cfcase>
        </cfswitch>

        <cflocation url="#variables.PATH#" addtoken="false" />
    </cffunction>


    <cffunction name="logout" access="public" returntype="void" output="false"
        hint="Sign this browser out, ending its stay-signed-in device too, then go home.">

        <cfif len(cookie.deviceid ?: "")>
            <cfquery>
            DELETE FROM moo_profile_extended_session
            WHERE device_id = <cfqueryparam cfsqltype="varchar" value="#cookie.deviceid#" />
            </cfquery>
            <cfcookie name="deviceid" value="" path="/" expires="0" httponly="true" secure="true" samesite="Lax">
        </cfif>
        <cfset structDelete(session, "auth") />
        <cfset structDelete(session, "signin") />
        <cflocation url="/" addtoken="false" />
    </cffunction>


    <!--- ===================================================================================== --->
    <!--- The flow                                                                               --->
    <!--- ===================================================================================== --->

    <cffunction name="start" access="private" returntype="string" output="false"
        hint="Record a request for this email and, when someone can sign in with it, email them the link. Returns a problem to show, or empty.">
        <cfargument name="email" type="string" required="true" />

        <cfset var address = lCase(trim(arguments.email)) />
        <cfif NOT isValid("email", address)>
            <cfreturn "Enter your email address." />
        </cfif>

        <cfset var ip = clientIp() />
        <cfquery name="local.qRecent" returntype="array">
            SELECT count(*) FILTER (WHERE email = <cfqueryparam cfsqltype="varchar" value="#address#" />) AS by_email,
                   count(*) FILTER (WHERE request_ip = <cfqueryparam cfsqltype="varchar" value="#ip#" />) AS by_ip
            FROM moo_signin_request
            WHERE created_at > now() - make_interval(mins => <cfqueryparam cfsqltype="integer" value="#variables.TTL_MINUTES#" />)
        </cfquery>
        <cfif local.qRecent[1].by_email GTE variables.MAX_PER_EMAIL OR local.qRecent[1].by_ip GTE variables.MAX_PER_IP>
            <cfreturn "Too many sign-in requests. Wait a few minutes, then try again." />
        </cfif>

        <cfset var profileId = profileFor(address) />
        <!--- A configured hub sysadmin without a usable profile gets the link too; their profile is
              made or enabled only when the link is approved, which proves they own the mailbox --->
        <cfset var canSignIn = len(profileId) OR isConfiguredSysadmin(address) />
        <cfset var approveToken = application.lib.core.generateSecureToken(32) />
        <cfset var browserSecret = application.lib.core.generateSecureToken(32) />
        <cfset var userAgent = left(cgi.http_user_agent ?: "", 500) />
        <cfset var place = clientPlace() />

        <cfquery name="local.qRequest" returntype="array">
            INSERT INTO moo_signin_request
                (app_name, email, profile_id, status, approve_token_hash, browser_token_hash, expires_at, request_ip, request_user_agent, request_place)
            VALUES (
                <cfqueryparam cfsqltype="varchar" value="#appName()#" />,
                <cfqueryparam cfsqltype="varchar" value="#address#" />,
                NULLIF(<cfqueryparam cfsqltype="varchar" value="#profileId#" />, '')::uuid,
                'pending',
                <cfqueryparam cfsqltype="varchar" value="#tokenHash(approveToken)#" />,
                <cfqueryparam cfsqltype="varchar" value="#tokenHash(browserSecret)#" />,
                now() + make_interval(mins => <cfqueryparam cfsqltype="integer" value="#variables.TTL_MINUTES#" />),
                <cfqueryparam cfsqltype="varchar" value="#ip#" />,
                <cfqueryparam cfsqltype="varchar" value="#userAgent#" />,
                <cfqueryparam cfsqltype="varchar" value="#place#" />
            )
            RETURNING id::text AS id
        </cfquery>

        <cfset session.signin = {
            id = local.qRequest[1].id,
            secret = browserSecret,
            email = address,
            dev_link = ""
        } />

        <cfif canSignIn>
            <cfset var link = approveUrl(approveToken) />
            <cfif isDevelopment()>
                <cfset session.signin.dev_link = link />
            </cfif>
            <!--- A failed send is logged (sendLink) and otherwise looks like any other request: saying
                  so would tell the asker this email has an account --->
            <cfset sendLink(address, link, describeDevice(userAgent), place) />
        </cfif>

        <cfreturn "" />
    </cffunction>


    <cffunction name="status" access="private" returntype="string" output="false"
        hint="Where the asking browser's request stands: pending, approved, denied, used or expired (none: it has none).">

        <cfif NOT structKeyExists(session, "signin")>
            <cfreturn "none" />
        </cfif>

        <cfquery name="local.qStatus" returntype="array">
            SELECT status, expires_at > now() AS live
            FROM moo_signin_request
            WHERE id = <cfqueryparam cfsqltype="other" value="#session.signin.id#" />
              AND browser_token_hash = <cfqueryparam cfsqltype="varchar" value="#tokenHash(session.signin.secret)#" />
        </cfquery>

        <cfif NOT arrayLen(local.qStatus)>
            <cfreturn "expired" />
        </cfif>
        <cfif NOT local.qStatus[1].live AND listFind("pending,approved", local.qStatus[1].status)>
            <cfreturn "expired" />
        </cfif>
        <cfreturn local.qStatus[1].status />
    </cffunction>


    <cffunction name="complete" access="private" returntype="void" output="false"
        hint="Sign the asking browser in, if its request is approved and live. Atomic: a request signs in once.">

        <cfif NOT structKeyExists(session, "signin")>
            <cfreturn />
        </cfif>

        <cfquery name="local.qUse" returntype="array">
            UPDATE moo_signin_request
            SET status = 'used', used_at = now()
            WHERE id = <cfqueryparam cfsqltype="other" value="#session.signin.id#" />
              AND browser_token_hash = <cfqueryparam cfsqltype="varchar" value="#tokenHash(session.signin.secret)#" />
              AND status = 'approved'
              AND expires_at > now()
              AND profile_id IS NOT NULL
            RETURNING profile_id::text AS profile_id
        </cfquery>

        <cfif NOT arrayLen(local.qUse)>
            <cfreturn />
        </cfif>

        <cfset var profileId = local.qUse[1].profile_id />
        <cfquery>
            UPDATE moo_profile SET last_login_at = now()
            WHERE id = <cfqueryparam cfsqltype="other" value="#profileId#" />
        </cfquery>

        <cfset structDelete(session, "signin") />
        <!--- Stay signed in on this device for 30 days (moo_profile.login): with no password, signing in
              again is a trip to the inbox --->
        <cfset application.lib.db.getService("moo_profile").login(
            profile_id = profileId,
            stay_logged_in = true,
            user_directory = "email_link"
        ) />

        <cflocation url="#application.lib.core.getRedirectUrl(clear=true, fallback='/')#" addtoken="false" />
    </cffunction>


    <cffunction name="decide" access="private" returntype="string" output="false"
        hint="Approve or turn down the request an emailed link belongs to, if it is still waiting.">
        <cfargument name="token" type="string" required="true" />
        <cfargument name="approve" type="boolean" required="true" />

        <!--- A configured sysadmin's first approval: holding the emailed link shows they own the mailbox, so
              give them a hub profile (or enable theirs) first. The approving statement below then sets the
              status and the profile together: if making the profile fails, the request is still pending and
              Approve can be tried again, never approved without a profile. --->
        <cfset var bootstrapProfileId = "" />
        <cfif arguments.approve>
            <cfquery name="local.qWaiting" returntype="array">
                SELECT email
                FROM moo_signin_request
                WHERE approve_token_hash = <cfqueryparam cfsqltype="varchar" value="#tokenHash(arguments.token)#" />
                  AND status = 'pending'
                  AND expires_at > now()
                  AND profile_id IS NULL
                  AND app_name = 'hub'
                  AND email IN (<cfqueryparam cfsqltype="varchar" value="#sysadminList()#" list="true" />)
            </cfquery>
            <cfif arrayLen(local.qWaiting)>
                <cfset bootstrapProfileId = sysadminProfile(local.qWaiting[1].email) />
            </cfif>
        </cfif>

        <cfquery name="local.qDecide" returntype="array">
            UPDATE moo_signin_request
            SET status = <cfqueryparam cfsqltype="varchar" value="#arguments.approve ? 'approved' : 'denied'#" />,
                profile_id = COALESCE(profile_id, NULLIF(<cfqueryparam cfsqltype="varchar" value="#bootstrapProfileId#" />, '')::uuid),
                decided_at = now(),
                decide_ip = <cfqueryparam cfsqltype="varchar" value="#clientIp()#" />,
                decide_user_agent = <cfqueryparam cfsqltype="varchar" value="#left(cgi.http_user_agent ?: '', 500)#" />
            WHERE approve_token_hash = <cfqueryparam cfsqltype="varchar" value="#tokenHash(arguments.token)#" />
              AND status = 'pending'
              AND expires_at > now()
              AND (profile_id IS NOT NULL
                   OR (app_name = 'hub' AND email IN (<cfqueryparam cfsqltype="varchar" value="#sysadminList()#" list="true" />)))
              <!--- Approving needs a profile, now or from just above; turning down doesn't --->
              <cfif arguments.approve>AND COALESCE(profile_id, NULLIF(<cfqueryparam cfsqltype="varchar" value="#bootstrapProfileId#" />, '')::uuid) IS NOT NULL</cfif>
            RETURNING id::text AS id
        </cfquery>

        <cfif NOT arrayLen(local.qDecide)>
            <!--- Decided already, used or expired: the approve page says which --->
            <cfreturn approvePage(arguments.token) />
        </cfif>

        <!--- Approved in the browser that asked: straight on to Continue --->
        <cfif arguments.approve AND structKeyExists(session, "signin") AND session.signin.id EQ local.qDecide[1].id>
            <cflocation url="#variables.PATH#" addtoken="false" />
        </cfif>

        <cfreturn arguments.approve ? decidedPage("approved") : decidedPage("denied") />
    </cffunction>


    <!--- ===================================================================================== --->
    <!--- Pages                                                                                  --->
    <!--- ===================================================================================== --->

    <cffunction name="emailPage" access="private" returntype="string" output="false">
        <cfargument name="email" type="string" default="" />
        <cfargument name="error" type="string" default="" />

        <cfset var body = "" />
        <cfsavecontent variable="body"><cfoutput>
            <form class="card signin" method="post" action="#variables.PATH#">
                <div class="card-body">
                    <div class="stack-xs">
                        <h1>Sign in</h1>
                        <p class="signin-lead">We'll email you a link to sign in with. No password needed.</p>
                    </div>
                    <input type="hidden" name="action" value="start">
                    <div class="field">
                        <label class="label" for="signin-email">Email</label>
                        <input id="signin-email" class="input<cfif len(arguments.error)> is-invalid</cfif>" type="email" name="email" value="#encodeForHTMLAttribute(arguments.email)#" autocomplete="email" autofocus required>
                        <cfif len(arguments.error)><p class="field-error">#encodeForHTML(arguments.error)#</p></cfif>
                    </div>
                    <button type="submit" class="btn btn-primary btn-block"><i class="fa-solid fa-envelope"></i> Email me a link</button>
                </div>
            </form>
        </cfoutput></cfsavecontent>
        <cfreturn page("Sign in", body) />
    </cffunction>


    <cffunction name="waitingPage" access="private" returntype="string" output="false">
        <cfset var body = "" />
        <cfsavecontent variable="body"><cfoutput>
            <div class="card signin">
                <div class="card-body">
                    <span class="signin-icon"><i class="fa-solid fa-envelope"></i></span>
                    <div class="stack-xs">
                        <h1>Check your email</h1>
                        <p class="signin-lead">If <strong>#encodeForHTML(session.signin.email)#</strong> can sign in, a link is on its way. Open it on any device, your phone is fine, and approve the sign-in. This page carries on by itself.</p>
                    </div>
                    <p class="signin-waiting" role="status"><i class="fa-solid fa-circle-notch fa-spin"></i> Waiting for approval…</p>
                    <cfif len(session.signin.dev_link)>
                        <div class="alert alert-info"><i class="fa-solid fa-code"></i><div>Development: <a href="#encodeForHTMLAttribute(session.signin.dev_link)#" target="_blank" rel="noopener">open the emailed link</a></div></div>
                    </cfif>
                    <div class="signin-foot">
                        #restartForm("Use a different email")#
                        <form method="post" action="#variables.PATH#">
                            <input type="hidden" name="action" value="start">
                            <input type="hidden" name="email" value="#encodeForHTMLAttribute(session.signin.email)#">
                            <button type="submit" class="btn-link">Send again</button>
                        </form>
                    </div>
                </div>
            </div>
            <script>
                // Ask every couple of seconds whether the request has moved on, and when it has, reload so the
                // server shows the next step. Not while the tab is hidden (the database can rest while the
                // person is off in their email); straight away when it's shown again.
                (function () {
                    let busy = false;
                    async function check() {
                        if (busy) return;
                        busy = true;
                        try {
                            const r = await fetch('#variables.PATH#', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Fetch-Request': 'true' }, body: JSON.stringify({ action: 'status' }), credentials: 'same-origin' });
                            const s = (await r.json()).status;
                            if (s && s !== 'pending') window.location.replace('#variables.PATH#');
                        } catch (e) {} finally { busy = false; }
                    }
                    setInterval(() => { if (!document.hidden) check(); }, 2000);
                    document.addEventListener('visibilitychange', () => { if (!document.hidden) check(); });
                })();
            </script>
        </cfoutput></cfsavecontent>
        <cfreturn page("Check your email", body) />
    </cffunction>


    <cffunction name="approvedPage" access="private" returntype="string" output="false">
        <cfset var body = "" />
        <cfsavecontent variable="body"><cfoutput>
            <form class="card signin" method="post" action="#variables.PATH#">
                <div class="card-body">
                    <span class="signin-icon is-success"><i class="fa-solid fa-check"></i></span>
                    <div class="stack-xs">
                        <h1>Sign-in approved</h1>
                        <p class="signin-lead">You approved this sign-in for <strong>#encodeForHTML(session.signin.email)#</strong>.</p>
                    </div>
                    <input type="hidden" name="action" value="continue">
                    <button type="submit" class="btn btn-primary btn-block" autofocus>Continue to #encodeForHTML(projectTitle())# <i class="fa-solid fa-arrow-right"></i></button>
                </div>
            </form>
            <div class="signin-foot" style="border-top: 0; padding-top: 0">#restartForm("Start again")#</div>
        </cfoutput></cfsavecontent>
        <cfreturn page("Sign-in approved", body) />
    </cffunction>


    <cffunction name="endedPage" access="private" returntype="string" output="false"
        hint="The asking browser's request is over without signing in: denied or expired.">
        <cfargument name="why" type="string" required="true" />

        <cfset var denied = arguments.why EQ "denied" />
        <cfset var heading = denied ? "Sign-in declined" : "Link expired" />
        <cfset var message = denied ? "The sign-in was turned down from the emailed link." : "Sign-in links last " & variables.TTL_MINUTES & " minutes. Ask for a new one." />
        <cfset var body = "" />
        <cfsavecontent variable="body"><cfoutput>
            <div class="card signin">
                <div class="card-body">
                    <span class="signin-icon is-danger"><i class="fa-solid #denied ? 'fa-ban' : 'fa-clock'#"></i></span>
                    <div class="stack-xs">
                        <h1>#heading#</h1>
                        <p class="signin-lead">#message#</p>
                    </div>
                    <form method="post" action="#variables.PATH#">
                        <input type="hidden" name="action" value="restart">
                        <button type="submit" class="btn btn-primary btn-block">Start again</button>
                    </form>
                </div>
            </div>
        </cfoutput></cfsavecontent>
        <cfreturn page(heading, body) />
    </cffunction>


    <cffunction name="approvePage" access="private" returntype="string" output="false"
        hint="What an emailed link opens: the waiting request, to approve or turn down. Opening it changes nothing.">
        <cfargument name="token" type="string" required="true" />

        <cfquery name="local.qRequest" returntype="array">
            SELECT email, status, expires_at > now() AS live, request_user_agent, request_place,
                   floor(extract(epoch FROM now() - created_at))::int AS age_seconds
            FROM moo_signin_request
            WHERE approve_token_hash = <cfqueryparam cfsqltype="varchar" value="#tokenHash(arguments.token)#" />
              AND (profile_id IS NOT NULL
                   OR (app_name = 'hub' AND email IN (<cfqueryparam cfsqltype="varchar" value="#sysadminList()#" list="true" />)))
        </cfquery>

        <cfif NOT arrayLen(local.qRequest)>
            <cfreturn linkOverPage("This link isn't valid. Use the newest link we emailed you, or ask for a new one.") />
        </cfif>

        <cfset var r = local.qRequest[1] />
        <cfif r.status EQ "approved">
            <cfreturn decidedPage("approved") />
        </cfif>
        <cfif r.status EQ "denied">
            <cfreturn decidedPage("denied") />
        </cfif>
        <cfif r.status EQ "used">
            <cfreturn linkOverPage("This sign-in is done: the link has been used.") />
        </cfif>
        <cfif NOT r.live>
            <cfreturn linkOverPage("This link has expired. Links last " & variables.TTL_MINUTES & " minutes; ask for a new one on the device you're signing in on.") />
        </cfif>

        <cfset var body = "" />
        <cfsavecontent variable="body"><cfoutput>
            <form class="card signin" method="post" action="#variables.PATH#">
                <div class="card-body">
                    <div class="stack-xs">
                        <h1>Sign in to #encodeForHTML(projectTitle())#?</h1>
                        <p class="signin-lead">Someone asked to sign in as you. Approve it only if it was you.</p>
                    </div>
                    <div class="kv-grid">
                        <div class="kv-label">Email</div><div class="kv-value">#encodeForHTML(r.email)#</div>
                        <div class="kv-label">Device</div><div class="kv-value">#encodeForHTML(describeDevice(r.request_user_agent ?: ""))#</div>
                        <cfif len(r.request_place ?: "")><div class="kv-label">Near</div><div class="kv-value">#encodeForHTML(r.request_place)#</div></cfif>
                        <div class="kv-label">Asked</div><div class="kv-value">#ago(r.age_seconds)#</div>
                    </div>
                    <input type="hidden" name="t" value="#encodeForHTMLAttribute(arguments.token)#">
                    <div class="cluster">
                        <button type="submit" name="action" value="approve" class="btn btn-primary"><i class="fa-solid fa-check"></i> Approve</button>
                        <button type="submit" name="action" value="deny" class="btn">Not me</button>
                    </div>
                </div>
            </form>
        </cfoutput></cfsavecontent>
        <cfreturn page("Approve sign-in", body) />
    </cffunction>


    <cffunction name="decidedPage" access="private" returntype="string" output="false"
        hint="Shown where the link was opened, once the request is approved or turned down.">
        <cfargument name="decision" type="string" required="true" />

        <cfset var approved = arguments.decision EQ "approved" />
        <cfset var heading = approved ? "Sign-in approved" : "Sign-in declined" />
        <cfset var message = approved
            ? "Go back to the device you're signing in on: it carries on by itself. You can close this page."
            : "Nobody was signed in. If you didn't ask to sign in, you can ignore this; your account is unchanged." />
        <cfset var body = "" />
        <cfsavecontent variable="body"><cfoutput>
            <div class="card signin">
                <div class="card-body">
                    <span class="signin-icon #approved ? 'is-success' : 'is-danger'#"><i class="fa-solid #approved ? 'fa-check' : 'fa-ban'#"></i></span>
                    <div class="stack-xs">
                        <h1>#heading#</h1>
                        <p class="signin-lead">#message#</p>
                    </div>
                </div>
            </div>
        </cfoutput></cfsavecontent>
        <cfreturn page(heading, body) />
    </cffunction>


    <cffunction name="linkOverPage" access="private" returntype="string" output="false">
        <cfargument name="message" type="string" required="true" />

        <cfset var body = "" />
        <cfsavecontent variable="body"><cfoutput>
            <div class="card signin">
                <div class="card-body">
                    <span class="signin-icon is-danger"><i class="fa-solid fa-link-slash"></i></span>
                    <div class="stack-xs">
                        <h1>Link can't be used</h1>
                        <p class="signin-lead">#encodeForHTML(arguments.message)#</p>
                    </div>
                </div>
            </div>
        </cfoutput></cfsavecontent>
        <cfreturn page("Link can't be used", body) />
    </cffunction>


    <cffunction name="restartForm" access="private" returntype="string" output="false">
        <cfargument name="label" type="string" required="true" />
        <cfreturn '<form method="post" action="#variables.PATH#"><input type="hidden" name="action" value="restart"><button type="submit" class="btn-link">#encodeForHTML(arguments.label)#</button></form>' />
    </cffunction>


    <cffunction name="page" access="private" returntype="string" output="false"
        hint="A sign-in page: moopa_bare with this body. Never cached: each is one person's step.">
        <cfargument name="title" type="string" required="true" />
        <cfargument name="body" type="string" required="true" />

        <cfset var html = "" />
        <cfheader name="Cache-Control" value="no-store" />
        <cfsavecontent variable="html"><cfmodule template="/moopa/tags/moopa_bare.cfm" title="#arguments.title#"><cfoutput>#arguments.body#</cfoutput></cfmodule></cfsavecontent>
        <cfreturn html />
    </cffunction>


    <!--- ===================================================================================== --->
    <!--- Email                                                                                  --->
    <!--- ===================================================================================== --->

    <cffunction name="sendLink" access="private" returntype="boolean" output="false"
        hint="Email the approve link. False (and logged) if it couldn't be sent.">
        <cfargument name="to" type="string" required="true" />
        <cfargument name="link" type="string" required="true" />
        <cfargument name="device" type="string" required="true" />
        <cfargument name="place" type="string" required="true" />

        <cfset var title = projectTitle() />
        <cfset var where = arguments.device & (len(arguments.place) ? ", near " & arguments.place : "") />
        <cfset var html = "" />
        <cfsavecontent variable="html"><cfoutput>
<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;color:##1f1a17;line-height:1.5">
    <h1 style="font-size:20px;font-weight:600;margin:0 0 12px">Sign in to #encodeForHTML(title)#</h1>
    <p style="margin:0 0 16px">Someone asked to sign in to #encodeForHTML(title)# as #encodeForHTML(arguments.to)# from #encodeForHTML(where)#. If it was you, open the link and approve it.</p>
    <p style="margin:0 0 24px"><a href="#encodeForHTMLAttribute(arguments.link)#" style="display:inline-block;padding:10px 18px;border-radius:8px;background:##1f1a17;color:##ffffff;text-decoration:none;font-weight:600">Review sign-in</a></p>
    <p style="margin:0 0 8px;color:##6b625c;font-size:14px">The link works for #variables.TTL_MINUTES# minutes and can be opened on any device. Opening it doesn't sign anyone in; approving it does.</p>
    <p style="margin:0;color:##6b625c;font-size:14px">If it wasn't you, ignore this email or choose Not me.</p>
</div>
        </cfoutput></cfsavecontent>
        <cfset var text = "Sign in to #title#" & chr(10) & chr(10)
            & "Someone asked to sign in to #title# as #arguments.to# from #where#. If it was you, open this link and approve it:" & chr(10) & chr(10)
            & arguments.link & chr(10) & chr(10)
            & "The link works for #variables.TTL_MINUTES# minutes and can be opened on any device. Opening it doesn't sign anyone in; approving it does." & chr(10)
            & "If it wasn't you, ignore this email or choose Not me." />

        <cftry>
            <cfset var result = application.lib.email.send(to = arguments.to, subject = "Sign in to #title#", html = html, text = text) />
            <cfif NOT (result.success ?: false)>
                <cflog file="signin" type="error" text="Sign-in email to #arguments.to# not sent: #serializeJSON(result.errors ?: [])#" />
            </cfif>
            <cfreturn result.success ?: false />
            <cfcatch>
                <cflog file="signin" type="error" text="Sign-in email to #arguments.to# failed: #cfcatch.message#" />
                <cfreturn false />
            </cfcatch>
        </cftry>
    </cffunction>


    <!--- ===================================================================================== --->
    <!--- Helpers                                                                                --->
    <!--- ===================================================================================== --->

    <cffunction name="profileFor" access="private" returntype="string" output="false"
        hint="The id of this app's profile that can sign in with this email, else empty. Reads only.">
        <cfargument name="email" type="string" required="true" />

        <cfquery name="local.qProfile" returntype="array">
            SELECT id::text AS id
            FROM moo_profile
            WHERE app_name = <cfqueryparam cfsqltype="varchar" value="#appName()#" />
              AND lower(email) = <cfqueryparam cfsqltype="varchar" value="#arguments.email#" />
              AND can_login = true
            LIMIT 1
        </cfquery>
        <cfreturn arrayLen(local.qProfile) ? local.qProfile[1].id : "" />
    </cffunction>


    <cffunction name="isConfiguredSysadmin" access="private" returntype="boolean" output="false"
        hint="Whether this email is one of the hub's configured sysadmins (SYSADMIN_EMAIL) and this is the hub.">
        <cfargument name="email" type="string" required="true" />
        <cfreturn appName() EQ "hub" AND listFindNoCase(sysadminEmails(), arguments.email) GT 0 />
    </cffunction>


    <cffunction name="sysadminProfile" access="private" returntype="string" output="false"
        hint="A configured sysadmin's hub profile id, made or enabled. Called only once they've approved an emailed link, so a new project's first sign-in needs no setup.">
        <cfargument name="email" type="string" required="true" />

        <cfquery name="local.qProfile" returntype="array">
            SELECT id::text AS id, can_login
            FROM moo_profile
            WHERE app_name = 'hub'
              AND lower(email) = <cfqueryparam cfsqltype="varchar" value="#arguments.email#" />
            ORDER BY can_login DESC
            LIMIT 1
        </cfquery>

        <cfif arrayLen(local.qProfile)>
            <cfif NOT local.qProfile[1].can_login>
                <cfquery>
                    UPDATE moo_profile SET can_login = true
                    WHERE id = <cfqueryparam cfsqltype="other" value="#local.qProfile[1].id#" />
                </cfquery>
            </cfif>
            <cfreturn local.qProfile[1].id />
        </cfif>

        <cfset var profile = application.lib.db.save(
            table_name = "moo_profile",
            data = { app_name = "hub", full_name = arguments.email, email = arguments.email, can_login = true },
            returnFormat = "cfml"
        ) />
        <cfreturn profile.id />
    </cffunction>


    <cffunction name="sysadminList" access="private" returntype="string" output="false"
        hint="sysadminEmails() for an IN list, never empty (an empty list would match nothing, but some drivers reject it).">
        <cfset var list = sysadminEmails() />
        <cfreturn len(list) ? list : "-" />
    </cffunction>


    <cffunction name="sysadminEmails" access="public" returntype="string" output="false"
        hint="SYSADMIN_EMAIL as a lower-case list: the hub's configured sysadmins.">
        <cfset var list = "" />
        <cfset var address = "" />
        <cfloop list="#server.system.environment.SYSADMIN_EMAIL ?: ''#" item="address">
            <cfif len(trim(address))><cfset list = listAppend(list, lCase(trim(address))) /></cfif>
        </cfloop>
        <cfreturn list />
    </cffunction>


    <cffunction name="approveUrl" access="private" returntype="string" output="false"
        hint="The emailed link: on BASE_URL, never the request's Host header, which the asker controls.">
        <cfargument name="token" type="string" required="true" />

        <cfset var base = trim(server.system.environment.BASE_URL ?: "") />
        <cfif NOT len(base)>
            <cfthrow type="moopa.signin.config" message="BASE_URL must be set for sign-in links." />
        </cfif>
        <cfif right(base, 1) EQ "/"><cfset base = left(base, len(base) - 1) /></cfif>
        <cfreturn base & variables.PATH & "?t=" & encodeForURL(arguments.token) />
    </cffunction>


    <cffunction name="tokenHash" access="private" returntype="string" output="false">
        <cfargument name="token" type="string" required="true" />
        <cfreturn lCase(hash(arguments.token, "SHA-256")) />
    </cffunction>


    <cffunction name="clientIp" access="private" returntype="string" output="false"
        hint="The asker's address. A proxy's header for it only when TRUSTED_PROXY says the app is behind that proxy (a client can send any header); else the connection's. Never X-Forwarded-For, whose first entry the client writes.">
        <cfset var headers = getHttpRequestData().headers />
        <cfset var fromProxy = "" />
        <cfif trustedProxy() EQ "cloudflare">
            <cfset fromProxy = headers["CF-Connecting-IP"] ?: "" />
        <cfelseif trustedProxy() EQ "digitalocean">
            <cfset fromProxy = headers["DO-Connecting-IP"] ?: "" />
        </cfif>
        <cfreturn left(trim(len(trim(fromProxy)) ? fromProxy : (cgi.remote_addr ?: "")), 64) />
    </cffunction>


    <cffunction name="clientPlace" access="private" returntype="string" output="false"
        hint="Roughly where the asker is, from Cloudflare's visitor location headers, only when TRUSTED_PROXY=cloudflare; else empty.">
        <cfif trustedProxy() NEQ "cloudflare">
            <cfreturn "" />
        </cfif>
        <cfset var headers = getHttpRequestData().headers />
        <cfset var parts = [] />
        <cfloop list="CF-IPCity,CF-Region,CF-IPCountry" item="local.name">
            <cfset local.value = trim(headers[local.name] ?: "") />
            <cfif len(local.value) AND local.value NEQ "XX" AND NOT arrayFind(parts, local.value)>
                <cfset arrayAppend(parts, local.value) />
            </cfif>
        </cfloop>
        <cfreturn left(arrayToList(parts, ", "), 120) />
    </cffunction>


    <cffunction name="trustedProxy" access="private" returntype="string" output="false"
        hint="TRUSTED_PROXY: cloudflare or digitalocean when every request reaches the app through that proxy, which sets its client headers itself; else empty.">
        <cfreturn lCase(trim(server.system.environment.TRUSTED_PROXY ?: "")) />
    </cffunction>


    <cffunction name="describeDevice" access="private" returntype="string" output="false"
        hint="A browser and system from a user agent, e.g. 'Chrome on macOS'.">
        <cfargument name="userAgent" type="string" required="true" />

        <cfset var ua = arguments.userAgent />
        <cfset var browser = "A browser" />
        <cfif findNoCase("Edg/", ua)><cfset browser = "Edge" />
        <cfelseif findNoCase("OPR/", ua)><cfset browser = "Opera" />
        <cfelseif findNoCase("SamsungBrowser", ua)><cfset browser = "Samsung Internet" />
        <cfelseif findNoCase("Firefox/", ua) OR findNoCase("FxiOS", ua)><cfset browser = "Firefox" />
        <cfelseif findNoCase("Chrome/", ua) OR findNoCase("CriOS", ua)><cfset browser = "Chrome" />
        <cfelseif findNoCase("Safari/", ua)><cfset browser = "Safari" />
        </cfif>

        <cfset var system = "" />
        <cfif findNoCase("iPhone", ua)><cfset system = "iPhone" />
        <cfelseif findNoCase("iPad", ua)><cfset system = "iPad" />
        <cfelseif findNoCase("Android", ua)><cfset system = "Android" />
        <cfelseif findNoCase("Mac OS X", ua) OR findNoCase("Macintosh", ua)><cfset system = "macOS" />
        <cfelseif findNoCase("Windows", ua)><cfset system = "Windows" />
        <cfelseif findNoCase("CrOS", ua)><cfset system = "ChromeOS" />
        <cfelseif findNoCase("Linux", ua)><cfset system = "Linux" />
        </cfif>

        <cfreturn len(system) ? browser & " on " & system : browser />
    </cffunction>


    <cffunction name="ago" access="private" returntype="string" output="false">
        <cfargument name="seconds" type="numeric" required="true" />
        <cfif arguments.seconds LT 60><cfreturn "Just now" /></cfif>
        <cfset var minutes = int(arguments.seconds / 60) />
        <cfreturn minutes EQ 1 ? "1 minute ago" : minutes & " minutes ago" />
    </cffunction>


    <cffunction name="appName" access="private" returntype="string" output="false">
        <cfreturn application.app_name ?: "hub" />
    </cffunction>


    <cffunction name="projectTitle" access="private" returntype="string" output="false">
        <cfreturn application.project_title ?: "Moopa" />
    </cffunction>


    <cffunction name="isDevelopment" access="private" returntype="boolean" output="false">
        <cfreturn (server.system.environment.APP_ENVIRONMENT ?: "production") EQ "development" />
    </cffunction>

</cfcomponent>
