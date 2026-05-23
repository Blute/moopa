<cfcomponent displayName="schema_loader" output="false" hint="Load raw table definitions from Moopa package table directories before normalization.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>

    <cffunction name="loadFromPackages" access="public" returntype="struct" output="false" hint="Merge table definitions from conventional package /tables directories.">
        <cfargument name="packages" type="array" required="true" />

        <cfset var codeSchema = {} />
        <cfset var packageSchema = {} />
        <cfset var packageInfo = {} />
        <cfset var tableName = "" />

        <cfloop array="#arguments.packages#" item="packageInfo">
            <cfif directoryExists(expandPath("#packageInfo.path#/tables"))>
                <cfset packageSchema = processDirectory(packageInfo.path) />
                <cfloop collection="#packageSchema#" item="tableName">
                    <!--- Later conventional packages override earlier table definitions.
                          This lets shared project tables intentionally replace Moopa core
                          tables such as moo_profile while keeping convention over configuration. --->
                    <cfset codeSchema[tableName] = packageSchema[tableName] />
                </cfloop>
            </cfif>
        </cfloop>

        <cfreturn codeSchema />
    </cffunction>

    <cffunction name="processDirectory" returntype="struct" access="private" output="false" hint="Load all table definition CFCs from one package directory.">
        <cfargument name="path" type="string" required="true" />

        <cfset var local = {} />
        <cfset local.codeSchema = {} />

        <!--- List all CFC files in the directory --->
        <cfdirectory action="list" directory="#arguments.path#/tables" name="local.directoryList" filter="*.cfc" />

        <cfloop query="local.directoryList">
            <cfset local.tableName = listFirst(local.directoryList.name, ".") />
            <cfset local.filePath = replace(local.directoryList.directory, expandPath(arguments.path), arguments.path) & "/" & local.tableName />

            <!--- Create and initialize the table service object --->
            <cfset local.tableService = createObject("component", local.filePath).init() />
            <cfset local.tableService.definition.path = local.filePath />

            <!--- Validate the table definition --->
            <cfif NOT structKeyExists(local.tableService.definition, "fields")>
                <cfthrow message="Model must contain fields" />
            </cfif>

            <!--- Set table name if not provided --->
            <cfif NOT len(local.tableService.definition.name ?: "")>
                <cfset local.tableService.definition.name = listFirst(local.directoryList.name, ".") />
            </cfif>

            <!--- Validate table name --->
            <cfset local.validTableNamePattern = "^[a-z_][a-z0-9_]{0,62}$" />
            <cfif NOT reFind(local.validTableNamePattern, local.tableService.definition.name)>
                <cfthrow message="#local.tableService.definition.name# is not a valid postgresql table name." />
            </cfif>

            <!--- Add to codeSchema --->
            <cfset local.codeSchema[local.tableService.definition.name] = local.tableService.definition />
        </cfloop>

        <cfreturn local.codeSchema />
    </cffunction>

</cfcomponent>
