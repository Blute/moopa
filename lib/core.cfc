<cfcomponent displayname="core" hint="Core Library" >

	<cffunction name="init" access="public" returntype="core" output="false" hint="Lib Constructor">
		<cfreturn this />
	</cffunction>


    <!---
    Generate a cryptographically secure URL-safe token.
    Uses AES-256 key generation (32 bytes) encoded as base64url.
    Returns a 43-character URL-safe string.
    --->
    <cffunction name="generateSecureToken" access="public" returntype="string" output="false">
        <cfargument name="bytes" type="numeric" default="32" hint="Number of random bytes (default 32 = 256 bits)" />

        <!--- Generate cryptographically secure random bytes using AES key generation --->
        <cfset var secretKey = generateSecretKey("AES", arguments.bytes * 8) />

        <!--- Decode the base64 key to binary --->
        <cfset var binaryKey = binaryDecode(secretKey, "base64") />

        <!--- Encode as URL-safe base64 (no padding, - instead of +, _ instead of /) --->
        <cfset var base64Token = binaryEncode(binaryKey, "base64") />
        <cfset var urlSafeToken = replace(replace(replace(base64Token, "+", "-", "all"), "/", "_", "all"), "=", "", "all") />

        <cfreturn urlSafeToken />
    </cffunction>




    <cffunction name="ArrayOfStructSort" returntype="array" access="public" output="no">
        <cfargument name="base" type="array" required="yes" />
        <cfargument name="sortType" type="string" required="no" default="text" />
        <cfargument name="sortOrder" type="string" required="no" default="ASC" />
        <cfargument name="pathToSubElement" type="string" required="no" default="" />

        <cfset var tmpStruct = StructNew()>
        <cfset var returnVal = ArrayNew(1)>
        <cfset var i = 0>
        <cfset var keys = "">

        <cfloop from="1" to="#ArrayLen(base)#" index="i">
          <cfset tmpStruct[i] = base[i]>
        </cfloop>

        <cfset keys = StructSort(tmpStruct, sortType, sortOrder, pathToSubElement)>

        <cfloop from="1" to="#ArrayLen(keys)#" index="i">
          <cfset returnVal[i] = tmpStruct[keys[i]]>
        </cfloop>

        <cfreturn returnVal>
    </cffunction>


    <cffunction name="getDateOnly" output="false">
        <cfargument name="date" default="#now()#">

        <cfif isDate(arguments.date)>
            <cfreturn createDate( year(arguments.date), month(arguments.date), day(arguments.date) ) />
        <cfelse>
            <cfreturn "">
        </cfif>
    </cffunction>


    <cffunction name="convertUTCToLocal">
        <cfargument name="utcDateTimeString" default="#now()#" />
        <cfargument name="timezone" default="Australia/Sydney" />

        <cfset utcDateTimeStringToFormat = arguments.utcDateTimeString />

        <cfif isDate(utcDateTimeStringToFormat)>
            <cfset utcDateTimeStringToFormat = dateTimeFormat(utcDateTimeStringToFormat, "yyyy-mm-dd HH:nn") />
        </cfif>

        <!--- Create a SimpleDateFormat object with the expected format --->
        <cfset formatter = createObject("java", "java.text.SimpleDateFormat").init("yyyy-MM-dd HH:mm")>

        <!--- Explicitly set the formatter's timezone to UTC --->
        <cfset formatter.setTimeZone(createObject("java", "java.util.TimeZone").getTimeZone("UTC"))>

        <!--- Parse the string into a Java Date object --->
        <cfset utcDateTime = formatter.parse(utcDateTimeStringToFormat)>

        <!--- Now convert this UTC date to Sydney time --->
        <cfset localTimeZone = createObject("java", "java.util.TimeZone").getTimeZone(arguments.timezone)>
        <cfset formatter.setTimeZone(localTimeZone)>

        <!--- Format the date as string in Sydney timezone --->
        <cfset localDateTimeString = formatter.format(utcDateTime)>

        <cfreturn parseDateTime(localDateTimeString) />

    </cffunction>


    <cffunction name="convertLocalToUTC">
        <cfargument name="localDateTimeString" type="string" required="yes" />
        <cfargument name="timezone" default="Australia/Sydney" type="string" />

        <cfset localDateTimeStringToFormat = arguments.localDateTimeString />

        <cfif isDate(localDateTimeStringToFormat)>
            <cfset localDateTimeStringToFormat = dateTimeFormat(localDateTimeStringToFormat, "yyyy-mm-dd HH:nn") />
        </cfif>

        <!--- Create a SimpleDateFormat object with the expected format --->
        <cfset var formatter = createObject("java", "java.text.SimpleDateFormat").init("yyyy-MM-dd HH:mm")>

        <!--- Set the formatter's timezone to the provided local timezone --->
        <cfset var localTimeZone = createObject("java", "java.util.TimeZone").getTimeZone(arguments.timezone)>
        <cfset formatter.setTimeZone(localTimeZone)>

        <!--- Parse the local date-time string into a Java Date object --->
        <cfset var localDate = formatter.parse(localDateTimeStringToFormat)>

        <!--- Change formatter's timezone to UTC for conversion --->
        <cfset formatter.setTimeZone(createObject("java", "java.util.TimeZone").getTimeZone("UTC"))>

        <!--- Format the date as string in UTC timezone --->
        <cfset var utcDateTimeString = formatter.format(localDate)>

        <cfreturn parseDateTime(utcDateTimeString) />
    </cffunction>


    <cffunction name="generateVerificationCode" access="public" output="false" returntype="string">
        <cfargument name="length" type="numeric" required="false" default="6" />

        <cfset var code = "" />
        <cfset var i = 0 />

        <cfloop from="1" to="#arguments.length#" index="i">
            <cfset code &= randRange(0, 9) />
        </cfloop>

        <cfreturn code />
    </cffunction>


    <cffunction name="hashCode" access="public" output="false" returntype="string">
        <cfargument name="code" type="string" required="true" />
        <cfargument name="salt" type="string" required="true" />

        <cfreturn lCase(hash("#arguments.salt#:#trim(arguments.code)#", "SHA-256")) />
    </cffunction>


    <cffunction name="normalizeRedirectRoute" access="public" output="false" returntype="string">
        <cfargument name="route" type="string" required="true" />
        <cfargument name="fallback" type="string" required="false" default="" />

        <cfset var normalizedRoute = trim(arguments.route ?: "") />

        <cfif !len(normalizedRoute)>
            <cfreturn arguments.fallback />
        </cfif>

        <cfif left(normalizedRoute, 1) NEQ "/" OR left(normalizedRoute, 2) EQ "//">
            <cfreturn arguments.fallback />
        </cfif>

        <cfreturn normalizedRoute />
    </cffunction>


    <cffunction name="getRedirectUrl" access="public" output="false" returntype="string">
        <cfargument name="clear" type="boolean" required="false" default="false" />
        <cfargument name="fallback" type="string" required="false" default="/" />

        <cfset var redirectUrl = arguments.fallback />

        <cfif structKeyExists(session, "login_redirect_route")>
            <cfset redirectUrl = normalizeRedirectRoute(session.login_redirect_route ?: "", arguments.fallback) />
            <cfif arguments.clear>
                <cfset structDelete(session, "login_redirect_route") />
            </cfif>
        </cfif>

        <cfreturn redirectUrl />
    </cffunction>


    <cffunction name="isSuccessfulStatusCode" access="public" output="false" returntype="boolean">
        <cfargument name="statusCode" type="string" required="true" />

        <cfset var parsedCode = val(listFirst(trim(arguments.statusCode ?: ""), " ")) />

        <cfreturn parsedCode GTE 200 AND parsedCode LT 300 />
    </cffunction>


    <cffunction name="hasMoopaProfileTable" access="public" output="false" returntype="boolean">
        <cftry>
            <cfquery name="local.qCheck">
                SELECT 1 FROM moo_profile LIMIT 1
            </cfquery>
            <cfreturn true />
            <cfcatch type="database">
                <cfreturn false />
            </cfcatch>
        </cftry>
    </cffunction>


    <cffunction name="hasSystemProfile" access="public" output="false" returntype="boolean">
        <cfargument name="app_name" type="string" required="false" default="hub" />

        <cfif NOT hasMoopaProfileTable()>
            <cfreturn false />
        </cfif>

        <cfquery name="local.qProfiles">
            SELECT count(*) AS profile_count
            FROM moo_profile
            WHERE app_name = <cfqueryparam cfsqltype="varchar" value="#arguments.app_name#" />
            AND can_login = true
        </cfquery>

        <cfreturn val(local.qProfiles.profile_count) GT 0 />
    </cffunction>


    <cffunction name="requiresHubSetup" access="public" output="false" returntype="boolean">
        <cfset var sysadminEmails = "" />
        <cfset var sysadminEmail = "" />

        <cfloop list="#server.system.environment.SYSADMIN_EMAIL ?: ''#" item="sysadminEmail">
            <cfset sysadminEmail = lCase(trim(sysadminEmail)) />
            <cfif len(sysadminEmail)>
                <cfset sysadminEmails = listAppend(sysadminEmails, sysadminEmail) />
            </cfif>
        </cfloop>

        <cfif NOT hasMoopaProfileTable()>
            <cfreturn true />
        </cfif>

        <cfif NOT len(sysadminEmails)>
            <cfreturn true />
        </cfif>

        <cfquery name="local.qAccounts">
            SELECT count(*) AS account_count
            FROM moo_profile_auth
            INNER JOIN moo_profile ON moo_profile.id = moo_profile_auth.profile_id
            WHERE moo_profile.app_name = <cfqueryparam cfsqltype="varchar" value="hub" />
            AND moo_profile.can_login = true
            AND lower(moo_profile.email) IN (<cfqueryparam cfsqltype="varchar" value="#sysadminEmails#" list="true" />)
            AND moo_profile_auth.app_name = <cfqueryparam cfsqltype="varchar" value="hub" />
            AND moo_profile_auth.provider = <cfqueryparam cfsqltype="varchar" value="local_password" />
        </cfquery>

        <cfreturn val(local.qAccounts.account_count) EQ 0 />
    </cffunction>




    <cffunction name="logError" returntype="void" output="true">

        <cfargument name="Exception" type="any" required="true" />
        <cfargument name="EventName" type="string" required="false" default="" />


        <cfset error_line = "From: Unknown Line" />
        <cfif arrayLen(arguments.Exception.tagContext?:[])>
            <cfset error_line = "#replaceNoCase(arguments.Exception.tagContext[1].template,"/var/www","")#:#arguments.Exception.tagContext[1].line#" />
        </cfif>


        <cfset new_error_log = application.lib.db.save(
                table_name = "moo_error_log",
                data = {
                    message = "#arguments.Exception.message#",
                    line = "#error_line#",
                    tag = "500 Error",
                    exception = "#serializeJSON(arguments.Exception)#",
                    current_auth = "#serializeJSON(session.auth?:{})#",
                    cgi_scope = "#serializeJSON(cgi?:{})#",
                    form_scope = "#serializeJSON(form?:{})#",
                    request_scope = "#serializeJSON(request?:{})#",
                    url_scope = "#serializeJSON(url?:{})#",
                    session_scope = "#serializeJSON(session?:{})#"
                },
                returnAsCFML=true
            ) />

        <!--- Only send email in production when an error recipient is configured. --->
        <cfset local.errorEmailTo = server.system.environment.SYSADMIN_EMAIL ?: "" />
        <cfif (server.system.environment.APP_ENVIRONMENT?:'production') EQ 'production' AND len(trim(local.errorEmailTo))>
            <cfset email_subject = "MOOPA 500 ERROR [#dateFormat(now(),'ddd dd-mmm-yyyy')#]"/>

            <cfsavecontent variable="email_body">
                <cfoutput>
                #error_line# <br>
                #arguments.exception.message?:''# <br>
                <a href="#server.system.environment.base_url#/moo_error_log">Error Log</a>
                </cfoutput>
            </cfsavecontent>

            <cfset result = application.lib.postmark.sendEmail(
                to="#local.errorEmailTo#",
                subject="#email_subject#",
                htmlBody="#email_body#",
                tag="500 Error"
            ) />
        </cfif>


    </cffunction>



    <!---
        Sanitizes a filename for safe use as an S3 object key.
        Removes or replaces characters that could cause issues per AWS S3 documentation.
        allowed_extensions: comma list to validate extension (default: standard types). Use "*" for no restriction.
        max_base_length: truncates base name (filename before extension).
    --->
    <cffunction name="sanitize_s3_key" access="public" returntype="string">
        <cfargument name="filename" type="string" required="true" />
        <cfargument name="allowed_extensions" type="string" required="false" default="png,jpg,jpeg,webp,gif,bmp,svg,tiff,tif,pdf,xls,xlsx,xlsm,mp4,webm,mov,avi,mkv,m4v,mp3,wav,ogg,m4a,aac,flac" />
        <cfargument name="max_base_length" type="numeric" required="false" default="0" />

        <cfset var sanitized = arguments.filename />
        <cfset var base_name = "" />
        <cfset var extension = "" />

        <cfif len(arguments.allowed_extensions) AND arguments.allowed_extensions NEQ "*">
            <!--- Strip path segments and parse base + extension --->
            <cfset sanitized = trim(sanitized) />
            <cfset sanitized = reReplace(sanitized, "^.*[\\/]", "", "one") />
            <cfif listLen(sanitized, ".") GT 1>
                <cfset extension = lCase(listLast(sanitized, ".")) />
                <cfset base_name = listDeleteAt(sanitized, listLen(sanitized, "."), ".") />
            <cfelse>
                <cfset base_name = sanitized />
                <cfset extension = "" />
            </cfif>
            <cfif !listFindNoCase(arguments.allowed_extensions, extension)>
                <cfthrow type="InvalidExtension" message="File extension '#extension#' is not allowed. Allowed: #arguments.allowed_extensions#" />
            </cfif>
            <cfset sanitized = base_name />
        </cfif>

        <!--- Characters to avoid: \ { } ^ % ` ] " > [ ~ < # | --->
        <cfset sanitized = reReplace(sanitized, '[\\{}\^%`\]"><\[~##\|]', '_', 'all') />

        <!--- Characters that require special handling: & $ @ = ; : + , ? / --->
        <cfset sanitized = reReplace(sanitized, '[&\$@=;:\+,\?/]', '_', 'all') />

        <!--- Replace whitespace with underscore --->
        <cfset sanitized = reReplace(sanitized, '\s+', '_', 'all') />

        <!--- Replace ASCII control characters (00-1F hex and 7F) --->
        <cfset sanitized = reReplace(sanitized, '[\x00-\x1F\x7F]', '_', 'all') />

        <!--- Replace non-printable ASCII (128-255 decimal) --->
        <cfset sanitized = reReplace(sanitized, '[\x80-\xFF]', '_', 'all') />

        <!--- Collapse multiple underscores into one --->
        <cfset sanitized = reReplace(sanitized, '_+', '_', 'all') />

        <!--- Trim leading/trailing underscores --->
        <cfset sanitized = reReplace(sanitized, '^_+|_+$', '', 'all') />

        <!--- Truncate if max_base_length specified --->
        <cfif arguments.max_base_length GT 0>
            <cfset sanitized = left(sanitized, arguments.max_base_length) />
            <cfset sanitized = reReplace(sanitized, '^_+|_+$', '', 'all') />
        </cfif>

        <!--- If filename is now empty (edge case), generate a fallback --->
        <cfif not len(sanitized)>
            <cfset sanitized = 'file' />
        </cfif>

        <cfif len(arguments.allowed_extensions) AND len(extension)>
            <cfreturn sanitized & "." & extension />
        </cfif>
        <cfreturn sanitized />
    </cffunction>

</cfcomponent>
