<cfcomponent displayname="file_upload" output="false"
    hint="A browser uploading a file straight to the default store, checked at both ends. start() makes the moo_file and a presigned PUT URL signed for one Content-Type and Content-Length, so the store refuses any other body; finish() checks what the store holds (its size, its type, and that its first bytes are the kind of file its name says) before the file counts, and removes it otherwise. Each upload belongs to an owner the caller vouches for (a profile, or a record the visitor owns): only an ask naming the same owner may finish or discard it. An upload never finished is abandoned; sweep() removes those with their objects. Uploads under way live in moo_file_upload.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <!--- Each kind of file a caller may accept: its extensions, the Content-Type each is stored as, and the
              signatures (hex of the first bytes, ? for any one byte) a file of the kind starts with. A file must start
              with a signature of its own kind, whichever extension it carries within it, so a JPEG named .png is still
              an image and a page named .jpg is not. SVG is no kind: it is a document that can run script. --->
        <cfscript>
            variables.KINDS = {
                "image": {
                    "types": { "jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "gif": "image/gif", "webp": "image/webp",
                               "heic": "image/heic", "heif": "image/heif", "tif": "image/tiff", "tiff": "image/tiff", "bmp": "image/bmp" },
                    "signatures": [
                        "ffd8ff",                                   // JPEG
                        "89504e470d0a1a0a",                         // PNG
                        "474946383761", "474946383961",             // GIF87a, GIF89a
                        "52494646????????57454250",                 // RIFF....WEBP
                        // ftyp with a HEIC/HEIF brand: heic, heix, hevc, hevx, heim, heis, mif1, msf1
                        "????????6674797068656963", "????????6674797068656978", "????????6674797068657663", "????????6674797068657678",
                        "????????667479706865696d", "????????6674797068656973", "????????667479706d696631", "????????667479706d736631",
                        "49492a00", "4d4d002a",                     // TIFF, little- and big-endian
                        "424d"                                      // BMP
                    ]
                },
                "pdf": {
                    "types": { "pdf": "application/pdf" },
                    "signatures": [ "255044462d" ]                  // %PDF-
                },
                "video": {
                    "types": { "mp4": "video/mp4", "m4v": "video/x-m4v", "mov": "video/quicktime", "webm": "video/webm", "mkv": "video/x-matroska", "avi": "video/x-msvideo" },
                    "signatures": [
                        "????????66747970",                         // ftyp (MP4, MOV)
                        // older QuickTime opens with another atom: moov, wide, mdat, free, skip
                        "????????6d6f6f76", "????????77696465", "????????6d646174", "????????66726565", "????????736b6970",
                        "1a45dfa3",                                 // EBML (WebM, Matroska)
                        "52494646????????41564920"                  // RIFF....AVI
                    ]
                },
                "zip": {
                    "types": { "zip": "application/zip" },
                    "signatures": [ "504b0304", "504b0506" ]        // PK, a zip with entries or an empty one
                },
                // Word, Excel and PowerPoint's current formats, each a zip of XML. The older .doc, .xls and .ppt are
                // not here: they are another format, and the usual carrier of macros.
                "office": {
                    "types": { "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                               "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                               "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation" },
                    "signatures": [ "504b0304" ]                    // PK, a zip with entries
                },
                // Drawings and models as a workshop exchanges them: STEP, DWG and DXF.
                "drawing": {
                    "types": { "step": "model/step", "stp": "model/step", "dwg": "application/acad", "dxf": "application/dxf" },
                    "signatures": [
                        "49534f2d31303330332d3231",                 // ISO-10303-21 (STEP)
                        "41433130",                                 // AC10.. (DWG, every version since R13)
                        // A text DXF opens with group code 0 and SECTION, the code bare or padded to three
                        // characters, on Unix or Windows lines...
                        "300a53454354494f4e", "300d0a53454354494f4e",
                        "20300a53454354494f4e", "20300d0a53454354494f4e",
                        "2020300a53454354494f4e", "2020300d0a53454354494f4e",
                        // ...or with a comment (group code 999) before it
                        "3939390a", "3939390d0a",
                        "4175746f4341442042696e61"                  // AutoCAD Bina(ry DXF)
                    ]
                }
            };
            // The file-type icon a moo_file shows until it has a thumbnail of its own: /_static/icons/fa/<name>.svg,
            // named for its extension except where two extensions share one.
            variables.ICONS = { "heic": "heif", "tif": "tiff", "m4v": "mp4", "zip": "default",
                                "docx": "default", "xlsx": "default", "pptx": "default",
                                "step": "default", "stp": "default", "dwg": "default", "dxf": "default" };
        </cfscript>
        <!--- How long the presigned URL works, and how long an upload may stay unfinished before sweep() takes it. --->
        <cfset variables.UPLOAD_SECONDS = 300 />
        <cfset variables.ABANDONED_SECONDS = 86400 />
        <!--- Enough of a file to read any signature above. --->
        <cfset variables.SIGNATURE_BYTES = 12 />
        <cfset variables.MESSAGES = {
            "file_type": "That kind of file can't be uploaded here.",
            "file_size": "That file is too big to upload here.",
            "empty": "That file is empty.",
            "unknown_upload": "That upload can't be found. Please try again.",
            "not_uploaded": "The file didn't finish uploading. Please try again.",
            "file_content": "That file isn't the kind of file its name says it is."
        } />
        <cfreturn this />
    </cffunction>


    <cffunction name="start" access="public" returntype="struct" output="false"
        hint="Starts an upload: makes the moo_file, records the upload for its owner, and returns { success: true, file, presignedURL, headers } for the browser to PUT the file's bytes to presignedURL with exactly these headers (its Content-Length is the browser's own, from the file). A file of a kind the caller doesn't accept, an empty one or one over max_bytes is { success: false, error_code (file_type, empty or file_size), error }, and makes nothing. Throws file_upload.invalid for a caller bug: no owner, an unknown kind, or max_bytes under 1.">
        <cfargument name="file_name" type="string" required="true" hint="The file's own name, as the browser has it." />
        <cfargument name="file_size" type="any" required="true" hint="Its size in bytes, as the browser has it: the URL is signed for exactly this many." />
        <cfargument name="owner" type="string" required="true" hint="Who the upload belongs to, as the caller vouches: finish() and discard() need the same." />
        <cfargument name="kinds" type="string" required="true" hint="The kinds of file accepted: a list of image, pdf, video, zip, office and drawing." />
        <cfargument name="max_bytes" type="numeric" required="true" hint="The largest file accepted, in bytes." />

        <cfset assertOwner(arguments.owner) />
        <cfset var types = typesFor(arguments.kinds) />
        <cfif NOT isWholeNumber(arguments.max_bytes) OR arguments.max_bytes LT 1>
            <cfthrow type="file_upload.invalid" message="max_bytes is a whole number of bytes, at least 1, not #arguments.max_bytes#" />
        </cfif>

        <cfset var name = trim(arguments.file_name) />
        <cfset var extension = listLen(name, ".") GT 1 ? lCase(listLast(name, ".")) : "" />
        <cfif NOT structKeyExists(types, extension)>
            <cfreturn refusal("file_type") />
        </cfif>
        <cfif NOT isWholeNumber(arguments.file_size) OR arguments.file_size LT 1>
            <cfreturn refusal("empty") />
        </cfif>
        <cfif arguments.file_size GT arguments.max_bytes>
            <cfreturn refusal("file_size") />
        </cfif>

        <cfset var contentType = types[extension] />
        <cfset var size = int(arguments.file_size) />
        <cfset var safeName = application.lib.core.sanitize_s3_key(filename = name, allowed_extensions = structKeyList(types), max_base_length = 100) />
        <cfset var path = "/moo_file/#dateFormat(now(), 'yyyy-mm')#/#lCase(createUUID())#/#safeName#" />
        <cfset var store = application.lib.s3_client.defaultStore() />

        <cfset var saved = application.lib.db.save(
            table_name = "moo_file",
            data = {
                "name": name,
                "size": size,
                "thumbnail": "/_static/icons/fa/#variables.ICONS[extension] ?: extension#.svg",
                "path": path
            },
            returnFormat = "cfml"
        ) />
        <cftry>
            <cfset application.lib.db.save(
                table_name = "moo_file_upload",
                data = { "file_id": saved.id, "owner": arguments.owner, "content_type": contentType, "size": size }
            ) />
            <cfset var presignedURL = application.lib.s3_client.presignedUrl(
                store = store,
                objectKey = path,
                method = "PUT",
                expiresSeconds = variables.UPLOAD_SECONDS,
                signedHeaders = { "Content-Type": contentType, "Content-Length": size }
            ) />
            <cfcatch>
                <!--- Nothing was given to the browser: the file and its upload go (the upload by the cascade). --->
                <cfset application.lib.db.delete(table_name = "moo_file", id = saved.id) />
                <cfrethrow />
            </cfcatch>
        </cftry>

        <cfreturn {
            "success": true,
            "file": application.lib.db.read(table_name = "moo_file", id = saved.id, returnFormat = "cfml"),
            "presignedURL": presignedURL,
            "headers": { "Content-Type": contentType }
        } />
    </cffunction>


    <cffunction name="answer" access="public" returntype="struct" output="false"
        hint="An upload endpoint's whole answer, for the usual endpoint that only uploads: finish() when the request names a file_id, start() otherwise (with its file_name and file_size). A refusal sets the response to 422 marked X-Refusal, so req() shows its error, and returns { error, error_code }; anything else is start()'s or finish()'s own answer.">
        <cfargument name="data" type="struct" required="true" hint="The request's data: { file_name, file_size } to start, { file_id } to finish." />
        <cfargument name="owner" type="string" required="true" />
        <cfargument name="kinds" type="string" required="true" />
        <cfargument name="max_bytes" type="numeric" required="true" />

        <cfset var result = len(trim(arguments.data.file_id ?: ""))
            ? finish(file_id = trim(arguments.data.file_id), owner = arguments.owner)
            : start(file_name = arguments.data.file_name ?: "", file_size = arguments.data.file_size ?: "", owner = arguments.owner, kinds = arguments.kinds, max_bytes = arguments.max_bytes) />
        <cfif result.success>
            <cfreturn result />
        </cfif>
        <cfheader statuscode="422" />
        <cfheader name="X-Refusal" value="true" />
        <cfreturn { "error": result.error, "error_code": result.error_code } />
    </cffunction>


    <cffunction name="finish" access="public" returntype="struct" output="false"
        hint="Finishes an upload once the browser's PUT is done: checks the store holds the file at the size and type its URL was signed for, and that its first bytes are a file of its kind. Returns { success: true, file } (an image's thumbnail now its own picture), and the upload is no longer under way. An upload this owner has no such upload of is { success: false, error_code: unknown_upload, error } and changes nothing. A file the store doesn't hold, or holds as something else, is removed with its upload: { success: false, error_code (not_uploaded or file_content), error }.">
        <cfargument name="file_id" type="string" required="true" />
        <cfargument name="owner" type="string" required="true" />

        <cfset assertOwner(arguments.owner) />
        <cfset var upload = uploadFor(arguments.file_id, arguments.owner) />
        <cfif structIsEmpty(upload)>
            <cfreturn refusal("unknown_upload") />
        </cfif>

        <cfset var fault = storedFault(upload.path, upload.size, upload.content_type) />
        <cfif len(fault)>
            <cfset remove(upload) />
            <cfreturn refusal(fault) />
        </cfif>

        <cfquery>
            DELETE FROM moo_file_upload WHERE file_id = <cfqueryparam cfsqltype="other" value="#upload.file_id#" />
        </cfquery>
        <cfif kindOf(upload.content_type) EQ "image">
            <cfset application.lib.db.save(
                table_name = "moo_file",
                data = {
                    "id": upload.file_id,
                    "thumbnail": application.lib.cloudflare.signed_asset_url(
                        key = upload.path,
                        expiry_type = "NEVER",
                        kind = "i",
                        options = { width = 300, height = 300, fit = "cover" }
                    )
                }
            ) />
        </cfif>
        <cfreturn { "success": true, "file": application.lib.db.read(table_name = "moo_file", id = upload.file_id, returnFormat = "cfml") } />
    </cffunction>


    <cffunction name="discard" access="public" returntype="boolean" output="false"
        hint="Drops an upload of this owner's still under way (the browser gave up on it): its object, if the PUT got there, its moo_file and its upload. False when this owner has no such upload, which changes nothing.">
        <cfargument name="file_id" type="string" required="true" />
        <cfargument name="owner" type="string" required="true" />

        <cfset assertOwner(arguments.owner) />
        <cfset var upload = uploadFor(arguments.file_id, arguments.owner) />
        <cfif structIsEmpty(upload)>
            <cfreturn false />
        </cfif>
        <cfset remove(upload) />
        <cfreturn true />
    </cffunction>


    <cffunction name="underWay" access="public" returntype="numeric" output="false"
        hint="How many of this owner's uploads are under way: started, and neither finished, discarded nor swept. A caller that caps how many files an owner holds counts these with the finished ones.">
        <cfargument name="owner" type="string" required="true" />

        <cfset assertOwner(arguments.owner) />
        <cfquery name="local.qCount" returntype="array">
            SELECT count(*)::int AS n FROM moo_file_upload WHERE owner = <cfqueryparam cfsqltype="varchar" value="#arguments.owner#" />
        </cfquery>
        <cfreturn local.qCount[1].n />
    </cffunction>


    <cffunction name="sweep" access="public" returntype="numeric" output="false"
        hint="Removes every upload left unfinished for longer than older_than_seconds (a day by default): its object, its moo_file and its upload. Returns how many it removed. A project runs it on a schedule.">
        <cfargument name="older_than_seconds" type="numeric" required="false" default="#variables.ABANDONED_SECONDS#" />

        <cfif NOT isWholeNumber(arguments.older_than_seconds) OR arguments.older_than_seconds LT variables.UPLOAD_SECONDS>
            <cfthrow type="file_upload.invalid" message="sweep() takes uploads at least #variables.UPLOAD_SECONDS# seconds old (the life of their URL), not #arguments.older_than_seconds#" />
        </cfif>
        <cfquery name="local.qAbandoned" returntype="array">
            SELECT u.file_id::text AS file_id, u.owner, u.content_type, u.size, f.path
            FROM moo_file_upload u
            JOIN moo_file f ON f.id = u.file_id
            WHERE u.created_at < now() - make_interval(secs => <cfqueryparam cfsqltype="integer" value="#arguments.older_than_seconds#" />)
            ORDER BY u.created_at
        </cfquery>
        <cfloop array="#local.qAbandoned#" item="local.upload">
            <cfset remove(local.upload) />
        </cfloop>
        <cfreturn arrayLen(local.qAbandoned) />
    </cffunction>


    <cffunction name="storedFault" access="public" returntype="string" output="false"
        hint="What is wrong with the object the default store holds at path, against what its upload URL was signed for: not_uploaded when there is none, file_content when its size or type differs or its first bytes aren't a file of the type's kind, and an empty string when it is right. lib video_upload checks its uploads with this too.">
        <cfargument name="path" type="string" required="true" />
        <cfargument name="size" type="numeric" required="true" />
        <cfargument name="content_type" type="string" required="true" />

        <cfset var store = application.lib.s3_client.defaultStore() />
        <cfset var held = application.lib.s3_client.headObject(store, arguments.path) />
        <cfif NOT held.exists>
            <cfreturn "not_uploaded" />
        </cfif>
        <cfif held.size NEQ arguments.size OR compareNoCase(trim(listFirst(held.contentType, ";")), arguments.content_type) NEQ 0
              OR NOT startsAsKind(application.lib.s3_client.readObjectStart(store, arguments.path, variables.SIGNATURE_BYTES), kindOf(arguments.content_type))>
            <cfreturn "file_content" />
        </cfif>
        <cfreturn "" />
    </cffunction>


    <cffunction name="refusalMessage" access="public" returntype="string" output="false"
        hint="The words a refusal with this error code is given: lib video_upload's refusals read the same.">
        <cfargument name="code" type="string" required="true" />
        <cfif NOT structKeyExists(variables.MESSAGES, arguments.code)>
            <cfthrow type="file_upload.invalid" message="'#arguments.code#' isn't a refusal (#structKeyList(variables.MESSAGES)#)" />
        </cfif>
        <cfreturn variables.MESSAGES[arguments.code] />
    </cffunction>


    <cffunction name="kinds" access="public" returntype="struct" output="false"
        hint="Each kind's extensions and the Content-Type each is stored as: { image: { jpg: 'image/jpeg', ... }, ... }.">
        <cfset var result = {} />
        <cfloop collection="#variables.KINDS#" item="local.kind">
            <cfset result[local.kind] = duplicate(variables.KINDS[local.kind].types) />
        </cfloop>
        <cfreturn result />
    </cffunction>


    <cffunction name="startsAsKind" access="public" returntype="boolean" output="false"
        hint="Whether these first bytes of a file are a signature of the kind (image, pdf, video, zip, office or drawing).">
        <cfargument name="bytes" type="binary" required="true" />
        <cfargument name="kind" type="string" required="true" />

        <cfif NOT structKeyExists(variables.KINDS, arguments.kind)>
            <cfthrow type="file_upload.invalid" message="'#arguments.kind#' isn't a kind of file (#structKeyList(variables.KINDS)#)" />
        </cfif>
        <cfset var hex = lCase(binaryEncode(arguments.bytes, "hex")) />
        <cfloop array="#variables.KINDS[arguments.kind].signatures#" item="local.signature">
            <cfif len(hex) GTE len(local.signature) AND reFind("^" & replace(local.signature, "?", ".", "all"), hex)>
                <cfreturn true />
            </cfif>
        </cfloop>
        <cfreturn false />
    </cffunction>


    <!--- The upload with this file id, if it is this owner's: { file_id, owner, content_type, size, path }, or {}. --->
    <cffunction name="uploadFor" access="private" returntype="struct" output="false">
        <cfargument name="file_id" type="string" required="true" />
        <cfargument name="owner" type="string" required="true" />

        <cfif NOT reFind("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", arguments.file_id)>
            <cfreturn {} />
        </cfif>
        <cfquery name="local.qUpload" returntype="array">
            SELECT u.file_id::text AS file_id, u.owner, u.content_type, u.size, f.path
            FROM moo_file_upload u
            JOIN moo_file f ON f.id = u.file_id
            WHERE u.file_id = <cfqueryparam cfsqltype="other" value="#arguments.file_id#" />
              AND u.owner = <cfqueryparam cfsqltype="varchar" value="#arguments.owner#" />
        </cfquery>
        <cfreturn arrayLen(local.qUpload) ? local.qUpload[1] : {} />
    </cffunction>


    <!--- Removes an upload: its object (deleting one that never arrived succeeds), then its moo_file, which takes the
          upload with it. --->
    <cffunction name="remove" access="private" returntype="void" output="false">
        <cfargument name="upload" type="struct" required="true" />

        <cfset application.lib.s3_client.deleteObject(application.lib.s3_client.defaultStore(), arguments.upload.path) />
        <cfset application.lib.db.delete(table_name = "moo_file", id = arguments.upload.file_id) />
    </cffunction>


    <!--- Extension -> Content-Type for every kind in the list. --->
    <cffunction name="typesFor" access="private" returntype="struct" output="false">
        <cfargument name="kinds" type="string" required="true" />

        <cfset var types = {} />
        <cfif NOT listLen(arguments.kinds)>
            <cfthrow type="file_upload.invalid" message="An upload accepts at least one kind of file (#structKeyList(variables.KINDS)#)" />
        </cfif>
        <cfloop list="#arguments.kinds#" item="local.kind">
            <cfif NOT structKeyExists(variables.KINDS, trim(local.kind))>
                <cfthrow type="file_upload.invalid" message="'#local.kind#' isn't a kind of file (#structKeyList(variables.KINDS)#)" />
            </cfif>
            <cfset structAppend(types, variables.KINDS[trim(local.kind)].types) />
        </cfloop>
        <cfreturn types />
    </cffunction>


    <!--- The kind a Content-Type this lib signed belongs to. --->
    <cffunction name="kindOf" access="private" returntype="string" output="false">
        <cfargument name="content_type" type="string" required="true" />

        <cfloop collection="#variables.KINDS#" item="local.kind">
            <cfloop collection="#variables.KINDS[local.kind].types#" item="local.extension">
                <cfif variables.KINDS[local.kind].types[local.extension] EQ arguments.content_type>
                    <cfreturn local.kind />
                </cfif>
            </cfloop>
        </cfloop>
        <cfthrow type="file_upload.invalid" message="'#arguments.content_type#' isn't a type this lib signs uploads for" />
    </cffunction>


    <cffunction name="assertOwner" access="private" returntype="void" output="false">
        <cfargument name="owner" type="string" required="true" />
        <cfif NOT len(trim(arguments.owner))>
            <cfthrow type="file_upload.invalid" message="An upload belongs to an owner the caller names; none was given" />
        </cfif>
    </cffunction>


    <!--- A whole number of 0 or more, however big: not isValid("integer"), which stops at 2^31 (2 GiB as bytes). --->
    <cffunction name="isWholeNumber" access="private" returntype="boolean" output="false">
        <cfargument name="value" type="any" required="true" />
        <cfreturn isSimpleValue(arguments.value) AND reFind("^[0-9]+$", trim(arguments.value)) GT 0 />
    </cffunction>


    <cffunction name="refusal" access="private" returntype="struct" output="false">
        <cfargument name="code" type="string" required="true" />
        <cfreturn { "success": false, "error_code": arguments.code, "error": variables.MESSAGES[arguments.code] } />
    </cffunction>

</cfcomponent>
