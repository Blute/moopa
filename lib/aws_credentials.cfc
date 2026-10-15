<cfcomponent displayname="AWS Credentials" hint="Resolves AWS SigV4 signing credentials: explicit static keys when configured, otherwise the ECS task role via the container credentials endpoint. Container credentials are cached per endpoint and refreshed ahead of expiry.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfset variables.containerCache = {} />
        <cfset variables.refreshLeadSeconds = 300 />
        <cfreturn this />
    </cffunction>

    <!--- Returns { accessKeyId, secretAccessKey, sessionToken } for the given static keys, or the task role when both are empty.
          A half-configured static pair is a configuration error, never a fallback. --->
    <cffunction name="resolve" access="public" returntype="struct" output="false">
        <cfargument name="accessKeyId" type="string" required="false" default="" />
        <cfargument name="secretAccessKey" type="string" required="false" default="" />
        <cfargument name="label" type="string" required="false" default="AWS" hint="Names the consumer in error messages" />

        <cfset var keyId = trim(arguments.accessKeyId) />
        <cfset var secret = trim(arguments.secretAccessKey) />

        <cfif len(keyId) AND len(secret)>
            <cfreturn { accessKeyId: keyId, secretAccessKey: secret, sessionToken: "" } />
        </cfif>

        <cfif len(keyId) OR len(secret)>
            <cfthrow type="aws.credentials.incomplete" message="#arguments.label#: static AWS credentials are half-configured (access key id and secret must both be set, or neither)" />
        </cfif>

        <cfreturn resolveContainerCredentials(label = arguments.label) />
    </cffunction>

    <cffunction name="resolveContainerCredentials" access="private" returntype="struct" output="false">
        <cfargument name="label" type="string" required="true" />

        <cfset var endpoint = getContainerCredentialsEndpoint() />
        <cfset var cached = {} />
        <cfset var httpResult = {} />
        <cfset var fresh = {} />

        <cfif NOT len(endpoint)>
            <cfthrow type="aws.credentials.unavailable" message="#arguments.label#: no static AWS credentials configured and no ECS container credentials endpoint is present (AWS_CONTAINER_CREDENTIALS_RELATIVE_URI / AWS_CONTAINER_CREDENTIALS_FULL_URI)" />
        </cfif>

        <cfif structKeyExists(variables.containerCache, endpoint)>
            <cfset cached = variables.containerCache[endpoint] />
            <cfif NOT needsRefresh(expiration = cached.expiration, asOf = now())>
                <cfreturn cached.credentials />
            </cfif>
        </cfif>

        <cflock name="aws_credentials_#hash(endpoint)#" type="exclusive" timeout="30">
            <cfif structKeyExists(variables.containerCache, endpoint) AND NOT needsRefresh(expiration = variables.containerCache[endpoint].expiration, asOf = now())>
                <cfreturn variables.containerCache[endpoint].credentials />
            </cfif>

            <cfhttp url="#endpoint#" method="GET" result="httpResult" timeout="10">
                <cfif len(server.system.environment.AWS_CONTAINER_AUTHORIZATION_TOKEN ?: "")>
                    <cfhttpparam type="header" name="Authorization" value="#server.system.environment.AWS_CONTAINER_AUTHORIZATION_TOKEN#" />
                </cfif>
            </cfhttp>

            <cfif left(httpResult.statusCode ?: "", 3) NEQ "200">
                <cfthrow type="aws.credentials.fetchFailed" message="#arguments.label#: container credentials endpoint returned #httpResult.statusCode ?: 'no status'#" detail="#left(httpResult.fileContent ?: '', 500)#" />
            </cfif>

            <cfset fresh = parseContainerCredentials(httpResult.fileContent ?: "") />
            <cfset variables.containerCache[endpoint] = fresh />
        </cflock>

        <cfreturn fresh.credentials />
    </cffunction>

    <!--- Pure: parses the container credentials JSON into { credentials: {...}, expiration: date }. Throws on any missing field. --->
    <cffunction name="parseContainerCredentials" access="public" returntype="struct" output="false">
        <cfargument name="json" type="string" required="true" />

        <cfset var payload = {} />
        <cfset var required = ["AccessKeyId", "SecretAccessKey", "Token", "Expiration"] />
        <cfset var field = "" />

        <cfif NOT isJSON(arguments.json)>
            <cfthrow type="aws.credentials.malformed" message="Container credentials response is not JSON" />
        </cfif>
        <cfset payload = deserializeJSON(arguments.json) />

        <cfloop array="#required#" item="field">
            <cfif NOT structKeyExists(payload, field) OR NOT len(trim(payload[field]))>
                <cfthrow type="aws.credentials.malformed" message="Container credentials response is missing #field#" />
            </cfif>
        </cfloop>

        <cfreturn {
            credentials: {
                accessKeyId: trim(payload.AccessKeyId),
                secretAccessKey: trim(payload.SecretAccessKey),
                sessionToken: trim(payload.Token)
            },
            expiration: parseIso8601Utc(trim(payload.Expiration))
        } />
    </cffunction>

    <!--- Pure: true when the credentials expire within the refresh lead window (or already have). --->
    <cffunction name="needsRefresh" access="public" returntype="boolean" output="false">
        <cfargument name="expiration" type="date" required="true" />
        <cfargument name="asOf" type="date" required="true" />
        <cfreturn dateDiff("s", arguments.asOf, arguments.expiration) LTE variables.refreshLeadSeconds />
    </cffunction>

    <cffunction name="getContainerCredentialsEndpoint" access="private" returntype="string" output="false">
        <cfset var fullUri = trim(server.system.environment.AWS_CONTAINER_CREDENTIALS_FULL_URI ?: "") />
        <cfset var relativeUri = trim(server.system.environment.AWS_CONTAINER_CREDENTIALS_RELATIVE_URI ?: "") />

        <cfif len(fullUri)>
            <cfreturn fullUri />
        </cfif>
        <cfif len(relativeUri)>
            <cfreturn "http://169.254.170.2" & relativeUri />
        </cfif>
        <cfreturn "" />
    </cffunction>

    <!--- Container credentials carry an ISO-8601 UTC expiry such as 2026-09-08T04:12:33Z. Lucee's date parser rejects the Z form, so parse via Java. --->
    <cffunction name="parseIso8601Utc" access="private" returntype="date" output="false">
        <cfargument name="value" type="string" required="true" />

        <cfset var instant = "" />
        <cftry>
            <cfset instant = createObject("java", "java.time.Instant").parse(arguments.value) />
            <cfcatch>
                <cfthrow type="aws.credentials.malformed" message="Container credentials Expiration is not ISO-8601: #arguments.value#" />
            </cfcatch>
        </cftry>

        <cfreturn createObject("java", "java.util.Date").from(instant) />
    </cffunction>

</cfcomponent>
