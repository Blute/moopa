<cfcomponent extends="moopa.lib.published_files" output="false" hint="lib/published_files.cfc with its private steps callable, for the harness to check what each does with a state a concurrent save left behind.">
    <cffunction name="callRepair" access="public" returntype="boolean" output="false">
        <cfargument name="key" /><cfargument name="path" /><cfargument name="table_name" /><cfargument name="id" />
        <cfreturn repairCopy(arguments.key, arguments.path, arguments.table_name, arguments.id) />
    </cffunction>
    <cffunction name="callRetire" access="public" returntype="boolean" output="false">
        <cfargument name="key" /><cfargument name="table_name" /><cfargument name="id" />
        <cfreturn retire(arguments.key, arguments.table_name, arguments.id) />
    </cffunction>
    <cffunction name="callRemoveStray" access="public" returntype="boolean" output="false">
        <cfargument name="key" />
        <cfreturn removeStray(arguments.key) />
    </cffunction>
</cfcomponent>
