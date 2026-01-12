<cfcomponent displayname="ImageKit" hint="ImageKit signed URL generation">


    <cffunction name="init">
        <cfset variables.IMAGEKIT_PRIVATE_KEY = server.system.environment.IMAGEKIT_PRIVATE_KEY ?: "" />
        <cfset variables.IMAGEKIT_URL_ENDPOINT = server.system.environment.IMAGEKIT_URL_ENDPOINT ?: "" />
        <cfreturn this />
    </cffunction>


    <!--- Helper functions for common expiry patterns --->
    <cffunction name="getEndOfMinute" returntype="date" output="false">
        <cfargument name="date" type="date" default="#Now()#" />
        <cfreturn CreateDateTime(Year(arguments.date), Month(arguments.date), Day(arguments.date), Hour(arguments.date), Minute(arguments.date), 59) />
    </cffunction>

    <cffunction name="getEndOfHour" returntype="date" output="false">
        <cfargument name="date" type="date" default="#Now()#" />
        <cfreturn CreateDateTime(Year(arguments.date), Month(arguments.date), Day(arguments.date), Hour(arguments.date), 59, 59) />
    </cffunction>

    <cffunction name="getEndOfDay" returntype="date" output="false">
        <cfargument name="date" type="date" default="#Now()#" />
        <cfreturn CreateDateTime(Year(arguments.date), Month(arguments.date), Day(arguments.date), 23, 59, 59) />
    </cffunction>

    <cffunction name="getEndOfWeek" returntype="date" output="false">
        <cfargument name="date" type="date" default="#Now()#" />
        <!--- Get next Sunday (day 1) --->
        <cfset var daysUntilSunday = 8 - DayOfWeek(arguments.date) />
        <cfif daysUntilSunday EQ 8><cfset daysUntilSunday = 1 /></cfif>
        <cfset var endOfWeek = DateAdd("d", daysUntilSunday, arguments.date) />
        <cfreturn CreateDateTime(Year(endOfWeek), Month(endOfWeek), Day(endOfWeek), 23, 59, 59) />
    </cffunction>

    <cffunction name="getEndOfMonth" returntype="date" output="false">
        <cfargument name="date" type="date" default="#Now()#" />
        <cfset var lastDayOfMonth = DaysInMonth(arguments.date) />
        <cfreturn CreateDateTime(Year(arguments.date), Month(arguments.date), lastDayOfMonth, 23, 59, 59) />
    </cffunction>

    <cffunction name="getEndOfYear" returntype="date" output="false">
        <cfargument name="date" type="date" default="#Now()#" />
        <cfreturn CreateDateTime(Year(arguments.date), 12, 31, 23, 59, 59) />
    </cffunction>


    <!--- RFC 3986 compliant URL encoding --->
    <cffunction name="imagekit_encode_url" returntype="string" output="false">
        <cfargument name="str" type="string" required="true" />
        <cfargument name="encodeSlash" type="boolean" default="true" />
        <cfset var result = replaceList(encodeForURL(arguments.str), '%2D,%2E,%5F,%7E,+,*', '-,.,_,~,%20,%2A') />
        <cfif NOT arguments.encodeSlash>
            <cfset result = replace(result, '%2F', '/', 'all') />
        </cfif>
        <cfreturn result />
    </cffunction>


    <!--- Function to generate signed ImageKit URL --->
    <cffunction name="url" returntype="string" output="false">
        <cfargument name="file_path" type="string" required="true" hint="Path to the file (e.g., /folder/image.jpg)" />
        <cfargument name="expires" type="any" default="MONTH" hint="Duration in seconds (numeric) or end-of period (string like 'hour', 'day', etc.)" />
        <cfargument name="params" type="any" default="" hint="ImageKit transformation params as struct or string (e.g., {width:400, height:300} or 'w-400,h-300')" />
        <cfargument name="thumbnail" type="boolean" default="false" hint="For PDF/video to image conversion, appends /ik-thumbnail.jpg" />

        <!--- Build ImageKit transformation string --->
        <cfset var transform_string = "" />
        <cfif isStruct(arguments.params) AND NOT structIsEmpty(arguments.params)>
            <cfset transform_string = buildParams(arguments.params) />
        <cfelseif isSimpleValue(arguments.params) AND len(arguments.params)>
            <cfset transform_string = toString(arguments.params) />
        </cfif>

        <!--- Handle file path - ensure leading slash --->
        <cfset var cleanPath = arguments.file_path />
        <cfif NOT left(cleanPath, 1) EQ "/">
            <cfset cleanPath = "/" & cleanPath />
        </cfif>

        <!--- URL-encode the path (preserving slashes) to handle spaces and special chars --->
        <!--- The signature must be computed on the encoded URL, as that's what ImageKit receives --->
        <cfset cleanPath = imagekit_encode_url(cleanPath, false) />

        <!---
            Append /ik-thumbnail.jpg ONLY for file types where ImageKit generates a derived thumbnail image
            (e.g., pdf/video/psd). For normal images (jpg/png/webp/etc) transforms apply to the original
            asset directly and we should NOT append /ik-thumbnail.jpg.
        --->
        <cfif arguments.thumbnail>
            <cfset var fileExt = lcase(listLast(cleanPath, ".")) />
            <cfif listFindNoCase("pdf,psd,eps,ai,mp4,mov,avi,webm,mkv,gif", fileExt)>
                <cfset cleanPath = cleanPath & "/ik-thumbnail.jpg" />
            </cfif>
        </cfif>

        <!--- Build the full image URL --->
        <cfset var urlEndpoint = variables.IMAGEKIT_URL_ENDPOINT />
        <!--- Ensure endpoint has trailing slash --->
        <cfif right(urlEndpoint, 1) NEQ "/">
            <cfset urlEndpoint = urlEndpoint & "/" />
        </cfif>

        <!--- Build full URL with optional transforms --->
        <cfset var imageUrl = "" />
        <cfif len(transform_string)>
            <cfset imageUrl = urlEndpoint & "tr:" & transform_string & cleanPath />
        <cfelse>
            <!--- Remove leading slash since endpoint has trailing slash --->
            <cfset imageUrl = urlEndpoint & right(cleanPath, len(cleanPath) - 1) />
        </cfif>

        <!--- Calculate expiration timestamp (UTC Unix timestamp) --->
        <cfset var expiryTimestamp = 0 />
        <cfif isNumeric(arguments.expires) AND arguments.expires EQ 0>
            <!--- expires=0 => 10 years from now --->
            <cfset var expiryDate = DateAdd("yyyy", 10, Now()) />
            <cfset expiryTimestamp = DateDiff("s", CreateDateTime(1970,1,1,0,0,0), DateConvert("local2utc", expiryDate)) />
        <cfelseif isNumeric(arguments.expires)>
            <!--- Numeric value means duration in seconds from now --->
            <cfset expiryTimestamp = DateDiff("s", CreateDateTime(1970,1,1,0,0,0), DateConvert("local2utc", Now())) + arguments.expires />
        <cfelse>
            <!--- String value means end-of period --->
            <cfset var expiryDate = Now() />
            <cfswitch expression="#UCase(arguments.expires)#">
                <cfcase value="MINUTE,N,EOMIN">
                    <cfset expiryDate = getEndOfMinute() />
                </cfcase>
                <cfcase value="HOUR,H,EOH">
                    <cfset expiryDate = getEndOfHour() />
                </cfcase>
                <cfcase value="DAY,D,EOD">
                    <cfset expiryDate = getEndOfDay() />
                </cfcase>
                <cfcase value="WEEK,W,EOW">
                    <cfset expiryDate = getEndOfWeek() />
                </cfcase>
                <cfcase value="MONTH,M,EOM">
                    <cfset expiryDate = getEndOfMonth() />
                </cfcase>
                <cfcase value="YEAR,Y,EOY">
                    <cfset expiryDate = getEndOfYear() />
                </cfcase>
                <cfdefaultcase>
                    <cfthrow type="configuration" message="Invalid expires value. Use numeric seconds or string like 'hour', 'day', 'week', 'month', 'year' (or shorthand H, D, W, M, Y, EOM, EOH, etc.)." detail="Received: '#arguments.expires#'" />
                </cfdefaultcase>
            </cfswitch>
            <cfset expiryTimestamp = DateDiff("s", CreateDateTime(1970,1,1,0,0,0), DateConvert("local2utc", expiryDate)) />
        </cfif>

        <!--- Remove the URL endpoint from image URL to get the path for signing --->
        <cfset var pathToSign = replace(imageUrl, urlEndpoint, "") />
        <!--- Append the expiry timestamp --->
        <cfset var stringToSign = pathToSign & expiryTimestamp />

        <!--- Calculate HMAC-SHA1 signature using private key --->
        <cfset var mac = CreateObject("java", "javax.crypto.Mac") />
        <cfset var secretKeySpec = CreateObject("java", "javax.crypto.spec.SecretKeySpec") />
        <cfset var keyBytes = CharsetDecode(variables.IMAGEKIT_PRIVATE_KEY, "UTF-8") />
        <cfset var keySpec = secretKeySpec.init(keyBytes, "HmacSHA1") />
        <cfset var hmac = mac.getInstance("HmacSHA1") />
        <cfset hmac.init(keySpec) />
        <cfset hmac.update(CharsetDecode(stringToSign, "UTF-8")) />
        <cfset var signatureBytes = hmac.doFinal() />

        <!--- Convert signature to lowercase hex string --->
        <cfset var signature = lCase(BinaryEncode(signatureBytes, "hex")) />

        <!--- Build final URL with ik-t and ik-s query parameters --->
        <cfset var finalUrl = imageUrl & "?ik-t=" & expiryTimestamp & "&ik-s=" & signature />

        <cfreturn finalUrl />
    </cffunction>


    <!--- Helper to build ImageKit transformation params from struct --->
    <cffunction name="buildParams" returntype="string" output="false">
        <cfargument name="opts" type="struct" required="true" />
        <!--- opts: width, height, format, quality, rotate, etc. --->
        <cfset var parts = [] />

        <!--- Width --->
        <cfif arguments.opts.keyExists("width") AND val(arguments.opts.width) GT 0>
            <cfset arrayAppend(parts, "w-#val(arguments.opts.width)#") />
        </cfif>

        <!--- Height --->
        <cfif arguments.opts.keyExists("height") AND val(arguments.opts.height) GT 0>
            <cfset arrayAppend(parts, "h-#val(arguments.opts.height)#") />
        </cfif>

        <!--- Crop mode / aspect ratio --->
        <cfif arguments.opts.keyExists("crop")>
            <cfset arrayAppend(parts, "c-#lCase(arguments.opts.crop)#") />
        </cfif>

        <!--- Focus / gravity --->
        <cfif arguments.opts.keyExists("focus")>
            <cfset arrayAppend(parts, "fo-#lCase(arguments.opts.focus)#") />
        </cfif>

        <!--- Format --->
        <cfif arguments.opts.keyExists("format") AND len(arguments.opts.format)>
            <cfset arrayAppend(parts, "f-#lCase(arguments.opts.format)#") />
        </cfif>

        <!--- Quality (1-100) --->
        <cfif arguments.opts.keyExists("quality") AND val(arguments.opts.quality) GT 0>
            <cfset arrayAppend(parts, "q-#val(arguments.opts.quality)#") />
        </cfif>

        <!--- Rotation --->
        <cfif arguments.opts.keyExists("rotate") AND listFind("0,90,180,270,360", val(arguments.opts.rotate))>
            <cfset arrayAppend(parts, "rt-#val(arguments.opts.rotate)#") />
        </cfif>

        <!--- Blur --->
        <cfif arguments.opts.keyExists("blur") AND val(arguments.opts.blur) GT 0>
            <cfset arrayAppend(parts, "bl-#val(arguments.opts.blur)#") />
        </cfif>

        <!--- Grayscale --->
        <cfif arguments.opts.keyExists("grayscale") AND arguments.opts.grayscale>
            <cfset arrayAppend(parts, "e-grayscale") />
        </cfif>

        <!--- DPR (device pixel ratio) --->
        <cfif arguments.opts.keyExists("dpr") AND val(arguments.opts.dpr) GT 0>
            <cfset arrayAppend(parts, "dpr-#val(arguments.opts.dpr)#") />
        </cfif>

        <!--- Page (for PDFs) --->
        <cfif arguments.opts.keyExists("page") AND val(arguments.opts.page) GT 0>
            <cfset arrayAppend(parts, "pg-#val(arguments.opts.page)#") />
        </cfif>


        <cfreturn arrayToList(parts, ",") />
    </cffunction>


</cfcomponent>
