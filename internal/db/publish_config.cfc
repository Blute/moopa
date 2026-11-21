<cfcomponent displayName="publish_config" output="false"
    hint="Reads the publish settings of table definitions (docs/object-storage.md: Publishing a table's files): which many-to-many file fields have their files published at an address on one of the project's sites, and when. Validates them at start, so a mistake fails loudly then, not on a save. Pure: it reads table definitions and touches nothing else.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>

    <cffunction name="anyPublished" access="public" returntype="boolean" output="false"
        hint="Whether any field of any table publishes its files. Only then does a project get the moo_published_file table.">
        <cfargument name="codeSchema" type="struct" required="true" />
        <cfset var tableName = "" />
        <cfset var fieldName = "" />
        <cfloop collection="#arguments.codeSchema#" item="tableName">
            <cfloop collection="#arguments.codeSchema[tableName].fields ?: {}#" item="fieldName">
                <cfif isStruct(arguments.codeSchema[tableName].fields[fieldName]) AND structKeyExists(arguments.codeSchema[tableName].fields[fieldName], "publish")>
                    <cfreturn true />
                </cfif>
            </cfloop>
        </cfloop>
        <cfreturn false />
    </cffunction>

    <cffunction name="build" access="public" returntype="struct" output="false"
        hint="The tables that publish files, each with its publishing fields: { table: { field: { site, address, when, first, bridge } } }. Throws moopa.publish.invalid naming the table and field for a setting that can't work.">
        <cfargument name="codeSchema" type="struct" required="true" />

        <cfset var publishing = {} />
        <cfset var tableName = "" />
        <cfset var fieldName = "" />
        <cfset var field = {} />
        <cfset var where = "" />

        <cfloop collection="#arguments.codeSchema#" item="tableName">
            <cfloop collection="#arguments.codeSchema[tableName].fields ?: {}#" item="fieldName">
                <cfset field = arguments.codeSchema[tableName].fields[fieldName] />
                <cfif NOT isStruct(field) OR NOT structKeyExists(field, "publish")>
                    <cfcontinue />
                </cfif>
                <cfset where = "#tableName#.#fieldName#" />
                <cfif NOT structKeyExists(publishing, tableName)>
                    <cfset publishing[tableName] = {} />
                </cfif>
                <cfset publishing[tableName][fieldName] = fieldSetting(arguments.codeSchema[tableName], field, where) />
            </cfloop>
        </cfloop>
        <cfreturn publishing />
    </cffunction>

    <cffunction name="fieldSetting" access="private" returntype="struct" output="false">
        <cfargument name="tableDef" type="struct" required="true" />
        <cfargument name="field" type="struct" required="true" />
        <cfargument name="where" type="string" required="true" />

        <cfset var setting = arguments.field.publish />
        <cfset var address = "" />
        <cfset var placeholder = "" />
        <cfset var name = "" />
        <cfset var whenField = "" />

        <cfif (arguments.field.type ?: "") NEQ "many_to_many" OR (arguments.field.foreign_key_table ?: "") NEQ "moo_file">
            <cfset fail(arguments.where, "only a many_to_many field of moo_file can publish its files") />
        </cfif>
        <cfif NOT isStruct(setting)>
            <cfset fail(arguments.where, "publish is a struct: { site, address, when }") />
        </cfif>
        <cfif NOT isSimpleValue(setting.site ?: "") OR reFind("[^a-z0-9-]", setting.site ?: "") OR NOT reFind("^[a-z0-9][a-z0-9-]{0,62}$", setting.site ?: "")>
            <cfset fail(arguments.where, "publish.site is a site name: lowercase letters, digits and dashes") />
        </cfif>

        <cfset address = isSimpleValue(setting.address ?: "") ? trim(setting.address ?: "") : "" />
        <!--- Literal parts are an address's own characters; {placeholders} name the record's fields, or the file's
              {name} and {ext}. --->
        <cfif left(address, 1) NEQ "/" OR reFind("[^A-Za-z0-9._/{}-]", address) OR NOT reFind("^(/|[A-Za-z0-9._-]|\{[a-z_][a-z0-9_]*\})+$", address) OR right(address, 1) EQ "/">
            <cfset fail(arguments.where, "publish.address is a path starting with /, of letters, digits, dot, dash, underscore and {placeholders}, ending in a file name: /datasheets/{slug}.pdf") />
        </cfif>
        <cfloop array="#reMatch('\{[a-z_][a-z0-9_]*\}', address)#" item="placeholder">
            <cfset name = mid(placeholder, 2, len(placeholder) - 2) />
            <cfif name EQ "name" OR name EQ "ext">
                <cfcontinue />
            </cfif>
            <cfif NOT structKeyExists(arguments.tableDef.fields, name) OR NOT isStruct(arguments.tableDef.fields[name]) OR listFindNoCase("many_to_many", arguments.tableDef.fields[name].type ?: "")>
                <cfset fail(arguments.where, "publish.address names {#name#}, which is not a column of the table") />
            </cfif>
        </cfloop>

        <cfset whenField = isSimpleValue(setting.when ?: "") ? trim(setting.when ?: "") : "" />
        <cfif len(whenField) AND (NOT structKeyExists(arguments.tableDef.fields, whenField) OR NOT listFindNoCase("bool,boolean", arguments.tableDef.fields[whenField].type ?: ""))>
            <cfset fail(arguments.where, "publish.when names #whenField#, which is not a bool column of the table") />
        </cfif>
        <cfif NOT len(arguments.field.bridgingTableName ?: "")>
            <cfset fail(arguments.where, "the field has no bridging table") />
        </cfif>

        <cfreturn {
            "site": setting.site,
            "address": address,
            "when": whenField,
            <!--- Without {name}, every file would have one address: only the field's first file is published. --->
            "first": NOT find("{name}", address),
            "bridge": arguments.field.bridgingTableName
        } />
    </cffunction>

    <cffunction name="fail" access="private" returntype="void" output="false">
        <cfargument name="where" type="string" required="true" />
        <cfargument name="message" type="string" required="true" />
        <cfthrow type="moopa.publish.invalid" message="#arguments.where#: #arguments.message#" />
    </cffunction>

</cfcomponent>
