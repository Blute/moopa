<!---
Render a content block once per request.

Usage:
<cf_once id="my_script" position="body">
    <script>...</script>
</cf_once>

position: head, body, or inline (default)
--->

<cfif !structKeyExists(attributes, "id")>
    <cfthrow message="The 'id' attribute is required.">
</cfif>

<cfparam name="attributes.content" default="" />
<cfparam name="attributes.position" default="inline" hint="head, inline, body" />

<cfif thistag.executionmode EQ "start">

    <cfif !structKeyExists(request, "code_block_rendered")>
        <cfset request.code_block_rendered = {} />
    </cfif>

    <cfif structKeyExists(request.code_block_rendered, attributes.id)>
        <cfexit>
    </cfif>

    <cfset request.code_block_rendered[attributes.id] = true />

<cfelseif thistag.executionmode EQ "end">

    <cfif len(trim(thisTag.generatedContent))>
        <cfset attributes.content = trim(thisTag.generatedContent) />
        <cfset thisTag.generatedContent = "" />
    </cfif>

    <cfoutput>
        <cfswitch expression="#attributes.position#">
            <cfcase value="head">
                <cfhtmlhead>#attributes.content#</cfhtmlhead>
            </cfcase>
            <cfcase value="body">
                <cfhtmlbody>#attributes.content#</cfhtmlbody>
            </cfcase>
            <cfdefaultcase>
                #attributes.content#
            </cfdefaultcase>
        </cfswitch>
    </cfoutput>

</cfif>
