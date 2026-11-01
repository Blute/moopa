<cfcomponent output="false" hint="Standalone application for the schema normalizer harness: maps /moopa to this checkout so the harness loads internal/db without Moopa's own application.cfc.">
    <cfset this.name = "moopa_schema_normalizer_test" />
    <cfset this.mappings["/moopa"] = getDirectoryFromPath(getCurrentTemplatePath()) & "../../" />
</cfcomponent>
