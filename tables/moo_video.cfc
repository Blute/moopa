<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "title": "Video",
            "title_plural": "Videos",
            "item_label_template": "`${item.path}`",
            "fields": {
                "name": { "max_length": 2048 },
                "duration": { "type" : "int8" },
                "path": { "max_length": 2048 },
                "thumbnail": { "max_length": 2048 },
                "metadata": { "type":"jsonb" },
                "cloudflare_stream_id": { "max_length": 2048 }
            }
          }

        />

        <cfreturn this>
    </cffunction>





    <cffunction name="getVideoMetadata" access="private" returntype="struct" output="false">
        <cfargument name="video_record" type="struct" required="true" />

        <cfset var metadata = arguments.video_record.metadata ?: {} />
        <cfif isSimpleValue(metadata) AND isJSON(metadata)>
            <cfset metadata = deserializeJSON(metadata) />
        </cfif>
        <cfif !isStruct(metadata)>
            <cfset metadata = {} />
        </cfif>

        <cfreturn metadata />
    </cffunction>

    <cffunction name="getVideoId" access="private" returntype="string" output="false">
        <cfargument name="value" type="any" required="false" default="" />

        <cfif isStruct(arguments.value ?: "")>
            <cfreturn trim(arguments.value.id ?: "") />
        </cfif>

        <cfreturn trim(arguments.value ?: "") />
    </cffunction>

    <cffunction name="getCloudflareConfig" access="private" returntype="struct" output="false">
        <cfreturn {
            account_id: trim(server.system.environment.CLOUDFLARE_ACCOUNT_ID ?: ""),
            api_token: trim(server.system.environment.CLOUDFLARE_STREAM_API_TOKEN ?: "")
        } />
    </cffunction>

    <cffunction name="requestCloudflare" access="private" returntype="struct" output="false">
        <cfargument name="method" type="string" required="true" />
        <cfargument name="path" type="string" required="true" />
        <cfargument name="body" type="struct" required="false" default="#structNew()#" />

        <cfset var config = getCloudflareConfig() />
        <cfset var request_url = "https://api.cloudflare.com/client/v4/accounts/#config.account_id##arguments.path#" />
        <cfset var api_result = {} />
        <cfset var parsed = {} />
        <cfset var body_json = "" />

        <cfif listFindNoCase("POST,PUT,PATCH", arguments.method)>
            <cfset body_json = serializeJSON(arguments.body) />
        </cfif>

        <cfhttp method="#uCase(arguments.method)#" url="#request_url#" result="api_result" timeout="30">
            <cfhttpparam type="header" name="Authorization" value="Bearer #config.api_token#" />
            <cfhttpparam type="header" name="Content-Type" value="application/json" />
            <cfhttpparam type="header" name="Accept" value="application/json" />
            <cfif len(body_json)>
                <cfhttpparam type="body" value="#body_json#" />
            </cfif>
        </cfhttp>

        <cfif len(trim(api_result.fileContent ?: ""))>
            <cfset parsed = deserializeJSON(api_result.fileContent) />
        <cfelse>
            <cfset parsed = {} />
        </cfif>

        <cfreturn {
            success: true,
            result: (isStruct(parsed) ? (parsed.result ?: {}) : {}),
            details: parsed
        } />
    </cffunction>

    <cffunction name="signedStreamUrl" access="private" returntype="string" output="false">
        <cfargument name="stream_id" type="string" required="true" />
        <cfargument name="suffix" type="string" required="true" />
        <cfargument name="options" type="string" required="false" default="" />

        <cfset var clean_stream_id = trim(arguments.stream_id ?: "") />
        <cfif !len(clean_stream_id)>
            <cfreturn "" />
        </cfif>

        <cfreturn application.lib.cloudflare.signed_asset_url(clean_stream_id & arguments.suffix, "EOW", "v", arguments.options) />
    </cffunction>

    <cffunction name="buildVideoResponse" access="private" returntype="struct" output="false">
        <cfargument name="video_record" type="struct" required="true" />

        <cfset var metadata = getVideoMetadata(arguments.video_record) />
        <cfset var stream_id = trim(arguments.video_record.cloudflare_stream_id ?: "") />
        <cfset var stream_status = lCase(trim(metadata.stream_status ?: "")) />
        <cfset var stream_ready = metadata.stream_ready ?: false />
        <cfset var stream_iframe_url = signedStreamUrl(stream_id, "/iframe") />
        <cfset var stream_thumbnail = signedStreamUrl(stream_id, "/thumbnails/thumbnail.jpg", "time=1s") />

        <cfif NOT len(stream_status) AND len(stream_id)>
            <cfset stream_status = "inprogress" />
        </cfif>

        <cfreturn {
            id: arguments.video_record.id ?: "",
            name: arguments.video_record.name ?: "",
            path: arguments.video_record.path ?: "",
            cloudflare_stream_id: stream_id,
            stream_status: stream_status,
            stream_ready: stream_ready,
            stream_error: trim(metadata.stream_error ?: ""),
            video_iframe_url: stream_iframe_url,
            video_thumbnail: (len(stream_thumbnail) ? stream_thumbnail : (arguments.video_record.thumbnail ?: ""))
        } />
    </cffunction>

    <cffunction name="triggerCaptionGenerationIfReady" access="private" returntype="struct" output="false">
        <cfargument name="video_record" type="struct" required="true" />
        <cfargument name="metadata" type="struct" required="true" />

        <cfset var result_metadata = duplicate(arguments.metadata) />
        <cfset var config = getCloudflareConfig() />
        <cfset var stream_id = trim(arguments.video_record.cloudflare_stream_id ?: "") />
        <cfset var language_codes = ["cs", "nl", "en", "fr", "de", "it", "ja", "ko", "pl", "pt", "ru", "es"] />
        <cfset var language_code = "" />
        <cfset var thread_name = "" />
        <cfset var thread_names = [] />
        <cfset var caption_results = {} />
        <cfset var idx = 0 />
        <cfset var thread_result = {} />
        <cfset var has_failure = false />

        <cfif NOT (result_metadata.stream_ready ?: false)>
            <cfreturn result_metadata />
        </cfif>
        <cfif NOT len(stream_id)>
            <cfreturn result_metadata />
        </cfif>
        <cfif result_metadata.captions_generation_requested_at ?: "" NEQ "">
            <cfreturn result_metadata />
        </cfif>

        <cfset result_metadata.captions_generation_status = {} />

        <cfloop array="#language_codes#" index="language_code">
            <cfset idx = idx + 1 />
            <cfset thread_name = "caption_generate_#replace(createUUID(), '-', '', 'all')#_#idx#" />
            <cfset arrayAppend(thread_names, thread_name) />

            <cfthread
                action="run"
                name="#thread_name#"
                account_id="#config.account_id#"
                api_token="#config.api_token#"
                stream_id="#stream_id#"
                language="#language_code#"
            >
                <cfset var call_result = { success: true, error: "" } />
                <cfset var api_result = {} />
                <cfset var request_url = "https://api.cloudflare.com/client/v4/accounts/#attributes.account_id#/stream/#attributes.stream_id#/captions/#attributes.language#/generate" />
                <cfset call_result.language = attributes.language />

                <cfhttp method="POST" url="#request_url#" result="api_result" timeout="30">
                    <cfhttpparam type="header" name="Authorization" value="Bearer #attributes.api_token#" />
                    <cfhttpparam type="header" name="Content-Type" value="application/json" />
                    <cfhttpparam type="header" name="Accept" value="application/json" />
                </cfhttp>

                <cfset thread.caption_result = call_result />
            </cfthread>
        </cfloop>

        <cfthread action="join" name="#arrayToList(thread_names)#" timeout="120000" />

        <cfloop array="#thread_names#" index="thread_name">
            <cfset thread_result = cfthread[thread_name].caption_result ?: { success: false, error: "No response" } />
            <cfset caption_results[thread_result.language ?: thread_name] = thread_result />
            <cfif NOT (thread_result.success ?: false)>
                <cfset has_failure = true />
            </cfif>
        </cfloop>

        <cfset result_metadata.captions_generation_requested_at = dateTimeFormat(now(), "yyyy-mm-dd HH:nn:ss") />
        <cfset result_metadata.captions_languages = language_codes />
        <cfset result_metadata.captions_generation_status = caption_results />
        <cfif has_failure>
            <cfset result_metadata.captions_generation_error = "One or more caption generation requests failed" />
        <cfelse>
            <cfset result_metadata.captions_generation_error = "" />
        </cfif>

        <cfreturn result_metadata />
    </cffunction>

    <cffunction name="uploadVideoInit" access="public" returntype="struct" output="false">
        <cfargument name="data" type="struct" required="true" />

        <cfset var file_name = trim(arguments.data.file_name ?: "") />
        <cfset var extension = lCase(listLast(file_name, ".")) />
        <cfif !listFindNoCase("JPG,JPEG,PNG,GIF,WEBP,SVG,TIFF,BMP,HEIF,PDF,MOV,MP4,AVI,MKV,WEBM", extension)>
            <cfset extension = "default" />
        </cfif>
        <cfset var safe_filename = application.lib.core.sanitize_s3_key(file_name) />
        <cfset var new_path = "/moo_video/#dateFormat(now(),'yyyy-mm')#/#createUniqueId()#/#safe_filename#" />
        <cfset var new_thumbnail = '/_static/icons/fa/#extension#.svg' />
        <cfset var new_video = application.lib.db.save(
            table_name = "moo_video",
            data = {
                name: file_name,
                path: new_path,
                thumbnail: new_thumbnail,
                metadata: {
                    stream_status: "uploading",
                    stream_ready: false,
                    stream_error: ""
                }
            },
            returnAsCFML = true
        ) />

        <cfreturn {
            video: buildVideoResponse(application.lib.db.read(table_name = "moo_video", id = new_video.id, returnAsCFML = true)),
            video_id: new_video.id,
            presignedURL: s3generatePresignedUrl(
                bucket= '#server.system.environment.S3_bucket#',
                objectName = new_path,
                httpMethod = "PUT",
                expireDate = dateAdd('n', 20, now())
            )
        } />
    </cffunction>

    <cffunction name="uploadVideoComplete" access="public" returntype="struct" output="false">
        <cfargument name="data" type="struct" required="true" />
        <cfargument name="source" type="string" required="false" default="rea_agent_tender_submission" />

        <cfset var video_id = getVideoId(arguments.data.video_id ?: arguments.data.id ?: arguments.data.video ?: "") />
        <cfset var video_record = application.lib.db.read(table_name = "moo_video", id = video_id, returnAsCFML = true) />
        <cfset var metadata = getVideoMetadata(video_record) />
        <cfset var presigned_get = s3generatePresignedUrl(
            bucket= '#server.system.environment.S3_bucket#',
            objectName = video_record.path,
            httpMethod = "GET",
            expireDate = dateAdd('n', 120, now())
        ) />
        <cfset var cloudflare_copy = requestCloudflare(
            method = "POST",
            path = "/stream/copy",
            body = {
                url: presigned_get,
                meta: {
                    source: arguments.source,
                    video_id: video_id,
                    name: (video_record.name ?: "Video")
                }
            }
        ) />
        <cfset var stream_data = cloudflare_copy.result ?: {} />
        <cfset var stream_status_data = isStruct(stream_data.status ?: "") ? stream_data.status : {} />
        <cfset var stream_id = trim(stream_data.uid ?: "") />

        <cfset metadata.stream_status = lCase(trim(stream_status_data.state ?: "inprogress")) />
        <cfset metadata.stream_ready = (stream_data.readyToStream ?: false) OR metadata.stream_status EQ "ready" />
        <cfset metadata.stream_error = "" />
        <cfset metadata.stream_last_checked_at = dateTimeFormat(now(), "yyyy-mm-dd HH:nn:ss") />
        <cfset metadata = triggerCaptionGenerationIfReady(video_record = { cloudflare_stream_id: stream_id }, metadata = metadata) />

        <cfset application.lib.db.save(
            table_name = "moo_video",
            data = {
                id: video_id,
                cloudflare_stream_id: stream_id,
                metadata: metadata
            }
        ) />

        <cfset video_record = application.lib.db.read(table_name = "moo_video", id = video_id, returnAsCFML = true) />
        <cfreturn buildVideoResponse(video_record) />
    </cffunction>

    <cffunction name="pollVideoStatuses" access="public" returntype="array" output="false">
        <cfargument name="video_ids" type="array" required="true" />

        <cfset var clean_ids = [] />
        <cfset var pending_id = "" />
        <cfset var video_record = {} />
        <cfset var metadata = {} />
        <cfset var cloudflare_response = {} />
        <cfset var cloudflare_result = {} />
        <cfset var stream_status_data = {} />
        <cfset var output_records = [] />

        <cfloop array="#arguments.video_ids#" index="pending_id">
            <cfset pending_id = getVideoId(pending_id) />
            <cfif len(pending_id) AND arrayFindNoCase(clean_ids, pending_id) EQ 0>
                <cfset arrayAppend(clean_ids, pending_id) />
            </cfif>
        </cfloop>

        <cfloop array="#clean_ids#" index="pending_id">
            <cfset video_record = application.lib.db.read(table_name = "moo_video", id = pending_id, returnAsCFML = true) />
            <cfset metadata = getVideoMetadata(video_record) />

            <cfif NOT len(trim(video_record.cloudflare_stream_id ?: ""))>
                <cfset arrayAppend(output_records, buildVideoResponse(video_record)) />
                <cfcontinue />
            </cfif>

            <cfset cloudflare_response = requestCloudflare(method = "GET", path = "/stream/#urlEncodedFormat(video_record.cloudflare_stream_id)#") />
            <cfset cloudflare_result = cloudflare_response.result ?: {} />
            <cfset stream_status_data = isStruct(cloudflare_result.status ?: "") ? cloudflare_result.status : {} />
            <cfset metadata.stream_status = lCase(trim(stream_status_data.state ?: "inprogress")) />
            <cfset metadata.stream_ready = (cloudflare_result.readyToStream ?: false) OR metadata.stream_status EQ "ready" />
            <cfset metadata.stream_error = "" />
            <cfset metadata.stream_last_checked_at = dateTimeFormat(now(), "yyyy-mm-dd HH:nn:ss") />
            <cfset metadata = triggerCaptionGenerationIfReady(video_record = video_record, metadata = metadata) />

            <cfset application.lib.db.save(table_name = "moo_video", data = { id: video_record.id, metadata: metadata }) />

            <cfset video_record = application.lib.db.read(table_name = "moo_video", id = video_record.id, returnAsCFML = true) />
            <cfset arrayAppend(output_records, buildVideoResponse(video_record)) />
        </cfloop>

        <cfreturn output_records />
    </cffunction>

    <cffunction name="deleteVideo" access="public" returntype="struct" output="false">
        <cfargument name="video_id" type="any" required="true" />

        <cfset var clean_video_id = getVideoId(arguments.video_id) />
        <cfset var video_record = application.lib.db.read(table_name = "moo_video", id = clean_video_id, returnAsCFML = true) />
        <cfset var metadata = getVideoMetadata(video_record) />
        <cfset var stream_id = trim(video_record.cloudflare_stream_id ?: "") />

        <cfif len(stream_id)>
            <cfset requestCloudflare(method = "DELETE", path = "/stream/#urlEncodedFormat(stream_id)#") />
        </cfif>

        <cfset metadata.deleted_at = dateTimeFormat(now(), "yyyy-mm-dd HH:nn:ss") />
        <cfset metadata.stream_status = "deleted" />
        <cfset metadata.stream_ready = false />
        <cfset metadata.stream_error = "" />

        <cfset application.lib.db.save(
            table_name = "moo_video",
            data = {
                id: video_record.id,
                cloudflare_stream_id: "",
                metadata: metadata
            }
        ) />

        <cfreturn { success: true, video_id: video_record.id } />
    </cffunction>

    <cffunction name="handleVideoAction" access="public" returntype="any" output="false">
        <cfargument name="data" type="struct" required="true" />
        <cfargument name="source" type="string" required="false" default="rea_agent_tender_submission" />

        <cfif isArray(arguments.data.video_ids ?: "")>
            <cfreturn pollVideoStatuses(arguments.data.video_ids) />
        </cfif>

        <cfif (arguments.data.delete ?: false)>
            <cfreturn deleteVideo(arguments.data.video_id ?: "") />
        </cfif>

        <cfif len(trim(arguments.data.file_name ?: ""))>
            <cfreturn uploadVideoInit(arguments.data) />
        </cfif>

        <cfreturn uploadVideoComplete(arguments.data, arguments.source) />
    </cffunction>


</cfcomponent>
