<cfcomponent displayname="Cloudflare" hint="Cloudflare Assets signed URL helpers">


    <cffunction name="init" access="public" returntype="any" output="false">
        <cfset variables.CLOUDFLARE_ASSETS_BASE_URL = server.system.environment.CLOUDFLARE_ASSETS_BASE_URL ?: "" />
        <cfset variables.CLOUDFLARE_ASSETS_SIGNING_KEY_B64 = server.system.environment.CLOUDFLARE_ASSETS_SIGNING_KEY_B64 ?: "" />
        <cfset variables.CLOUDFLARE_ASSETS_BASE_URL = reReplace(variables.CLOUDFLARE_ASSETS_BASE_URL, "/+$", "", "all") />
        <cfreturn this />
    </cffunction>
    <cffunction name="signed_asset_url" access="public" returntype="string" output="false">
        <cfargument name="key" type="any" required="false" default="" />
        <cfargument name="expiry_type" type="string" required="true" />
        <cfargument name="kind" type="string" required="false" default="a" />
        <cfargument name="options" type="any" required="false" default="" />

        <cfset var signedPath = signed_asset_path(
            key = arguments.key,
            expiry_type = arguments.expiry_type,
            kind = arguments.kind,
            options = arguments.options
        ) />

        <cfif isNull(signedPath) OR !len(trim(signedPath ?: ""))>
            <cfreturn "" />
        </cfif>

        <cfreturn variables.CLOUDFLARE_ASSETS_BASE_URL & signedPath />
    </cffunction>


    <cffunction name="signed_asset_path" access="public" returntype="string" output="false">
        <cfargument name="key" type="any" required="false" default="" />
        <cfargument name="expiry_type" type="string" required="true" />
        <cfargument name="kind" type="string" required="false" default="a" />
        <cfargument name="options" type="any" required="false" default="" />

        <cfset var cleanKey = "" />
        <cfset var normalizedKind = normalize_kind(arguments.kind) />
        <cfset var path = "" />
        <cfset var exp_unix = 0 />
        <cfset var query_no_sig = "" />
        <cfset var canonical = "" />
        <cfset var sig_hex = "" />

        <cfif isNull(arguments.key)>
            <cfreturn "" />
        </cfif>

        <cfset cleanKey = trim(toString(arguments.key)) />

        <cfif !len(cleanKey)>
            <cfreturn "" />
        </cfif>

        <cfif !len(variables.CLOUDFLARE_ASSETS_SIGNING_KEY_B64)>
            <cfthrow type="configuration" message="Missing CLOUDFLARE_ASSETS_SIGNING_KEY_B64 environment variable" />
        </cfif>

        <cfset path = "/#normalizedKind#/#reReplace(cleanKey, '^/+', '', 'all')#" />
        <cfset exp_unix = signed_url_expiry(arguments.expiry_type) />
        <cfset query_no_sig = signed_url_query(arguments.options, exp_unix) />
        <cfset canonical = path & "?" & query_no_sig />
        <cfset sig_hex = hmac_sha256_hex(canonical, variables.CLOUDFLARE_ASSETS_SIGNING_KEY_B64) />

        <cfreturn path & "?" & query_no_sig & "&sig=" & sig_hex />
    </cffunction>


    <cffunction name="signed_url_expiry" access="public" returntype="numeric" output="false">
        <cfargument name="expiry_type" type="string" required="true" />

        <cfset var ts = now() />
        <cfset var result = ts />
        <cfset var exp = uCase(trim(arguments.expiry_type ?: "")) />

        <cfswitch expression="#exp#">
            <cfcase value="MINUTE,N,EOMIN">
                <cfset result = createDateTime(year(ts), month(ts), day(ts), hour(ts), minute(ts), 59) />
            </cfcase>
            <cfcase value="HOUR,H,EOH">
                <cfset result = createDateTime(year(ts), month(ts), day(ts), hour(ts), 59, 59) />
            </cfcase>
            <cfcase value="DAY,D,EOD">
                <cfset result = createDateTime(year(ts), month(ts), day(ts), 23, 59, 59) />
            </cfcase>
            <cfcase value="WEEK,W,EOW">
                <cfset var daysUntilSunday = 8 - dayOfWeek(ts) />
                <cfif daysUntilSunday EQ 8><cfset daysUntilSunday = 1 /></cfif>
                <cfset var endOfWeek = dateAdd("d", daysUntilSunday, ts) />
                <cfset result = createDateTime(year(endOfWeek), month(endOfWeek), day(endOfWeek), 23, 59, 59) />
            </cfcase>
            <cfcase value="MONTH,M,EOM">
                <cfset result = createDateTime(year(ts), month(ts), daysInMonth(ts), 23, 59, 59) />
            </cfcase>
            <cfcase value="YEAR,Y,EOY">
                <cfset result = createDateTime(year(ts), 12, 31, 23, 59, 59) />
            </cfcase>
            <cfdefaultcase>
                <cfthrow type="configuration" message="Invalid expiry type: #arguments.expiry_type#" />
            </cfdefaultcase>
        </cfswitch>

        <cfreturn dateDiff("s", createDateTime(1970, 1, 1, 0, 0, 0), dateConvert("local2utc", result)) />
    </cffunction>


    <cffunction name="signed_url_query" access="public" returntype="string" output="false">
        <cfargument name="options" type="any" required="false" default="" />
        <cfargument name="exp" type="numeric" required="true" />

        <cfset var optionString = normalize_options_string(arguments.options) />
        <cfset var pairs = [] />
        <cfset var parsedPairs = parse_query_pairs(optionString) />
        <cfset var i = 0 />
        <cfset var pair = {} />
        <cfset var key = "" />
        <cfset var value = "" />
        <cfset var out = [] />

        <cfset pairs = parsedPairs />
        <cfset arrayAppend(pairs, { key = "exp", value = toString(arguments.exp) }) />

        <cfset arraySort(pairs, function(a, b) {
            if (compare(a.key, b.key) LT 0) return -1;
            if (compare(a.key, b.key) GT 0) return 1;
            return 0;
        }) />

        <cfloop from="1" to="#arrayLen(pairs)#" index="i">
            <cfset pair = pairs[i] />
            <cfset key = pair.key ?: "" />
            <cfset value = escape_query_value(pair.value ?: "") />
            <cfset arrayAppend(out, key & "=" & value) />
        </cfloop>

        <cfreturn arrayToList(out, "&") />
    </cffunction>


    <cffunction name="normalize_kind" access="private" returntype="string" output="false">
        <cfargument name="kind" type="string" required="false" default="a" />

        <cfset var k = lCase(trim(arguments.kind ?: "a")) />

        <cfswitch expression="#k#">
            <cfcase value="a,asset"><cfreturn "a" /></cfcase>
            <cfcase value="i,image"><cfreturn "i" /></cfcase>
            <cfcase value="v,video"><cfreturn "v" /></cfcase>
            <cfdefaultcase><cfreturn "a" /></cfdefaultcase>
        </cfswitch>
    </cffunction>


    <cffunction name="normalize_options_string" access="private" returntype="string" output="false">
        <cfargument name="options" type="any" required="false" default="" />

        <cfset var parts = [] />
        <cfset var k = "" />

        <cfif isSimpleValue(arguments.options)>
            <cfreturn trim(toString(arguments.options ?: "")) />
        </cfif>

        <cfif isStruct(arguments.options)>
            <cfloop collection="#arguments.options#" item="k">
                <cfif len(trim(k))>
                    <cfset arrayAppend(parts, trim(k) & "=" & toString(arguments.options[k] ?: "")) />
                </cfif>
            </cfloop>
        </cfif>

        <cfreturn arrayToList(parts, "&") />
    </cffunction>


    <cffunction name="parse_query_pairs" access="private" returntype="array" output="false">
        <cfargument name="query_string" type="string" required="true" />

        <cfset var rows = [] />
        <cfset var segments = [] />
        <cfset var i = 0 />
        <cfset var segment = "" />
        <cfset var key = "" />
        <cfset var value = "" />
        <cfset var pos = 0 />

        <cfif !len(arguments.query_string)>
            <cfreturn rows />
        </cfif>

        <cfset segments = listToArray(arguments.query_string, "&", true) />

        <cfloop from="1" to="#arrayLen(segments)#" index="i">
            <cfset segment = segments[i] />
            <cfset pos = find("=", segment) />

            <cfif pos GT 0>
                <cfset key = left(segment, pos - 1) />
                <cfset value = mid(segment, pos + 1, len(segment) - pos) />
            <cfelse>
                <cfset key = segment />
                <cfset value = "" />
            </cfif>

            <cfif len(key)>
                <cfset arrayAppend(rows, { key = key, value = value }) />
            </cfif>
        </cfloop>

        <cfreturn rows />
    </cffunction>


    <cffunction name="escape_query_value" access="private" returntype="string" output="false">
        <cfargument name="value" type="string" required="true" />

        <cfset var v = arguments.value />
        <cfset v = replace(v, "%", "%25", "all") />
        <cfset v = replace(v, "&", "%26", "all") />
        <cfset v = replace(v, "=", "%3D", "all") />
        <cfreturn v />
    </cffunction>


    <cffunction name="hmac_sha256_hex" access="private" returntype="string" output="false">
        <cfargument name="message" type="string" required="true" />
        <cfargument name="key_b64" type="string" required="true" />

        <cfset var mac = createObject("java", "javax.crypto.Mac") />
        <cfset var secretKeySpec = createObject("java", "javax.crypto.spec.SecretKeySpec") />
        <cfset var keyBytes = binaryDecode(arguments.key_b64, "base64") />
        <cfset var keySpec = secretKeySpec.init(keyBytes, "HmacSHA256") />
        <cfset var hmac = mac.getInstance("HmacSHA256") />
        <cfset var signatureBytes = "" />

        <cfset hmac.init(keySpec) />
        <cfset hmac.update(charsetDecode(arguments.message, "UTF-8")) />
        <cfset signatureBytes = hmac.doFinal() />

        <cfreturn lCase(binaryEncode(signatureBytes, "hex")) />
    </cffunction>


</cfcomponent>
