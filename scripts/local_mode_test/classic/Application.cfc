<cfcomponent output="false" hint="Standalone application for the local mode harness, running in classic local mode: maps /moopa to this checkout.">
    <cfset this.name = "moopa_local_mode_test_classic" />
    <cfset this.mappings["/moopa"] = getDirectoryFromPath(getCurrentTemplatePath()) & "../../../" />
    <cfset this.localMode = "classic" />
</cfcomponent>
