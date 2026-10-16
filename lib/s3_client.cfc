<cfcomponent displayname="S3 Client" hint="REST client for S3-compatible object stores (AWS S3, Cloudflare R2): read, write, stream to disk, check, delete and list objects, and presign URLs for a browser to upload or download directly. Every call takes a store from configure() or defaultStore(); credentials come from aws_credentials and signing from aws_sigv4, so the same client serves static-key and ECS task-role stores. Needs no Lucee S3 extension.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>

    <!--- Builds a validated store config. Throws immediately on a missing bucket, region or endpoint so misconfiguration
          surfaces at the call site that owns the settings, never as a later signing failure.
          endpoint: base URL of the S3 API (https://s3.ap-southeast-2.amazonaws.com or https://<account>.r2.cloudflarestorage.com).
          region: the SigV4 signing region (ap-southeast-2; R2 signs as "auto").
          Requests use path-style addressing (/bucket/key), which both AWS S3 and R2 support. --->
    <cffunction name="configure" access="public" returntype="struct" output="false">
        <cfargument name="label" type="string" required="true" hint="Names the store in error messages, e.g. 'Uploads store'" />
        <cfargument name="bucket" type="string" required="true" />
        <cfargument name="region" type="string" required="true" />
        <cfargument name="endpoint" type="string" required="true" />
        <cfargument name="accessKeyId" type="string" required="false" default="" hint="Static key; leave empty with secretAccessKey to use the ECS task role" />
        <cfargument name="secretAccessKey" type="string" required="false" default="" />

        <cfset var baseUrl = normalizeBaseUrl(arguments.endpoint) />

        <cfif NOT len(trim(arguments.bucket))>
            <cfthrow type="s3.config.missing" message="#arguments.label#: bucket is not configured" />
        </cfif>
        <cfif NOT len(trim(arguments.region))>
            <cfthrow type="s3.config.missing" message="#arguments.label#: region is not configured" />
        </cfif>
        <cfif NOT len(baseUrl)>
            <cfthrow type="s3.config.missing" message="#arguments.label#: endpoint is not configured" />
        </cfif>

        <cfreturn {
            label: arguments.label,
            bucket: trim(arguments.bucket),
            region: trim(arguments.region),
            baseUrl: baseUrl,
            host: hostFromBaseUrl(baseUrl),
            accessKeyId: trim(arguments.accessKeyId),
            secretAccessKey: trim(arguments.secretAccessKey)
        } />
    </cffunction>

    <!--- The application's own store, the one Moopa's uploads (moo_file, moo_video) use. Its bucket is the S3_BUCKET
          environment variable; its endpoint, region and keys are the Application.cfc S3 settings, in Lucee's own names:
            this.s3 = { host: "<endpoint>", defaultLocation: "<region>", accessKeyId: "...", awsSecretKey: "..." };
          defaultLocation is the signing region (R2: "auto"). Leave both keys empty to sign with the ECS task role. --->
    <cffunction name="defaultStore" access="public" returntype="struct" output="false">
        <cfreturn storeFromSettings(
            settings = getApplicationSettings().s3 ?: {},
            bucket = server.system.environment.S3_BUCKET ?: ""
        ) />
    </cffunction>

    <!--- The default store from given S3 settings and bucket: what defaultStore() reads from the application, taken as
          arguments so it can be checked without one. A missing setting throws s3.config.missing naming the exact
          this.s3 key or variable to set. --->
    <cffunction name="storeFromSettings" access="public" returntype="struct" output="false">
        <cfargument name="settings" type="struct" required="true" hint="An application's this.s3, as getApplicationSettings().s3 returns it." />
        <cfargument name="bucket" type="string" required="true" />

        <cfset var label = "Default S3 store (S3_BUCKET and this.s3)" />
        <cfif NOT len(trim(arguments.bucket))>
            <cfthrow type="s3.config.missing" message="#label#: the bucket is not configured; set the S3_BUCKET environment variable." />
        </cfif>
        <cfif NOT len(trim(arguments.settings.host ?: ""))>
            <cfthrow type="s3.config.missing" message="#label#: the endpoint is not configured; set this.s3.host in Application.cfc (e.g. https://<account>.r2.cloudflarestorage.com)." />
        </cfif>
        <cfif NOT len(trim(arguments.settings.defaultLocation ?: ""))>
            <cfthrow type="s3.config.missing" message="#label#: the region is not configured; set this.s3.defaultLocation in Application.cfc to the store's signing region (Cloudflare R2: ""auto""; AWS S3: e.g. ""ap-southeast-2"")." />
        </cfif>
        <cfreturn configure(
            label = label,
            bucket = arguments.bucket,
            region = arguments.settings.defaultLocation,
            endpoint = arguments.settings.host,
            accessKeyId = arguments.settings.accessKeyId ?: "",
            secretAccessKey = arguments.settings.awsSecretKey ?: ""
        ) />
    </cffunction>

    <!--- Returns [{ key, etag, size, last_modified }] for every object under prefix, following continuation tokens. Leading
          slashes are dropped from the prefix, as from every object key. --->
    <cffunction name="listObjects" access="public" returntype="array" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="prefix" type="string" required="true" />

        <cfset var sigv4 = application.lib.aws_sigv4 />
        <cfset var httpResult = {} />
        <cfset var listing = "" />
        <cfset var results = [] />
        <cfset var node = "" />
        <cfset var isTruncated = true />
        <cfset var continuationToken = "" />
        <cfset var queryString = "" />
        <cfset var prefix = reReplace(arguments.prefix, "^/+", "") />

        <cfloop condition="isTruncated">
            <!--- SigV4 requires canonical query string parameters sorted alphabetically --->
            <cfif len(continuationToken)>
                <cfset queryString = "continuation-token=" & sigv4.uriEncode(continuationToken) & "&list-type=2&prefix=" & sigv4.uriEncode(prefix) />
            <cfelse>
                <cfset queryString = "list-type=2&prefix=" & sigv4.uriEncode(prefix) />
            </cfif>

            <cfset httpResult = signedRequest(
                store = arguments.store,
                method = "GET",
                canonicalUri = "/" & arguments.store.bucket,
                canonicalQueryString = queryString
            ) />
            <!--- A ListBucketResult holds each object as a Contents child of the root, beside IsTruncated and
                  NextContinuationToken. Read by walking the root's children by local name, not XPath, which engines
                  support unevenly. --->
            <cfset listing = xmlParse(httpResult.fileContent ?: "").xmlRoot />
            <cfloop array="#listing.xmlChildren#" item="node">
                <cfif localName(node) EQ "Contents">
                    <cfset arrayAppend(results, {
                        key: childText(node, "Key"),
                        etag: replace(childText(node, "ETag"), '"', "", "all"),
                        size: childText(node, "Size"),
                        last_modified: childText(node, "LastModified")
                    }) />
                </cfif>
            </cfloop>

            <cfset continuationToken = childText(listing, "IsTruncated") EQ "true" ? childText(listing, "NextContinuationToken") : "" />
            <cfset isTruncated = len(continuationToken) GT 0 />
        </cfloop>

        <cfreturn results />
    </cffunction>

    <!--- An object's contents as text. --->
    <cffunction name="readObject" access="public" returntype="string" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="objectKey" type="string" required="true" />

        <cfset var httpResult = signedRequest(
            store = arguments.store,
            method = "GET",
            canonicalUri = objectCanonicalUri(arguments.store, arguments.objectKey),
            canonicalQueryString = ""
        ) />

        <cfreturn httpResult.fileContent ?: "" />
    </cffunction>

    <!--- An object's contents as bytes, held in memory: for a file small enough to handle whole, such as a PDF. A large
          object belongs on disk: downloadObject(). --->
    <cffunction name="readObjectBinary" access="public" returntype="binary" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="objectKey" type="string" required="true" />

        <cfset var httpResult = signedRequest(
            store = arguments.store,
            method = "GET",
            canonicalUri = objectCanonicalUri(arguments.store, arguments.objectKey),
            canonicalQueryString = "",
            binaryResponse = true
        ) />

        <cfreturn httpResult.fileContent />
    </cffunction>

    <!--- Streams an object to a file on disk, never holding it in memory. A failed download leaves no file behind. --->
    <cffunction name="downloadObject" access="public" returntype="void" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="objectKey" type="string" required="true" />
        <cfargument name="filePath" type="string" required="true" hint="Absolute path of the file to write; its directory must exist." />

        <cfset signedRequest(
            store = arguments.store,
            method = "GET",
            canonicalUri = objectCanonicalUri(arguments.store, arguments.objectKey),
            canonicalQueryString = "",
            filePath = arguments.filePath
        ) />
    </cffunction>

    <!--- Writes an object: value is text or bytes. --->
    <cffunction name="writeObject" access="public" returntype="void" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="objectKey" type="string" required="true" />
        <cfargument name="value" type="any" required="true" hint="A string or binary" />
        <cfargument name="contentType" type="string" required="false" default="application/octet-stream" />

        <cfif NOT isSimpleValue(arguments.value) AND NOT isBinary(arguments.value)>
            <cfthrow type="s3.request.invalid" message="#arguments.store.label#: writeObject takes a string or binary for #arguments.objectKey#" />
        </cfif>
        <cfset signedRequest(
            store = arguments.store,
            method = "PUT",
            canonicalUri = objectCanonicalUri(arguments.store, arguments.objectKey),
            canonicalQueryString = "",
            body = arguments.value,
            contentType = arguments.contentType
        ) />
    </cffunction>

    <!--- Whether an object exists, asking the store itself (a HEAD request): true on 200, false on 404, and anything else
          throws, since it says nothing about the object. --->
    <cffunction name="objectExists" access="public" returntype="boolean" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="objectKey" type="string" required="true" />

        <cfset var httpResult = signedRequest(
            store = arguments.store,
            method = "HEAD",
            canonicalUri = objectCanonicalUri(arguments.store, arguments.objectKey),
            canonicalQueryString = "",
            allowedStatuses = "404"
        ) />

        <cfreturn left(httpResult.statusCode ?: "", 3) NEQ "404" />
    </cffunction>

    <!--- Deletes an object. Deleting a key that isn't there succeeds, as S3 answers it. --->
    <cffunction name="deleteObject" access="public" returntype="void" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="objectKey" type="string" required="true" />

        <cfset signedRequest(
            store = arguments.store,
            method = "DELETE",
            canonicalUri = objectCanonicalUri(arguments.store, arguments.objectKey),
            canonicalQueryString = ""
        ) />
    </cffunction>

    <!--- A presigned URL for a client holding no credentials, typically a browser uploading (PUT) or downloading (GET)
          straight to the store. Works for expiresSeconds from now; any body and Content-Type may be sent with it. --->
    <cffunction name="presignedUrl" access="public" returntype="string" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="objectKey" type="string" required="true" />
        <cfargument name="method" type="string" required="true" hint="GET, PUT, HEAD or DELETE" />
        <cfargument name="expiresSeconds" type="numeric" required="true" />

        <cfset var canonicalUri = objectCanonicalUri(arguments.store, arguments.objectKey) />
        <cfset var credentials = application.lib.aws_credentials.resolve(
            accessKeyId = arguments.store.accessKeyId,
            secretAccessKey = arguments.store.secretAccessKey,
            label = arguments.store.label
        ) />

        <cfif NOT listFind("GET,PUT,HEAD,DELETE", uCase(arguments.method))>
            <cfthrow type="s3.request.invalid" message="#arguments.store.label#: a presigned URL is for GET, PUT, HEAD or DELETE, not #arguments.method#" />
        </cfif>

        <cfreturn arguments.store.baseUrl & canonicalUri & "?" & application.lib.aws_sigv4.presign(
            method = uCase(arguments.method),
            host = arguments.store.host,
            canonicalUri = canonicalUri,
            region = arguments.store.region,
            service = "s3",
            credentials = credentials,
            signingTime = now(),
            expiresSeconds = arguments.expiresSeconds
        ) />
    </cffunction>

    <!--- One signed request. Throws s3.request.failed unless the store answers 2xx, or one of allowedStatuses.
          binaryResponse keeps the body as bytes; filePath streams it to that file instead of memory. --->
    <cffunction name="signedRequest" access="private" returntype="struct" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="method" type="string" required="true" />
        <cfargument name="canonicalUri" type="string" required="true" />
        <cfargument name="canonicalQueryString" type="string" required="true" />
        <cfargument name="body" type="any" required="false" default="" />
        <cfargument name="contentType" type="string" required="false" default="" />
        <cfargument name="binaryResponse" type="boolean" required="false" default="false" />
        <cfargument name="filePath" type="string" required="false" default="" />
        <cfargument name="allowedStatuses" type="string" required="false" default="" />

        <cfset var httpResult = {} />
        <cfset var payloadHash = application.lib.aws_sigv4.sha256Hex(arguments.body) />
        <cfset var credentials = application.lib.aws_credentials.resolve(
            accessKeyId = arguments.store.accessKeyId,
            secretAccessKey = arguments.store.secretAccessKey,
            label = arguments.store.label
        ) />
        <cfset var signature = application.lib.aws_sigv4.sign(
            method = arguments.method,
            host = arguments.store.host,
            canonicalUri = arguments.canonicalUri,
            canonicalQueryString = arguments.canonicalQueryString,
            headers = { "x-amz-content-sha256": payloadHash },
            payloadHash = payloadHash,
            region = arguments.store.region,
            service = "s3",
            credentials = credentials,
            signingTime = now()
        ) />
        <cfset var requestUrl = arguments.store.baseUrl & arguments.canonicalUri & (len(arguments.canonicalQueryString) ? ("?" & arguments.canonicalQueryString) : "") />
        <cfset var toFile = len(arguments.filePath) GT 0 />
        <cfset var status = "" />
        <cfset var detail = "" />

        <!--- A streamed download that fails before an answer (a timeout, a dropped connection) may have written part of
              the file: remove it before the failure goes on. --->
        <cftry>
            <cfhttp url="#requestUrl#" method="#arguments.method#" result="httpResult" timeout="120" encodeurl="false"
                    getasbinary="#(arguments.binaryResponse OR toFile) ? 'yes' : 'auto'#"
                    attributeCollection="#toFile ? { path: getDirectoryFromPath(arguments.filePath), file: getFileFromPath(arguments.filePath) } : {}#">
                <cfhttpparam type="header" name="Host" value="#arguments.store.host#" />
                <cfhttpparam type="header" name="x-amz-date" value="#signature.amzDate#" />
                <cfhttpparam type="header" name="x-amz-content-sha256" value="#payloadHash#" />
                <cfif len(credentials.sessionToken)>
                    <cfhttpparam type="header" name="x-amz-security-token" value="#credentials.sessionToken#" />
                </cfif>
                <cfhttpparam type="header" name="Authorization" value="#signature.authorization#" />
                <cfif len(arguments.contentType)>
                    <cfhttpparam type="header" name="Content-Type" value="#arguments.contentType#" />
                </cfif>
                <cfif arguments.method EQ "PUT">
                    <cfhttpparam type="body" value="#arguments.body#" />
                </cfif>
            </cfhttp>
            <cfcatch>
                <cfif toFile>
                    <cfset discardFile(arguments.filePath) />
                </cfif>
                <cfrethrow />
            </cfcatch>
        </cftry>

        <cfset status = left(httpResult.statusCode ?: "", 3) />
        <cfif left(status, 1) NEQ "2" AND NOT listFind(arguments.allowedStatuses, status)>
            <!--- A streamed download wrote the store's answer to the file: read its start for the message, then remove it. --->
            <cfif toFile>
                <cfset detail = fileStart(arguments.filePath) />
                <cfset discardFile(arguments.filePath) />
            <cfelse>
                <cfset detail = isBinary(httpResult.fileContent ?: "") ? charsetEncode(httpResult.fileContent, "utf-8") : (httpResult.fileContent ?: "") />
            </cfif>
            <cfthrow type="s3.request.failed" message="#arguments.store.label#: #arguments.method# #arguments.canonicalUri# failed" detail="#httpResult.statusCode ?: 'unknown status'# #left(detail, 1000)#" />
        </cfif>

        <cfreturn httpResult />
    </cffunction>

    <!--- The first 1000 characters of a file as text, or "" when there's no file or it can't be read as text. --->
    <cffunction name="fileStart" access="private" returntype="string" output="false">
        <cfargument name="filePath" type="string" required="true" />
        <cfset var text = "" />
        <cfif fileExists(arguments.filePath) AND getFileInfo(arguments.filePath).size LTE 65536>
            <cftry>
                <cfset text = left(fileRead(arguments.filePath, "utf-8"), 1000) />
                <cfcatch><cfset text = "" /></cfcatch>
            </cftry>
        </cfif>
        <cfreturn text />
    </cffunction>

    <cffunction name="discardFile" access="private" returntype="void" output="false">
        <cfargument name="filePath" type="string" required="true" />
        <cfif fileExists(arguments.filePath)>
            <cffile action="delete" file="#arguments.filePath#" />
        </cfif>
    </cffunction>

    <cffunction name="objectCanonicalUri" access="private" returntype="string" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="objectKey" type="string" required="true" />
        <cfreturn "/" & arguments.store.bucket & "/" & encodeObjectKey(arguments.objectKey) />
    </cffunction>

    <!--- An object key as it goes on the wire: leading slashes dropped, each byte RFC 3986-encoded but "/". --->
    <cffunction name="encodeObjectKey" access="public" returntype="string" output="false">
        <cfargument name="objectKey" type="string" required="true" />
        <cfreturn application.lib.aws_sigv4.uriEncode(reReplace(arguments.objectKey, "^/+", ""), false) />
    </cffunction>

    <!--- The trimmed text of a node's first child element with this local name (any namespace prefix), or "". --->
    <cffunction name="childText" access="private" returntype="string" output="false">
        <cfargument name="parentNode" type="any" required="true" />
        <cfargument name="name" type="string" required="true" />

        <cfset var child = "" />
        <cfloop array="#arguments.parentNode.xmlChildren#" item="child">
            <cfif localName(child) EQ arguments.name>
                <cfreturn trim(child.xmlText ?: "") />
            </cfif>
        </cfloop>
        <cfreturn "" />
    </cffunction>

    <cffunction name="localName" access="private" returntype="string" output="false">
        <cfargument name="node" type="any" required="true" />
        <cfreturn listLast(arguments.node.xmlName, ":") />
    </cffunction>

    <cffunction name="normalizeBaseUrl" access="private" returntype="string" output="false">
        <cfargument name="value" type="string" required="true" />

        <cfset var baseUrl = trim(arguments.value) />
        <cfif NOT len(baseUrl)>
            <cfreturn "" />
        </cfif>
        <cfif NOT reFindNoCase("^https?://", baseUrl)>
            <cfset baseUrl = "https://" & baseUrl />
        </cfif>
        <cfreturn reReplace(baseUrl, "/+$", "", "all") />
    </cffunction>

    <cffunction name="hostFromBaseUrl" access="private" returntype="string" output="false">
        <cfargument name="value" type="string" required="true" />

        <cfset var hostValue = reReplace(trim(arguments.value), "^https?://", "", "one") />
        <cfreturn listFirst(hostValue, "/") />
    </cffunction>

</cfcomponent>
