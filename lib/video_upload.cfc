<cfcomponent displayname="video_upload" output="false"
    hint="A browser uploading a video straight to the default store, checked at both ends, then handed to Cloudflare Stream: lib file_upload's checks for a moo_video. start() makes the moo_video and a presigned PUT URL signed for one Content-Type and Content-Length, so the store refuses any other body; finish() checks what the store holds (lib file_upload storedFault(): its size, its type, and that its first bytes are a video) and only then sends it to Stream (moo_video sendToStream()), removing it otherwise. Each upload belongs to an owner the caller vouches for: only an ask naming the same owner may finish or discard it. An upload never finished is abandoned; sweep() removes those with their videos and objects. Uploads under way live in moo_video_upload.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <!--- How long the presigned URL works (a video takes longer to send than a photo), and how long an upload may
              stay unfinished before sweep() takes it. --->
        <cfset variables.UPLOAD_SECONDS = 1800 />
        <cfset variables.ABANDONED_SECONDS = 86400 />
        <!--- The file-type icon a moo_video shows until Stream has a thumbnail: /_static/icons/fa/<name>.svg, named for
              its extension except where two extensions share one. --->
        <cfset variables.ICONS = { "m4v": "mp4" } />
        <cfreturn this />
    </cffunction>


    <cffunction name="start" access="public" returntype="struct" output="false"
        hint="Starts a video upload: makes the moo_video (with the caller's metadata merged into its own), records the upload for its owner, and returns { success: true, video, video_id, presignedURL, headers } for the browser to PUT the file to presignedURL with exactly these headers. A file that isn't a video, an empty one or one over max_bytes is { success: false, error_code (file_type, empty or file_size), error }, and makes nothing. Throws video_upload.invalid for a caller bug: no owner, or max_bytes under 1.">
        <cfargument name="file_name" type="string" required="true" hint="The file's own name, as the browser has it." />
        <cfargument name="file_size" type="any" required="true" hint="Its size in bytes, as the browser has it: the URL is signed for exactly this many." />
        <cfargument name="owner" type="string" required="true" hint="Who the upload belongs to, as the caller vouches: finish() and discard() need the same." />
        <cfargument name="max_bytes" type="numeric" required="true" hint="The largest video accepted, in bytes." />
        <cfargument name="metadata" type="struct" required="false" default="#{}#" hint="More for the video's metadata, written with the row (what the video is for, a length limit)." />

        <cfset assertOwner(arguments.owner) />
        <cfif NOT isWholeNumber(arguments.max_bytes) OR arguments.max_bytes LT 1>
            <cfthrow type="video_upload.invalid" message="max_bytes is a whole number of bytes, at least 1, not #arguments.max_bytes#" />
        </cfif>

        <cfset var types = application.lib.file_upload.kinds().video />
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
        <cfset var path = "/moo_video/#dateFormat(now(), 'yyyy-mm')#/#createUniqueId()#/#safeName#" />
        <cfset var metadata = duplicate(arguments.metadata) />
        <cfset structAppend(metadata, { "stream_status": "uploading", "stream_ready": false, "stream_error": "" }, true) />

        <cfset var saved = application.lib.db.save(
            table_name = "moo_video",
            data = {
                "name": name,
                "path": path,
                "thumbnail": "/_static/icons/fa/#variables.ICONS[extension] ?: extension#.svg",
                "metadata": metadata
            },
            returnFormat = "cfml"
        ) />
        <cftry>
            <cfset application.lib.db.save(
                table_name = "moo_video_upload",
                data = { "video_id": saved.id, "owner": arguments.owner, "content_type": contentType, "size": size }
            ) />
            <cfset var presignedURL = application.lib.s3_client.presignedUrl(
                store = application.lib.s3_client.defaultStore(),
                objectKey = path,
                method = "PUT",
                expiresSeconds = variables.UPLOAD_SECONDS,
                signedHeaders = { "Content-Type": contentType, "Content-Length": size }
            ) />
            <cfcatch>
                <!--- Nothing was given to the browser: the video and its upload go (the upload by the cascade). --->
                <cfset application.lib.db.delete(table_name = "moo_video", id = saved.id) />
                <cfrethrow />
            </cfcatch>
        </cftry>

        <cfreturn {
            "success": true,
            "video": application.lib.db.getService(table_name = "moo_video").describe(saved.id),
            "video_id": saved.id,
            "presignedURL": presignedURL,
            "headers": { "Content-Type": contentType }
        } />
    </cffunction>


    <cffunction name="finish" access="public" returntype="struct" output="false"
        hint="Finishes a video upload once the browser's PUT is done: checks the store holds the video at the size and type its URL was signed for and that its first bytes are a video, then hands it to Stream (moo_video sendToStream()). Returns { success: true, video } (the video as describe() gives it), and the upload is no longer under way. An upload this owner has no such upload of is { success: false, error_code: unknown_upload, error } and changes nothing. A file the store doesn't hold, or holds as something else, is removed with its video and upload: { success: false, error_code (not_uploaded or file_content), error }, and Stream is never asked. A copy Stream refuses throws moo_video.streamRefused and leaves the upload under way, to finish again or be swept; any other failure throws and leaves it finished, since Stream may hold a video.">
        <cfargument name="video_id" type="string" required="true" />
        <cfargument name="owner" type="string" required="true" />
        <cfargument name="source" type="string" required="true" hint="What the video is for, recorded in Stream's metadata." />
        <cfargument name="release" type="any" required="false" default="" hint="For a caller whose own record refers to the video before its upload finishes: a function, given the video id, that lets go of it, called before a refused upload's video is removed." />

        <cfset assertOwner(arguments.owner) />
        <cfif NOT isSimpleValue(arguments.release) AND NOT isCustomFunction(arguments.release)>
            <cfthrow type="video_upload.invalid" message="release is a function given the video id" />
        </cfif>
        <cfset var upload = uploadFor(arguments.video_id, arguments.owner) />
        <cfif structIsEmpty(upload)>
            <cfreturn refusal("unknown_upload") />
        </cfif>

        <cfset var fault = application.lib.file_upload.storedFault(upload.path, upload.size, upload.content_type) />
        <cfif len(fault)>
            <cfif NOT isSimpleValue(arguments.release)>
                <cfset arguments.release(upload.video_id) />
            </cfif>
            <cfset remove(upload) />
            <cfreturn refusal(fault) />
        </cfif>

        <!--- Claimed in one statement, so of two finishes at once only one goes on to Stream; the other finds no
              upload. Only a copy Stream certainly refused (moo_video.streamRefused) puts the upload back as it was, to
              finish again or be swept: after any other failure Stream may hold a video, and asking again could bill a
              second one, so the upload stays finished and the caller sees the error. --->
        <cfquery name="local.qClaimed" returntype="array">
            DELETE FROM moo_video_upload
            WHERE video_id = <cfqueryparam cfsqltype="other" value="#upload.video_id#" />
              AND owner = <cfqueryparam cfsqltype="varchar" value="#arguments.owner#" />
            RETURNING id::text AS id, created_at::text AS created_at, created_by::text AS created_by
        </cfquery>
        <cfif NOT arrayLen(local.qClaimed)>
            <cfreturn refusal("unknown_upload") />
        </cfif>
        <cftry>
            <cfset var video = application.lib.db.getService(table_name = "moo_video").sendToStream(upload.video_id, arguments.source) />
            <cfcatch type="moo_video.streamRefused">
                <cfquery>
                    INSERT INTO moo_video_upload (id, video_id, owner, content_type, size, created_at, created_by)
                    VALUES (
                        <cfqueryparam cfsqltype="other" value="#local.qClaimed[1].id#" />,
                        <cfqueryparam cfsqltype="other" value="#upload.video_id#" />,
                        <cfqueryparam cfsqltype="varchar" value="#upload.owner#" />,
                        <cfqueryparam cfsqltype="varchar" value="#upload.content_type#" />,
                        <cfqueryparam cfsqltype="bigint" value="#upload.size#" />,
                        <cfqueryparam cfsqltype="varchar" value="#local.qClaimed[1].created_at#" />::timestamptz,
                        <cfqueryparam cfsqltype="other" value="#local.qClaimed[1].created_by ?: ''#" null="#NOT len(local.qClaimed[1].created_by ?: '')#" />
                    )
                </cfquery>
                <cfrethrow />
            </cfcatch>
        </cftry>
        <cfreturn { "success": true, "video": video } />
    </cffunction>


    <cffunction name="refused" access="public" returntype="struct" output="false"
        hint="An endpoint's answer for a refused start() or finish(): sets the response to 422 marked X-Refusal, so req() shows its error, and returns { error, error_code }.">
        <cfargument name="result" type="struct" required="true" hint="What start() or finish() returned, success false." />
        <cfif arguments.result.success>
            <cfthrow type="video_upload.invalid" message="refused() answers a refusal, not a successful upload" />
        </cfif>
        <cfheader statuscode="422" />
        <cfheader name="X-Refusal" value="true" />
        <cfreturn { "error": arguments.result.error, "error_code": arguments.result.error_code } />
    </cffunction>


    <cffunction name="discard" access="public" returntype="boolean" output="false"
        hint="Drops a video upload of this owner's still under way (the browser gave up on it): its object, if the PUT got there, its moo_video and its upload. False when this owner has no such upload, which changes nothing. A record that refers to the video (a draft's video_id) must let go of it first: the moo_video goes.">
        <cfargument name="video_id" type="string" required="true" />
        <cfargument name="owner" type="string" required="true" />

        <cfset assertOwner(arguments.owner) />
        <cfset var upload = uploadFor(arguments.video_id, arguments.owner) />
        <cfif structIsEmpty(upload)>
            <cfreturn false />
        </cfif>
        <cfset remove(upload) />
        <cfreturn true />
    </cffunction>


    <cffunction name="underWay" access="public" returntype="array" output="false"
        hint="The ids of this owner's video uploads under way (started, and neither finished, discarded nor swept), oldest first.">
        <cfargument name="owner" type="string" required="true" />

        <cfset assertOwner(arguments.owner) />
        <cfquery name="local.qUnderWay" returntype="array">
            SELECT video_id::text AS video_id FROM moo_video_upload
            WHERE owner = <cfqueryparam cfsqltype="varchar" value="#arguments.owner#" />
            ORDER BY created_at
        </cfquery>
        <cfreturn local.qUnderWay.map(function(row) { return row.video_id; }) />
    </cffunction>


    <cffunction name="abandoned" access="public" returntype="array" output="false"
        hint="The video uploads sweep() would remove now: { video_id, owner } for each left unfinished longer than older_than_seconds (a day by default), oldest first. A project whose own records refer to a video before its upload finishes lets go of these before the sweep.">
        <cfargument name="older_than_seconds" type="numeric" required="false" default="#variables.ABANDONED_SECONDS#" />

        <cfreturn abandonedUploads(arguments.older_than_seconds).map(function(upload) {
            return { "video_id": upload.video_id, "owner": upload.owner };
        }) />
    </cffunction>


    <cffunction name="sweep" access="public" returntype="numeric" output="false"
        hint="Removes every video upload left unfinished for longer than older_than_seconds (a day by default): its object, its moo_video and its upload. Returns how many it removed. One that can't be removed (a record still refers to its video: let go of abandoned() first) doesn't stop the rest; they are named in a video_upload.sweepIncomplete thrown at the end. A project runs it on a schedule.">
        <cfargument name="older_than_seconds" type="numeric" required="false" default="#variables.ABANDONED_SECONDS#" />

        <cfset var uploads = abandonedUploads(arguments.older_than_seconds) />
        <cfset var failed = [] />
        <cfloop array="#uploads#" item="local.upload">
            <!--- One upload that can't go (a record still refers to its video) doesn't stop the rest. --->
            <cftry>
                <cfset remove(local.upload) />
                <cfcatch>
                    <cfset arrayAppend(failed, "#local.upload.video_id# (#cfcatch.message#)") />
                </cfcatch>
            </cftry>
        </cfloop>
        <cfif arrayLen(failed)>
            <cfthrow type="video_upload.sweepIncomplete" message="#arrayLen(uploads) - arrayLen(failed)# of #arrayLen(uploads)# abandoned video uploads were removed; these could not be: #arrayToList(failed, '; ')#" />
        </cfif>
        <cfreturn arrayLen(uploads) />
    </cffunction>


    <cffunction name="abandonedUploads" access="private" returntype="array" output="false">
        <cfargument name="older_than_seconds" type="numeric" required="true" />

        <cfif NOT isWholeNumber(arguments.older_than_seconds) OR arguments.older_than_seconds LT variables.UPLOAD_SECONDS>
            <cfthrow type="video_upload.invalid" message="Abandoned video uploads are at least #variables.UPLOAD_SECONDS# seconds old (the life of their URL), not #arguments.older_than_seconds#" />
        </cfif>
        <cfquery name="local.qAbandoned" returntype="array">
            SELECT u.video_id::text AS video_id, u.owner, u.content_type, u.size, v.path
            FROM moo_video_upload u
            JOIN moo_video v ON v.id = u.video_id
            WHERE u.created_at < now() - make_interval(secs => <cfqueryparam cfsqltype="integer" value="#arguments.older_than_seconds#" />)
            ORDER BY u.created_at
        </cfquery>
        <cfreturn local.qAbandoned />
    </cffunction>


    <!--- The upload with this video id, if it is this owner's: { video_id, owner, content_type, size, path }, or {}. --->
    <cffunction name="uploadFor" access="private" returntype="struct" output="false">
        <cfargument name="video_id" type="string" required="true" />
        <cfargument name="owner" type="string" required="true" />

        <cfif NOT reFind("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", arguments.video_id)>
            <cfreturn {} />
        </cfif>
        <cfquery name="local.qUpload" returntype="array">
            SELECT u.video_id::text AS video_id, u.owner, u.content_type, u.size, v.path
            FROM moo_video_upload u
            JOIN moo_video v ON v.id = u.video_id
            WHERE u.video_id = <cfqueryparam cfsqltype="other" value="#arguments.video_id#" />
              AND u.owner = <cfqueryparam cfsqltype="varchar" value="#arguments.owner#" />
        </cfquery>
        <cfreturn arrayLen(local.qUpload) ? local.qUpload[1] : {} />
    </cffunction>


    <!--- Removes an upload: its object (deleting one that never arrived succeeds), then its moo_video, which takes the
          upload with it. --->
    <cffunction name="remove" access="private" returntype="void" output="false">
        <cfargument name="upload" type="struct" required="true" />

        <cfset application.lib.s3_client.deleteObject(application.lib.s3_client.defaultStore(), arguments.upload.path) />
        <cfset application.lib.db.delete(table_name = "moo_video", id = arguments.upload.video_id) />
    </cffunction>


    <cffunction name="assertOwner" access="private" returntype="void" output="false">
        <cfargument name="owner" type="string" required="true" />
        <cfif NOT len(trim(arguments.owner))>
            <cfthrow type="video_upload.invalid" message="An upload belongs to an owner the caller names; none was given" />
        </cfif>
    </cffunction>


    <!--- A whole number of 0 or more, however big: not isValid("integer"), which stops at 2^31. --->
    <cffunction name="isWholeNumber" access="private" returntype="boolean" output="false">
        <cfargument name="value" type="any" required="true" />
        <cfreturn isSimpleValue(arguments.value) AND reFind("^[0-9]+$", trim(arguments.value)) GT 0 />
    </cffunction>


    <cffunction name="refusal" access="private" returntype="struct" output="false">
        <cfargument name="code" type="string" required="true" />
        <cfreturn { "success": false, "error_code": arguments.code, "error": application.lib.file_upload.refusalMessage(arguments.code) } />
    </cffunction>

</cfcomponent>
