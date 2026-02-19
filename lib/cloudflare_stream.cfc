<!--- Cloudflare Stream API client --->
<!--- https://developers.cloudflare.com/stream/ --->

<cfcomponent displayname="cloudflare_stream" hint="Cloudflare Stream API client for video hosting and adaptive bitrate streaming" output="false">


    <cffunction name="init">
        <cfset variables.apiToken = server.system.environment.CLOUDFLARE_STREAM_API_TOKEN />
        <cfset variables.accountId = server.system.environment.CLOUDFLARE_ACCOUNT_ID />
        <cfset variables.customerSubdomain = server.system.environment.CLOUDFLARE_CUSTOMER_SUBDOMAIN />
    
        <cfreturn this />
    </cffunction>
    
    
    <cffunction name="uploadFromUrl" returntype="struct" hint="Upload a video to Cloudflare Stream via URL-to-stream copy">
        <cfargument name="url" required="true" hint="Presigned URL of the video to upload" />
        <cfargument name="meta" default="#{}#" hint="Metadata to attach to the video" />
    
        <cfset var jsonBody = serializeJSON({
            "url": arguments.url,
            "meta": arguments.meta
        }) />
    
        <cfhttp url="https://api.cloudflare.com/client/v4/accounts/#variables.accountId#/stream/copy" method="POST" result="stHTTP" timeout="120">
            <cfhttpparam type="header" name="Authorization" value="Bearer #variables.apiToken#" />
            <cfhttpparam type="header" name="Content-Type" value="application/json" />
            <cfhttpparam type="body" value="#jsonBody#" />
        </cfhttp>
    
        <cfset var result = deserializeJSON(stHTTP.filecontent) />
    
        <cfif result.success AND structKeyExists(result, "result") AND structKeyExists(result.result, "uid")>
            <cfreturn {
                "success": true,
                "uid": result.result.uid,
                "status": result.result.status ?: {}
            } />
        </cfif>
    
        <cfreturn {
            "success": false,
            "errors": result.errors ?: [],
            "messages": result.messages ?: []
        } />
    </cffunction>
    
    
    <cffunction name="getVideo" returntype="struct" hint="Get video status and details from Cloudflare Stream">
        <cfargument name="uid" required="true" />
    
        <cfhttp url="https://api.cloudflare.com/client/v4/accounts/#variables.accountId#/stream/#arguments.uid#" method="GET" result="stHTTP" timeout="30">
            <cfhttpparam type="header" name="Authorization" value="Bearer #variables.apiToken#" />
        </cfhttp>
    
        <cfreturn deserializeJSON(stHTTP.filecontent) />
    </cffunction>
    
    
    <cffunction name="deleteVideo" returntype="struct" hint="Delete a video from Cloudflare Stream">
        <cfargument name="uid" required="true" />
    
        <cftry>
            <cfhttp url="https://api.cloudflare.com/client/v4/accounts/#variables.accountId#/stream/#arguments.uid#" method="DELETE" result="stHTTP" timeout="30">
                <cfhttpparam type="header" name="Authorization" value="Bearer #variables.apiToken#" />
            </cfhttp>
    
            <!--- Cloudflare may return 204 No Content on successful delete --->
            <cfset var status_code = val(listFirst(stHTTP.statusCode ?: "0", " ")) />
            <cfif status_code GTE 200 AND status_code LT 300>
                <cfreturn {
                    "success": true,
                    "uid": arguments.uid
                } />
            </cfif>
    
            <cfset var response = {} />
            <cfif len(stHTTP.filecontent ?: "") AND isJSON(stHTTP.filecontent)>
                <cfset response = deserializeJSON(stHTTP.filecontent) />
            </cfif>
    
            <cfif structKeyExists(response, "success") AND response.success>
                <cfreturn {
                    "success": true,
                    "uid": arguments.uid
                } />
            </cfif>
    
            <cfreturn {
                "success": false,
                "uid": arguments.uid,
                "errors": response.errors ?: [],
                "messages": response.messages ?: []
            } />
        <cfcatch type="any">
            <cfreturn {
                "success": false,
                "uid": arguments.uid,
                "errors": [{
                    "message": cfcatch.message
                }]
            } />
        </cfcatch>
        </cftry>
    </cffunction>
    
    
    <cffunction name="createAudioDownload" returntype="struct" hint="Request an audio-only downloadable asset for a Stream video">
        <cfargument name="uid" required="true" />
    
        <cftry>
            <cfhttp url="https://api.cloudflare.com/client/v4/accounts/#variables.accountId#/stream/#arguments.uid#/downloads/audio" method="POST" result="stHTTP" timeout="30">
                <cfhttpparam type="header" name="Authorization" value="Bearer #variables.apiToken#" />
                <cfhttpparam type="header" name="Content-Type" value="application/json" />
            </cfhttp>
    
            <cfset var response = {} />
            <cfif len(stHTTP.filecontent ?: "")>
                <cfset response = deserializeJSON(stHTTP.filecontent) />
            </cfif>
    
            <cfif (response.success ?: false)>
                <cfreturn {
                    "success": true,
                    "result": response.result ?: {}
                } />
            </cfif>
    
            <cfreturn {
                "success": false,
                "errors": response.errors ?: [],
                "messages": response.messages ?: []
            } />
        <cfcatch type="any">
            <cfreturn {
                "success": false,
                "errors": [{
                    "message": cfcatch.message
                }]
            } />
        </cfcatch>
        </cftry>
    </cffunction>
    
    
    <cffunction name="generateCaption" returntype="struct" hint="Generate captions for a Stream video in the requested language">
        <cfargument name="uid" required="true" />
        <cfargument name="language" default="en" />
    
        <cftry>
            <cfhttp url="https://api.cloudflare.com/client/v4/accounts/#variables.accountId#/stream/#arguments.uid#/captions/#arguments.language#/generate" method="POST" result="stHTTP" timeout="30">
                <cfhttpparam type="header" name="Authorization" value="Bearer #variables.apiToken#" />
                <cfhttpparam type="header" name="Content-Type" value="application/json" />
            </cfhttp>
    
            <cfset var response = {} />
            <cfif len(stHTTP.filecontent ?: "")>
                <cfset response = deserializeJSON(stHTTP.filecontent) />
            </cfif>
    
            <cfif (response.success ?: false)>
                <cfreturn {
                    "success": true,
                    "result": response.result ?: {}
                } />
            </cfif>
    
            <cfreturn {
                "success": false,
                "errors": response.errors ?: [],
                "messages": response.messages ?: []
            } />
        <cfcatch type="any">
            <cfreturn {
                "success": false,
                "errors": [{
                    "message": cfcatch.message
                }]
            } />
        </cfcatch>
        </cftry>
    </cffunction>
    
    
    <cffunction name="getCaptionVtt" returntype="struct" hint="Fetch generated VTT captions for a Stream video">
        <cfargument name="uid" required="true" />
        <cfargument name="language" default="en" />
    
        <cftry>
            <cfhttp url="https://api.cloudflare.com/client/v4/accounts/#variables.accountId#/stream/#arguments.uid#/captions/#arguments.language#/vtt" method="GET" result="stHTTP" timeout="30">
                <cfhttpparam type="header" name="Authorization" value="Bearer #variables.apiToken#" />
            </cfhttp>
    
            <cfif left(stHTTP.statusCode ?: "", 3) EQ "200">
                <cfreturn {
                    "success": true,
                    "vtt": stHTTP.filecontent ?: ""
                } />
            </cfif>
    
            <cfset var response = {} />
            <cfif len(stHTTP.filecontent ?: "") AND isJSON(stHTTP.filecontent)>
                <cfset response = deserializeJSON(stHTTP.filecontent) />
            </cfif>
    
            <cfreturn {
                "success": false,
                "status_code": stHTTP.statusCode ?: "",
                "errors": response.errors ?: [],
                "messages": response.messages ?: []
            } />
        <cfcatch type="any">
            <cfreturn {
                "success": false,
                "errors": [{
                    "message": cfcatch.message
                }]
            } />
        </cfcatch>
        </cftry>
    </cffunction>
    
    <cffunction name="listCaptions" returntype="struct" hint="List available captions/subtitles for a Stream video">
        <cfargument name="uid" required="true" />
    
        <cftry>
            <cfhttp url="https://api.cloudflare.com/client/v4/accounts/#variables.accountId#/stream/#arguments.uid#/captions" method="GET" result="stHTTP" timeout="30">
                <cfhttpparam type="header" name="Authorization" value="Bearer #variables.apiToken#" />
            </cfhttp>
    
            <cfset var response = {} />
            <cfif len(stHTTP.filecontent ?: "") AND isJSON(stHTTP.filecontent)>
                <cfset response = deserializeJSON(stHTTP.filecontent) />
            </cfif>
    
            <cfif (response.success ?: false)>
                <cfset var normalized_captions = [] />
                <cfif isArray(response.result ?: [])>
                    <cfset normalized_captions = response.result />
                <cfelseif isStruct(response.result ?: {})>
                    <cfif isArray(response.result.captions ?: [])>
                        <cfset normalized_captions = response.result.captions />
                    <cfelseif isArray(response.result.subtitles ?: [])>
                        <cfset normalized_captions = response.result.subtitles />
                    </cfif>
                </cfif>
    
                <cfreturn {
                    "success": true,
                    "captions": normalized_captions,
                    "raw_result": response.result ?: ""
                } />
            </cfif>
    
            <cfreturn {
                "success": false,
                "errors": response.errors ?: [],
                "messages": response.messages ?: []
            } />
        <cfcatch type="any">
            <cfreturn {
                "success": false,
                "errors": [{
                    "message": cfcatch.message
                }]
            } />
        </cfcatch>
        </cftry>
    </cffunction>
    
    <cffunction name="uploadCaptionVtt" returntype="struct" hint="Upload WebVTT captions for a Stream video language">
        <cfargument name="uid" required="true" />
        <cfargument name="language" required="true" />
        <cfargument name="vtt_text" required="true" />
        <cfargument name="label" default="" />
    
        <cfset var temp_file_path = "" />
    
        <cftry>
            <cfif NOT len(trim(arguments.vtt_text ?: ""))>
                <cfreturn {
                    "success": false,
                    "errors": [{
                        "message": "VTT content is empty"
                    }]
                } />
            </cfif>
    
            <cfset temp_file_path = getTempDirectory() & createUUID() & "-" & reReplace(arguments.language, "[^a-zA-Z0-9_-]", "", "all") & ".vtt" />
            <cffile action="write" file="#temp_file_path#" output="#arguments.vtt_text#" charset="utf-8" />
    
            <cfhttp url="https://api.cloudflare.com/client/v4/accounts/#variables.accountId#/stream/#arguments.uid#/captions/#arguments.language#" method="PUT" result="stHTTP" timeout="60" multipart="true">
                <cfhttpparam type="header" name="Authorization" value="Bearer #variables.apiToken#" />
                <cfif len(trim(arguments.label ?: ""))>
                    <cfhttpparam type="formfield" name="label" value="#arguments.label#" />
                </cfif>
                <cfhttpparam type="file" name="file" file="#temp_file_path#" />
            </cfhttp>
    
            <cfset var status_code = val(listFirst(stHTTP.statusCode ?: "0", " ")) />
            <cfset var response = {} />
    
            <cfif len(stHTTP.filecontent ?: "") AND isJSON(stHTTP.filecontent)>
                <cfset response = deserializeJSON(stHTTP.filecontent) />
            </cfif>
    
            <cfif status_code GTE 200 AND status_code LT 300>
                <cfif structIsEmpty(response) OR (response.success ?: false)>
                    <cfreturn {
                        "success": true,
                        "language": arguments.language
                    } />
                </cfif>
            </cfif>
    
            <cfreturn {
                "success": false,
                "status_code": stHTTP.statusCode ?: "",
                "errors": response.errors ?: [],
                "messages": response.messages ?: []
            } />
        <cfcatch type="any">
            <cfreturn {
                "success": false,
                "errors": [{
                    "message": cfcatch.message
                }]
            } />
        </cfcatch>
        <cffinally>
            <cfif len(temp_file_path) AND fileExists(temp_file_path)>
                <cffile action="delete" file="#temp_file_path#" />
            </cfif>
        </cffinally>
        </cftry>
    </cffunction>
    
    
    <cffunction name="isReady" returntype="boolean" hint="Check if a Cloudflare Stream video is ready for playback">
        <cfargument name="uid" required="true" />
    
        <cftry>
            <cfhttp url="https://api.cloudflare.com/client/v4/accounts/#variables.accountId#/stream/#arguments.uid#" method="GET" result="stHTTP" timeout="30">
                <cfhttpparam type="header" name="Authorization" value="Bearer #variables.apiToken#" />
            </cfhttp>
    
            <!--- Search the raw response for the ready state to avoid struct key casing issues --->
            <cfreturn findNoCase('"state":"ready"', stHTTP.filecontent) GT 0 OR findNoCase('"state": "ready"', stHTTP.filecontent) GT 0 />
        <cfcatch type="any">
            <cfreturn false />
        </cfcatch>
        </cftry>
    </cffunction>
    
    
    <cffunction name="getPlayerUrl" returntype="string" hint="Returns the HLS manifest URL for a Cloudflare Stream video">
        <cfargument name="uid" required="true" />
    
        <cfreturn "https://#variables.customerSubdomain#/#arguments.uid#/manifest/video.m3u8" />
    </cffunction>
    
    <cffunction name="isPlaybackReady" returntype="boolean" hint="Checks if the public HLS manifest is reachable for playback">
        <cfargument name="uid" required="true" />
        <cfargument name="timeout" default="10" />
    
        <cftry>
            <cfset var manifest_url = getPlayerUrl(arguments.uid) />
            <cfhttp url="#manifest_url#" method="GET" result="stHTTP" timeout="#arguments.timeout#">
                <cfhttpparam type="header" name="Accept" value="application/vnd.apple.mpegurl,text/plain,*/*" />
                <cfhttpparam type="header" name="Range" value="bytes=0-1024" />
            </cfhttp>
    
            <cfset var status_text = stHTTP.statusCode ?: "" />
            <cfset var status_code = val(listFirst(status_text, " ")) />
    
            <cfif status_code EQ 200 OR status_code EQ 206>
                <cfreturn true />
            </cfif>
    
            <cfreturn false />
        <cfcatch type="any">
            <cfreturn false />
        </cfcatch>
        </cftry>
    </cffunction>
    
    
    <cffunction name="getIframeUrl" returntype="string" hint="Returns the iframe embed URL for a Cloudflare Stream video">
        <cfargument name="uid" required="true" />
    
        <cfreturn "https://#variables.customerSubdomain#/#arguments.uid#/iframe" />
    </cffunction>
    
    <cffunction name="getThumbnailUrl" returntype="string" hint="Returns a thumbnail image URL for a Cloudflare Stream video">
        <cfargument name="uid" required="true" />
        <cfargument name="time" default="1s" />
    
        <cfreturn "https://#variables.customerSubdomain#/#arguments.uid#/thumbnails/thumbnail.jpg?time=#urlEncodedFormat(arguments.time)#" />
    </cffunction>
    
    
    </cfcomponent>
    