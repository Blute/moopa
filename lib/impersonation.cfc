<cfcomponent displayname="impersonation" output="false"
    hint="Impersonation links (docs/impersonation.md): System → Impersonation makes one with createGrant(), and a project's /auth/impersonate/ route hands its get and post to get() and post(). Opening the link changes nothing; only its button (a POST) signs in, as link previews and mail scanners open links before the person does. The grant itself is lib.login_grant's, of kind impersonation.">

    <cfset variables.PATH = "/auth/impersonate/" />
    <cfset variables.KIND = "impersonation" />
    <cfset variables.SYSTEM_ROUTE = "/sysadmin/impersonation/" />

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>


    <!--- ===================================================================================== --->
    <!--- Making a link                                                                          --->
    <!--- ===================================================================================== --->

    <cffunction name="createGrant" access="public" returntype="struct" output="false"
        hint="A new impersonation link for the signed-in profile to sign in as target_profile_id: { success, url }. Throws unless they may use System → Impersonation's create_grant and the target can sign in and isn't one of the hub's sysadmins. The link is on the target's app's address.">
        <cfargument name="target_profile_id" type="string" required="true" />

        <!--- Whoever may use the System page's create_grant; sysadmins always may --->
        <cfset var mooRoute = application.lib.db.getService("moo_route") />
        <cfset var routeData = mooRoute.parseRoute(variables.SYSTEM_ROUTE) />
        <cfif structIsEmpty(routeData.stRoute ?: {})>
            <cfthrow type="moopa.impersonation.routeMissing" message="The impersonation System page is not registered. Re-initialise the application." />
        </cfif>
        <cfif NOT mooRoute.checkAccess(route_data = routeData, endpoint = "create_grant", sysadmin_has_access = true)>
            <cfthrow type="moopa.impersonation.denied" message="You do not have permission to impersonate users." />
        </cfif>

        <cfset var target = application.lib.db.read(
            table_name = "moo_profile",
            id = arguments.target_profile_id,
            field_list = "id,full_name,email,can_login,app_name",
            returnFormat = "cfml"
        ) />
        <cfif NOT len(target.id ?: "")>
            <cfthrow type="moopa.impersonation.target" message="That profile doesn't exist." />
        </cfif>
        <cfif (target.can_login ?: false) NEQ true>
            <cfthrow type="moopa.impersonation.target" message="That profile can't sign in." />
        </cfif>
        <cfif (target.app_name ?: "") EQ "hub" AND listFindNoCase(application.lib.signin.sysadminEmails(), trim(target.email ?: ""))>
            <cfthrow type="moopa.impersonation.target" message="The hub's sysadmins can't be impersonated." />
        </cfif>

        <cfset var grant = application.lib.login_grant.issue(
            kind = variables.KIND,
            target_profile_id = target.id,
            impersonator_profile_id = session.auth.profile.id
        ) />

        <cfreturn {
            success = true,
            url = appBaseUrl(len(target.app_name ?: "") ? target.app_name : (application.app_name ?: "")) & variables.PATH & "?token=" & encodeForURL(grant.token)
        } />
    </cffunction>


    <!--- ===================================================================================== --->
    <!--- Opening a link                                                                         --->
    <!--- ===================================================================================== --->

    <cffunction name="get" access="public" returntype="string" output="false"
        hint="GET /auth/impersonate/?token=: who the link signs in as, and the button that does it. Changes nothing.">
        <cfset var token = isSimpleValue(url.token ?: "") ? trim(url.token ?: "") : "" />
        <cfif NOT len(token)>
            <cfreturn noTokenPage() />
        </cfif>

        <cfset var grant = application.lib.login_grant.peek(token = token, kind = variables.KIND) />
        <cfif NOT grant.live>
            <cfreturn unusablePage() />
        </cfif>

        <cfset var target = profileName(grant.target_profile_id) />
        <cfset var impersonator = profileName(grant.impersonator_profile_id) />
        <cfset var body = "" />
        <cfsavecontent variable="body"><cfoutput>
            <div class="auth-body">
                <form method="post" action="#variables.PATH#" data-once>
                    <input type="hidden" name="token" value="#encodeForHTMLAttribute(token)#">
                    <button type="submit" class="btn btn-primary btn-block" autofocus>Continue as #encodeForHTML(target)# <i class="fa-solid fa-arrow-right"></i></button>
                </form>
            </div>
            <!--- Send once: a second press would find the link used and show the expired page over the signed-in one. A page restored from the back-forward cache reloads, as sign-in's do. --->
            <script>
                document.querySelectorAll('form[data-once]').forEach(function (form) {
                    form.addEventListener('submit', function (event) {
                        if (form.dataset.sent) { event.preventDefault(); return; }
                        form.dataset.sent = '1';
                        form.querySelector('button').setAttribute('aria-disabled', 'true');
                    });
                });
                // Back to a page the browser kept: show it fresh, not mid-send, so its button works (and says if the link is spent)
                window.addEventListener('pageshow', function (event) { if (event.persisted) window.location.reload(); });
            </script>
        </cfoutput></cfsavecontent>
        <cfreturn page(
            "Sign in as #target#",
            head(
                heading = "Sign in as " & encodeForHTML(target),
                lead = "<strong>" & encodeForHTML(impersonator) & "</strong> made this link to sign you in as <strong>" & encodeForHTML(target) & "</strong>. It works once. Closing the browser, or ending the session, signs you out.",
                icon = "fa-user-secret"
            ) & body
        ) />
    </cffunction>


    <cffunction name="post" access="public" returntype="string" output="false"
        hint="POST /auth/impersonate/ (token): use the grant, sign this browser in as its target, and go to the target's app's home. A link that's unknown, used or expired gets a page saying so; any other failure is Moopa's error handling's (docs/errors.md).">
        <cfset var token = isSimpleValue(request.data.token ?: "") ? trim(request.data.token ?: "") : "" />
        <cfif NOT len(token)>
            <cfreturn noTokenPage() />
        </cfif>

        <cftry>
            <cfset var grant = application.lib.login_grant.consume(token = token, kind = variables.KIND) />
            <cfcatch type="loginGrant.unusable">
                <cfreturn unusablePage() />
            </cfcatch>
        </cftry>

        <!--- After the sign-in, which starts session.auth afresh. The layout's banner reads these. --->
        <cfset var impersonator = application.lib.db.read(
            table_name = "moo_profile",
            id = grant.impersonator_profile_id,
            field_list = "id,full_name,email,mobile",
            returnFormat = "cfml"
        ) />
        <cfset session.auth.is_impersonating = true />
        <cfset session.auth.impersonator = {
            id = impersonator.id ?: grant.impersonator_profile_id,
            full_name = impersonator.full_name ?: "",
            email = impersonator.email ?: "",
            mobile = impersonator.mobile ?: ""
        } />

        <cfset var appName = len(grant.app_name) ? grant.app_name : (application.app_name ?: "") />
        <cfset var home = structKeyExists(application, "app_homes") AND isStruct(application.app_homes) AND isSimpleValue(application.app_homes[appName] ?: {}) AND len(application.app_homes[appName] ?: "")
            ? application.app_homes[appName] : "/" />
        <cflocation url="#home#" addtoken="false" />
    </cffunction>


    <!--- ===================================================================================== --->
    <!--- During a session                                                                       --->
    <!--- ===================================================================================== --->

    <cffunction name="isImpersonating" access="public" returntype="boolean" output="false"
        hint="Whether this session was signed in by an impersonation link.">
        <cfreturn (session.auth.is_impersonating ?: false) EQ true />
    </cffunction>


    <cffunction name="impersonator" access="public" returntype="struct" output="false"
        hint="Who is impersonating in this session: { id, full_name, email, mobile }, or {} when nobody is.">
        <cfreturn isImpersonating() ? (session.auth.impersonator ?: {}) : {} />
    </cffunction>


    <!--- ===================================================================================== --->
    <!--- Pages                                                                                  --->
    <!--- ===================================================================================== --->

    <cffunction name="noTokenPage" access="private" returntype="string" output="false">
        <cfreturn page("Invalid link", head(
            heading = "This link isn't complete",
            lead = "It has no token. Copy the whole link, or ask for a new one.",
            icon = "fa-link-slash",
            tone = "is-danger"
        ) & homeLink()) />
    </cffunction>


    <cffunction name="unusablePage" access="private" returntype="string" output="false">
        <cfreturn page("Link expired or used", head(
            heading = "This link has expired or been used",
            lead = "An impersonation link works once, within 5 minutes of being made. Ask for a new one.",
            icon = "fa-clock"
        ) & homeLink()) />
    </cffunction>


    <cffunction name="homeLink" access="private" returntype="string" output="false">
        <cfreturn '<div class="auth-body"><a href="/" class="btn btn-block">Go home</a></div>' />
    </cffunction>


    <cffunction name="head" access="private" returntype="string" output="false"
        hint="A page's head, in the sign-in pages' style. heading and lead are HTML: encode what they carry.">
        <cfargument name="heading" type="string" required="true" />
        <cfargument name="lead" type="string" required="true" />
        <cfargument name="icon" type="string" required="true" />
        <cfargument name="tone" type="string" default="" hint="Empty or is-danger." />

        <cfreturn '<div class="auth-head"><span class="auth-icon #arguments.tone#"><i class="fa-solid #arguments.icon#"></i></span>'
            & '<h1>#arguments.heading#</h1><p class="auth-lead">#arguments.lead#</p></div>' />
    </cffunction>


    <cffunction name="page" access="private" returntype="string" output="false"
        hint="A page of its own in moopa_bare's split layout, as the sign-in pages are. Its address carries a live token: never cached, indexed or sent on as a referrer.">
        <cfargument name="title" type="string" required="true" />
        <cfargument name="body" type="string" required="true" />

        <cfset var html = "" />
        <cfheader name="Cache-Control" value="no-store" />
        <cfheader name="X-Robots-Tag" value="noindex, nofollow" />
        <cfheader name="Referrer-Policy" value="no-referrer" />
        <cfsavecontent variable="html"><cfmodule template="/moopa/tags/moopa_bare.cfm" title="#arguments.title#" welcome="Impersonation" welcomeText="See the app as someone else sees it, from a link made on System, Impersonation."><cfoutput><div class="auth-panel">#arguments.body#</div></cfoutput></cfmodule></cfsavecontent>
        <cfreturn html />
    </cffunction>


    <cffunction name="profileName" access="private" returntype="string" output="false">
        <cfargument name="profile_id" type="string" required="true" />

        <cfif NOT len(arguments.profile_id)>
            <cfreturn "someone" />
        </cfif>
        <cfset var profile = application.lib.db.read(
            table_name = "moo_profile",
            id = arguments.profile_id,
            field_list = "id,full_name",
            returnFormat = "cfml"
        ) />
        <cfreturn len(trim(profile.full_name ?: "")) ? trim(profile.full_name) : "someone" />
    </cffunction>


    <cffunction name="appBaseUrl" access="private" returntype="string" output="false"
        hint="An app's address without a trailing slash, by the same rule as sign-in links (docs/signin.md, BASE_URL): the app's own in application.app_base_urls, else BASE_URL. Never the request's Host header.">
        <cfargument name="app_name" type="string" required="true" />

        <cfset var base = "" />
        <cfif len(arguments.app_name) AND structKeyExists(application, "app_base_urls") AND isStruct(application.app_base_urls) AND isSimpleValue(application.app_base_urls[arguments.app_name] ?: {})>
            <cfset base = trim(application.app_base_urls[arguments.app_name]) />
        </cfif>
        <cfif NOT len(base)>
            <cfset base = trim(server.system.environment.BASE_URL ?: "") />
        </cfif>
        <cfif NOT len(base)>
            <cfthrow type="moopa.impersonation.config" message="BASE_URL must be set for impersonation links." />
        </cfif>
        <cfreturn reReplace(base, "/+$", "") />
    </cffunction>

</cfcomponent>
