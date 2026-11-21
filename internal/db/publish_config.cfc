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
                <cfloop collection="#publishing[tableName]#" item="local.other">
                    <cfif local.other NEQ fieldName AND publishing[tableName][local.other].site EQ publishing[tableName][fieldName].site
                        AND compare(publishing[tableName][local.other].address, publishing[tableName][fieldName].address) EQ 0>
                        <cfset fail(where, "publishes at the same addresses as #tableName#.#local.other#") />
                    </cfif>
                </cfloop>
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
        <cfset var key = "" />
        <cfset var columns = [] />
        <cfset var sample = "" />
        <cfset var segment = "" />
        <cfset var literalPart = "" />

        <cfif (arguments.field.type ?: "") NEQ "many_to_many" OR (arguments.field.foreign_key_table ?: "") NEQ "moo_file">
            <cfset fail(arguments.where, "only a many_to_many field of moo_file can publish its files") />
        </cfif>
        <cfif NOT isStruct(setting)>
            <cfset fail(arguments.where, "publish is a struct: { site, address, when }") />
        </cfif>
        <!--- A misspelt key (wen, if) would otherwise be ignored, and with it the condition it meant. --->
        <cfloop collection="#setting#" item="key">
            <cfif NOT listFindNoCase("site,address,when", key)>
                <cfset fail(arguments.where, "publish has no setting '#key#' (site, address, when)") />
            </cfif>
        </cfloop>
        <cfif NOT isSimpleValue(setting.site ?: "") OR reFind("[^a-z0-9-]", setting.site ?: "") OR NOT reFind("^[a-z0-9][a-z0-9-]{0,62}$", setting.site ?: "")>
            <cfset fail(arguments.where, "publish.site is a site name: lowercase letters, digits and dashes") />
        </cfif>

        <cfset address = isSimpleValue(setting.address ?: "") ? trim(setting.address ?: "") : "" />
        <!--- Literal parts are lowercase letters, digits, dot, dash and underscore; {placeholders} name the record's
              columns, or the file's {name} and {ext}. Every address made from it is then lowercase, as its values are
              made readable: one spelling per address. --->
        <cfif left(address, 1) NEQ "/" OR reFind("[^a-z0-9._/{}-]", reReplace(address, "\{[a-z_][a-z0-9_]*\}", "", "all")) OR NOT reFind("^(/|[a-z0-9._-]|\{[a-z_][a-z0-9_]*\})+$", address) OR right(address, 1) EQ "/">
            <cfset fail(arguments.where, "publish.address is a path starting with /, of lowercase letters, digits, dot, dash, underscore and {placeholders}, ending in a file name: /datasheets/{slug}.pdf") />
        </cfif>
        <cfloop array="#reMatch('\{[a-z_][a-z0-9_]*\}', address)#" item="placeholder">
            <cfset name = mid(placeholder, 2, len(placeholder) - 2) />
            <!--- {name} and {ext} are always the file's, whatever the table's columns are called. --->
            <cfif name EQ "name" OR name EQ "ext">
                <cfcontinue />
            </cfif>
            <cfif NOT structKeyExists(arguments.tableDef.fields, name) OR NOT isStruct(arguments.tableDef.fields[name])
                OR listFindNoCase("many_to_many,relation,json,jsonb,tsvector,vector,geometry,geography,point,polygon,bytea", arguments.tableDef.fields[name].type ?: "")>
                <cfset fail(arguments.where, "publish.address names {#name#}, which is not a plain column of the table") />
            </cfif>
            <cfif NOT arrayFindNoCase(columns, name)>
                <cfset arrayAppend(columns, name) />
            </cfif>
        </cfloop>
        <!--- Filled in, the template must make an address the store and the Worker accept: no empty, "." or ".." segment,
              none over 200 characters. --->
        <cfset sample = reReplace(address, "\{[a-z_][a-z0-9_]*\}", "x", "all") />
        <cfloop list="#mid(sample, 2, len(sample))#" delimiters="/" item="segment">
            <cfif segment EQ "." OR segment EQ ".." OR len(segment) GT 200>
                <cfset fail(arguments.where, "publish.address has a segment no address can have ('#segment#')") />
            </cfif>
        </cfloop>
        <cfif find("//", sample)>
            <cfset fail(arguments.where, "publish.address has an empty segment") />
        </cfif>

        <cfif structKeyExists(setting, "when")>
            <cfset whenField = isSimpleValue(setting.when) ? trim(setting.when) : "" />
            <cfif NOT len(whenField) OR NOT structKeyExists(arguments.tableDef.fields, whenField) OR NOT isStruct(arguments.tableDef.fields[whenField]) OR NOT listFindNoCase("bool,boolean", arguments.tableDef.fields[whenField].type ?: "")>
                <cfset fail(arguments.where, "publish.when ('#isSimpleValue(setting.when) ? setting.when : '(not a name)'#') is not a bool column of the table") />
            </cfif>
            <cfif NOT arrayFindNoCase(columns, whenField)>
                <cfset arrayAppend(columns, whenField) />
            </cfif>
        </cfif>
        <cfif NOT len(arguments.field.bridgingTableName ?: "")>
            <cfset fail(arguments.where, "the field has no bridging table") />
        </cfif>

        <!--- The literal folder the template's addresses are under (/datasheets/ for /datasheets/{slug}.pdf): syncAll
              clears copies there that no record accounts for. "/" when the template has none. --->
        <cfset literalPart = find("{", address) ? left(address, find("{", address) - 1) : address />
        <cfset literalPart = left(literalPart, len(literalPart) - find("/", reverse(literalPart)) + 1) />

        <cfreturn {
            "site": setting.site,
            "address": address,
            "when": whenField,
            <!--- Without {name}, every file would have one address: only the field's first file is published. --->
            "first": NOT find("{name}", address),
            "bridge": arguments.field.bridgingTableName,
            "columns": columns,
            "folder": literalPart
        } />
    </cffunction>

    <cffunction name="fail" access="private" returntype="void" output="false">
        <cfargument name="where" type="string" required="true" />
        <cfargument name="message" type="string" required="true" />
        <cfthrow type="moopa.publish.invalid" message="#arguments.where#: #arguments.message#" />
    </cffunction>

</cfcomponent>
