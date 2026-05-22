<cfcomponent displayName="db" hint="Shared runtime CRUD and query helpers backed by Moopa table metadata.">

    <!--- Initialize function for setting up the database connection --->
    <cffunction name="init" access="public" returntype="any" hint="Initialize db with the database connection information.">
        <!--- <cfargument name="dbinfo" type="struct" required="true" hint="A struct containing the database connection information.">
        <cfset this.dbOldinfo = arguments.dbOldinfo> --->

        <cfset this.codeSchema = {} />
        <cfset this.searchable_tables = {} />


        <!--- Merge table definitions from conventional packages. --->
        <cfif NOT (isDefined("application.moopa_packages") AND isArray(application.moopa_packages))>
            <cfthrow message="Cannot initialize db library: application.moopa_packages is not initialized." />
        </cfif>

        <cfloop array="#application.moopa_packages#" item="local.package">
            <cfif directoryExists(expandPath("#local.package.path#/tables"))>
                <cfset local.packageSchema = processDirectory(local.package.path) />
                <cfloop collection="#local.packageSchema#" item="local.tableName">
                    <!--- Later conventional packages override earlier table definitions.
                          This lets shared project tables intentionally replace Moopa core
                          tables such as moo_profile while keeping convention over configuration. --->
                    <cfset this.codeSchema[local.tableName] = local.packageSchema[local.tableName] />
                </cfloop>
            </cfif>
        </cfloop>


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


    <cffunction name="getSearchableTables" hint="Returns the struct containing tables with pg_trgm trigram search enabled">
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
        <cfargument name="sql_type" type="string" default="condensed" hint="simple,expanded,condensed" />
        <cfargument name="sql_table_name" type="string" default="#arguments.table_name#" />
        <cfargument name="include_sensitive" type="boolean" default="false" hint="Include fields marked sensitive: true" />

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

        <!--- Exclude sensitive fields unless explicitly included in field_list or include_sensitive=true --->
        <cfset var explicit_field_list = len(trim(arguments.field_list)) AND arguments.field_list NEQ "*" />
        <cfif !arguments.include_sensitive AND !explicit_field_list>
            <cfset var sensitive_fields = this.codeSchema[arguments.table_name]._sensitive_fields ?: "" />
            <cfif len(sensitive_fields)>
                <cfloop list="#sensitive_fields#" item="sensitive_field">
                    <cfset pos = listFindNoCase(field_list_to_loop, sensitive_field) />
                    <cfif pos GT 0>
                        <cfset field_list_to_loop = listDeleteAt(field_list_to_loop, pos) />
                    </cfif>
                </cfloop>
            </cfif>
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
        <cfargument name="sql_type" type="string" default="condensed" hint="Simple, expanded, condensed" />
        <cfargument name="returnAsCFML" type="boolean" required="false" default=false />
        <cfargument name="include_sensitive" type="boolean" required="false" default=false hint="Include fields marked sensitive: true" />

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
                    SELECT #select(table_name=arguments.table_name, field_list="#arguments.field_list#", exclude_list="#arguments.exclude_list#", sql_type="#arguments.sql_type#", include_sensitive=arguments.include_sensitive)#
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

                        <!--- Use pg_trgm trigram similarity search on search_text column --->
                        <!--- The <% operator finds rows where query has word similarity to search_text --->
                        AND <cfqueryparam cfsqltype="varchar" value="#arguments.q#" /> <% search_text

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

                <!--- Order by word_similarity score when searching, otherwise use default order --->
                <cfif len(arguments.q) AND structKeyExists(this.searchable_tables, arguments.table_name)>
                    ORDER BY word_similarity(<cfqueryparam cfsqltype="varchar" value="#arguments.q#" />, search_text) DESC
                <cfelse>
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

    <cffunction name="idsInSearchTerm" hint="Returns array of IDs matching the search term using pg_trgm trigram similarity">
        <cfargument name="table_name" required="true" />
        <cfargument name="term" required="true" />
        <cfargument name="limit" required="false" default="20">

        <cfset search_ids = [] />

        <cfif structKeyExists(this.searchable_tables, arguments.table_name) AND len(arguments.term)>

            <!--- Use pg_trgm trigram similarity on search_text column --->
            <cfquery name="qSearchIds">
                SELECT id
                FROM #arguments.table_name#
                WHERE <cfqueryparam cfsqltype="varchar" value="#arguments.term#" /> <% search_text
                ORDER BY word_similarity(<cfqueryparam cfsqltype="varchar" value="#arguments.term#" />, search_text) DESC
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

        <!--- Note: pg_trgm search uses the search_text generated column which is automatically updated --->

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

        <!--- Note: pg_trgm search uses the search_text generated column which is automatically updated --->

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
                                                        "foreign_key_onDelete": "SET NULL",
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
                                                        "foreign_key_onDelete": "SET NULL",
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

                <cfif !structKeyExists(field, "condensed")>
                    <cfset field.condensed = false />
                </cfif>
                <cfif !structKeyExists(field, "sensitive")>
                    <cfset field.sensitive = false />
                </cfif>

                <cfif not structKeyExists(field, "is_nullable")>
                    <cfif structKeyExists(field, "nullable")>
                        <cfset field.is_nullable = field.nullable>
                    <cfelseif (field.primary_key?:false) OR arrayFind(table.primary_keys,field.name)>
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

                <!--- Explicit UI metadata must win over schema-derived control defaults.
                      Legacy and project table definitions commonly use html.type="file",
                      "email", "tel", etc. If we eagerly default uuid FK fields to combobox,
                      file fields such as moo_profile.profile_picture_id render as searchable
                      foreign-key dropdowns and call endpoints that do not exist. --->
                <cfif !structKeyExists(field.html, "control") AND len(field.html.type ?: "")>
                    <cfset field.html.control = "control_#replaceNoCase(field.html.type, 'input_', '')#" />
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
                        <cfset field.html.control = (field.html.control?:'control_datetime') />
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
                        <cfset field.html.control = (field.html.control?:'control_switch') />
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
                    <cfset indexName = "idx_#table.table_name#_#field.name#" />

                    <cfif isStruct(field.index)>
                        <cfset indexInfo = {
                            "name": indexName,
                            "type": field.index.type,
                            "fields": field.name,
                            "unique": field.index.unique?:false
                        } />

                        <cfif NOT structKeyExists(table.indexes, indexInfo.name)>
                            <cfset table.indexes[indexInfo.name] = indexInfo>
                        </cfif>
                    <cfelseif isBoolean(field.index) AND field.index>
                        <cfset indexInfo = {
                            "name": indexName,
                            "type": "btree",
                            "fields": field.name,
                            "unique": false
                        } />

                        <cfif NOT structKeyExists(table.indexes, indexInfo.name)>
                            <cfset table.indexes[indexInfo.name] = indexInfo>
                        </cfif>

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



            <!--- Collect searchable fields for pg_trgm trigram search --->
            <!--- Table-level searchable_fields is the preferred API; field.searchable remains supported. --->
            <!--- JSONB fields are tracked but skipped when building the search_text column. --->
            <cfset declared_searchable_fields = table.searchable_fields ?: "" />
            <cfset table.searchable_fields = "" />
            <cfset searchable_field_configs = {} />

            <cfloop list="#declared_searchable_fields#" item="searchable_field_name">
                <cfset searchable_field_name = trim(searchable_field_name) />
                <cfif len(searchable_field_name)>
                    <cfif NOT structKeyExists(table.fields, searchable_field_name)>
                        <cfthrow message="Table #table.table_name# searchable_fields references unknown field: #searchable_field_name#" />
                    </cfif>
                    <cfif NOT listFindNoCase(table.searchable_fields, searchable_field_name)>
                        <cfset table.searchable_fields = listAppend(table.searchable_fields, searchable_field_name) />
                        <cfset searchable_field_configs[searchable_field_name] = { "field_type": table.fields[searchable_field_name].type } />
                    </cfif>
                </cfif>
            </cfloop>

            <cfloop collection="#table.fields#" item="field" index="field_name">
                <cfif structKeyExists(field, "searchable")>
                    <cfset include_searchable_field = false />

                    <cfif isBoolean(field.searchable)>
                        <cfset include_searchable_field = field.searchable />
                    <cfelseif isSimpleValue(field.searchable)>
                        <cfset include_searchable_field = len(trim(field.searchable)) GT 0 />
                    <cfelseif isStruct(field.searchable)>
                        <cfset include_searchable_field = true />
                    <cfelse>
                        <cfthrow message="Table #table.table_name# field #field_name# has unsupported searchable metadata." />
                    </cfif>

                    <cfif include_searchable_field AND NOT listFindNoCase(table.searchable_fields, field_name)>
                        <cfset table.searchable_fields = listAppend(table.searchable_fields, field_name) />
                        <cfset searchable_field_configs[field_name] = { "field_type": field.type } />
                    </cfif>
                </cfif>
            </cfloop>

            <cfif len(table.searchable_fields)>

                <cfset this.searchable_tables[table.table_name] = {
                    'table_name': table.table_name,
                    'searchable_fields': table.searchable_fields,
                    'field_configs': searchable_field_configs
                } />

                <!--- Build search_text generated column using pg_trgm trigram similarity --->
                <!--- This concatenates all searchable fields into a single text column for efficient searching --->
                <!--- JSONB fields are skipped - use generated columns or searchable with json_path to extract text --->
                <cfset search_text_parts = [] />
                <cfloop list="#table.searchable_fields#" item="searchable_field_name">
                    <cfset field_config = searchable_field_configs[searchable_field_name] />
                    <cfset field_type = field_config.field_type ?: "varchar" />
                    <cfset field_def = table.fields[searchable_field_name] />

                    <!--- Skip JSONB fields - these should have separate generated columns for searching --->
                    <cfif field_type EQ "jsonb">
                        <cfcontinue />
                    </cfif>

                    <!--- If the field has a generation_expression, use that expression directly --->
                    <!--- This avoids PostgreSQL error: cannot reference another generated column --->
                    <cfif len(field_def.generation_expression?:'')>
                        <cfset arrayAppend(search_text_parts, "COALESCE((#field_def.generation_expression#)::text, '')") />
                    <cfelse>
                        <!--- Regular field - reference by name --->
                        <cfset arrayAppend(search_text_parts, "COALESCE(#searchable_field_name#::text, '')") />
                    </cfif>
                </cfloop>

                <!--- Only create search_text if we have searchable text fields --->
                <cfif arrayLen(search_text_parts)>
                    <!--- Build the generation expression: COALESCE(f1,'') || ' ' || COALESCE(f2,'') ... --->
                    <cfset search_text_expression = arrayToList(search_text_parts, " || ' ' || ") />

                    <!--- Add search_text as a generated column --->
                    <!--- All field properties must be set since this is added after the field processing loop --->
                    <cfset table.fields['search_text'] = {
                        "name": "search_text",
                        "label": "Search Text",
                        "type": "text",
                        "cfsqltype": "varchar",
                        "is_system": true,
                        "is_nullable": true,
                        "searchable": false,
                        "default": "",
                        "sql_select_simple": "",
                        "html": {},
                        "generation_expression": "#search_text_expression#"
                    } />

                    <!--- Add GIN index with gin_trgm_ops for trigram similarity search --->
                    <cfset table.indexes['#table.table_name#_search_trgm_idx'] = {
                        "name": "#table.table_name#_search_trgm_idx",
                        "type": "gin",
                        "fields": "search_text",
                        "unique": false
                    } />
                </cfif>

            </cfif>

            <!--- Build condensed/sensitive field lists for FK/M2M/relation SQL generation --->
            <cfset table._condensed_fields = "" />
            <cfset table._sensitive_fields = "" />
            <cfloop collection="#table.fields#" item="f" index="fn">
                <cfif f.condensed ?: false>
                    <cfset table._condensed_fields = listAppend(table._condensed_fields, fn) />
                </cfif>
                <cfif f.sensitive ?: false>
                    <cfset table._sensitive_fields = listAppend(table._sensitive_fields, fn) />
                </cfif>
            </cfloop>
            <!--- Ensure id is always in condensed --->
            <cfif len(table._condensed_fields) AND !listFindNoCase(table._condensed_fields, "id")>
                <cfset table._condensed_fields = listPrepend(table._condensed_fields, "id") />
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
                            <!--- Skip sensitive fields from expanded view --->
                            <cfif listFindNoCase(arguments.codeSchemaInput[field.foreign_key_table]._sensitive_fields ?: "", foreign_table_field_name)>
                                <cfcontinue />
                            </cfif>
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
                    <!--- Build condensed pairs from _condensed_fields, fall back to id,label --->
                    <cfset condensed_fields = arguments.codeSchemaInput[field.foreign_key_table]._condensed_fields ?: "" />
                    <cfif !len(condensed_fields)>
                        <cfset condensed_pairs = "'id',id,'label',label" />
                    <cfelse>
                        <cfset condensed_pairs = "" />
                        <cfloop list="#condensed_fields#" item="cf">
                            <cfset condensed_pairs = listAppend(condensed_pairs, "'#cf#',#cf#") />
                        </cfloop>
                    </cfif>
                    <cfsavecontent variable="field.sql_select_condensed">
                    <cfoutput>
                        coalesce((
                            SELECT jsonb_agg(
                                jsonb_build_object(#condensed_pairs#)
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

                                <!--- Skip sensitive fields from expanded view --->
                                <cfif listFindNoCase(arguments.codeSchemaInput[field.foreign_key_table]._sensitive_fields ?: "", foreign_table_field_name)>
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
                        <!--- Build condensed pairs from _condensed_fields, fall back to id,label --->
                        <cfset condensed_fields = arguments.codeSchemaInput[field.foreign_key_table]._condensed_fields ?: "" />
                        <cfif !len(condensed_fields)>
                            <cfset condensed_pairs = "'id',id,'label',label" />
                        <cfelse>
                            <cfset condensed_pairs = "" />
                            <cfloop list="#condensed_fields#" item="cf">
                                <cfset condensed_pairs = listAppend(condensed_pairs, "'#cf#',#cf#") />
                            </cfloop>
                        </cfif>
                        <cfsavecontent variable="field.sql_select_condensed">
                        <cfoutput>
                            coalesce((
                                SELECT json_build_object(#condensed_pairs#)
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
                                <!--- Skip sensitive fields from expanded view --->
                                <cfif listFindNoCase(arguments.codeSchemaInput[field.foreign_key_table]._sensitive_fields ?: "", foreign_table_field_name)>
                                    <cfcontinue />
                                </cfif>
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
                        <!--- Build condensed field list from _condensed_fields, fall back to id,label --->
                        <cfset condensed_fields = arguments.codeSchemaInput[field.foreign_key_table]._condensed_fields ?: "" />
                        <cfif !len(condensed_fields)>
                            <cfset condensed_field_list = "id,label" />
                        <cfelse>
                            <cfset condensed_field_list = condensed_fields />
                        </cfif>
                        <cfsavecontent variable="field.sql_select_condensed">
                            <cfoutput>
                            coalesce((
                                SELECT jsonb_agg(to_jsonb(sq.*))
                                FROM (
                                    SELECT #condensed_field_list#
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

</cfcomponent>
