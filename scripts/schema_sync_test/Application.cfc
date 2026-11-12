<cfcomponent output="false" hint="Standalone application for the schema sync harness: maps /moopa to this checkout so the harness loads lib/schemaSync without Moopa's own application.cfc.">
    <cfset this.name = "moopa_schema_sync_test" />
    <cfset this.mappings["/moopa"] = getDirectoryFromPath(getCurrentTemplatePath()) & "../../" />
</cfcomponent>
