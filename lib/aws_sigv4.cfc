<cfcomponent displayname="AWS SigV4" hint="Pure AWS Signature Version 4 signer for any AWS-compatible API (S3 and S3-compatible stores such as Cloudflare R2, Secrets Manager, Bedrock): header signing for requests the app sends itself, and query signing for presigned URLs a browser uses. No HTTP here: callers send the request with exactly the headers they signed. Built only on CFML functions (hash, hmac, charsetDecode, binaryEncode), with no Java classes, so it signs identically on Lucee and on engines without a JVM such as RustCFML.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>

    <!--- Signs one request. Returns { authorization, amzDate, signedHeaders, signature, headers } where headers is the full
          set the caller must send (the supplied headers plus host, x-amz-date and, with a session token, x-amz-security-token).
          headers: struct of extra headers to sign, e.g. { "x-amz-content-sha256": hash } or { "content-type": "application/json" }.
          canonicalUri must already be URI-encoded exactly as it will go on the wire. credentials: { accessKeyId, secretAccessKey, sessionToken }.
          Fully parameterised (including signingTime) so it can be checked against AWS's published test vectors. --->
    <cffunction name="sign" access="public" returntype="struct" output="false">
        <cfargument name="method" type="string" required="true" />
        <cfargument name="host" type="string" required="true" />
        <cfargument name="canonicalUri" type="string" required="true" />
        <cfargument name="canonicalQueryString" type="string" required="true" />
        <cfargument name="headers" type="struct" required="true" />
        <cfargument name="payloadHash" type="string" required="true" />
        <cfargument name="region" type="string" required="true" />
        <cfargument name="service" type="string" required="true" />
        <cfargument name="credentials" type="struct" required="true" />
        <cfargument name="signingTime" type="date" required="true" />

        <cfset var amzDate = dateTimeFormat(arguments.signingTime, "yyyyMMdd'T'HHnnss'Z'", "UTC") />
        <cfset var dateStamp = dateTimeFormat(arguments.signingTime, "yyyyMMdd", "UTC") />
        <cfset var sessionToken = trim(arguments.credentials.sessionToken ?: "") />
        <cfset var allHeaders = {} />
        <cfset var name = "" />
        <cfset var names = [] />
        <cfset var canonicalHeaders = "" />
        <cfset var signedHeaders = "" />
        <cfset var canonicalRequest = "" />
        <cfset var credentialScope = dateStamp & "/" & arguments.region & "/" & arguments.service & "/aws4_request" />
        <cfset var signature = "" />

        <cfloop collection="#arguments.headers#" item="name">
            <cfset allHeaders[lCase(trim(name))] = trim(arguments.headers[name]) />
        </cfloop>
        <cfset allHeaders["host"] = trim(arguments.host) />
        <cfset allHeaders["x-amz-date"] = amzDate />
        <cfif len(sessionToken)>
            <cfset allHeaders["x-amz-security-token"] = sessionToken />
        </cfif>

        <cfset names = structKeyArray(allHeaders) />
        <cfset arraySort(names, "text") />
        <cfloop array="#names#" item="name">
            <cfset canonicalHeaders &= name & ":" & allHeaders[name] & chr(10) />
        </cfloop>
        <cfset signedHeaders = arrayToList(names, ";") />

        <cfset canonicalRequest = arguments.method & chr(10) & arguments.canonicalUri & chr(10) & arguments.canonicalQueryString & chr(10)
            & canonicalHeaders & chr(10) & signedHeaders & chr(10) & arguments.payloadHash />
        <cfset signature = signatureFor(
            secretAccessKey = arguments.credentials.secretAccessKey,
            dateStamp = dateStamp,
            region = arguments.region,
            service = arguments.service,
            stringToSign = "AWS4-HMAC-SHA256" & chr(10) & amzDate & chr(10) & credentialScope & chr(10) & sha256Hex(canonicalRequest)
        ) />

        <cfset allHeaders["authorization"] = "AWS4-HMAC-SHA256 Credential=#arguments.credentials.accessKeyId#/#credentialScope#, SignedHeaders=#signedHeaders#, Signature=#signature#" />

        <cfreturn {
            authorization: allHeaders["authorization"],
            amzDate: amzDate,
            signedHeaders: signedHeaders,
            signature: signature,
            headers: allHeaders
        } />
    </cffunction>

    <!--- Presigns one request in the query string, for a client that holds no credentials (a browser uploading or
          downloading straight to the store). Returns the query string, without the "?", to append to the URL whose host and
          canonicalUri were signed. Only the host header is signed and the payload is UNSIGNED-PAYLOAD, so the client may send
          any body and other headers (a PUT's Content-Type) without breaking the signature. A session token is signed into
          the query as X-Amz-Security-Token. canonicalUri must already be URI-encoded exactly as it will go on the wire.
          Fully parameterised (including signingTime) so it can be checked against AWS's published example. --->
    <cffunction name="presign" access="public" returntype="string" output="false">
        <cfargument name="method" type="string" required="true" />
        <cfargument name="host" type="string" required="true" />
        <cfargument name="canonicalUri" type="string" required="true" />
        <cfargument name="region" type="string" required="true" />
        <cfargument name="service" type="string" required="true" />
        <cfargument name="credentials" type="struct" required="true" />
        <cfargument name="signingTime" type="date" required="true" />
        <cfargument name="expiresSeconds" type="numeric" required="true" hint="How long the URL works: 1 second to 7 days." />

        <cfset var amzDate = dateTimeFormat(arguments.signingTime, "yyyyMMdd'T'HHnnss'Z'", "UTC") />
        <cfset var dateStamp = dateTimeFormat(arguments.signingTime, "yyyyMMdd", "UTC") />
        <cfset var credentialScope = dateStamp & "/" & arguments.region & "/" & arguments.service & "/aws4_request" />
        <cfset var sessionToken = trim(arguments.credentials.sessionToken ?: "") />
        <cfset var parameters = [] />
        <cfset var pairs = [] />
        <cfset var parameter = [] />
        <cfset var canonicalQueryString = "" />
        <cfset var canonicalRequest = "" />
        <cfset var signature = "" />

        <cfif NOT isValid("integer", arguments.expiresSeconds) OR arguments.expiresSeconds LT 1 OR arguments.expiresSeconds GT 604800>
            <cfthrow type="aws.sigv4.invalid" message="A presigned URL expires in 1 to 604800 seconds (7 days), not #arguments.expiresSeconds#" />
        </cfif>

        <cfset parameters = [
            ["X-Amz-Algorithm", "AWS4-HMAC-SHA256"],
            ["X-Amz-Credential", arguments.credentials.accessKeyId & "/" & credentialScope],
            ["X-Amz-Date", amzDate],
            ["X-Amz-Expires", int(arguments.expiresSeconds)],
            ["X-Amz-SignedHeaders", "host"]
        ] />
        <cfif len(sessionToken)>
            <cfset arrayAppend(parameters, ["X-Amz-Security-Token", sessionToken]) />
        </cfif>
        <!--- The canonical query sorts by the encoded name, by code point. --->
        <cfloop array="#parameters#" item="parameter">
            <cfset arrayAppend(pairs, [uriEncode(parameter[1]), uriEncode(parameter[2])]) />
        </cfloop>
        <cfset arraySort(pairs, function(a, b) { return compare(a[1], b[1]); }) />
        <cfloop array="#pairs#" item="parameter">
            <cfset canonicalQueryString = listAppend(canonicalQueryString, parameter[1] & "=" & parameter[2], "&") />
        </cfloop>

        <cfset canonicalRequest = arguments.method & chr(10) & arguments.canonicalUri & chr(10) & canonicalQueryString & chr(10)
            & "host:" & trim(arguments.host) & chr(10) & chr(10) & "host" & chr(10) & "UNSIGNED-PAYLOAD" />
        <cfset signature = signatureFor(
            secretAccessKey = arguments.credentials.secretAccessKey,
            dateStamp = dateStamp,
            region = arguments.region,
            service = arguments.service,
            stringToSign = "AWS4-HMAC-SHA256" & chr(10) & amzDate & chr(10) & credentialScope & chr(10) & sha256Hex(canonicalRequest)
        ) />

        <cfreturn canonicalQueryString & "&X-Amz-Signature=" & signature />
    </cffunction>

    <!--- The lower-case hex SHA-256 of a payload: a string (hashed as its UTF-8 bytes) or binary (hashed as is). --->
    <cffunction name="sha256Hex" access="public" returntype="string" output="false">
        <cfargument name="value" type="any" required="true" />
        <cfreturn lCase(hash(isBinary(arguments.value) ? arguments.value : charsetDecode(toString(arguments.value), "utf-8"), "SHA-256")) />
    </cffunction>

    <!--- RFC 3986 percent-encoding as SigV4 requires: every UTF-8 byte but A-Z a-z 0-9 - _ . ~ is encoded as %XX (upper-case
          hex), so a space is %20 and * is %2A. encodeSlash false keeps "/" for an object key's path. Byte by byte over the
          UTF-8 encoding, so it doesn't depend on any engine's urlEncodedFormat rules. --->
    <cffunction name="uriEncode" access="public" returntype="string" output="false">
        <cfargument name="value" type="string" required="true" />
        <cfargument name="encodeSlash" type="boolean" required="false" default="true" />

        <cfset var hex = uCase(binaryEncode(charsetDecode(arguments.value, "utf-8"), "hex")) />
        <cfset var parts = [] />
        <cfset var position = 0 />
        <cfset var pair = "" />
        <cfset var code = 0 />

        <cfloop from="1" to="#len(hex)#" step="2" index="position">
            <cfset pair = mid(hex, position, 2) />
            <cfset code = inputBaseN(pair, 16) />
            <cfif (code GTE 48 AND code LTE 57) OR (code GTE 65 AND code LTE 90) OR (code GTE 97 AND code LTE 122)
                  OR code EQ 45 OR code EQ 46 OR code EQ 95 OR code EQ 126 OR (code EQ 47 AND NOT arguments.encodeSlash)>
                <cfset arrayAppend(parts, chr(code)) />
            <cfelse>
                <cfset arrayAppend(parts, "%" & pair) />
            </cfif>
        </cfloop>
        <cfreturn arrayToList(parts, "") />
    </cffunction>

    <cffunction name="signatureFor" access="private" returntype="string" output="false">
        <cfargument name="secretAccessKey" type="string" required="true" />
        <cfargument name="dateStamp" type="string" required="true" />
        <cfargument name="region" type="string" required="true" />
        <cfargument name="service" type="string" required="true" />
        <cfargument name="stringToSign" type="string" required="true" />

        <cfset var kDate = hmacSHA256Binary("AWS4" & arguments.secretAccessKey, arguments.dateStamp) />
        <cfset var kRegion = hmacSHA256Binary(kDate, arguments.region) />
        <cfset var kService = hmacSHA256Binary(kRegion, arguments.service) />
        <cfset var kSigning = hmacSHA256Binary(kService, "aws4_request") />
        <cfreturn lCase(binaryEncode(hmacSHA256Binary(kSigning, arguments.stringToSign), "hex")) />
    </cffunction>

    <!--- HMAC-SHA256 of data (UTF-8) as bytes, so each step of the key derivation can key the next. --->
    <cffunction name="hmacSHA256Binary" access="private" returntype="binary" output="false">
        <cfargument name="key" type="any" required="true" hint="String (UTF-8) or binary key" />
        <cfargument name="data" type="string" required="true" />
        <cfreturn binaryDecode(hmac(arguments.data, arguments.key, "HMACSHA256", "utf-8"), "hex") />
    </cffunction>

</cfcomponent>
