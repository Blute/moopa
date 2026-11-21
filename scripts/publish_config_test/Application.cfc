<cfcomponent output="false" hint="Standalone application for the published files harness: maps /moopa to this checkout so the harness loads internal/db and lib/published_files without Moopa's own application.cfc.">
    <cfset this.name = "moopa_publish_config_test" />
    <cfset this.mappings["/moopa"] = getDirectoryFromPath(getCurrentTemplatePath()) & "../../" />
    <!--- The mode Moopa runs in (docs/local-mode.md) --->
    <cfset this.localMode = "modern" />
</cfcomponent>
