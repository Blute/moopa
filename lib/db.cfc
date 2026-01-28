<cfcomponent displayName="db" hint="A library for synchronizing database schema with a JSON payload.">

    <!--- Initialize function for setting up the database connection --->
    <cffunction name="init" access="public" returntype="any" hint="Initialize db with the database connection information.">
        <!--- <cfargument name="dbinfo" type="struct" required="true" hint="A struct containing the database connection information.">
        <cfset this.dbOldinfo = arguments.dbOldinfo> --->

        <cfset this.codeSchema = {} />
        <cfset this.searchable_tables = {} />

        <!--- Use the following regex pattern to normalize column defaults and generated expressions between the definition and how postgresql depoloys --->
        <!--- <cfset this.normalizeFieldPattern = "::[a-zA-Z0-9_ ]*|[()]| " /> --->
        <cfset this.normalizeFieldPattern = "::[a-zA-Z0-9_ ]*|[()]| |\r?\n" />

        <!--- Use the following regex pattern to normalize index field definitions --->
        <!--- Removes: parentheses, quotes, type casts (::text, ::jsonb, etc.), spaces, newlines --->
        <cfset this.normalizeIndexPattern = "::[a-zA-Z0-9_]*|[()']| |\r?\n" />


        <!--- Merge the results --->
        <cfset structAppend(this.codeSchema, processDirectory('/moopa'))>
        <cfset structAppend(this.codeSchema, processDirectory('/project'))>




        <cfset this.codeSchema = sanitizeCodeSchema(this.codeSchema)>


        <cfreturn this>
    </cffunction>

    <!--- Function to process a single directory --->
    <cffunction name="processDirectory" returntype="struct" access="private">
        <cfargument name="path" type="string" required="true">

        <cfset var local = {}>
        <cfset local.codeSchema = {}>

        <!--- List all CFC files in the directory --->
        <cfdirectory action="list" directory="#arguments.path#/tables" name="local.directoryList" filter="*.cfc">

        <cfloop query="local.directoryList">
            <cfset local.tableName = listFirst(local.directoryList.name, '.')>
            <cfset local.filePath = replace(local.directoryList.directory, expandPath(arguments.path), arguments.path) & '/' & local.tableName>

            <!--- Create and initialize the table service object --->
            <cfset local.tableService = createObject('component', local.filePath).init()>
            <cfset local.tableService.definition.path = local.filePath>

            <!--- Validate the table definition --->
            <cfif NOT structKeyExists(local.tableService.definition, 'fields')>
                <cfthrow message="Model must contain fields">
            </cfif>

            <!--- Set table name if not provided --->
            <cfif NOT len(local.tableService.definition.name ?: '')>
                <cfset local.tableService.definition.name = listFirst(local.directoryList.name, '.')>
            </cfif>

            <!--- Validate table name --->
            <cfset local.validTableNamePattern = "^[a-z_][a-z0-9_]{0,62}$">
            <cfif NOT reFind(local.validTableNamePattern, local.tableService.definition.name)>
                <cfthrow message="#local.tableService.definition.name# is not a valid postgresql table name.">
            </cfif>

            <!--- Add to codeSchema --->
            <cfset local.codeSchema[local.tableService.definition.name] = local.tableService.definition>
        </cfloop>

        <cfreturn local.codeSchema>
    </cffunction>

<!---
search
getNewObject
read
delete
save (insert/update) -- upsert basically


data: {
    id: 123
}

Create - Save Without id
Update - Save With id
Read - read
Delete - delete
 --->

    <cffunction name="run" hint="switch function to perform CRUD based on the action passed in">
        <cfargument name="operation" type="string" hint="Create/Read/Update/Delete" />
        <cfargument name="table_name" type="string" />
        <cfargument name="data" type="struct" default="#structNew()#" />
        <cfargument name="returnAsCFML" type="boolean" required="false" default=false />

        <cfset var res = "" />

        <cfswitch expression="#arguments.operation#">
            <cfcase value="Create">
                <cfset res = application.lib.db.save(argumentCollection = arguments ) />
            </cfcase>
            <cfcase value="Read">
                <cfset res = application.lib.db.read(argumentCollection = arguments ) />
            </cfcase>
            <cfcase value="Update">
                <cfset res = application.lib.db.save(argumentCollection = arguments ) />
            </cfcase>
            <cfcase value="Delete">
                <cfset res = application.lib.db.delete(argumentCollection = arguments ) />
            </cfcase>
        </cfswitch>

        <cfreturn res />
    </cffunction>


    <cffunction name="getSearchableTables" hint="Returns the struct containing tables with BM25 full-text search enabled">
        <cfreturn this.searchable_tables />
    </cffunction>


    <cffunction name="getService" hint="Returns an instatiated table component">
        <cfargument name="table_name" type="string" />

        <cfreturn CreateObject('component', this.codeSchema[arguments.table_name].path).init() />
    </cffunction>

    <cffunction name="getTableDef" hint="Returns the sanitized code that defines the table">
        <cfargument name="table_name" type="string" />

        <cfreturn duplicate(this.codeSchema[arguments.table_name]) />
    </cffunction>

    <cffunction name="getFieldDef" hint="Returns the sanitized code that defines the table">
        <cfargument name="table_name" type="string" />
        <cfargument name="field_name" type="string" />

        <cfreturn this.codeSchema[arguments.table_name].fields[arguments.field_name] />
    </cffunction>

    <cffunction name="getNewObject">
        <cfargument name="table_name" type="string" />
        <cfargument name="data" type="struct" default="#structNew()#" />
        <cfargument name="returnAsCFML" type="boolean" required="false" default=false />
        <cfargument name="create" type="boolean" required="false" default=false />


        <!--- Initialize variables --->
        <cfset var dynamicSQL = "'is_new_record',true">
        <cfset var defaultValueList = "">

        <cfset var table = this.codeSchema[arguments.table_name] />
        <cfset var stDefaultObject = {} />


        <cfloop collection="#table.fields#" item="field" index="i">
            <cfif !(field.is_system?:false)>
                <cfswitch expression="#field.type#">
                    <cfcase value="int2,int4,int8">
                        <cfset stDefaultObject[field.name] = 0 />
                    </cfcase>
                    <cfcase value="bool">
                        <cfset stDefaultObject[field.name] = false />
                    </cfcase>
                    <cfcase value="many_to_many">
                        <cfset stDefaultObject[field.name] = [] />
                    </cfcase>
                    <cfcase value="relation">
                        <cfset stDefaultObject[field.name] = [] />
                    </cfcase>
                    <cfdefaultcase>
                        <cfset stDefaultObject[field.name] = "" />
                    </cfdefaultcase>
                </cfswitch>

                <cftry>
                    <cfif len(field.default)>
                        <cfset stDefaultObject[field.name] = evaluate(item.default) />
                    </cfif>
                    <cfcatch type="any">
                        <!--- IGNORE --->
                    </cfcatch>
                </cftry>
            </cfif>
        </cfloop>


        <cfloop collection="#table.fields#" item="field" index="i">
            <cfif len(field.default?:'')  AND !(field.is_system?:false)>

                <cfset defaultValue = field.default>

                <cfif field.type EQ "date">
                    <cfset defaultValue = "#defaultValue#::date">
                </cfif>

                <cfif field.type EQ "uuid">
                    <cfset defaultValue = "#defaultValue#::text">
                </cfif>
                <cfif field.type EQ "jsonb">
                    <cfset defaultValue = "#defaultValue#::jsonb">
                </cfif>
                <!--- SELECT jsonb_build_object('lease_terms', '[]'::jsonb, 'title', 'test') as json_object --->
                <!--- Build the dynamic SQL statement --->
                <cfset dynamicSQL = listAppend(dynamicSQL, "'#field.name#', #defaultValue#" )>
            </cfif>
        </cfloop>

        <cfif len(trim(dynamicSQL))>
            <!--- Output the final SQL statement --->

            <cfquery name="qNewDBObject">
                <!--- Constructed SQL statement --->
                SELECT jsonb_build_object(#PreserveSingleQuotes(dynamicSQL)#) as json_object
            </cfquery>

            <cfloop collection="#deserializeJSON(qNewDBObject.json_object)#" item="column_value" index="column_name">
                <cfset stDefaultObject[column_name] = column_value />
            </cfloop>
        </cfif>


        <cfset structAppend(stDefaultObject, arguments.data, true) />

        <cfif arguments.create>
            <cfset new_object = save(table_name=arguments.table_name, data=stDefaultObject, returnAsCFML=true) />
            <cfset stDefaultObject = read(table_name=arguments.table_name, id=new_object.id, returnAsCFML=true) />
        </cfif>

        <cfif !arguments.returnAsCFML>
            <cfreturn serializeJSON(stDefaultObject) />
        </cfif>

        <cfreturn stDefaultObject />
    </cffunction>


    <cffunction name="select" hint="Returns a list of fields that can be used in a query SELECT statement">
        <cfargument name="table_name" required="true" type="string" />
        <cfargument name="field_list" type="string" default="" hint="List of fields to include" />
        <cfargument name="exclude_list" type="string" default="" hint="List of fields to exclude" />
        <cfargument name="sql_type" type="string" default="expanded" hint="simple,expanded,condensed" />
        <cfargument name="sql_table_name" type="string" default="#arguments.table_name#" />

        <cfif arguments.field_list EQ "*">
            <cfset field_list_to_loop = structKeyList(this.codeSchema[arguments.table_name].fields) />
        <cfelseif len(trim(arguments.field_list))>
            <cfset field_list_to_loop = arguments.field_list />
        <cfelse>
            <!--- Default behavior: all fields except created_by and last_updated_by --->
            <cfset var allFields = structKeyList(this.codeSchema[arguments.table_name].fields) />
            <cfset field_list_to_loop = listDeleteAt(allFields, listFindNoCase(allFields, "created_by")) />
            <cfset field_list_to_loop = listDeleteAt(field_list_to_loop, listFindNoCase(field_list_to_loop, "last_updated_by")) />
        </cfif>

        <!--- Exclude specified fields if exclude_list is not empty --->
        <cfif len(trim(arguments.exclude_list))>
            <cfloop list="#arguments.exclude_list#" index="exclude_field">
                <cfset pos = listFind(field_list_to_loop, exclude_field) />
                <cfif pos GT 0>
                    <cfset field_list_to_loop = listDeleteAt(field_list_to_loop, pos) />
                </cfif>
            </cfloop>
        </cfif>

        <cfset return_select_fields = "" />

        <cftry>
            <cfloop list="#field_list_to_loop#" item="field_name">
                <cfset field_sql = "" />
                <cfswitch expression="#arguments.sql_type#">
                    <cfcase value="simple">
                        <cfif len(trim(this.codeSchema[arguments.table_name].fields[field_name].sql_select_simple ?: ''))>
                            <cfset field_sql = this.codeSchema[arguments.table_name].fields[field_name].sql_select_simple>
                        </cfif>
                    </cfcase>
                    <cfcase value="expanded">
                        <cfif len(trim(this.codeSchema[arguments.table_name].fields[field_name].sql_select_expanded ?: ''))>
                            <cfset field_sql = this.codeSchema[arguments.table_name].fields[field_name].sql_select_expanded>
                        </cfif>
                    </cfcase>
                    <cfcase value="condensed">
                        <cfif len(trim(this.codeSchema[arguments.table_name].fields[field_name].sql_select_condensed ?: ''))>
                            <cfset field_sql = this.codeSchema[arguments.table_name].fields[field_name].sql_select_condensed>
                        </cfif>
                    </cfcase>
                </cfswitch>

                <cfif len(trim(field_sql))>
                    <cfif arguments.sql_table_name NEQ arguments.table_name>
                        <!--- I need to convert #arguments.table_name#.id to #arguments.sql_table_name#.id --->
                        <cfset field_sql = replaceNoCase(trim(field_sql), "#arguments.table_name#.", "#arguments.sql_table_name#.", "one ")>
                    </cfif>
                    <cfset return_select_fields = listAppend(return_select_fields, field_sql) />
                </cfif>
            </cfloop>

            <cfcatch type="any">
                <cfdump var="#cfcatch#" expand="true">
                <cfdump var="#this.codeSchema[arguments.table_name].fields#" expand="true">
                <cfabort>
            </cfcatch>
        </cftry>

        <cfreturn "#return_select_fields#" />
    </cffunction>



    <cffunction name="orderby" hint="Returns the default sql order by clause for a table">
        <cfargument name="table_name" required="true" type="string" />

        <cfset order_by = "" />

        <cfif len(trim(this.codeSchema[arguments.table_name].order_by))>
            <cfset order_by = this.codeSchema[arguments.table_name].order_by />
        </cfif>

        <cfreturn "ORDER BY #order_by#" />
    </cffunction>


    <cffunction name="imagekit" returntype="string" hint="Returns the postgresql imagekit_url function call">
        <cfargument name="path" type="string" required="true" hint="Column name or SQL expression containing the file path" />
        <cfargument name="params" type="any" required="false" default="" hint="Struct of transforms or prebuilt ImageKit transform string (e.g., 'w-400,h-300')" />
        <cfargument name="expires" type="any" required="false" default="MONTH" hint="Duration in seconds (numeric) or end-of period (string like 'hour', 'day', etc.)" />
        <cfargument name="thumbnail" type="boolean" required="false" default="false" hint="For PDF/video to image conversion, appends /ik-thumbnail.jpg" />
        <cfargument name="private_key" type="string" required="false" default="#server.system.environment.IMAGEKIT_PRIVATE_KEY#" />
        <cfargument name="url_endpoint" type="string" required="false" default="#server.system.environment.IMAGEKIT_URL_ENDPOINT#" />

        <!--- Turn struct params into ImageKit transform string --->
        <cfset var params_string = "" />
        <cfif isStruct(arguments.params) AND NOT structIsEmpty(arguments.params)>
            <cfset params_string = application.lib.imagekit.buildParams(arguments.params) />
        <cfelseif isSimpleValue(arguments.params)>
            <cfset params_string = toString(arguments.params) />
        </cfif>

        <!--- Assemble Postgres function call string (note: path is an expression, not quoted) --->
        <cfreturn "imagekit_url(" & arguments.path & ", '" & arguments.private_key & "', '" & arguments.url_endpoint & "', '" & arguments.expires & "', '" & params_string & "', " & arguments.thumbnail & ")" />

    </cffunction>


    <cffunction name="read" returntype="any" hint="Returns a JSON object or a CFML array for the matching id">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="false" default="" />
        <cfargument name="data" type="struct" required="false" default="#structNew()#" />
        <cfargument name="field_list" type="string" default="" hint="List of fields to include" />
        <cfargument name="exclude_list" type="string" default="" hint="List of fields to exclude" />
        <cfargument name="sql_type" type="string" default="expanded" hint="Simple, expanded, condensed" />
        <cfargument name="returnAsCFML" type="boolean" required="false" default=false />

        <cfset res = {} />

        <cfif !structKeyExists(this.codeSchema, arguments.table_name)>
            <cfthrow message="Invalid Table Name" />
        </cfif>

        <cfif len(arguments.data.id?:'')>
            <cfset idValue = arguments.data.id />
        <cfelseif len(arguments.id)>
            <cfset idValue = arguments.id />
        <cfelse>
            <cfthrow message="No ID provided" />
        </cfif>

        <cftry>
            <cfquery name="qData" result="qResult">
                SELECT COALESCE(row_to_json(data)::text, '{}') as recordset
                FROM (
                    SELECT #select(table_name=arguments.table_name, field_list="#arguments.field_list#", exclude_list="#arguments.exclude_list#", sql_type="#arguments.sql_type#")#
                    FROM #arguments.table_name#
                    WHERE id = <cfqueryparam cfsqltype="other" value="#local.idValue#" />
                    #orderby(table_name=arguments.table_name)#
                ) AS data
            </cfquery>
            <cfcatch type="any">
                <cfdump var="#cfcatch#" expand="true">
                <cfabort>
            </cfcatch>
        </cftry>

        <cfif len(qData.recordset)>
            <cfset res = qData.recordset />
        <cfelse>
            <cfset res = "{}" />
        </cfif>


        <cfif arguments.returnAsCFML>
            <cftry>
            <cfreturn deserializeJSON(res) />
                <cfcatch type="any">
                    <cfdump var="#cfcatch#">
                    <cfdump var="#qResult#"><cfabort>
                </cfcatch>
            </cftry>
        <cfelse>
            <cfreturn res />
        </cfif>
    </cffunction>



    <cffunction name="search" returntype="any" hint="returns an array for ids or search query string (q)">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="field_list" type="string" required="false" default="*" />
        <cfargument name="q" type="string" required="false" default="" />
        <cfargument name="where" type="struct" required="false" default="#structNew()#" />
        <cfargument name="ids" type="array" required="false" default="#arrayNew()#" />
        <cfargument name="exclude_ids" type="string" required="false" default="" />
        <cfargument name="offset" type="numeric" required="false" />
        <cfargument name="limit" type="string" required="false" default=250 />
        <cfargument name="select_append" type="string" required="false" default="" hint="Additional SELECT expressions to append (e.g. subqueries, computed fields)" />
        <cfargument name="returnAsCFML" type="boolean" required="false" default=false />

        <cfif !structKeyExists(this.codeSchema, arguments.table_name)>
            <cfthrow message="Invalid Table Name" />
        </cfif>



        <cfquery name="qData">
            SELECT COALESCE(array_to_json(array_agg(row_to_json(data)))::text, '[]') AS recordset
            FROM (
                SELECT #select(table_name=arguments.table_name, field_list="#arguments.field_list#")#
                    <cfif len(arguments.select_append)>
                        , #preserveSingleQuotes(arguments.select_append)#
                    </cfif>
                FROM #arguments.table_name#
                WHERE 1 = 1


                <!--- Process where conditions inside the query --->
                <cfloop collection="#arguments.where#" item="field">
                    <cfset local.value = arguments.where[field] />

                    <cfif isStruct(local.value) AND structKeyExists(local.value, "operator")>
                        <cfset local.operator = local.value.operator />
                        <cfset local.sqlType = structKeyExists(local.value, "type") ? local.value.type : getFieldDef(table_name='#arguments.table_name#', field_name='#field#').cfsqltype />

                        <cfswitch expression="#local.operator#">
                            <cfcase value="IN">
                                AND #field# IN (<cfqueryparam cfsqltype="#local.sqlType#" value="#local.value.value#" list="true" />)
                            </cfcase>
                            <cfcase value="LIKE">
                                AND #field# LIKE <cfqueryparam cfsqltype="#local.sqlType#" value="%#local.value.value#%" />
                            </cfcase>
                            <cfcase value="<,>,<=,>=,<>">
                                AND #field# #local.operator# <cfqueryparam cfsqltype="#local.sqlType#" value="#local.value.value#" />
                            </cfcase>
                            <cfdefaultcase>
                                AND #field# = <cfqueryparam cfsqltype="#local.sqlType#" value="#local.value.value#" />
                            </cfdefaultcase>
                        </cfswitch>
                    <cfelse>
                        AND #field# = <cfqueryparam cfsqltype="#getFieldDef(table_name='#arguments.table_name#', field_name='#field#').cfsqltype#" value="#local.value#" />
                    </cfif>
                </cfloop>


                <cfif len(arguments.q)>
                    <cfif structKeyExists(this.searchable_tables, arguments.table_name)>

                        <!--- Use ParadeDB legacy API BM25 full-text search --->
                        <!--- Legacy syntax: field @@@ 'query' --->
                        <!--- See: https://docs.paradedb.com/legacy/full-text/overview --->
                        <!--- NOTE: Skip JSONB fields - they are not indexed in legacy API --->
                        <cfset search_field_configs = this.searchable_tables[arguments.table_name].field_configs />
                        AND (
                            <cfset bFirst = true />
                            <cfloop list="#this.searchable_tables[arguments.table_name].searchable_fields#" item="search_field_name">
                                <!--- Skip JSONB fields --->
                                <cfif (search_field_configs[search_field_name].field_type ?: "varchar") EQ "jsonb">
                                    <cfcontinue />
                                </cfif>
                                <cfif NOT bFirst> OR </cfif><cfset bFirst = false />
                                #search_field_name# @@@ <cfqueryparam cfsqltype="varchar" value="#replace(arguments.q, "'", "''", "ALL")#" />
                            </cfloop>
                        )

                    <cfelse>

                        AND label ILIKE <cfqueryparam cfsqltype="varchar" value="%#arguments.q#%" />
                    </cfif>

                </cfif>


                <cfif arraylen(arguments.ids)>
                    AND id in (<cfqueryparam cfsqltype="other" list="true" value="#arguments.ids#" />)
                </cfif>

                <cfif len(arguments.exclude_ids)>
                    AND id NOT IN (<cfqueryparam cfsqltype="other" list="true" value="#arguments.exclude_ids#" />)
                </cfif>

                <!--- Legacy ParadeDB: @@@ operator returns results in relevance order by default --->
                <cfif NOT (len(arguments.q) AND structKeyExists(this.searchable_tables, arguments.table_name))>
                    #orderby(table_name=arguments.table_name)#
                </cfif>

                <cfif structKeyExists(arguments, "offset")>
                    OFFSET <cfqueryparam cfsqltype="numeric" value="#arguments.offset#" />
                </cfif>

                LIMIT <cfqueryparam cfsqltype="numeric" value="#arguments.limit#" />
            ) AS data
        </cfquery>

        <cfif arraylen(arguments.ids) GT 1>
            <cfset orderedRecordset = sortRecordsetByIds(qData.recordset, arguments.ids) />

            <cfif arguments.returnAsCFML>
                <cfreturn orderedRecordset />
            <cfelse>
                <cfreturn serializeJSON(orderedRecordset) />
            </cfif>

        <cfelse>

            <cfif arguments.returnAsCFML>
                <cfreturn deserializeJSON(qData.recordset) />
            <cfelse>
                <cfreturn qData.recordset />
            </cfif>
        </cfif>
    </cffunction>

    <cffunction name="idsInSearchTerm" hint="Returns array of IDs matching the search term using BM25 full-text search">
        <cfargument name="table_name" required="true" />
        <cfargument name="term" required="true" />
        <cfargument name="limit" required="false" default="20">

        <cfset search_ids = [] />

        <cfif structKeyExists(this.searchable_tables, arguments.table_name) AND len(arguments.term)>

            <!--- Legacy ParadeDB: field @@@ 'query' --->
            <!--- See: https://docs.paradedb.com/legacy/full-text/overview --->
            <!--- NOTE: Skip JSONB fields - they are not indexed in legacy API --->
            <cfset search_field_configs = this.searchable_tables[arguments.table_name].field_configs />
            <cfquery name="qSearchIds">
                SELECT id
                FROM #arguments.table_name#
                WHERE (
                    <cfset bFirst = true />
                    <cfloop list="#this.searchable_tables[arguments.table_name].searchable_fields#" item="search_field_name">
                        <!--- Skip JSONB fields --->
                        <cfif (search_field_configs[search_field_name].field_type ?: "varchar") EQ "jsonb">
                            <cfcontinue />
                        </cfif>
                        <cfif NOT bFirst> OR </cfif><cfset bFirst = false />
                        #search_field_name# @@@ <cfqueryparam cfsqltype="varchar" value="#replace(arguments.term, "'", "''", "ALL")#" />
                    </cfloop>
                )
                LIMIT <cfqueryparam cfsqltype="numeric" value="#arguments.limit#" />
            </cfquery>

            <cfloop query="qSearchIds">
                <cfset arrayAppend(search_ids, qSearchIds.id) />
            </cfloop>
        </cfif>

        <cfif !arrayLen(search_ids)>
            <cfset search_ids = ['607ceee8-2cc0-4f9a-bed8-9f2f3affc575']>
        </cfif>

        <cfreturn search_ids />

    </cffunction>



    <cffunction name="sortRecordsetByIds">
        <cfargument name="recordset" required="true" />
        <cfargument name="ids" required="true" type="array" />

        <!--- We need to sort the results based on the search response --->

        <cfif isJSON(arguments.recordset)>
            <cfset unorderedRecordset = deserializeJSON(arguments.recordset) />
        <cfelse>
            <cfset unorderedRecordset = arguments.recordset />
        </cfif>

        <cfif !arraylen(arguments.ids?:[])>
            <cfreturn unorderedRecordset />
        </cfif>


        <cfset orderedRecordset = []>

        <cfloop array="#arguments.ids#" item="id">
            <cfloop array="#unorderedRecordset#" item="record">
                <cfif record.id EQ id>
                    <cfset ArrayAppend(orderedRecordset, record)>
                    <cfbreak>
                </cfif>
            </cfloop>
        </cfloop>
        <cfreturn orderedRecordset />


    </cffunction>


    <cffunction name="delete" returntype="any" hint="returns a json or cfml object for the results of the deletion">
        <cfargument name="table_name" required="true" />
        <cfargument name="id" type="string" required="false" default="" />
        <cfargument name="data" type="struct" required="false" default="#structNew()#" />
        <cfargument name="returnAsCFML" type="boolean" required="false" default=false />

        <cfif len(arguments.data.id?:'')>
            <cfset idValue = arguments.data.id />
        <cfelseif len(arguments.id)>
            <cfset idValue = arguments.id />
        <cfelse>
            <cfthrow message="No ID provided" />
        </cfif>

        <cfquery name="q" result="result">
            DELETE
            FROM #arguments.table_name#
            WHERE id = <cfqueryparam cfsqltype="other" value="#idValue#" />
        </cfquery>

        <!--- Note: BM25 search index is automatically updated when record is deleted --->

        <cfif arguments.returnAsCFML>
            <cfreturn result />
        <cfelse>
            <cfreturn serializeJSON(result) />
        </cfif>
    </cffunction>



    <!---
    dynamically insert or update record based on the presence of an id in the provided data.
    If no id is included, insert!
    If id is included, search for existing record. if exists, update otherwise insert using the id.
     --->
    <cffunction name="save" returntype="any" hint="create/insert based on data.id.">
        <cfargument name="table_name" required="true" />
        <cfargument name="data" default="#structNew()#"/>
        <cfargument name="returnAsCFML" type="boolean" required="false" default=false />
        <cfargument name="index_record" type="boolean" default=true />

        <cfset var result = {
            id : (arguments.data.id?:''),
            sql_statements : []
        } />

        <cfset var stModel = this.codeSchema[arguments.table_name] />

        <!--- MAIN PAYLOAD --->
        <cfset var stDataFields = {} />




        <cfloop collection="#arguments.data#" item="data_field" index="field_name">

            <!--- Remove keys not in the table --->
            <cfif !structKeyExists(stModel.fields, field_name)>
                <cfcontinue />
            </cfif>

            <cfif len(stModel.fields[field_name].generation_expression?:'')>
                <cfcontinue />
            </cfif>
            <cfif findNoCase('serial', stModel.fields[field_name].type)>
                <cfcontinue />
            </cfif>

            <cfif isNull(arguments.data[field_name])>
                <cfset stDataFields[field_name] = "" />
                <cfcontinue />
            </cfif>

            <cfset stDataFields[field_name] = arguments.data[field_name] />

            <cfset model_field = stModel.fields[field_name] />

            <!--- CONVERT STRUCT TO JUST THE Foreign Key --->
            <cfif len(model_field.foreign_key_field?:'') AND isStruct(stDataFields[field_name])>
                <cfif isEmpty(stDataFields[field_name])>
                    <cfset stDataFields[field_name] = "" />
                <cfelse>
                    <cfset stDataFields[field_name] = stDataFields[field_name][model_field.foreign_key_field] />
                </cfif>
            </cfif>
        </cfloop>

        <cfset recordExists = false />

        <cfif len(stDataFields.id?:'')>

            <cfif !(data.is_new_record?:false)>
                <cfset recordExists = true />
            </cfif>
<!---
            <cfquery name="qExists">
                SELECT id::text
                FROM #stModel.table_name#
                WHERE
                    <cfset bFirst = true />
                    <cfloop array="#stModel.primary_keys#" item="pk_name" index="i">
                        <cfif NOT bFirst>AND</cfif><cfset bFirst = false />

                        <cfset stParams = {
                                                cfsqltype: 'other'
                                                , value='#stDataFields[pk_name]#'
                                                , null=false
                            } />
                        #pk_name# = <cfqueryparam attributeCollection="#stParams#" />
                    </cfloop>
            </cfquery>
            <cfif qExists.recordCount>
                <cfset recordExists = true />
            </cfif> --->

        </cfif>

        <cfif recordExists>
            <cfquery name="qUpdate" result="sql">
                UPDATE #stModel.table_name#
                SET last_updated_at = now(),

                <!--- LAST_UPDATED_BY --->
                <cfif len(session.auth.profile.id?:'')>
                    last_updated_by = '#session.auth.profile.id?:''#'
                <cfelse>
                    last_updated_by = null
                </cfif>

                    <cfloop collection="#stDataFields#" item="data_field" index="data_field_name">


                            <cfset model_field = stModel.fields[data_field_name] />

                            <cfif !(model_field.is_system?:false) AND (model_field.type NEQ "many_to_many") AND (model_field.type NEQ "relation")>

                                ,

                                <cfset stParams = {
                                                    cfsqltype: 'varchar'
                                                    , value=data_field
                                                    , null=false
                                } />

                                <cfif model_field.is_nullable AND !len(stParams.value)>
                                    <cfset stParams.null = true />
                                </cfif>

                                <cfswitch expression="#model_field.type#">
                                    <cfcase value="timestamptz">
                                        <cfset stParams.cfsqltype = 'timestamp' />
                                    </cfcase>
                                    <cfcase value="date">
                                        <cfset stParams.cfsqltype = 'date' />
                                    </cfcase>
                                    <cfcase value="bool">
                                        <cfset stParams.cfsqltype = 'boolean' />
                                    </cfcase>
                                    <cfcase value="jsonb">
                                        <cfset stParams.cfsqltype = 'other' />
                                        <cfif  !IsSimpleValue(stParams.value)>
                                            <cfset stParams.value = serializeJSON(stParams.value) />
                                        </cfif>

                                        <cfif !len(trim(stParams.value))>
                                            <cfset stParams.value = '' />
                                            <cfset stParams.null = true />
                                        </cfif>
                                    </cfcase>
                                    <cfcase value="uuid">
                                        <cfset stParams.cfsqltype = 'other' />
                                        <cfif !len(trim(data_field))>
                                            <cfset stParams.value = '' />
                                            <cfset stParams.null = true />
                                        </cfif>

                                    </cfcase>
                                    <cfcase value="int2,int4,int8,smallserial,serial,bigserial,numeric">
                                        <cfset stParams.cfsqltype = 'numeric' />
                                    </cfcase>

                                    <cfdefaultcase>
                                        <cfset stParams.cfsqltype = model_field.type />

                                        <cfif isSimpleValue(stParams.value)>
                                            <cfset stParams.value = trim(stParams.value) />
                                        </cfif>
                                    </cfdefaultcase>
                                </cfswitch>


                                <cfif isNull(data_field)>
                                    <cfset stParams.value = '' />
                                    <cfset stParams.null = true />
                                </cfif>

                                #data_field_name#=<cfqueryparam attributeCollection="#stParams#" />
                            </cfif>
                    </cfloop>
                WHERE
                    <cfset bFirst = true />
                    <cfloop array="#stModel.primary_keys#" item="pk_name" index="i">
                        <cfif NOT bFirst>AND</cfif><cfset bFirst = false />

                        <cfset stParams = {
                                                cfsqltype: 'other'
                                                , value='#stDataFields[pk_name]#'
                                                , null=false
                            } />
                        #pk_name# = <cfqueryparam attributeCollection="#stParams#" />
                    </cfloop>
                </cfquery>

                <cfset arrayAppend(result.sql_statements, sql) />

        <cfelse>

            <cfif structIsEmpty(arguments.data)>
                <cfquery name="qCreate" result="sql">
                INSERT INTO #stModel.table_name# DEFAULT VALUES;
                </cfquery>
            <cfelse>
                <cfquery name="qCreate" result="sql">
                INSERT INTO #stModel.table_name# (

                    created_by

                    <cfloop collection="#stDataFields#" item="data_field" index="data_field_name">
                        <cfif structKeyExists(stModel.fields, data_field_name)>
                            <cfset model_field = stModel.fields[data_field_name] />
                            <cfif !(model_field.is_system?:false) AND (model_field.type NEQ "many_to_many") AND (model_field.type NEQ "relation")>
                                , #data_field_name#
                            </cfif>
                        </cfif>
                    </cfloop>

                    <cfif len(stDataFields.id?:'')>
                        , id
                    </cfif>



                )
                VALUES (


                    <!--- CREATED_BY --->
                    <cfif len(session.auth.profile.id?:'')>
                        '#session.auth.profile.id?:''#'
                    <cfelse>
                        null
                    </cfif>


                    <cfloop collection="#stDataFields#" item="data_field" index="data_field_name">
                        <cfif structKeyExists(stModel.fields, data_field_name)>

                            <cfset model_field = stModel.fields[data_field_name] />

                            <cfif !(model_field.is_system?:false) AND (model_field.type NEQ "many_to_many") AND (model_field.type NEQ "relation")>

                                ,

                                <cfset stParams = {
                                                    cfsqltype: 'varchar'
                                                    , value=data_field
                                                    , null=false
                                } />

                                <cfif model_field.is_nullable AND !len(stParams.value)>
                                    <cfset stParams.null = true />
                                </cfif>

                                <cfswitch expression="#model_field.type#">
                                    <cfcase value="timestamptz">
                                        <cfset stParams.cfsqltype = 'timestamp' />
                                    </cfcase>
                                    <cfcase value="date">
                                        <cfset stParams.cfsqltype = 'date' />
                                    </cfcase>
                                    <cfcase value="bool">
                                        <cfset stParams.cfsqltype = 'boolean' />
                                    </cfcase>
                                    <cfcase value="jsonb">
                                        <cfset stParams.cfsqltype = 'other' />
                                        <cfif  !IsSimpleValue(stParams.value)>
                                            <cfset stParams.value = serializeJSON(stParams.value) />
                                        </cfif>

                                        <cfif !len(trim(stParams.value))>
                                            <cfset stParams.value = '' />
                                            <cfset stParams.null = true />
                                        </cfif>
                                    </cfcase>
                                    <cfcase value="uuid">
                                        <cfset stParams.cfsqltype = 'other' />
                                        <cfif !len(trim(data_field))>
                                            <cfset stParams.value = '' />
                                            <cfset stParams.null = true />
                                        </cfif>

                                    </cfcase>
                                    <cfcase value="int2,int4,int8,smallserial,serial,bigserial,numeric">
                                        <cfset stParams.cfsqltype = 'numeric' />
                                    </cfcase>

                                    <cfdefaultcase>
                                        <cfset stParams.cfsqltype = model_field.type />
                                    </cfdefaultcase>
                                </cfswitch>


                                <cfif isNull(data_field)>
                                    <cfset stParams.value = '' />
                                    <cfset stParams.null = true />

                                </cfif>
                                <!--- <cfdump var="#stParams#" label="stParams for #data_field_name#" expand="true"> --->
                                <cfqueryparam attributeCollection="#stParams#" />
                            </cfif>
                        </cfif>
                    </cfloop>


                    <cfif len(stDataFields.id?:'')>
                        ,
                        <cfqueryparam cfsqltype="other" value="#stDataFields.id#" />
                    </cfif>


                )
                </cfquery>
            </cfif>
            <!--- Update the currentID with the id of the new record --->
            <cfset result.id = sql.id />

            <cfset arrayAppend(result.sql_statements, sql) />

        </cfif>

        <!--- many_to_many PAYLOADS --->
        <cfloop collection="#arguments.data#" item="data_field" index="data_field_name">
            <cfif structKeyExists(stModel.fields, data_field_name)>

                <cfset model_field = stModel.fields[data_field_name] />
                <cfif (model_field.type?:'') EQ "many_to_many">


                    <cfquery name="q" result="sql">
                        DELETE FROM #model_field.bridgingTableName#
                        WHERE primary_id = <cfqueryparam cfsqltype="other" value="#result.id#" />;

                        <cfloop array="#data_field#" item="item" index="seq">
                            <cfif isStruct(item)>
                                <cfset fk_value = item.id />
                            <cfelse>
                                <cfset fk_value = item />
                            </cfif>
                            INSERT INTO #model_field.bridgingTableName# (primary_id,foreign_id,sequence) VALUES ('#result.id#', '#fk_value#', #seq#);
                        </cfloop>


                    </cfquery>

                    <cfset arrayAppend(result.sql_statements, sql) />

                </cfif>
            </cfif>
        </cfloop>

        <!--- Note: BM25 search indexing is now handled automatically via the search_text generated column --->

        <!--- PURCHASE LOGGING --->
        <cfif arguments.table_name EQ "purchase">
            <cfset application.lib.db.getService("purchase_log").log_now( purchase_id=result.id, reason="save" ) />
        </cfif>

        <cfif arguments.returnAsCFML>
            <cfreturn result />
        <cfelse>
            <cfreturn serializeJSON(result) />
        </cfif>

    </cffunction>




    <!--- HELPER FUNCTIONS --->

    <cffunction name="formatLabelFromFieldName" access="private">
        <cfargument name="field_name" />
        <!---   = "this_is_a_sample_string"> --->

        <cfset stringWithSpaces = reReplace(field_name, "_", " ", "all")>
        <cfset wordsArray = listToArray(stringWithSpaces, " ")>

        <cfset formattedLabel = "">
        <cfloop array="#wordsArray#" index="word">
            <cfif len(word) GT 1>
                <cfset formattedLabel = formattedLabel & ucase(left(word, 1)) & right(word, len(word) - 1) & " ">
            <cfelse>
                <cfset formattedLabel = formattedLabel & ucase(word) & " ">
            </cfif>
        </cfloop>

        <cfreturn trim(formattedLabel) />
    </cffunction>




    <cffunction name="sanitizeCodeSchema" returnType="struct" hint="This will intelligently fill out missing metadata">
        <cfargument name="codeSchemaInput" type="struct" required="true">

        <cfset codeSchemaOutput = {}>

        <cfloop collection="#arguments.codeSchemaInput#" item="table" index="table_key">
            <cfif not structKeyExists(table, "table_name")>
              <cfset table.table_name = table_key>
            </cfif>
            <cfif not structKeyExists(table, "title")>
              <cfset table.title = table.table_name>
            </cfif>
            <cfif not structKeyExists(table, "title_plural")>
              <cfset table.title_plural = "#table.title#s">
            </cfif>

            <cfset table.item_label_template = (table.item_label_template?:'`#table.table_name# ${item.id}`')>
            <cfset table.label_generation_expression = (table.label_generation_expression?:"'#table.table_name#: ' || COALESCE(id::text, '')")>



            <cfif not structKeyExists(table, "searchable_fields")>
                <cfset table.searchable_fields = "">
            </cfif>


          <cfif not structKeyExists(table, "add_system_fields")>
            <cfset table.add_system_fields = true />
          </cfif>


          <cfif !len(table.order_by?:'')>
            <cfif table.add_system_fields>
                <cfset table.order_by = "created_at desc">
            <cfelse>
                <cfset table.order_by = "">
            </cfif>
          </cfif>


          <cfif not structKeyExists(table, "primary_keys")>
            <cfset table.primary_keys = []>
          </cfif>

          <cfif not structKeyExists(table, "indexes")>
            <cfset table.indexes = {}>
          </cfif>

          <cfif not structKeyExists(table, "foreign_keys")>
            <cfset table.foreign_keys = {}>
          </cfif>




          <!--- ADD SYSTEM FIELDS --->

            <cfif !structKeyExists(table.fields,'id')>
                <cfset table.fields['id'] = {
                                                "type": "uuid",
                                                "primary_key": true,
                                                "is_system": true,
                                                "default": 'uuid_generate_v7()'} />
            </cfif>

            <cfif !structKeyExists(table.fields,'label')>
                <cfset table.fields['label'] = {
                                                "type": "varchar",
                                                "is_system": true,
                                                "generation_expression": "#table.label_generation_expression#"} />
            </cfif>


            <cfif !structKeyExists(table.fields,'created_at')>
                <cfset table.fields['created_at'] = {
                                                        "type": "timestamptz",
                                                        "is_system": true,
                                                        "default": 'now()',
                                                        "html": {
                                                            "type": "input_date",
                                                            "display_format": "dd mmm yyyy"
                                                        }
                                                    }  />
            </cfif>


            <cfif !structKeyExists(table.fields,'last_updated_at')>
                <cfset table.fields['last_updated_at'] = {
                                                        "type": "timestamptz",
                                                        "is_system": true,
                                                        "default": 'now()',
                                                        "html": {
                                                            "type": "input_date",
                                                            "display_format": "dd mmm yyyy"
                                                        }
                                                    }  />
            </cfif>


            <cfif !structKeyExists(table.fields,'created_by')>
                <cfset table.fields['created_by'] = {
                                                        "type": "uuid",
                                                        "is_system": true,
                                                        "index": true,
                                                        "foreign_key_table": "moo_profile",
                                                        "foreign_key_field": "id",
                                                        "foreign_key_onDelete": "NO ACTION",
                                                        "foreign_key_onUpdate": "NO ACTION",
                                                        "html": {
                                                            "type": "input_many_to_one"
                                                        }
                                                    }  />
            </cfif>


            <cfif !structKeyExists(table.fields,'last_updated_by')>
                <cfset table.fields['last_updated_by'] = {
                                                        "type": "uuid",
                                                        "is_system": true,
                                                        "index": true,
                                                        "foreign_key_table": "moo_profile",
                                                        "foreign_key_field": "id",
                                                        "foreign_key_onDelete": "NO ACTION",
                                                        "foreign_key_onUpdate": "NO ACTION",
                                                        "html": {
                                                            "type": "input_many_to_one"
                                                        }
                                                    }  />
            </cfif>




            <cfloop collection="#table.fields#" item="field" index="field_name">

                <cfset field.name = field_name />


                <cfif !structKeyExists(field, "label")>
                    <cfset field.label = formatLabelFromFieldName(field_name) />
                </cfif>

                <cfif !structKeyExists(field, "type")>
                    <cfset field.type = "varchar" />
                </cfif>

                <cfif !structKeyExists(field, "cfsqltype")>
                    <cfset field.cfsqltype = "varchar" />
                </cfif>

                <cfif !structKeyExists(field, "searchable")>
                    <cfset field.searchable = false />
                </cfif>


                <cfif not structKeyExists(field, "is_nullable")>
                    <cfif (field.primary_key?:false) OR arrayFind(table.primary_keys,field.name)>
                        <cfset field.is_nullable = false>
                    <cfelse>
                        <cfset field.is_nullable = true>
                    </cfif>

                </cfif>

                <cfif not structKeyExists(field, "default")>
                    <cfset field.default = ""> <!--- Implys no default set --->
                </cfif>

                <cfset field.sql_select_simple = "#table.table_name#.#field_name# AS #field_name#">

                <cfif !structKeyExists(field, "html")>
                    <cfset field.html = { }>
                </cfif>

                <cfswitch expression="#field.type#">
                    <cfcase value="numeric">
                        <cfset field.html.control = (field.html.control?:'control_number') />
                        <cfif not structKeyExists(field, "precision")>
                            <cfset field.precision = 18>
                        </cfif>

                        <cfif not structKeyExists(field, "scale")>
                            <cfset field.scale = 4>
                        </cfif>


                    </cfcase>

                    <cfcase value="varchar">
                        <cfset field.html.control = (field.html.control?:'control_text') />
                        <cfif not structKeyExists(field, "max_length")>
                            <cfset field.max_length = 255>
                        </cfif>
                    </cfcase>
                    <cfcase value="uuid">

                        <cfset field.cfsqltype = "other" />
                        <cfset field.foreign_key_field = (field.foreign_key_field?:'id') />
                        <cfset field.foreign_key_onDelete = (field.foreign_key_onDelete?:'NO ACTION') />
                        <cfset field.foreign_key_onUpdate = (field.foreign_key_onUpdate?:'NO ACTION') />

                        <cfif !(field.primary_key?:false)>
                            <cfset field.index = (field.index?:true) />
                            <cfset field.html.control = (field.html.control?:'control_combobox') />
                        </cfif>

                        <cfset field.sql_select_simple = "#table.table_name#.#field_name#::text as #field_name#">
                    </cfcase>

                    <cfcase value="jsonb">
                        <cfset field.html.control = (field.html.control?:'control_textarea') />
                        <cfset field.sql_select_simple = "#table.table_name#.#field_name#::jsonb as #field_name#">
                    </cfcase>

                    <cfcase value="relation">
                        <cfset field.html.control = (field.html.control?:'') />
                        <!--- not a field that gets deployed --->
                        <cfset field.sql_select_simple = "">
                    </cfcase>

                    <cfcase value="tsvector">
                        <cfset field.html.control = (field.html.control?:'') />
                        <cfset field.sql_select_simple = "">
                    </cfcase>

                    <cfcase value="date">
                        <cfset field.cfsqltype = "date" />
                        <cfset field.html.control = (field.html.control?:'control_date') />
                    </cfcase>

                    <cfcase value="timestamptz">
                        <cfset field.cfsqltype = "timestamp" />
                        <cfset field.html.control = (field.html.control?:'control_datetime_local') />
                    </cfcase>

                    <cfcase value="text">
                        <cfset field.html.control = (field.html.control?:'control_textarea') />
                    </cfcase>


                    <cfcase value="int2,int4,int8,smallserial,serial,bigserial">
                        <cfset field.cfsqltype = "numeric" />
                        <cfset field.html.control = (field.html.control?:'control_number') />
                    </cfcase>

                    <cfcase value="bool,boolean">
                        <cfset field.cfsqltype = "boolean" />
                        <cfset field.html.control = (field.html.control?:'control_text') />
                    </cfcase>

                    <cfcase value="geometry">
                        <cfset field.html.control = (field.html.control?:'control_text') />
                        <cfset field.cfsqltype = "other" />

                        <!--- Set default geometry type if not specified --->
                        <cfif not structKeyExists(field, "geometry_type")>
                            <cfset field.geometry_type = "GEOMETRY">
                        </cfif>

                        <!--- Set default SRID if not specified --->
                        <cfif not structKeyExists(field, "srid")>
                            <cfset field.srid = 4326> <!--- WGS84 default --->
                        </cfif>

                        <!--- Validate geometry type --->
                        <cfset valid_geometry_types = "GEOMETRY,POINT,LINESTRING,POLYGON,MULTIPOINT,MULTILINESTRING,MULTIPOLYGON,GEOMETRYCOLLECTION">
                        <cfif not listFindNoCase(valid_geometry_types, field.geometry_type)>
                            <cfthrow message="Invalid geometry type: #field.geometry_type#. Valid types: #valid_geometry_types#">
                        </cfif>

                        <!--- Generate proper SQL select for geometry fields --->
                        <cfset field.sql_select_simple = "ST_AsText(#table.table_name#.#field_name#) as #field_name#">
                    </cfcase>

                    <!--- Keep backward compatibility for legacy point/polygon definitions --->
                    <cfcase value="point,polygon">
                        <cfset field.html.control = (field.html.control?:'control_text') />
                        <cfset field.cfsqltype = "other" />
                    </cfcase>

                    <cfcase value="many_to_many">
                        <cfset field.html.control = (field.html.control?:'control_combobox') />
                        <cfset field.html.multiple = true />
                        <cfif not structKeyExists(field, "foreign_key_field")>
                            <cfset field.foreign_key_field = "id">
                        </cfif>


                        <!--- We will populate this after all the primary tables are built so that we know all the fields that have been sanitized --->
                        <cfset field.sql_select_simple = "">



                        <cfset field.bridgingTableName = "#table.table_name#_#field.name#">
                        <cfset stBridgingTable = {
                            "table_name": field.bridgingTableName,
                            "fields": {
                                "primary_id": {
                                    "name": "primary_id",
                                    "label": "#formatLabelFromFieldName('primary_id')#",
                                    "type": "uuid",
                                    "foreign_key_table": table.table_name,
                                    "foreign_key_fields": "id",
                                    "is_nullable": false
                                },
                                "foreign_id": {
                                    "name": "foreign_id",
                                    "label": "#formatLabelFromFieldName('foreign_id')#",
                                    "type": "uuid",
                                    "foreign_key_table": field.foreign_key_table,
                                    "foreign_key_field": field.foreign_key_field,
                                    "is_nullable": false
                                },
                                "sequence": {
                                    "name": "sequence",
                                    "label": "Sequence",
                                    "type": "int4",
                                    "is_nullable": false,
                                    "default": 999
                                }
                            },
                            "indexes": {},
                            "primary_keys":["primary_id", "foreign_id"],
                            "foreign_keys": {
                                "fk_#field.bridgingTableName#_primary_id": {
                                    "field_name": "primary_id",
                                    "foreign_key_table": table.table_name,
                                    "foreign_key_field": "id",
                                    "onDelete": 'CASCADE',
                                    "onUpdate": 'NO ACTION'
                                },
                                "fk_#field.bridgingTableName#_foreign_id": {
                                    "field_name": "foreign_id",
                                    "foreign_key_table": field.foreign_key_table,
                                    "foreign_key_field": field.foreign_key_field,
                                    "onDelete": 'NO ACTION',
                                    "onUpdate": 'NO ACTION'
                                }
                            }
                        }>

                        <cfset codeSchemaOutput[field.bridgingTableName] = stBridgingTable>



                    </cfcase>

                    <cfdefaultcase>
                        <cfthrow message="Unsupported data type: #field.type#">
                    </cfdefaultcase>
                </cfswitch>


                <cfset field.sql_select_expanded = field.sql_select_simple>
                <cfset field.sql_select_condensed = field.sql_select_simple>


                <cfif structKeyExists(field, "index")>
                    <cfif isStruct(field.index)>
                        <cfset indexInfo = {
                            "name": "idx_#table.table_name#_#field.name#",
                            "type": field.index.type,
                            "fields": field.name,
                            "unique": field.index.unique?:false
                        } />

                        <cfset table.indexes[indexInfo.name] = indexInfo>
                    <cfelseif isBoolean(field.index) AND field.index>
                        <cfset indexInfo = {
                            "name": "idx_#table.table_name#_#field.name#",
                            "type": "btree",
                            "fields": field.name,
                            "unique": false
                        } />

                        <cfset table.indexes[indexInfo.name] = indexInfo>

                    </cfif>

                    <cfset structDelete(field, "index")>
                </cfif>


                <cfif (field.primary_key?:false)>

                    <cfif !arrayFind(table.primary_keys, field.name)>
                        <cfset arrayAppend(table.primary_keys, field.name)>
                    </cfif>

                    <cfset structDelete(field, "primary_key")>
                </cfif>


                <cfif field.type EQ "uuid" AND len(field.foreign_key_table?:'') AND len(field.foreign_key_field?:'') >
                    <cfset fkeyInfo = {
                        name: "fk_#table.table_name#_#field.name#",
                        field_name: field.name,
                        foreign_key_table: field.foreign_key_table,
                        foreign_key_field: field.foreign_key_field,
                        onDelete: field.foreign_key_onDelete,
                        onUpdate: field.foreign_key_onUpdate
                    }>

                    <cfset table.foreign_keys[fkeyInfo.name] = fkeyInfo>
                </cfif>



            </cfloop>



            <!--- Now lets get the searchable columns with per-field tokenizer config --->
            <!--- searchable can be: true (defaults to ngram), "simple", "ngram", or struct with tokenizer config --->
            <!--- Note: jsonb fields with simple tokenizer must NOT have ::text cast, but ngram requires ::text cast --->
            <!--- Clear any pre-existing searchable_fields to rebuild from field definitions --->
            <cfset table.searchable_fields = "" />
            <cfset searchable_field_configs = {} />
            <cfloop collection="#table.fields#" item="field" index="field_name">
                <cfif structKeyExists(field, "searchable") AND isSimpleValue(field.searchable) AND field.searchable NEQ false AND len(field.searchable)>
                    <cfset table.searchable_fields = listAppend(table.searchable_fields, field_name) />

                    <!--- Parse tokenizer config from searchable property --->
                    <cfif isBoolean(field.searchable) AND field.searchable>
                        <!--- searchable: true defaults to ngram --->
                        <cfset searchable_field_configs[field_name] = { "tokenizer": "ngram", "field_type": field.type } />
                    <cfelse>
                        <!--- searchable: "simple" or "ngram" --->
                        <cfset searchable_field_configs[field_name] = { "tokenizer": field.searchable, "field_type": field.type } />
                    </cfif>
                <cfelseif structKeyExists(field, "searchable") AND isStruct(field.searchable)>
                    <cfset table.searchable_fields = listAppend(table.searchable_fields, field_name) />
                    <!--- searchable: { tokenizer: "ngram", min_gram: 3, max_gram: 3 } --->
                    <cfset searchable_field_configs[field_name] = field.searchable />
                    <cfset searchable_field_configs[field_name].field_type = field.type />
                    <cfif !structKeyExists(searchable_field_configs[field_name], "tokenizer")>
                        <cfset searchable_field_configs[field_name].tokenizer = "ngram" />
                    </cfif>
                </cfif>
            </cfloop>

            <cfif len(table.searchable_fields)>

                <cfset this.searchable_tables[table.table_name] = {
                    'table_name': table.table_name,
                    'searchable_fields': table.searchable_fields,
                    'field_configs': searchable_field_configs
                } />

                <!--- Build BM25 index fields using ParadeDB legacy API --->
                <!--- Legacy API uses plain field names in index, tokenizer config goes in WITH clause --->
                <!--- See: https://docs.paradedb.com/legacy/indexing/field-options --->
                <!--- NOTE: JSONB fields are skipped - use generated columns to extract text for searching --->
                <cfset bm25_field_parts = ["id"] />
                <cfset text_fields_config = {} />
                <cfset text_field_types = "varchar,text,char,nvarchar,nchar" />
                <cfloop list="#table.searchable_fields#" item="searchable_field_name">
                    <cfset field_config = searchable_field_configs[searchable_field_name] />
                    <cfset field_tokenizer = field_config.tokenizer ?: "ngram" />
                    <cfset field_type = field_config.field_type ?: "varchar" />

                    <!--- Skip JSONB fields - legacy ParadeDB on Neon doesn't support json_fields properly --->
                    <!--- For JSONB fields, create a generated column to extract the text value instead --->
                    <cfif field_type EQ "jsonb">
                        <cfcontinue />
                    </cfif>

                    <!--- Add field name to index (plain, no type casting) --->
                    <cfset arrayAppend(bm25_field_parts, searchable_field_name) />

                    <cfif field_tokenizer EQ "simple">
                        <!--- simple tokenizer for text fields --->
                        <cfset text_fields_config[searchable_field_name] = {
                            "tokenizer": {"type": "default"}
                        } />
                    <cfelseif listFindNoCase(text_field_types, field_type)>
                        <!--- text-type fields with ngram tokenizer (default) --->
                        <cfset min_gram = field_config.min_gram ?: 3 />
                        <cfset max_gram = field_config.max_gram ?: 3 />
                        <cfset text_fields_config[searchable_field_name] = {
                            "tokenizer": {"type": "ngram", "min_gram": min_gram, "max_gram": max_gram, "prefix_only": false}
                        } />
                    <cfelse>
                        <!--- other non-text fields (date, timestamp, uuid, etc.): no tokenizer config needed --->
                    </cfif>
                </cfloop>

                <!--- Build WITH options with text_fields config (no json_fields for legacy API) --->
                <cfset with_options_parts = ["key_field='id'"] />
                <cfif !structIsEmpty(text_fields_config)>
                    <cfset arrayAppend(with_options_parts, "text_fields='" & serializeJSON(text_fields_config) & "'") />
                </cfif>

                <!--- Add the BM25 index for full-text search with legacy API syntax --->
                <cfset table.indexes['#table.table_name#_search_idx'] = {
                    "name": "#table.table_name#_search_idx",
                    "type": "bm25",
                    "fields": arrayToList(bm25_field_parts, ", "),
                    "unique": false,
                    "with_options": arrayToList(with_options_parts, ", "),
                    "searchable_fields": "#table.searchable_fields#",
                    "field_configs": searchable_field_configs,
                    "text_fields_config": text_fields_config
                } />

            </cfif>



            <cfloop collection="#table.indexes#" item="index" index="index_name">
                <cfif !len(index.name?:'')>
                    <cfset index.name = index_name />
                </cfif>
                <cfif !len(index.type?:'')>
                    <cfset index.type = "btree" />
                </cfif>
                <cfif !len(index.unique?:'')>
                    <cfset index.unique = false />
                </cfif>

            </cfloop>



            <cfset codeSchemaOutput[table_key] = table />

        </cfloop>

        <!--- We need to populate all the many_to_many fields with their sql_select_simple not that all the primary tables are built so that we know all the fields that have been sanitized --->
        <cfloop collection="#arguments.codeSchemaInput#" item="table" index="table_key">
            <cfloop collection="#table.fields#" item="field" index="field_name">



                <cfif field.type EQ "many_to_many">

                    <!--- This helps us to convert the sql_select_simple values to be used in the json_agg function like:
                    SELECT json_agg(
                            json_build_object('id', #field.foreign_key_table#.id)
                        )
                     --->
                    <cfset json_build_object_field_list = "" />
                    <cfloop collection="#arguments.codeSchemaInput[field.foreign_key_table].fields#" item="foreign_table_field" index="foreign_table_field_name">
                        <cfif len(foreign_table_field['sql_select_simple'])>
                            <cfset json_build_object_field_sql_select_simple = rereplace(foreign_table_field['sql_select_simple'], "(?i)\bas\b.*", "", "ALL") /> <!--- Strip the "as fieldname" from the end of the sql_select_simple --->
                            <cfset json_build_object_field_list = listAppend(json_build_object_field_list, "'#foreign_table_field_name#', #json_build_object_field_sql_select_simple#") />
                        </cfif>
                    </cfloop>
                    <cfsavecontent variable="field.sql_select_expanded">
                    <cfoutput>
                        coalesce((
                            SELECT jsonb_agg(
                                jsonb_build_object(#json_build_object_field_list#)
                                ORDER BY #field.bridgingTableName#.sequence
                            )
                            FROM #field.bridgingTableName#
                            LEFT JOIN #field.foreign_key_table# ON #field.foreign_key_table#.id = #field.bridgingTableName#.foreign_id
                            WHERE #field.bridgingTableName#.primary_id = #table.table_name#.id

                        ),'[]')::jsonb AS #field_name#
                    </cfoutput>
                    </cfsavecontent>
                    <cfsavecontent variable="field.sql_select_condensed">
                    <cfoutput>
                        coalesce((
                            SELECT jsonb_agg(
                                jsonb_build_object('id',id,'label',label)
                                ORDER BY #field.bridgingTableName#.sequence
                            )
                            FROM #field.bridgingTableName#
                            LEFT JOIN #field.foreign_key_table# ON #field.foreign_key_table#.id = #field.bridgingTableName#.foreign_id
                            WHERE #field.bridgingTableName#.primary_id = #table.table_name#.id

                        ),'[]')::jsonb AS #field_name#
                    </cfoutput>
                    </cfsavecontent>

                </cfif>

                <!---  --->
                <cfif field.type EQ "uuid">


                     <cfif len(field.foreign_key_table?:'')>
                        <cftry>
                        <cfset json_build_object_field_list = "" />
                        <cfloop collection="#arguments.codeSchemaInput[field.foreign_key_table].fields#" item="foreign_table_field" index="foreign_table_field_name">

                            <cfif len(foreign_table_field['sql_select_simple'])>
                                <!--- when building a query for a uuid field, any many_to_many properties should be ignored and any uuid properties should just be the id and not the expanded.  --->

                                <cfif foreign_table_field.type EQ "many_to_many">
                                    <cfcontinue />
                                </cfif>

                                <!--- <cfif foreign_table_field.type EQ "uuid">
                                    <cfset json_build_object_field_list = listAppend(json_build_object_field_list, "'#foreign_table_field_name#', #foreign_table_field_name#::text") />
                                    <cfcontinue />
                                </cfif> --->
                                <cfset json_build_object_field_sql_select_simple = foreign_table_field['sql_select_simple'] />
                                <cfset json_build_object_field_sql_select_simple = rereplace(json_build_object_field_sql_select_simple, "(?i)\bas\b.*", "", "ALL") /> <!--- Strip the "as fieldname" from the end of the sql_select_simple --->
                                <cfset json_build_object_field_sql_select_simple = replaceNoCase(json_build_object_field_sql_select_simple, "#field.foreign_key_table#.", "", "ALL") /> <!--- Strip the "[table_name]." from the beginning of the sql_select_simple. We need to do this in case we are related to iteslf --->
                                <cfset json_build_object_field_list = listAppend(json_build_object_field_list, "'#foreign_table_field_name#', #json_build_object_field_sql_select_simple#") />

                            </cfif>
                        </cfloop>
                        <cfsavecontent variable="field.sql_select_expanded">
                        <cfoutput>
                            coalesce((
                                SELECT json_build_object(#json_build_object_field_list#)
                                FROM #field.foreign_key_table# as sub
                                WHERE sub.id = #table.table_name#.#field.name#
                            ),'{}')::jsonb AS #field.name#
                        </cfoutput>
                        </cfsavecontent>
                        <cfsavecontent variable="field.sql_select_condensed">
                        <cfoutput>
                            coalesce((
                                SELECT json_build_object('id',id,'label',label)
                                FROM #field.foreign_key_table# as sub
                                WHERE sub.id = #table.table_name#.#field.name#
                            ),'{}')::jsonb AS #field.name#
                        </cfoutput>
                        </cfsavecontent>
                        <cfcatch>
                            <!--- May not exist yet. This often happens when deploying multiple tables at the same time --->
                            <!--- <cfdump var="#table#" label="#field_name#" expand="true">
                            <cfdump var="#cfcatch#" label="cfcatch" expand="true"><cfabort> --->
                        </cfcatch>
                        </cftry>


                    </cfif>
                </cfif>

                <cfif field.type EQ "relation">

                    <!--- This helps us to convert the sql_select_simple values to be used in the json_agg function like:
                    SELECT json_agg(
                            json_build_object('id', #field.foreign_key_table#.id)
                        )
                     --->

                     <cfif len(field.foreign_key_table?:'') AND  len(field.foreign_key_field?:'')>
                        <cftry>


                        <cfset json_build_object_field_list = "" />
                        <cfloop collection="#arguments.codeSchemaInput[field.foreign_key_table].fields#" item="foreign_table_field" index="foreign_table_field_name">

                            <cfif len(foreign_table_field['sql_select_simple'])>
                                <cfset json_build_object_field_list = listAppend(json_build_object_field_list, foreign_table_field['sql_select_simple']) />
                            </cfif>

                        </cfloop>


                        <cfsavecontent variable="field.sql_select_expanded">
                            <cfoutput>
                            coalesce((
                                SELECT jsonb_agg(to_jsonb(sq.*))
                                FROM (
                                    SELECT #json_build_object_field_list#
                                    FROM #field.foreign_key_table#
                                    WHERE #field.foreign_key_table#.#field.foreign_key_field# = #table.table_name#.id
                                    ORDER BY #arguments.codeSchemaInput[field.foreign_key_table].order_by#
                                ) AS sq
                            ),'[]')::jsonb AS #field_name#
                        </cfoutput>
                        </cfsavecontent>
                        <cfsavecontent variable="field.sql_select_condensed">
                            <cfoutput>
                            coalesce((
                                SELECT jsonb_agg(to_jsonb(sq.*))
                                FROM (
                                    SELECT id,label
                                    FROM #field.foreign_key_table#
                                    WHERE #field.foreign_key_table#.#field.foreign_key_field# = #table.table_name#.id
                                    ORDER BY #arguments.codeSchemaInput[field.foreign_key_table].order_by#
                                ) AS sq
                            ),'[]')::jsonb AS #field_name#
                        </cfoutput>
                        </cfsavecontent>
                        <!--- <cfdump var="#json_build_object_field_list#" label="" expand="true">
                        <cfdump var="#field.sql_select_expanded#" label="" expand="true">

                        <cfdump var="#field.sql_select_expanded_v2#" label="" expand="true">

                        <cfabort> --->
                        <cfcatch>
                            <cfdump var="#table#" label="#field_name#" expand="true">
                            <cfdump var="#cfcatch#" label="cfcatch" expand="true"><cfabort>
                        </cfcatch>
                        </cftry>

                    </cfif>
                </cfif>

            </cfloop>
        </cfloop>


        <cfreturn codeSchemaOutput>
    </cffunction>



    <cffunction name="getTableColumns" returntype="array" hint="Gets the postgresql column metadata from existing database table">
        <cfargument name="tablename" type="string" required="true">
        <cfquery name="qColumns" returntype="array">
          SELECT
            column_name,
            udt_name as data_type,
            character_maximum_length,
            numeric_precision,
            numeric_scale,
            CASE
                WHEN is_nullable = 'YES' THEN true
                ELSE false
            END AS is_nullable,
            regexp_replace(
                    column_default,
                    '#this.normalizeFieldPattern#',
                    '',
                    'g'
            ) as column_default,
            is_generated,
            regexp_replace(
                    generation_expression,
                    '#this.normalizeFieldPattern#',
                    '',
                    'g'
                ) AS generation_expression
          FROM information_schema.columns
          WHERE table_name = <cfqueryparam value="#arguments.tablename#" cfsqltype="varchar">
          ORDER BY ordinal_position;
        </cfquery>
        <cfreturn qColumns>
      </cffunction>

      <cffunction name="getTableIndexes" returntype="struct" hint="Gets the postgresql index metadata from existing database table">
        <cfargument name="tablename" type="string" required="true">
        <cfquery name="stIndexes" returntype="struct" columnkey="name">
          SELECT
              i.relname AS name,
              string_agg(
                  a.attname || CASE WHEN (ix.indoption[array_position(ix.indkey, a.attnum)] & 1) = 1 THEN ' desc' ELSE '' END,
                  ', ' ORDER BY array_position(ix.indkey, a.attnum)
              ) AS fields,
              ix.indisunique AS unique,
              am.amname AS type,
              pg_get_indexdef(i.oid) AS indexdef
          FROM
              pg_class t
          JOIN
              pg_index ix ON t.oid = ix.indrelid
          JOIN
              pg_class i ON ix.indexrelid = i.oid
          JOIN
              pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
          LEFT JOIN
              pg_constraint c ON c.conrelid = ix.indrelid AND c.conname = i.relname AND c.contype = 'p'
          JOIN
              pg_am am ON i.relam = am.oid
          WHERE
              t.relkind = 'r'
              AND t.relname = <cfqueryparam value="#arguments.tablename#" cfsqltype="varchar">
              AND c.conname IS NULL
            GROUP BY
                t.relname, i.relname, ix.indisunique, am.amname, i.oid
        </cfquery>
        <cfreturn stIndexes>
      </cffunction>


      <cffunction name="getTableForeignKeys" returntype="struct" hint="Gets the postgresql foreignKey metadata from existing database table">
        <cfargument name="tablename" type="string" required="true">

        <cfquery name="stForeignKeys" returntype="struct" columnkey="name">
          SELECT
              tc.constraint_name as name,
              tc.table_name,
              kcu.column_name as field_name,
              ccu.table_name AS foreign_key_table,
              ccu.column_name AS foreign_key_field,
                rc.update_rule AS onUpdate,
                rc.delete_rule AS onDelete
            FROM
                information_schema.table_constraints AS tc
                JOIN information_schema.key_column_usage AS kcu
                ON tc.constraint_name = kcu.constraint_name
                JOIN information_schema.constraint_column_usage AS ccu
                ON ccu.constraint_name = tc.constraint_name
                JOIN information_schema.referential_constraints AS rc
                ON rc.constraint_name = tc.constraint_name
          WHERE
              tc.constraint_type = 'FOREIGN KEY' AND
              tc.table_name = <cfqueryparam value="#arguments.tablename#" cfsqltype="cf_sql_varchar">
        </cfquery>

        <cfreturn stForeignKeys>
      </cffunction>



      <cffunction name="getTablePrimaryKey" returntype="struct" hint="Gets the postgresql PrimaryKey metadata from existing database table">
        <cfargument name="tablename" type="string" required="true">

        <cfset stPrimaryKey = {} />

        <cfquery name="aPrimaryKey" returntype="array">
        SELECT
            tc.table_schema,
            tc.table_name,
            tc.constraint_name as primary_key_name,
            string_agg(kcu.column_name, ',') as primary_key_columns
        FROM
            information_schema.table_constraints AS tc
        JOIN
            information_schema.key_column_usage AS kcu
        ON
            tc.constraint_name = kcu.constraint_name
        WHERE
            tc.constraint_type = 'PRIMARY KEY'
            AND tc.table_name = <cfqueryparam value="#arguments.tablename#" cfsqltype="cf_sql_varchar">
        GROUP BY
            tc.table_schema,
            tc.table_name,
            tc.constraint_name;
        </cfquery>

        <cfif arrayLen(aPrimaryKey)>
            <cfset stPrimaryKey = aPrimaryKey[1] />
        </cfif>

        <cfreturn stPrimaryKey>
      </cffunction>






  <cffunction name="compareDatabaseSchema" returntype="array">
    <cfargument name="codeSchema" type="struct" required="true">

    <cfset var result = []>

    <cfloop collection="#arguments.codeSchema#" item="code_table_schema" index="table_name">

      <!--- Check if table exists --->
      <cfset db_table_columns = getTableColumns(table_name)>

      <cfif !arrayLen(db_table_columns)>

        <cfset sql = createTableFromCodeSchema(code_table_schema) />
        <cfset result = result.merge(sql) />

      <cfelse>
        <!--- Check columns, constraints, and indexes --->



        <!--- Check columns --->
        <cfloop collection="#code_table_schema.fields#" item="code_field_schema" index="field_name">

          <cfset found_column_in_db = ArrayFilter(db_table_columns, function(column) { return column.column_name == field_name; })>

          <cfif !arrayLen(found_column_in_db)>
            <cfif !listFindNoCase("many_to_many,relation",code_field_schema.type)>
                <cfset columnDef = getColumnDef(code_field_schema) />
                <cfset ArrayAppend(result, {
                "table_name": table_name,
                "priority": 10,
                "type": "ADD COLUMN",
                "title": "ADD COLUMN: #table_name#.#field_name#",
                "statement": "ALTER TABLE " & table_name & " ADD COLUMN " & columnDef
                })>
            </cfif>
          <cfelse>
            <cfset column_in_db = found_column_in_db[1] />
            <!--- Check for altered columns --->
            <cfset altered = false>

            <cfif findNoCase('serial', code_field_schema.type)>
                <!---
                Once deployed we assume serials have been setup correctly. If not, you will need to drop the column and add again or convince me to write the sql to handle
                This is becuase you really need to know what your doing with existing values in the column and needs more thought than just "change to serial"
                --->

                <cfcontinue>
            </cfif>

            <!--- Check for altered data type --->
            <cfif code_field_schema.type neq column_in_db.data_type>
              <cfset ArrayAppend(result, {
                "table_name": table_name,
                "priority": 11,
                "type": "ALTER COLUMN",
                "title": "ALTER COLUMN: #table_name#.#field_name#",
                "statement": "ALTER TABLE #table_name# ALTER COLUMN #field_name# TYPE #code_field_schema.type#;"
              })>
            </cfif>




            <!--- Check for altered default value --->

            <cfset simplifyExpression = reReplace((code_field_schema.default?:''), "#this.normalizeFieldPattern#", "", "ALL") />

            <!--- Need to remove newlines in case the default has a newline character /n --->
            <cfset simplifyExpression = replace(simplifyExpression, chr(10), "", "all")>
            <cfset simplifyExpression = replace(simplifyExpression, chr(13), "", "all")>

            <cfset simplifyDBExpression = replace(column_in_db.column_default, chr(10), "", "all")>
            <cfset simplifyDBExpression = replace(simplifyDBExpression, chr(13), "", "all")>


            <cfif trim(simplifyExpression) neq trim(simplifyDBExpression)>

                <!--- <cfoutput>
                    <pre>#code_field_schema.default#</pre>
                    into
                    <div id="left">#simplifyExpression# (#len(simplifyExpression)#</div>
                    neq
                    <div id="right">#simplifyDBExpression#  (#len(simplifyDBExpression)#</div>

                    <div>
                        <cfloop from="1" to="#len(simplifyExpression)#" index="i">
                            <cfif asc(mid(simplifyExpression, i, 1)) NEQ asc(mid(simplifyDBExpression, i, 1))>
                                <div>#i#: #asc(mid(simplifyExpression, i, 1))# vs #asc(mid(simplifyDBExpression, i, 1))#</div>
                            </cfif>
                        </cfloop>
                    </div>



                    </cfoutput>
                <cfabort> --->
                <cfset ArrayAppend(result, {
                  "table_name": table_name,
                  "priority": 1,
                  "type": "ALTER COLUMN",
                  "title": "ALTER COLUMN: #table_name#.#field_name#",
                  "statement": "ALTER TABLE #table_name# ALTER COLUMN #field_name# SET DEFAULT #code_field_schema.default#;",
                  "hint": "default: #code_field_schema.default# simplified into: #simplifyExpression# NEQ #column_in_db.column_default#"
                })>
            </cfif>

            <!--- Check for altered nullable property --->

            <cfif code_field_schema.is_nullable neq column_in_db.is_nullable>

                <!--- <cfoutput>#table_name#.#field_name#: #code_field_schema.is_nullable# neq #column_in_db.is_nullable#</cfoutput><cfabort> --->

                <cfif code_field_schema.is_nullable>

                    <cfset ArrayAppend(result, {
                        "table_name": table_name,
                        "priority": 1,
                        "type": "ALTER COLUMN",
                        "title": "ALTER COLUMN: #table_name#.#field_name#",
                        "statement": "ALTER TABLE #table_name# ALTER COLUMN #field_name# SET NOT NULL;"
                    })>
                <cfelse>

                    <cfset ArrayAppend(result, {
                        "table_name": table_name,
                        "priority": 1,
                        "type": "ALTER COLUMN",
                        "title": "ALTER COLUMN: #table_name#.#field_name#",
                        "statement": "ALTER TABLE #table_name# ALTER COLUMN #field_name# DROP NOT NULL;"
                      })>
                </cfif>
            </cfif>



            <!--- Now Check for length --->
            <cfif code_field_schema.type EQ "numeric">
                <cfif code_field_schema.precision NEQ column_in_db.numeric_precision OR code_field_schema.scale NEQ column_in_db.numeric_scale>
                    <cfset ArrayAppend(result, {
                        "table_name": table_name,
                        "priority": 1,
                        "type": "ALTER COLUMN",
                        "title": "ALTER COLUMN: #table_name#.#field_name#",
                        "statement": "ALTER TABLE #table_name# ALTER COLUMN #field_name# TYPE numeric(#code_field_schema.precision#, #code_field_schema.scale#);"
                      })>
                </cfif>
            </cfif>

            <cfif code_field_schema.type EQ "varchar">
                <cfif code_field_schema.max_length NEQ column_in_db.character_maximum_length>
                    <cfset ArrayAppend(result, {
                        "table_name": table_name,
                        "priority": 1,
                        "type": "ALTER COLUMN",
                        "title": "ALTER COLUMN: #table_name#.#field_name#",
                        "statement": "ALTER TABLE #table_name# ALTER COLUMN #field_name# TYPE varchar(#code_field_schema.max_length#);"
                      })>
                </cfif>
            </cfif>




            <!--- GENERATED COLUMNS CAN NOT BE ALTERED. WE NEED TO DROP AND ADD A GENERATED COLUMN IN THE NEXT REFRESH. --->
            <cfset simplifyExpression = reReplace((code_field_schema.generation_expression?:''), "#this.normalizeFieldPattern#", "", "ALL") />

            <cfif simplifyExpression neq column_in_db.generation_expression>
                <!--- DEBUG --->
                <!--- SELECT column_name, generation_expression FROM information_schema.columns WHERE table_name = 'your_table_name' --->

                <!--- If this is the search_text column, we need to drop and recreate the BM25 index --->
                <cfif field_name EQ "search_text" AND structKeyExists(code_table_schema.indexes, "#table_name#_search_idx")>
                    <cfset bm25_index = code_table_schema.indexes["#table_name#_search_idx"] />

                    <!--- Drop the BM25 index first (before dropping column) --->
                    <cfset ArrayAppend(result, {
                        "table_name": table_name,
                        "priority": 4,
                        "type": "DROP INDEX",
                        "title": "DROP INDEX: #table_name#_search_idx (required before dropping search_text column)",
                        "statement": "DROP INDEX IF EXISTS #table_name#_search_idx;"
                    })>
                </cfif>

                <cfset ArrayAppend(result, {
                    "table_name": table_name,
                    "priority": 6,
                    "type": "DROP COLUMN",
                    "title": "DROP COLUMN: #table_name#.#field_name#",
                    "statement": "ALTER TABLE " & table_name & " DROP COLUMN " & field_name & ";",
                    "hint": "generation_expression: #code_field_schema.generation_expression# simplified into: #simplifyExpression# NEQ #column_in_db.generation_expression#"
                  })>

                <cfset columnDef = getColumnDef(code_field_schema) />
                <cfset ArrayAppend(result, {
                    "table_name": table_name,
                    "priority": 10,
                    "type": "ADD COLUMN",
                    "title": "ADD COLUMN: #table_name#.#field_name#",
                    "statement": "ALTER TABLE " & table_name & " ADD COLUMN " & columnDef
                })>

                <!--- Recreate the BM25 index after adding the column back --->
                <cfif field_name EQ "search_text" AND structKeyExists(code_table_schema.indexes, "#table_name#_search_idx")>
                    <cfset with_clause = "" />
                    <cfif len(bm25_index.with_options?:'')>
                        <cfset with_clause = " WITH (#bm25_index.with_options#)" />
                    </cfif>
                    <cfset ArrayAppend(result, {
                        "table_name": table_name,
                        "priority": 14,
                        "type": "CREATE INDEX",
                        "title": "CREATE INDEX: #table_name#_search_idx (after recreating search_text column)",
                        "statement": "CREATE INDEX #table_name#_search_idx ON #table_name# USING bm25 (#bm25_index.fields#)#with_clause#"
                    })>
                </cfif>


            </cfif>


          </cfif>


        </cfloop>

        <!--- Check for additional columns --->
        <cfloop array="#db_table_columns#" item="column_in_db" index="i">
          <cfif NOT structKeyExists(code_table_schema.fields, column_in_db.column_name)>
            <cfset ArrayAppend(result, {
              "table_name": table_name,
              "priority": 6,
              "type": "DROP COLUMN",
              "title": "DROP COLUMN: #table_name#.#column_in_db.column_name#",
              "statement": "ALTER TABLE " & table_name & " DROP COLUMN " & column_in_db.column_name & ";"
            })>
          </cfif>
        </cfloop>




        <!--- Now check for keys, indexes and foreign keys --->
        <!--- <cfset db_primary_keys = getTablePrimaryKeys(table_name)> --->
        <cfset db_indexes = getTableIndexes(table_name)>
        <cfset db_foreign_keys = getTableForeignKeys(table_name)>
        <cfset db_primary_key = getTablePrimaryKey(table_name)>


        <!--- Now check for Foreign Keys --->

        <cfloop collection="#code_table_schema.indexes#" item="code_index" index="code_index_name">
            <cfset drop_index = false>
            <cfset create_index = false>
            <cfset index_mismatches = [] />
            <cftry>
            <cfset found_index_in_db = structKeyExists(db_indexes,code_index_name)>


            <cfif !(found_index_in_db)>
                <!--- We need to create the index --->
                <cfset create_index = true>
            <cfelse>
                <!--- We need to check to make sure everything matches. If it doesnt match, lets drop it and mark to create --->
                <!--- Only compare keys that exist in DB: fields, type, unique (not name, comment) --->
                <cfset params_to_compare = "fields,type,unique" />
                <cfif code_index.type EQ "bm25">
                    <!--- For BM25 indexes with legacy API, compare field names and WITH clause --->
                    <!--- Legacy format: CREATE INDEX name ON table USING bm25 (id, field1, field2) WITH (key_field='id', text_fields='...') --->
                    <cfset db_indexdef = lcase(db_indexes[code_index_name].indexdef?:'') />

                    <!--- Extract the fields portion from DB index definition --->
                    <cfset bm25_start = findNoCase("using bm25 (", db_indexdef) />
                    <cfset with_pos = findNoCase(") with", db_indexdef) />
                    <cfif bm25_start GT 0 AND with_pos GT bm25_start>
                        <cfset db_bm25_fields = trim(mid(db_indexdef, bm25_start + 12, with_pos - bm25_start - 12)) />
                        <!--- Remove spaces for consistent comparison --->
                        <cfset db_bm25_fields = reReplace(db_bm25_fields, "\s+", "", "ALL") />
                    <cfelse>
                        <cfset db_bm25_fields = "" />
                    </cfif>

                    <!--- Normalize code fields for comparison (lowercase, no spaces) --->
                    <cfset code_bm25_fields = lcase(reReplace(code_index.fields, "\s+", "", "ALL")) />

                    <!--- Compare the plain field lists --->
                    <cfif code_bm25_fields NEQ db_bm25_fields>
                        <cfset arrayAppend(index_mismatches, {
                            "param": "bm25_fields",
                            "code": code_bm25_fields,
                            "db": db_bm25_fields
                        }) />
                        <cfset drop_index = true>
                        <cfset create_index = true>
                    </cfif>

                    <!--- Also compare the WITH clause options (contains tokenizer config) --->
                    <!--- Need to normalize: DB may omit quotes on key_field, JSON key order may differ --->
                    <cfset with_start = findNoCase("with (", db_indexdef) />
                    <cfif with_start GT 0>
                        <cfset db_with_options = trim(mid(db_indexdef, with_start + 6, len(db_indexdef) - with_start - 6)) />
                        <cfset code_with_options = code_index.with_options />

                        <!--- Normalize both for comparison --->
                        <!--- 1. Lowercase and remove spaces --->
                        <cfset db_with_normalized = lcase(reReplace(db_with_options, "\s+", "", "ALL")) />
                        <cfset code_with_normalized = lcase(reReplace(code_with_options, "\s+", "", "ALL")) />

                        <!--- 2. Normalize key_field quotes: key_field=id -> key_field='id' --->
                        <cfset db_with_normalized = reReplace(db_with_normalized, "key_field=([^',]+)", "key_field='\1'", "ALL") />
                        <!--- Fix double quotes if already had them: key_field=''id'' -> key_field='id' --->
                        <cfset db_with_normalized = replace(db_with_normalized, "key_field=''", "key_field='", "ALL") />
                        <cfset db_with_normalized = reReplace(db_with_normalized, "''(,|$)", "'\1", "ALL") />

                        <!--- 3. Parse and re-serialize JSON portions to normalize key order --->
                        <!--- Extract text_fields JSON from both --->
                        <cfset db_text_fields_match = reFind("text_fields='(\{[^']+\})'", db_with_normalized, 1, true) />
                        <cfset code_text_fields_match = reFind("text_fields='(\{[^']+\})'", code_with_normalized, 1, true) />

                        <cfset with_options_match = true />

                        <!--- Compare text_fields JSON if present in both --->
                        <cfif arrayLen(db_text_fields_match.pos) GTE 2 AND db_text_fields_match.pos[2] GT 0
                              AND arrayLen(code_text_fields_match.pos) GTE 2 AND code_text_fields_match.pos[2] GT 0>
                            <cfset db_text_json = mid(db_with_normalized, db_text_fields_match.pos[2], db_text_fields_match.len[2]) />
                            <cfset code_text_json = mid(code_with_normalized, code_text_fields_match.pos[2], code_text_fields_match.len[2]) />
                            <cftry>
                                <cfset db_text_struct = deserializeJSON(db_text_json) />
                                <cfset code_text_struct = deserializeJSON(code_text_json) />
                                <!--- Re-serialize both to canonical form for comparison --->
                                <cfset db_text_canonical = serializeJSON(db_text_struct) />
                                <cfset code_text_canonical = serializeJSON(code_text_struct) />
                                <cfif lcase(db_text_canonical) NEQ lcase(code_text_canonical)>
                                    <cfset with_options_match = false />
                                </cfif>
                                <cfcatch>
                                    <!--- JSON parse failed, fall back to string comparison --->
                                    <cfif db_text_json NEQ code_text_json>
                                        <cfset with_options_match = false />
                                    </cfif>
                                </cfcatch>
                            </cftry>
                        <cfelseif (arrayLen(db_text_fields_match.pos) GTE 2 AND db_text_fields_match.pos[2] GT 0)
                                  NEQ (arrayLen(code_text_fields_match.pos) GTE 2 AND code_text_fields_match.pos[2] GT 0)>
                            <!--- One has text_fields, the other doesn't --->
                            <cfset with_options_match = false />
                        </cfif>

                        <!--- Compare json_fields JSON if present in both --->
                        <cfset db_json_fields_match = reFind("json_fields='(\{[^']+\})'", db_with_normalized, 1, true) />
                        <cfset code_json_fields_match = reFind("json_fields='(\{[^']+\})'", code_with_normalized, 1, true) />

                        <cfif arrayLen(db_json_fields_match.pos) GTE 2 AND db_json_fields_match.pos[2] GT 0
                              AND arrayLen(code_json_fields_match.pos) GTE 2 AND code_json_fields_match.pos[2] GT 0>
                            <cfset db_json_json = mid(db_with_normalized, db_json_fields_match.pos[2], db_json_fields_match.len[2]) />
                            <cfset code_json_json = mid(code_with_normalized, code_json_fields_match.pos[2], code_json_fields_match.len[2]) />
                            <cftry>
                                <cfset db_json_struct = deserializeJSON(db_json_json) />
                                <cfset code_json_struct = deserializeJSON(code_json_json) />
                                <cfset db_json_canonical = serializeJSON(db_json_struct) />
                                <cfset code_json_canonical = serializeJSON(code_json_struct) />
                                <cfif lcase(db_json_canonical) NEQ lcase(code_json_canonical)>
                                    <cfset with_options_match = false />
                                </cfif>
                                <cfcatch>
                                    <cfif db_json_json NEQ code_json_json>
                                        <cfset with_options_match = false />
                                    </cfif>
                                </cfcatch>
                            </cftry>
                        <cfelseif (arrayLen(db_json_fields_match.pos) GTE 2 AND db_json_fields_match.pos[2] GT 0)
                                  NEQ (arrayLen(code_json_fields_match.pos) GTE 2 AND code_json_fields_match.pos[2] GT 0)>
                            <cfset with_options_match = false />
                        </cfif>

                        <!--- If mismatch detected, flag for recreation --->
                        <cfif NOT with_options_match>
                            <cfset arrayAppend(index_mismatches, {
                                "param": "with_options",
                                "code": code_index.with_options,
                                "db": db_with_options
                            }) />
                            <cfset drop_index = true>
                            <cfset create_index = true>
                        </cfif>
                    </cfif>

                    <!--- Skip regular fields comparison for BM25 --->
                    <cfset params_to_compare = "type,unique" />
                </cfif>

                <cfloop list="#params_to_compare#" item="code_index_param" index="i">



                    <cfset codeIndexFieldList = listSort(lcase(reReplace(code_index[code_index_param], "\s+", "", "ALL")),"textnocase") />
                    <cfset dbIndexFieldList = listSort(lcase(reReplace((db_indexes[code_index_name][code_index_param]?:''), "\s+", "", "ALL")),"textnocase") />

                    <cfif codeIndexFieldList NEQ dbIndexFieldList>
                        <cfset arrayAppend(index_mismatches, {
                            "param": code_index_param,
                            "code": codeIndexFieldList,
                            "db": dbIndexFieldList
                        }) />
                        <cfset drop_index = true>
                        <cfset create_index = true>
                    </cfif>
                </cfloop>


            </cfif>

                <cfcatch>
                    <cfdump var="#cfcatch#" label="cfcatch" expand="true">
                    <cfdump var="#code_index#" label="code_index" expand="true">
                    <cfdump var="#db_indexes#" label="db_indexes,#code_index_name#" expand="true"><cfabort>
                </cfcatch>
            </cftry>

            <cfif create_index>

                <cfset index_field_list = code_index.fields />
                <cfif code_index.type EQ "gin">
                    <cfset index_field_list = ListMap(index_field_list, function(term) { return term & " gin_trgm_ops"; })>
                </cfif>

                <!--- Build the WITH clause for BM25 indexes --->
                <cfset with_clause = "" />
                <cfif len(code_index.with_options?:'')>
                    <cfset with_clause = " WITH (#code_index.with_options#)" />
                </cfif>

                <cfif drop_index>
                    <cfset sqlStatement = {
                        "table_name": "#table_name#",
                        "priority": 5,
                        "type": "DROP/CREATE INDEX",
                        "title": "DROP/CREATE INDEX #code_index.name#",
                        "statement": 'DROP INDEX #code_index.name#;CREATE #code_index.unique ? "UNIQUE" : ""# INDEX #code_index.name# ON #table_name# USING #code_index.type# (#index_field_list#)#with_clause#',
                        "mismatches": index_mismatches
                    } />
                <cfelse>
                    <cftry>
                    <cfset sqlStatement = {
                        "table_name": "#table_name#",
                        "priority": 14,
                        "type": "CREATE INDEX",
                        "title": "CREATE INDEX #code_index.name#",
                        "statement": "CREATE #code_index.unique ? "UNIQUE" : ""# INDEX #code_index.name# ON #table_name# USING #code_index.type# (#index_field_list#)#with_clause#"
                    } />

                    <cfcatch>
                        <cfdump var="#cfcatch#" label="cfcatch" expand="true">
                        <cfdump var="#index_field_list#" label="index_field_list" expand="true"><cfabort>
                    </cfcatch>
                </cftry>
                </cfif>

                <cfset arrayAppend(result, sqlStatement) />
            </cfif>
        </cfloop>



        <!--- Check for additional indexes --->
        <cfloop collection="#db_indexes#" item="db_index" index="db_index_name">
            <cftry>
            <cfif NOT structKeyExists(code_table_schema.indexes, db_index_name)>
                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 4,
                    "type": "DROP INDEX",
                    "title": "DROP INDEX #table_name#.#db_index_name#",
                    "statement": 'DROP INDEX #db_index_name#'
                } />

                <cfset arrayAppend(result, sqlStatement) />
            </cfif>
            <cfcatch>
                <cfdump var="#code_table_schema.indexes#" label="#db_index_name#" expand="true"><cfabort>
            </cfcatch>
            </cftry>
        </cfloop>


        <!--- PRIMARY KEY --->
        <cfif arrayLen(code_table_schema.primary_keys)>
            <cfset drop_pk = false>
            <cfset create_pk = false>

            <cfset code_pk_name = "#table_name#_pkey" />

            <cfif structIsEmpty(db_primary_key)>
                <!--- NO PRIMARY KEY AT ALL --->
                <cfset create_pk = true>

            <cfelseif db_primary_key.primary_key_name EQ code_pk_name>
                <!--- We have the correct primary key name--->

                <cfif db_primary_key.primary_key_columns NEQ arrayToList(code_table_schema.primary_keys)>
                    <!--- PRIMARY KEY IS DIFFERENT --->
                    <cfset drop_pk = true>
                    <cfset create_pk = true>
                </cfif>
            <cfelse>
                <!--- INCORRECT PRIMARY KEY CONSTRAINT NAME --->
                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 13,
                    "type": "RENAME PRIMARY KEY",
                    "title": "RENAME PRIMARY KEY #table_name#.#db_primary_key.primary_key_name#",
                    "statement": 'ALTER TABLE #table_name# RENAME CONSTRAINT #db_primary_key.primary_key_name# TO #code_pk_name#'
                } />

                <cfset arrayAppend(result, sqlStatement) />


            </cfif>

            <cfif drop_pk>
                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 1,
                    "type": "DROP PRIMARY KEY",
                    "title": "DROP PRIMARY KEY #table_name#.#db_primary_key.primary_key_name#",
                    "statement": 'ALTER TABLE #table_name# DROP CONSTRAINT #db_primary_key.primary_key_name#'
                } />

                <cfset arrayAppend(result, sqlStatement) />
            </cfif>

            <cfif create_pk>

                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 12,
                    "type": "ADD PRIMARY KEY",
                    "title": "ADD PRIMARY KEY #table_name#.#code_pk_name#",
                    "statement": 'ALTER TABLE #table_name# ADD CONSTRAINT #code_pk_name# PRIMARY KEY (#arrayToList(code_table_schema.primary_keys)#)'
                } />

                <cfset arrayAppend(result, sqlStatement) />
            </cfif>

        </cfif>



        <!--- FOREIGN KEYS --->
        <cfloop collection="#code_table_schema.foreign_keys#" item="code_fk" index="code_fk_name">

          <cfset drop_fk = false>
          <cfset create_fk = false>

          <cfset found_fk_in_db = structKeyExists(db_foreign_keys,code_fk_name)>

          <cfif !(found_fk_in_db)>
            <!--- We need to create the foregin key --->
            <cfset create_fk = true>
          <cfelse>
            <!--- We need to check to make sure everything matches. If it doesnt match, lets drop it and mark to create --->
            <cfloop list="#structKeyList(code_fk)#" item="code_fk_param" index="i">
                <cfif code_fk[code_fk_param] NEQ (db_foreign_keys[code_fk_name][code_fk_param]?:'')>
                    <!--- <cfdump var="#code_fk#" label="code_fk" expand="false">
                    <cfdump var="#db_foreign_keys#" label="db_foreign_keys" expand="false"><cfabort> --->
                    <cfset drop_fk = true>
                    <cfset create_fk = true>
                </cfif>
            </cfloop>


          </cfif>


          <cfif create_fk>
            <cfif drop_fk>
                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 3,
                    "type": "DROP/ADD CONSTRAINT",
                    "title": "DROP/ADD CONSTRAINT #table_name#.fk_#table_name#_#code_fk.field_name#",
                    "statement": 'ALTER TABLE #table_name# DROP CONSTRAINT fk_#table_name#_#code_fk.field_name#, ADD CONSTRAINT fk_#table_name#_#code_fk.field_name# FOREIGN KEY (#code_fk.field_name#) REFERENCES "#code_fk.foreign_key_table#" ("#code_fk.foreign_key_field#") ON DELETE #code_fk.onDelete# ON UPDATE #code_fk.onUpdate#'
                } />
                <cfset arrayAppend(result, sqlStatement) />
            <cfelse>
                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 15,
                    "type": "ADD CONSTRAINT",
                    "title": "ADD CONSTRAINT #table_name#.fk_#table_name#_#code_fk.field_name#",
                    "statement": 'ALTER TABLE #table_name# ADD CONSTRAINT fk_#table_name#_#code_fk.field_name# FOREIGN KEY (#code_fk.field_name#) REFERENCES "#code_fk.foreign_key_table#" ("#code_fk.foreign_key_field#") ON DELETE #code_fk.onDelete# ON UPDATE #code_fk.onUpdate#'
                } />
                <cfset arrayAppend(result, sqlStatement) />
            </cfif>

          </cfif>
        </cfloop>


        <!--- Check for additional foreign keys --->
        <cfloop collection="#db_foreign_keys#" item="db_fk" index="db_fk_name">
            <cfif NOT structKeyExists(code_table_schema.foreign_keys, db_fk_name)>
                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 2,
                    "type": "DROP CONSTRAINT",
                    "title": "DROP CONSTRAINT #table_name#.#db_fk_name#",
                    "statement": 'ALTER TABLE #table_name# DROP CONSTRAINT #db_fk_name#'
                } />

                <cfset arrayAppend(result, sqlStatement) />
            </cfif>
          </cfloop>




      </cfif>



    </cfloop>


    <cfif arrayLen(result)>
        <cfset arraySort(result, sortByPriority ) />
    </cfif>

    <cfreturn result>
  </cffunction>





    <cffunction name="sortByPriority" returntype="numeric" access="private">
        <cfargument name="a" type="struct" required="true">
        <cfargument name="b" type="struct" required="true">

        <cfscript>
            if (a.priority < b.priority) {
                return -1;
            } else if (a.priority > b.priority) {
                return 1;
            } else {
                return 0;
            }
        </cfscript>
    </cffunction>




    <cffunction name="getColumnDef" returnType="string">
        <cfargument name="field" type="struct" required="true">

        <cfset columnDef = '"#field.name#" #field.type#'>

        <!--- Handle geometry type specifications --->
        <cfif field.type EQ "geometry" AND structKeyExists(field, "geometry_type") AND structKeyExists(field, "srid")>
            <cfset columnDef &= "(#field.geometry_type#, #field.srid#)">
        <cfelseif (field.max_length?:0) GT 0 >
            <cfset columnDef &= " (#field.max_length#)">
        <cfelseif (field.precision?:0) GT 0 >
            <cfset columnDef &= " (#field.precision#,#(field.scale?:0)#)">
        </cfif>

        <!--- Setting as type serial will handle this --->
        <cfif !findNoCase("serial",field.type)>
            <cfif len(field.default?:'')>
                <cfset columnDef &= " DEFAULT #field.default#">
            </cfif>

            <cfif !(field.is_nullable?:true)>
                <cfset columnDef &= " NOT NULL">
            </cfif>
        </cfif>

        <cfif len(field.generation_expression?:'')>
            <cfset columnDef &= " GENERATED ALWAYS AS (#field.generation_expression#) STORED">
        </cfif>

        <!--- Add CHECK constraints if specified --->
        <cfif len(field.check?:'')>
            <cfset columnDef &= " CHECK (#field.check#)">
        </cfif>

        <cfreturn columnDef />
    </cffunction>



    <cffunction name="createTableFromCodeSchema" returnType="array">
        <cfargument name="codeSchema" type="struct" required="true">

        <cfset newTableName = "#arguments.codeSchema.table_name#" />

        <cfset sql = [] />

        <cfset columnDefinitions = [] />

        <cfloop collection="#arguments.codeSchema.fields#" item="field" index="field_name">

            <cfif !listFindNoCase("many_to_many,relation",field.type)>
                <cfset columnDef = getColumnDef(field) />

                <cfset arrayAppend(columnDefinitions, columnDef)>
            </cfif>
        </cfloop>

        <cfif arrayLen(arguments.codeSchema.primary_keys)>
            <cfset arrayAppend(columnDefinitions, "PRIMARY KEY (#arrayToList(arguments.codeSchema.primary_keys)#)")>
        </cfif>




        <!--- Build and execute CREATE TABLE statement --->
        <cfset sqlStatement = {
                                    "table_name": "#newTableName#",
                                    "priority": 7,
                                    "type": "CREATE TABLE",
                                    "title": "CREATE TABLE #newTableName#",
                                    "statement": 'CREATE TABLE "#newTableName#" (#arrayToList(columnDefinitions, ", ")#)'
                                } />

        <cfset arrayAppend(sql, sqlStatement) />


        <!--- Create indexes --->
        <cfloop collection="#arguments.codeSchema.indexes#" item="index" index="i">
            <cfset index_field_list = index.fields />
            <cfif index.type EQ "gin">
                <cfset index_field_list = ListMap(index_field_list, function(term) { return term & " gin_trgm_ops"; })>
            </cfif>
            <cfset sqlStatement = {
                "table_name": "#newTableName#",
                "priority": 8,
                "type": "CREATE INDEX (New Table)",
                "title": "CREATE INDEX (New Table) #index.name#",
                "statement": "CREATE #index.unique ? "UNIQUE" : ""# INDEX #index.name# ON #newTableName# USING #index.type# (#index_field_list#)"
            } />
            <cfset arrayAppend(sql, sqlStatement) />
        </cfloop>


        <cfloop collection="#arguments.codeSchema.foreign_keys#" item="fk" index="i">

            <cfset sqlStatement = {
                "table_name": "#newTableName#",
                "priority": 9,
                "type": "ADD CONSTRAINT (New Table)",
                "title": "ADD CONSTRAINT (New Table) #newTableName#.fk_#newTableName#_#fk.field_name#",
                "statement": 'ALTER TABLE #newTableName# ADD CONSTRAINT fk_#newTableName#_#fk.field_name# FOREIGN KEY (#fk.field_name#) REFERENCES "#fk.foreign_key_table#" ("#fk.foreign_key_field#")'
            } />
            <cfset arrayAppend(sql, sqlStatement) />


        </cfloop>


        <cfreturn sql />
    </cffunction>





</cfcomponent>
