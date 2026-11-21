<cfcomponent output="false" hint="An in-memory store standing in for lib/s3_client.cfc in the published files harness: the calls published_files makes, with keys compared exactly (as a store does), an ETag per copy, and failures on demand.">
    <cffunction name="init" access="public" returntype="any" output="false">
        <cfset variables.objects = {} />
        <cfset this.failCopyTo = "" />
        <cfset this.failDeleteOf = "" />
        <cfset this.failCopyAll = false />
        <cfreturn this />
    </cffunction>
    <cffunction name="slot" access="private" returntype="string" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfreturn "k" & binaryEncode(charsetDecode(reReplace(arguments.key, "^/+", ""), "utf-8"), "hex") />
    </cffunction>
    <cffunction name="defaultStore" access="public" returntype="struct" output="false">
        <cfreturn { "label": "stub store" } />
    </cffunction>
    <cffunction name="put" access="public" returntype="void" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfargument name="body" type="string" required="true" />
        <cfargument name="metadata" type="struct" required="false" default="#{}#" />
        <cfset variables.objects[slot(arguments.key)] = { "key": reReplace(arguments.key, "^/+", ""), "body": arguments.body, "etag": lCase(hash(arguments.body & createUUID(), "MD5")), "metadata": duplicate(arguments.metadata) } />
    </cffunction>
    <cffunction name="headObject" access="public" returntype="struct" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="objectKey" type="string" required="true" />
        <cfif NOT has(arguments.objectKey)>
            <cfreturn { "exists": false, "size": 0, "contentType": "", "metadata": {} } />
        </cfif>
        <cfset var object = variables.objects[slot(arguments.objectKey)] />
        <cfreturn { "exists": true, "size": len(object.body), "contentType": "application/octet-stream", "metadata": duplicate(object.metadata) } />
    </cffunction>
    <cffunction name="body" access="public" returntype="string" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfreturn variables.objects[slot(arguments.key)].body ?: "" />
    </cffunction>
    <cffunction name="has" access="public" returntype="boolean" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfreturn structKeyExists(variables.objects, slot(arguments.key)) />
    </cffunction>
    <cffunction name="setEtag" access="public" returntype="void" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfargument name="etag" type="string" required="true" />
        <cfset variables.objects[slot(arguments.key)].etag = arguments.etag />
    </cffunction>
    <cffunction name="copyObject" access="public" returntype="string" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="sourceKey" type="string" required="true" />
        <cfargument name="targetKey" type="string" required="true" />
        <cfargument name="metadata" type="struct" required="false" default="#{}#" />
        <cfif this.failCopyAll OR (len(this.failCopyTo) AND this.failCopyTo EQ arguments.targetKey) OR NOT has(arguments.sourceKey)>
            <cfthrow type="s3.request.failed" message="stub store: copying #arguments.sourceKey# to #arguments.targetKey# failed" />
        </cfif>
        <cfset put(arguments.targetKey, body(arguments.sourceKey), arguments.metadata) />
        <cfreturn variables.objects[slot(arguments.targetKey)].etag />
    </cffunction>
    <cffunction name="deleteObject" access="public" returntype="void" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="objectKey" type="string" required="true" />
        <cfif len(this.failDeleteOf) AND this.failDeleteOf EQ arguments.objectKey>
            <cfthrow type="s3.request.failed" message="stub store: deleting #arguments.objectKey# failed" />
        </cfif>
        <cfset structDelete(variables.objects, slot(arguments.objectKey)) />
    </cffunction>
    <cffunction name="listObjects" access="public" returntype="array" output="false">
        <cfargument name="store" type="struct" required="true" />
        <cfargument name="prefix" type="string" required="true" />
        <cfset var found = [] />
        <cfset var s = "" />
        <cfloop collection="#variables.objects#" item="s">
            <cfif left(variables.objects[s].key, len(arguments.prefix)) EQ arguments.prefix AND compare(left(variables.objects[s].key, len(arguments.prefix)), arguments.prefix) EQ 0>
                <cfset arrayAppend(found, { "key": variables.objects[s].key, "etag": variables.objects[s].etag, "size": len(variables.objects[s].body), "last_modified": "" }) />
            </cfif>
        </cfloop>
        <cfreturn found />
    </cffunction>
</cfcomponent>
