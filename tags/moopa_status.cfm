<!---
    moopa_status — the page for a status code (404, 403, 500), in Moopa's design with the project's theme.

    <cfmodule template="/moopa/tags/moopa_status.cfm" code="404" />

    It renders in moopa_bare, a page of its own outside moopa_layout: the 500 page may be showing because the
    database or the session failed, and moopa_bare reads neither. It sets the response status.

    Attributes
      code      404, 403 or 500 (default 404)
      title     the heading (default: the code's own)
      message   the line under it (default: the code's own)
      route     the page that was asked for: 403 shows it, and 500's "Try again" goes back to it
    The tag's body, if any, shows under the buttons (the 500 page's debug details in development).
--->
<cfif thisTag.executionMode EQ "start" AND thisTag.hasEndTag><cfexit method="exitTemplate"></cfif>

<cfparam name="attributes.code" default="404" type="numeric">
<cfparam name="attributes.title" default="" type="string">
<cfparam name="attributes.message" default="" type="string">
<cfparam name="attributes.route" default="" type="string">

<cfset statusBody = thisTag.hasEndTag ? thisTag.generatedContent : "" />
<cfset thisTag.generatedContent = "" />

<cfset statuses = {
    "403": { text: "Forbidden", title: "You don't have access", message: "Your account can't open this page. Ask an administrator for access, quoting its address." },
    "404": { text: "Not Found", title: "Page not found", message: "The address may be mistyped, or the page has moved or no longer exists." },
    "500": { text: "Server Error", title: "Something went wrong", message: "The error has been logged and an administrator told. Try again, or come back in a little while." }
} />
<cfset status = structKeyExists(statuses, attributes.code) ? statuses[attributes.code] : statuses["404"] />
<cfset heading = len(attributes.title) ? attributes.title : status.title />
<cfset message = len(attributes.message) ? attributes.message : status.message />
<!--- Only a path on this site goes in a link: one leading slash, no backslash (browsers read "/\" as "//") or control character; as application.cfc's _localPath --->
<cfset retryRoute = trim(attributes.route) />
<cfif left(retryRoute, 1) NEQ "/"
        OR left(retryRoute, 2) EQ "//"
        OR find("\", retryRoute)
        OR reFind("[\x00-\x1F\x7F]", retryRoute)>
    <cfset retryRoute = "/" />
</cfif>
<cfheader statuscode="#attributes.code#" statustext="#status.text#" />
<cfmodule template="/moopa/tags/moopa_bare.cfm" title="#heading#">
<cfoutput>
    <div class="status-page-body">
        <p class="status-code">#attributes.code#</p>
        <h1>#encodeForHTML(heading)#</h1>
        <p class="status-message">#encodeForHTML(message)#</p>
        <cfif attributes.code EQ 403 AND len(attributes.route)><code class="code-inline">#encodeForHTML(attributes.route)#</code></cfif>
        <div class="cluster status-actions">
            <cfif attributes.code EQ 500>
                <a class="btn btn-primary" href="#encodeForHTMLAttribute(retryRoute)#"><i class="fa-solid fa-rotate-right"></i> Try again</a>
                <a class="btn" href="/"><i class="fa-solid fa-house"></i> Home</a>
            <cfelse>
                <a class="btn btn-primary" href="/"><i class="fa-solid fa-house"></i> Home</a>
                <button type="button" class="btn" onclick="history.back()"><i class="fa-solid fa-arrow-left"></i> Go back</button>
            </cfif>
        </div>
    </div>
    <cfif len(trim(statusBody))><div class="status-detail">#statusBody#</div></cfif>
</cfoutput>
</cfmodule>
