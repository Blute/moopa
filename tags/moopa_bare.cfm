<!---
    moopa_bare — a page of its own, outside moopa_layout: the project's logo, then the tag's body, centred,
    in Moopa's design with the project's theme. The status pages (moopa_status) and the sign-in pages
    (lib/signin.cfc) render in it.

    It reads no session or database, so it renders when those are what failed. It writes the whole
    response: call it after any cfheader, and nothing written before it is kept.

    <cfmodule template="/moopa/tags/moopa_bare.cfm" title="Sign in">…</cfmodule>

    Attributes
      title     the page's title, before the project's in the browser tab
      scripts   true: load moopa.js and Alpine, for a page that needs them (default false)
--->
<cfif thisTag.executionMode EQ "start"><cfexit method="exitTemplate"></cfif>

<cfparam name="attributes.title" default="" type="string">
<cfparam name="attributes.scripts" default="false" type="boolean">

<cfset bareBody = thisTag.generatedContent />
<cfset thisTag.generatedContent = "" />

<cfset projectTitle = application.project_title ?: "Moopa" />
<cfset brandLogo = structKeyExists(application, "moopa_theme") AND isStruct(application.moopa_theme) AND structKeyExists(application.moopa_theme, "logo") ? application.moopa_theme.logo : "" />

<!--- The theme, if it can be read; Moopa's stylesheet on its own if not --->
<cftry>
    <cfset bareStyles = application.lib.system.stylesheets() />
    <cfcatch>
        <cfset bareStyles = '<link rel="stylesheet" href="/_moopa/static/moopa.css">' />
    </cfcatch>
</cftry>

<cfcontent type="text/html; charset=utf-8" reset="true" />
<cfoutput><!doctype html>
<html lang="en">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex">
    <title><cfif len(attributes.title)>#encodeForHTML(attributes.title)# - </cfif>#encodeForHTML(projectTitle)#</title>
    #bareStyles#
    <cfif attributes.scripts>
        <script src="#application.lib.system.staticUrl('moopa.js')#"></script>
        <script defer src="#application.lib.system.staticUrl('vendor/alpine-3.17.5/alpine.min.js')#"></script>
    </cfif>
</head>
<body>
<main class="status-page">
    <a class="status-brand" href="/"><cfif len(brandLogo)><img src="#encodeForHTMLAttribute(brandLogo)#" alt="#encodeForHTMLAttribute(projectTitle)#"><cfelse>#encodeForHTML(projectTitle)#</cfif></a>
    #bareBody#
</main>
</body>
</html></cfoutput>
