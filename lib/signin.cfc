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
            <cfset sendLink(address, link, describeDevice(userAgent), place, requestRef(local.qRequest[1].id)) />
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
    <!--- Each is moopa_bare's split layout: a brand panel ("Welcome back"), then the step: a head
          (step, heading, a line under it) and its body. On a phone the head sits on the brand colour
          and the body is a sheet below it. --->

    <cffunction name="emailPage" access="private" returntype="string" output="false">
        <cfargument name="email" type="string" default="" />
        <cfargument name="error" type="string" default="" />

        <cfset var body = "" />
        <cfsavecontent variable="body"><cfoutput>
            <form class="auth-body" method="post" action="#variables.PATH#">
                <input type="hidden" name="action" value="start">
                <div class="field">
                    <label class="label" for="signin-email">Email</label>
                    <input id="signin-email" class="input<cfif len(arguments.error)> is-invalid</cfif>" type="email" name="email" value="#encodeForHTMLAttribute(arguments.email)#" autocomplete="email" autofocus required>
                    <cfif len(arguments.error)><p class="field-error">#encodeForHTML(arguments.error)#</p></cfif>
                </div>
                <button type="submit" class="btn btn-primary btn-block"><i class="fa-solid fa-envelope"></i> Email me a link</button>
            </form>
        </cfoutput></cfsavecontent>
        <cfreturn page("Sign in", head(1, "Sign in to " & encodeForHTML(projectTitle()), "Enter your email and we'll send you a link to sign in with.") & body) />
    </cffunction>


    <cffunction name="waitingPage" access="private" returntype="string" output="false">
        <cfset var body = "" />
        <cfsavecontent variable="body"><cfoutput>
            <div class="auth-body">
                <div class="auth-wait" role="status">
                    <span class="auth-spinner" aria-hidden="true"></span>
                    <div>Waiting for approval<small>This page moves on by itself. The email's subject ends in <strong class="signin-ref">#requestRef(session.signin.id)#</strong>.</small></div>
                </div>
                <cfif len(session.signin.dev_link)>
                    <div class="alert alert-info"><i class="fa-solid fa-code"></i><div>Development: <a href="#encodeForHTMLAttribute(session.signin.dev_link)#" target="_blank" rel="noopener">open the emailed link</a></div></div>
                </cfif>
                <div class="auth-links">
                    #restartForm("Use a different email")#
                    <form method="post" action="#variables.PATH#">
                        <input type="hidden" name="action" value="start">
                        <input type="hidden" name="email" value="#encodeForHTMLAttribute(session.signin.email)#">
                        <button type="submit" class="btn-link">Send a new link</button>
                    </form>
                </div>
            </div>
            <script>
                // Ask whether the request has moved on, and when it has, reload so the server shows the next
                // step. Every 2 seconds for the first minute (approvals usually come quickly), every 5 to five
                // minutes, then every 15 until the request ends: a tab left open on an email nobody will approve
                // (it may have no account, and the page can't say so) asks rarely. Not while the tab is hidden
                // (the database can rest while the person is off in their email); straight away when it's
                // shown again.
                (function () {
                    const opened = Date.now();
                    let busy = false;
                    let timer = null;
                    async function check() {
                        if (busy) return;
                        busy = true;
                        try {
                            const r = await fetch('#variables.PATH#', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Fetch-Request': 'true' }, body: JSON.stringify({ action: 'status' }), credentials: 'same-origin' });
                            const s = (await r.json()).status;
                            if (s && s !== 'pending') window.location.replace('#variables.PATH#');
                        } catch (e) {} finally { busy = false; }
                    }
                    function schedule() {
                        const seconds = (Date.now() - opened) / 1000;
                        clearTimeout(timer);
                        timer = setTimeout(tick, seconds < 60 ? 2000 : seconds < 300 ? 5000 : 15000);
                    }
                    async function tick() {
                        timer = null;
                        if (document.hidden) return;
                        await check();
                        schedule();
                    }
                    schedule();
                    document.addEventListener('visibilitychange', () => {
                        if (document.hidden) return;
                        check();
                        schedule();
                    });
                })();
            </script>
        </cfoutput></cfsavecontent>
        <cfreturn page("Check your inbox", head(2, "Check your inbox", "If <strong>" & encodeForHTML(session.signin.email) & "</strong> can sign in, we've sent it a link. Open it on any device, your phone is fine, and approve the request.") & body) />
    </cffunction>


    <cffunction name="approvedPage" access="private" returntype="string" output="false">
        <cfset var body = "" />
        <cfsavecontent variable="body"><cfoutput>
            <div class="auth-body">
                <form method="post" action="#variables.PATH#">
                    <input type="hidden" name="action" value="continue">
                    <button type="submit" class="btn btn-primary btn-block" autofocus>Continue to #encodeForHTML(projectTitle())# <i class="fa-solid fa-arrow-right"></i></button>
                </form>
                <div class="auth-links">#restartForm("Not you? Start again")#</div>
            </div>
        </cfoutput></cfsavecontent>
        <cfreturn page("You're approved", head(3, "You're approved", "The request for <strong>" & encodeForHTML(session.signin.email) & "</strong> was approved from the emailed link.", "fa-check") & body) />
    </cffunction>


    <cffunction name="endedPage" access="private" returntype="string" output="false"
        hint="The asking browser's request is over without signing in: denied or expired.">
        <cfargument name="why" type="string" required="true" />

        <cfset var denied = arguments.why EQ "denied" />
        <cfset var heading = denied ? "Request declined" : "Link expired" />
        <cfset var message = denied ? "The request was turned down from the emailed link." : "Links last " & variables.TTL_MINUTES & " minutes. Ask for a new one." />
        <cfset var body = "" />
        <cfsavecontent variable="body"><cfoutput>
            <form class="auth-body" method="post" action="#variables.PATH#">
                <input type="hidden" name="action" value="restart">
                <button type="submit" class="btn btn-primary btn-block">Start again</button>
            </form>
        </cfoutput></cfsavecontent>
        <cfreturn page(heading, head(0, heading, message, denied ? "fa-ban" : "fa-clock", "is-danger") & body) />
    </cffunction>


    <cffunction name="approvePage" access="private" returntype="string" output="false"
        hint="What an emailed link opens: the waiting request, to approve or turn down. Opening it changes nothing.">
        <cfargument name="token" type="string" required="true" />

        <cfquery name="local.qRequest" returntype="array">
            SELECT id::text AS id, email, status, expires_at > now() AS live, request_user_agent, request_place,
                   floor(extract(epoch FROM now() - created_at))::int AS age_seconds,
                   ceil(extract(epoch FROM expires_at - now()) / 60)::int AS minutes_left
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
            <cfreturn linkOverPage("This request is done: the link has been used.") />
        </cfif>
        <cfif NOT r.live>
            <cfreturn linkOverPage("This link has expired. Links last " & variables.TTL_MINUTES & " minutes; ask for a new one on the device you're signing in on.") />
        </cfif>

        <cfset var remaining = r.minutes_left LTE 1 ? "under a minute" : r.minutes_left & " minutes" />
        <cfset var body = "" />
        <cfsavecontent variable="body"><cfoutput>
            <form class="auth-body" method="post" action="#variables.PATH#">
                <dl class="kv-grid auth-facts">
                    <dt class="kv-label">Email</dt><dd class="kv-value">#encodeForHTML(r.email)#</dd>
                    <dt class="kv-label">Device</dt><dd class="kv-value">#encodeForHTML(describeDevice(r.request_user_agent ?: ""))#</dd>
                    <cfif len(r.request_place ?: "")><dt class="kv-label">Near</dt><dd class="kv-value">#encodeForHTML(r.request_place)#</dd></cfif>
                    <dt class="kv-label">When</dt><dd class="kv-value">#ago(r.age_seconds)#</dd>
                    <dt class="kv-label">Request</dt><dd class="kv-value signin-ref">#requestRef(r.id)#</dd>
                </dl>
                <input type="hidden" name="t" value="#encodeForHTMLAttribute(arguments.token)#">
                <div class="auth-actions">
                    <button type="submit" name="action" value="approve" class="btn btn-primary btn-block"><i class="fa-solid fa-check"></i> Approve</button>
                    <button type="submit" name="action" value="deny" class="btn btn-block">Not me</button>
                </div>
                <p class="auth-note">This link expires in #remaining#.</p>
            </form>
        </cfoutput></cfsavecontent>
        <cfreturn page("Approve request", head(0, "Was this you?", "Someone is signing in to " & encodeForHTML(projectTitle()) & " as you. Approve it only if it was you.") & body) />
    </cffunction>


    <cffunction name="decidedPage" access="private" returntype="string" output="false"
        hint="Shown where the link was opened, once the request is approved or turned down.">
        <cfargument name="decision" type="string" required="true" />

        <cfset var approved = arguments.decision EQ "approved" />
        <cfset var heading = approved ? "Approved" : "Request declined" />
        <cfset var message = approved
            ? "Your computer is signing in now. Head back to it: you can close this page."
            : "Nobody was signed in. If you didn't ask to sign in, you can ignore this: your account is unchanged." />
        <cfreturn page(heading, head(0, heading, message, approved ? "fa-check" : "fa-ban", approved ? "" : "is-danger")) />
    </cffunction>


    <cffunction name="linkOverPage" access="private" returntype="string" output="false">
        <cfargument name="message" type="string" required="true" />
        <cfreturn page("Link can't be used", head(0, "Link can't be used", encodeForHTML(arguments.message), "fa-link-slash", "is-danger")) />
    </cffunction>


    <cffunction name="head" access="private" returntype="string" output="false"
        hint="A step's head. heading and lead are HTML: encode what they carry.">
        <cfargument name="step" type="numeric" required="true" hint="1 to 3 on the asking browser's way through; 0 for none." />
        <cfargument name="heading" type="string" required="true" />
        <cfargument name="lead" type="string" required="true" />
        <cfargument name="icon" type="string" default="" hint="A result's icon, e.g. fa-check." />
        <cfargument name="tone" type="string" default="" hint="Empty or is-danger." />

        <cfset var html = '<div class="auth-head">' />
        <cfif len(arguments.icon)>
            <cfset html &= '<span class="auth-icon #arguments.tone#"><i class="fa-solid #arguments.icon#"></i></span>' />
        </cfif>
        <cfif arguments.step>
            <cfset html &= '<p class="auth-step">Step #arguments.step# of 3</p>' />
        </cfif>
        <cfreturn html & '<h1>#arguments.heading#</h1><p class="auth-lead">#arguments.lead#</p></div>' />
    </cffunction>


    <cffunction name="restartForm" access="private" returntype="string" output="false">
        <cfargument name="label" type="string" required="true" />
        <cfreturn '<form method="post" action="#variables.PATH#"><input type="hidden" name="action" value="restart"><button type="submit" class="btn-link">#encodeForHTML(arguments.label)#</button></form>' />
    </cffunction>


    <cffunction name="page" access="private" returntype="string" output="false"
        hint="A sign-in page: moopa_bare's split layout with this step. Never cached: each is one person's step.">
        <cfargument name="title" type="string" required="true" />
        <cfargument name="body" type="string" required="true" />

        <cfset var html = "" />
        <cfheader name="Cache-Control" value="no-store" />
        <cfsavecontent variable="html"><cfmodule template="/moopa/tags/moopa_bare.cfm" title="#arguments.title#" welcome="Welcome back" welcomeText="No passwords to remember. We email you a link, and you approve it from wherever you read your email."><cfoutput><div class="auth-panel">#arguments.body#</div></cfoutput></cfmodule></cfsavecontent>
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
        <cfargument name="ref" type="string" required="true" hint="requestRef(): in the subject, so each email is its own thread." />

        <cfset var title = projectTitle() />
        <cfset var muted = "color:##6b7280;" />
        <cfset var facts = [ ["Email", arguments.to], ["Device", arguments.device] ] />
        <cfif len(arguments.place)><cfset arrayAppend(facts, ["Near", arguments.place]) /></cfif>
        <cfset arrayAppend(facts, ["Request", arguments.ref]) />

        <cfset var content = "" />
        <cfsavecontent variable="content"><cfoutput>
<cfif len(brandLogoUrl())><table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 28px;"><tr><td style="padding:10px 16px;border-radius:10px;background:##1f2534;"><img src="#encodeForHTMLAttribute(brandLogoUrl())#" alt="#encodeForHTMLAttribute(title)#" height="32" style="display:block;height:32px;width:auto;border:0;color:##ffffff;font-weight:600;"></td></tr></table></cfif>
<h1>Sign in to #encodeForHTML(title)#</h1>
<p style="#muted#">Someone asked to sign in as you. If it was you, review the request and approve it.</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin:0 0 24px;border:1px solid ##e5e7eb;border-radius:8px;background:##f9fafb;">
    <cfloop array="#facts#" item="local.fact">
    <tr>
        <td style="padding:8px 16px;width:90px;#muted#font-size:12px;letter-spacing:0.06em;text-transform:uppercase;vertical-align:baseline;">#local.fact[1]#</td>
        <td style="padding:8px 16px 8px 0;font-size:15px;vertical-align:baseline;word-break:break-word;">#encodeForHTML(local.fact[2])#</td>
    </tr>
    </cfloop>
</table>
<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 24px;"><tr><td style="border-radius:8px;background:##1f2534;"><a href="#encodeForHTMLAttribute(arguments.link)#" style="display:inline-block;padding:12px 22px;color:##ffffff;font-weight:600;text-decoration:none;">Review request</a></td></tr></table>
<p style="#muted#font-size:14px;">The link works for #variables.TTL_MINUTES# minutes, on any device. Opening it doesn't sign anyone in: only Approve does.</p>
<p style="#muted#font-size:14px;margin:0;">Didn't ask to sign in? Ignore this email, or open it and choose Not me.</p>
        </cfoutput></cfsavecontent>
        <cfset var html = application.lib.email.layout(content = content) />

        <cfset var text = "Sign in to #title#" & chr(10) & chr(10)
            & "Someone asked to sign in as you. If it was you, open this link and approve it:" & chr(10) & chr(10)
            & arguments.link & chr(10) & chr(10) />
        <cfloop array="#facts#" item="local.fact">
            <cfset text &= local.fact[1] & ": " & local.fact[2] & chr(10) />
        </cfloop>
        <cfset text &= chr(10) & "The link works for #variables.TTL_MINUTES# minutes, on any device. Opening it doesn't sign anyone in: only Approve does." & chr(10)
            & "Didn't ask to sign in? Ignore this email, or open it and choose Not me." />

        <cftry>
            <cfset var result = application.lib.email.send(to = arguments.to, subject = "Sign in to #title# (request #arguments.ref#)", html = html, text = text) />
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


    <cffunction name="brandLogoUrl" access="private" returntype="string" output="false"
        hint="The project's logo (application.moopa_theme.logo, made for a dark background) as an absolute URL for email, or empty.">
        <cfset var logo = structKeyExists(application, "moopa_theme") AND isStruct(application.moopa_theme) ? (application.moopa_theme.logo ?: "") : "" />
        <cfif NOT len(logo) OR reFindNoCase("^https?://", logo)>
            <cfreturn logo />
        </cfif>
        <cfset var base = reReplace(trim(server.system.environment.BASE_URL ?: ""), "/+$", "") />
        <cfreturn len(base) AND left(logo, 1) EQ "/" ? base & logo : "" />
    </cffunction>


    <cffunction name="requestRef" access="private" returntype="string" output="false"
        hint="A short reference for a request, shown on the waiting page, in the email's subject and on the approve page, so the three can be matched.">
        <cfargument name="id" type="string" required="true" />
        <cfreturn uCase(left(hash(arguments.id, "SHA-256"), 4)) />
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
