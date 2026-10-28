<cfcomponent displayname="Email" output="false" hint="Transactional email through Cloudflare Email Sending's REST API. Configured by CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_EMAIL_TOKEN and EMAIL_FROM. Outside production every message goes to SYSADMIN_EMAIL instead of its recipients.">

    <!---
        Cloudflare Email Sending, REST: POST /accounts/{account_id}/email/sending/send.

        Environment:
          CLOUDFLARE_ACCOUNT_ID   the Cloudflare account that owns the sending domain
          CLOUDFLARE_EMAIL_TOKEN  an API token with the Email Sending Write permission
          EMAIL_FROM              default From address; must be on an onboarded sending domain
          EMAIL_FROM_NAME         optional display name for EMAIL_FROM
          APP_ENVIRONMENT         anything but "production" redirects every message (below)
          SYSADMIN_EMAIL          where redirected messages go (comma-separated)

        Outside production a message goes only to SYSADMIN_EMAIL, never to its own to/cc/bcc, and its sender's
        display name says which environment sent it, so a copy is never mistaken for the real one. The result
        reports the addresses actually used.

        Limits: 50 recipients across to, cc and bcc; 5 MiB per message including attachments.
    --->

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfset variables.accountId = trim(server.system.environment.CLOUDFLARE_ACCOUNT_ID ?: "") />
        <cfset variables.token = trim(server.system.environment.CLOUDFLARE_EMAIL_TOKEN ?: "") />
        <cfset variables.fromAddress = trim(server.system.environment.EMAIL_FROM ?: "") />
        <cfset variables.fromName = trim(server.system.environment.EMAIL_FROM_NAME ?: "") />
        <cfset variables.environment = server.system.environment.APP_ENVIRONMENT ?: "production" />
        <cfset variables.isProduction = variables.environment EQ "production" />
        <cfset variables.sysadminEmail = trim(server.system.environment.SYSADMIN_EMAIL ?: "") />
        <cfreturn this />
    </cffunction>

    <cffunction name="isConfigured" access="public" returntype="boolean" output="false">
        <cfreturn len(variables.accountId) AND len(variables.token) AND len(variables.fromAddress) />
    </cffunction>

    <cffunction name="send" access="public" returntype="struct" output="false" hint="Send one message. Returns { success, status, errors, delivered, queued, bounced, to, cc, from, redirected }.">
        <cfargument name="to" type="string" required="true" hint="Comma-separated addresses." />
        <cfargument name="subject" type="string" required="true" />
        <cfargument name="html" type="string" required="true" />
        <cfargument name="text" type="string" default="" hint="Plain-text part. Empty: derived from html." />
        <cfargument name="cc" type="string" default="" />
        <cfargument name="bcc" type="string" default="" />
        <cfargument name="from" type="string" default="" hint="From address. Empty: EMAIL_FROM." />
        <cfargument name="fromName" type="string" default="" hint="Display name. Empty: EMAIL_FROM_NAME." />
        <cfargument name="replyTo" type="string" default="" />
        <cfargument name="attachments" type="array" default="#[]#" hint="Entries from attachment()." />

        <cfset var sender = {
            address: len(arguments.from) ? arguments.from : variables.fromAddress,
            name: len(arguments.fromName) ? arguments.fromName : variables.fromName
        } />
        <cfset var recipients = recipientsFor(arguments.to, arguments.cc, arguments.bcc) />
        <cfset var payload = {
            "to": recipients.to,
            "from": { "address": sender.address, "name": senderName(sender.name) },
            "subject": arguments.subject,
            "html": arguments.html,
            "text": len(arguments.text) ? arguments.text : htmlToText(arguments.html)
        } />
        <cfset var result = {} />

        <cfif NOT isConfigured()>
            <cfthrow type="moopa.email.notConfigured" message="CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_EMAIL_TOKEN and EMAIL_FROM must be set to send email." />
        </cfif>
        <cfif NOT arrayLen(recipients.to)>
            <cfthrow type="moopa.email.noRecipients" message="An email needs at least one recipient." />
        </cfif>
        <cfif arrayLen(recipients.cc)><cfset payload["cc"] = recipients.cc /></cfif>
        <cfif arrayLen(recipients.bcc)><cfset payload["bcc"] = recipients.bcc /></cfif>
        <cfif len(arguments.replyTo)><cfset payload["reply_to"] = arguments.replyTo /></cfif>
        <cfif arrayLen(arguments.attachments)><cfset payload["attachments"] = arguments.attachments /></cfif>

        <cfset result = post(payload) />
        <cfset result.to = arrayToList(recipients.to) />
        <cfset result.cc = arrayToList(recipients.cc) />
        <cfset result.from = sender.address />
        <cfset result.redirected = NOT variables.isProduction />
        <cfreturn result />
    </cffunction>

    <cffunction name="attachment" access="public" returntype="struct" output="false" hint="One attachment entry for send() from raw bytes.">
        <cfargument name="filename" type="string" required="true" />
        <cfargument name="content" type="binary" required="true" />
        <cfargument name="type" type="string" default="application/pdf" />
        <cfreturn {
            "filename": arguments.filename,
            "content": toBase64(arguments.content),
            "type": arguments.type,
            "disposition": "attachment"
        } />
    </cffunction>

    <cffunction name="layout" access="public" returntype="string" output="false" hint="Wrap a message body in a plain, widely supported email layout. footer is optional HTML (sender address, legal line).">
        <cfargument name="content" type="string" required="true" />
        <cfargument name="footer" type="string" default="" />
        <cfset var html = "" />
        <cfsavecontent variable="html"><cfoutput><!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light">
<style>
  body { margin: 0; padding: 0; background: ##f4f5f8; color: ##1f2534; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; font-size: 16px; line-height: 1.5; }
  .moo-email-body h1 { margin: 0 0 16px; font-size: 20px; line-height: 1.3; }
  .moo-email-body p { margin: 0 0 16px; }
  .moo-email-footer p { margin: 0 0 4px; }
</style>
</head>
<body>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:##f4f5f8;">
  <tr><td align="center" style="padding:24px 12px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:570px;background:##ffffff;border-radius:6px;">
      <tr><td class="moo-email-body" style="padding:32px;">#arguments.content#</td></tr>
    </table>
    <cfif len(arguments.footer)>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:570px;">
      <tr><td class="moo-email-footer" align="center" style="padding:16px 32px;color:##7f889b;font-size:13px;">#arguments.footer#</td></tr>
    </table>
    </cfif>
  </td></tr>
</table>
</body>
</html></cfoutput></cfsavecontent>
        <cfreturn html />
    </cffunction>

    <cffunction name="recipientsFor" access="private" returntype="struct" output="false">
        <cfargument name="to" type="string" required="true" />
        <cfargument name="cc" type="string" required="true" />
        <cfargument name="bcc" type="string" required="true" />
        <cfif variables.isProduction>
            <cfreturn { to: addressList(arguments.to), cc: addressList(arguments.cc), bcc: addressList(arguments.bcc) } />
        </cfif>
        <cfif NOT len(variables.sysadminEmail)>
            <cfthrow type="moopa.email.noRedirect" message="SYSADMIN_EMAIL must be set outside production: every email is redirected there." />
        </cfif>
        <cfreturn { to: addressList(variables.sysadminEmail), cc: [], bcc: [] } />
    </cffunction>

    <!--- The sender's display name: the given name, else the project title. Outside production it also names the
          environment, e.g. "Hub (staging)". --->
    <cffunction name="senderName" access="private" returntype="string" output="false">
        <cfargument name="name" type="string" required="true" />
        <cfset var label = len(arguments.name) ? arguments.name : (application.project_title ?: (application.app_name ?: "Moopa")) />
        <cfreturn variables.isProduction ? label : label & " (" & variables.environment & ")" />
    </cffunction>

    <cffunction name="addressList" access="private" returntype="array" output="false">
        <cfargument name="list" type="string" required="true" />
        <cfset var out = [] />
        <cfloop list="#arguments.list#" index="local.address" delimiters=",;">
            <cfif len(trim(local.address))>
                <cfset arrayAppend(out, trim(local.address)) />
            </cfif>
        </cfloop>
        <cfreturn out />
    </cffunction>

    <!--- A readable plain-text part from simple HTML: block ends become line breaks, tags go, entities decode. --->
    <cffunction name="htmlToText" access="public" returntype="string" output="false">
        <cfargument name="html" type="string" required="true" />
        <cfset var text = reReplaceNoCase(arguments.html, "<(head|style|script)[^>]*>[\s\S]*?</\1>", "", "all") />
        <cfset text = reReplaceNoCase(text, "<br\s*/?>", chr(10), "all") />
        <cfset text = reReplaceNoCase(text, "</(p|h[1-6]|div|tr|li)>", chr(10) & chr(10), "all") />
        <cfset text = reReplace(text, "<[^>]+>", "", "all") />
        <cfset text = replaceList(text, "&nbsp;,&amp;,&lt;,&gt;,&quot;,&##39;", " ,&,<,>,"",'") />
        <cfset text = reReplace(text, "[ \t]+", " ", "all") />
        <cfset text = reReplace(text, "(\r?\n ?){3,}", chr(10) & chr(10), "all") />
        <cfreturn trim(text) />
    </cffunction>

    <cffunction name="post" access="private" returntype="struct" output="false">
        <cfargument name="payload" type="struct" required="true" />
        <cfset var http = {} />
        <cfset var body = {} />
        <cfset var delivery = {} />

        <cfhttp url="https://api.cloudflare.com/client/v4/accounts/#variables.accountId#/email/sending/send" method="post" result="http" timeout="30">
            <cfhttpparam type="header" name="Authorization" value="Bearer #variables.token#" />
            <cfhttpparam type="header" name="Content-Type" value="application/json" />
            <cfhttpparam type="body" value="#serializeJSON(arguments.payload)#" />
        </cfhttp>

        <cfif isJSON(http.filecontent ?: "")>
            <cfset body = deserializeJSON(http.filecontent) />
        </cfif>

        <cfif structKeyExists(body, "result") AND isStruct(body.result)>
            <cfset delivery = body.result />
        </cfif>

        <cfreturn {
            success: isBoolean(body.success ?: "") AND body.success,
            status: val(http.status_code ?: 0),
            errors: isArray(body.errors ?: "") ? body.errors : [],
            delivered: delivery.delivered ?: [],
            queued: delivery.queued ?: [],
            bounced: delivery.permanent_bounces ?: []
        } />
    </cffunction>

</cfcomponent>
