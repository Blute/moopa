<cfcomponent output="false" hint="Standalone application for the front door harness: maps /moopa to this checkout.">
    <cfset this.name = "moopa_front_door_test" />
    <cfset this.mappings["/moopa"] = getDirectoryFromPath(getCurrentTemplatePath()) & "../../" />
    <cfset this.localMode = "modern" />
</cfcomponent>
