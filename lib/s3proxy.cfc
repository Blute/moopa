<cfcomponent displayname="S3 Proxy" hint="The API for Nginx S3 Proxy stuff">



    <cffunction name="init">

        <cfset variables.S3_PROXY_KEY = server.system.environment.S3_PROXY_KEY />
        <cfset variables.S3_PROXY_SALT = server.system.environment.S3_PROXY_SALT />
        <cfset variables.S3_PROXY_URL = server.system.environment.S3_PROXY_URL />
        <cfset variables.S3_BUCKET = server.system.environment.S3_BUCKET />
        <cfset variables.CLOUDINARY_CLOUD_NAME = server.system.environment.CLOUDINARY_CLOUD_NAME ?: "blute" />

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

    <!--- Function to generate signed S3 proxy URL (uses Cloudinary for transformations) --->
    <cffunction name="url" returntype="string">
        <cfargument name="bucket" type="string" default="#variables.S3_BUCKET#" />
        <cfargument name="file_path" type="string" required="true" />
        <cfargument name="expires" type="any" default="MONTH" hint="Duration in seconds (numeric) or end-of period (string like 'hour', 'day', etc.)" />
        <cfargument name="use_token" type="boolean" default="false" hint="Include s3p_token cookie in signature verification" />
        <!--- Allow struct or prebuilt string --->
        <cfargument name="params" type="any" default="" hint="Struct of transforms for Cloudinary" />

        <!--- Check if we have transformations --->
        <cfset var has_params = false />
        <cfset var cloudinary_params = "" />
        <cfif isStruct(arguments.params) AND NOT structIsEmpty(arguments.params)>
            <cfset has_params = true />
            <cfset cloudinary_params = buildCloudinaryParams(arguments.params) />
        <cfelseif isSimpleValue(arguments.params) AND len(arguments.params)>
            <cfset has_params = true />
            <cfset cloudinary_params = toString(arguments.params) />
        </cfif>

        <!--- Handle file path with leading slash --->
        <cfset arguments.file_path = reReplace(arguments.file_path, "^/+", "") />

        <!--- Encode path using RFC 3986 rules (same as Lua encode_uri_path function) --->
        <!--- This matches the Lua function: escape all non-unreserved except '/' --->
        <cfset var encoded_path = "" />
        <cfloop from="1" to="#len(arguments.file_path)#" index="i">
            <cfset var char = mid(arguments.file_path, i, 1) />
            <cfif reFind("[A-Za-z0-9\-\._~\/]", char)>
                <cfset encoded_path &= char />
            <cfelse>
                <cfset var hexValue = formatBaseN(asc(char), 16) />
                <cfif len(hexValue) EQ 1><cfset hexValue = "0" & hexValue /></cfif>
                <cfset encoded_path &= "%" & uCase(hexValue) />
            </cfif>
        </cfloop>

        <!--- Calculate expiration timestamp --->
        <cfif isNumeric(arguments.expires) AND arguments.expires EQ 0>
            <!--- expires=0 => convert to 10 years from now (absolute UNIX timestamp) --->
            <cfset var expiryDate10y = DateAdd("yyyy", 10, Now()) />
            <cfset var expires = DateDiff("s", CreateDateTime(1970,1,1,0,0,0), expiryDate10y) />
        <cfelseif isNumeric(arguments.expires)>
            <!--- Numeric value means duration in seconds --->
            <cfset var expires = DateDiff("s", CreateDateTime(1970,1,1,0,0,0), Now()) + arguments.expires />
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
            <cfset var expires = DateDiff("s", CreateDateTime(1970,1,1,0,0,0), expiryDate) />
        </cfif>

        <!--- Always use /s3/ prefix --->
        <cfset var urlPrefix = "/s3" />

        <!--- Build path to sign (never include transform params - those go to Cloudinary) --->
        <cfset var pathToSign = "#urlPrefix#/#arguments.bucket#/#encoded_path#?expires=#expires#" />
        <cfset var s3p_token = "" />
        <cfset var cookieParam = "" />

        <cfif arguments.use_token>
            <!--- Get s3p_token from cookie --->
            <cfif structKeyExists(cookie, "s3p_token")>
                <cfset s3p_token = cookie.s3p_token />
            </cfif>
            <cfset cookieParam = "&c=1" />
            <!--- Include cookie parameter in path to sign --->
            <cfset pathToSign = pathToSign & cookieParam />
        </cfif>

        <!--- Decode hex key and salt to binary --->
        <cfset var keyBinary = BinaryDecode(variables.S3_PROXY_KEY, "hex") />
        <cfset var saltBinary = BinaryDecode(variables.S3_PROXY_SALT, "hex") />

        <!--- Using Java for proper binary concatenation --->
        <cfset var mac = CreateObject("java", "javax.crypto.Mac") />
        <cfset var secretKeySpec = CreateObject("java", "javax.crypto.spec.SecretKeySpec") />
        <cfset var keySpec = secretKeySpec.init(keyBinary, "HmacSHA256") />
        <cfset var hmac = mac.getInstance("HmacSHA256") />
        <cfset hmac.init(keySpec) />

        <!--- Concatenate salt + path + token bytes --->
        <cfset hmac.update(saltBinary) />
        <cfset hmac.update(CharsetDecode(pathToSign, "UTF-8")) />
        <cfif len(s3p_token)>
            <cfset hmac.update(CharsetDecode(s3p_token, "UTF-8")) />
        </cfif>
        <cfset var signature = hmac.doFinal() />

        <!--- Convert to base64url (replace + with -, / with _, remove =) --->
        <cfset var base64Sig = BinaryEncode(signature, "base64") />
        <cfset base64Sig = Replace(base64Sig, "+", "-", "all") />
        <cfset base64Sig = Replace(base64Sig, "/", "_", "all") />
        <cfset base64Sig = Replace(base64Sig, "=", "", "all") />

        <!--- Build raw S3 proxy URL (no transformations) --->
        <cfset var rawS3URL = "#variables.S3_PROXY_URL##urlPrefix#/#arguments.bucket#/#encoded_path#?expires=#expires#&sig=#base64Sig##cookieParam#" />

        <!--- If we have transformations, wrap with Cloudinary fetch URL --->
        <cfif has_params>
            <!--- URL-encode the source URL for Cloudinary fetch (encode ?, &, = etc.) --->
            <cfset var encodedSourceURL = URLEncodedFormat(rawS3URL) />
            <cfreturn "https://res.cloudinary.com/#variables.CLOUDINARY_CLOUD_NAME#/image/fetch/#cloudinary_params#/#encodedSourceURL#" />
        <cfelse>
            <cfreturn rawS3URL />
        </cfif>
    </cffunction>


    <cffunction name="buildCloudinaryParams" returntype="string" output="false">
        <cfargument name="opts" type="struct" required="true" />
        <!--- opts: width, height, cover (bool), format, quality (1-100), stripmeta (bool),
            rotate (0|90|180|270), page (1-based), dpi (int), halign, valign, gravity --->
        <cfset var parts = [] />
        <cfset var width = val(arguments.opts.keyExists("width") ? arguments.opts.width : 0) />
        <cfset var height = val(arguments.opts.keyExists("height") ? arguments.opts.height : 0) />
        <cfset var cover = !!(arguments.opts.keyExists("cover") ? arguments.opts.cover : false) />
        <cfset var format = arguments.opts.keyExists("format") ? lCase(arguments.opts.format) : "" />
        <cfset var quality = val(arguments.opts.keyExists("quality") ? arguments.opts.quality : 0) />
        <cfset var stripmeta = !!(arguments.opts.keyExists("stripmeta") ? arguments.opts.stripmeta : false) />
        <cfset var rotate = val(arguments.opts.keyExists("rotate") ? arguments.opts.rotate : 0) />
        <cfset var page = arguments.opts.keyExists("page") ? val(arguments.opts.page) : 0 />
        <cfset var dpi = val(arguments.opts.keyExists("dpi") ? arguments.opts.dpi : 0) />
        <cfset var halign = arguments.opts.keyExists("halign") ? lCase(arguments.opts.halign) : "" />
        <cfset var valign = arguments.opts.keyExists("valign") ? lCase(arguments.opts.valign) : "" />
        <cfset var gravity = arguments.opts.keyExists("gravity") ? lCase(arguments.opts.gravity) : "" />
        <cfset var cloudinary_gravity = "" />
        <cfset var smart_crop = false />

        <!--- Map gravity/halign/valign to Cloudinary gravity --->
        <cfif len(gravity)>
            <cfswitch expression="#gravity#">
                <cfcase value="sm,smart">
                    <cfset smart_crop = true />
                    <cfset cloudinary_gravity = "auto" />
                </cfcase>
                <cfcase value="ce,center,centre">
                    <cfset cloudinary_gravity = "center" />
                </cfcase>
                <cfcase value="no,north,top">
                    <cfset cloudinary_gravity = "north" />
                </cfcase>
                <cfcase value="so,south,bottom">
                    <cfset cloudinary_gravity = "south" />
                </cfcase>
                <cfcase value="we,west,left">
                    <cfset cloudinary_gravity = "west" />
                </cfcase>
                <cfcase value="ea,east,right">
                    <cfset cloudinary_gravity = "east" />
                </cfcase>
                <cfcase value="nw,northwest,top_left,top-left">
                    <cfset cloudinary_gravity = "north_west" />
                </cfcase>
                <cfcase value="ne,northeast,top_right,top-right">
                    <cfset cloudinary_gravity = "north_east" />
                </cfcase>
                <cfcase value="sw,southwest,bottom_left,bottom-left">
                    <cfset cloudinary_gravity = "south_west" />
                </cfcase>
                <cfcase value="se,southeast,bottom_right,bottom-right">
                    <cfset cloudinary_gravity = "south_east" />
                </cfcase>
            </cfswitch>
        <cfelseif len(halign) OR len(valign)>
            <!--- Build gravity from halign/valign combo --->
            <cfset var v_part = "" />
            <cfset var h_part = "" />
            <cfswitch expression="#valign#">
                <cfcase value="top"><cfset v_part = "north" /></cfcase>
                <cfcase value="bottom"><cfset v_part = "south" /></cfcase>
            </cfswitch>
            <cfswitch expression="#halign#">
                <cfcase value="left"><cfset h_part = "west" /></cfcase>
                <cfcase value="right"><cfset h_part = "east" /></cfcase>
            </cfswitch>
            <cfif len(v_part) AND len(h_part)>
                <cfset cloudinary_gravity = "#v_part#_#h_part#" />
            <cfelseif len(v_part)>
                <cfset cloudinary_gravity = v_part />
            <cfelseif len(h_part)>
                <cfset cloudinary_gravity = h_part />
            </cfif>
        </cfif>

        <!--- If gravity implies cropping and cover not explicitly set, enable cover --->
        <cfif (smart_crop OR len(cloudinary_gravity)) AND width GT 0 AND height GT 0 AND NOT cover>
            <cfset cover = true />
        </cfif>

        <!--- Crop mode: c_fill (cover) or c_fit (fit-in) --->
        <cfif width GT 0 OR height GT 0>
            <cfif cover>
                <cfset arrayAppend(parts, "c_fill") />
            <cfelse>
                <cfset arrayAppend(parts, "c_fit") />
            </cfif>
        </cfif>

        <!--- Gravity for fill crops --->
        <cfif len(cloudinary_gravity) AND cover>
            <cfset arrayAppend(parts, "g_#cloudinary_gravity#") />
        </cfif>

        <!--- Dimensions --->
        <cfif width GT 0>
            <cfset arrayAppend(parts, "w_#width#") />
        </cfif>
        <cfif height GT 0>
            <cfset arrayAppend(parts, "h_#height#") />
        </cfif>

        <!--- Format --->
        <cfif len(format)>
            <cfset arrayAppend(parts, "f_#format#") />
        <cfelse>
            <!--- Default to auto format for best compression --->
            <cfset arrayAppend(parts, "f_auto") />
        </cfif>

        <!--- Quality --->
        <cfif quality GT 0>
            <cfset arrayAppend(parts, "q_#quality#") />
        <cfelse>
            <!--- Default to auto quality --->
            <cfset arrayAppend(parts, "q_auto") />
        </cfif>

        <!--- Strip metadata --->
        <cfif stripmeta>
            <cfset arrayAppend(parts, "fl_strip_profile") />
        </cfif>

        <!--- Rotation --->
        <cfif listFind("90,180,270", rotate)>
            <cfset arrayAppend(parts, "a_#rotate#") />
        </cfif>

        <!--- PDF page (Cloudinary uses pg_X) --->
        <cfif page GT 0>
            <cfset arrayAppend(parts, "pg_#page#") />
        </cfif>

        <!--- DPI (Cloudinary uses dn_X for density) --->
        <cfif dpi GT 0>
            <cfset arrayAppend(parts, "dn_#dpi#") />
        </cfif>

        <cfreturn arrayToList(parts, ",") />
    </cffunction>

</cfcomponent>
