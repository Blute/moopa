<cfcomponent extends="moopa.lib.published_files" output="false" hint="lib/published_files.cfc with its private steps callable, for the harness to check what each does with a state a concurrent save left behind.">
    <cffunction name="callRepair" access="public" returntype="boolean" output="false">
        <cfargument name="key" /><cfargument name="path" /><cfargument name="table_name" /><cfargument name="id" />
        <cfreturn underLock("repair", { "key": arguments.key, "path": arguments.path, "table_name": arguments.table_name, "id": arguments.id }) EQ "yes" />
    </cffunction>
    <cffunction name="callRetire" access="public" returntype="boolean" output="false">
        <cfargument name="key" /><cfargument name="table_name" /><cfargument name="id" />
        <cfset var retired = false />
        <!--- As reconcileRecord calls it: in a transaction, inside the address's savepoint. --->
        <cftransaction>
            <cfquery>SAVEPOINT moopa_published_address</cfquery>
            <cfset retired = retire(arguments.key, arguments.table_name, arguments.id, { "checkpointed": false }) />
        </cftransaction>
        <cfreturn retired />
    </cffunction>
    <cffunction name="callRemoveStray" access="public" returntype="boolean" output="false">
        <cfargument name="key" />
        <cfreturn underLock("remove", { "key": arguments.key }) EQ "yes" />
    </cffunction>
</cfcomponent>
