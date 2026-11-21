<cfcomponent output="false" hint="Stands in for lib/db.cfc in the published files harness: the publishing settings, read from fixture table definitions by the real normalizer and publish_config, and the codeSchema keys published_files looks at.">
    <cffunction name="init" access="public" returntype="any" output="false">
        <cfargument name="definitions" type="struct" required="true" />
        <cfset this.codeSchema = createObject("component", "moopa.internal.db.schema_normalizer").init().normalize(arguments.definitions, {}) />
        <cfset this.publishing = createObject("component", "moopa.internal.db.publish_config").init().build(this.codeSchema) />
        <cfreturn this />
    </cffunction>
    <cffunction name="getPublishing" access="public" returntype="struct" output="false">
        <cfreturn this.publishing />
    </cffunction>
</cfcomponent>
