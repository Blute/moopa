<cfcomponent displayName="db" hint="Shared runtime CRUD and query helpers backed by Moopa table metadata.">

    <!--- Initialize function for setting up the database connection --->
    <cffunction name="init" access="public" returntype="any" hint="Initialize db with the database connection information.">
        <!--- <cfargument name="dbinfo" type="struct" required="true" hint="A struct containing the database connection information.">
        <cfset this.dbOldinfo = arguments.dbOldinfo> --->

        <cfset this.codeSchema = {} />
        <cfset this.searchable_tables = {} />

        <cfset variables.returnFormatter = CreateObject("component", "/moopa/internal/db/return_formatter").init() />
        <cfset variables.writeMapper = CreateObject("component", "/moopa/internal/db/write_mapper").init() />
        <cfset variables.relationshipWriter = CreateObject("component", "/moopa/internal/db/relationship_writer").init() />
        <cfset variables.recordWriter = CreateObject("component", "/moopa/internal/db/record_writer").init(
            writeMapper = variables.writeMapper,
            relationshipWriter = variables.relationshipWriter,
            returnFormatter = variables.returnFormatter
        ) />
        <cfset variables.schemaNormalizer = CreateObject("component", "/moopa/internal/db/schema_normalizer").init() />


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


        <cfset this.codeSchema = variables.schemaNormalizer.normalize(this.codeSchema, this.searchable_tables)>


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
        <cfargument name="returnFormat" type="string" required="false" default="json" />

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
        <cfargument name="returnFormat" type="string" required="false" default="json" />
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
            <cfset new_object = save(table_name=arguments.table_name, data=stDefaultObject, returnFormat="cfml") />
            <cfset stDefaultObject = read(table_name=arguments.table_name, id=new_object.id, returnFormat="cfml") />
        </cfif>

        <cfreturn variables.returnFormatter.formatCFML(stDefaultObject, arguments.returnFormat) />
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


    <cffunction name="read" returntype="any" hint="Returns a JSON object string or CFML struct for the matching id">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="false" default="" />
        <cfargument name="data" type="struct" required="false" default="#structNew()#" />
        <cfargument name="field_list" type="string" default="" hint="List of fields to include" />
        <cfargument name="exclude_list" type="string" default="" hint="List of fields to exclude" />
        <cfargument name="sql_type" type="string" default="condensed" hint="Simple, expanded, condensed" />
        <cfargument name="returnFormat" type="string" required="false" default="json" />
        <cfargument name="include_sensitive" type="boolean" required="false" default=false hint="Include fields marked sensitive: true" />

        <cfset var res = {} />

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


        <cfreturn variables.returnFormatter.formatJSONText(res, arguments.returnFormat) />
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
        <cfargument name="returnFormat" type="string" required="false" default="json" />

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

            <cfreturn variables.returnFormatter.formatCFML(orderedRecordset, arguments.returnFormat) />

        <cfelse>

            <cfreturn variables.returnFormatter.formatJSONText(qData.recordset, arguments.returnFormat) />
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
        <cfargument name="returnFormat" type="string" required="false" default="json" />

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

        <cfreturn variables.returnFormatter.formatCFML(result, arguments.returnFormat) />
    </cffunction>



    <!---
    dynamically insert or update record based on the presence of an id in the provided data.
    If no id is included, insert!
    If id is included, search for existing record. if exists, update otherwise insert using the id.
     --->
    <cffunction name="save" returntype="any" hint="create/insert based on data.id.">
        <cfargument name="table_name" required="true" />
        <cfargument name="data" default="#structNew()#"/>
        <cfargument name="returnFormat" type="string" required="false" default="json" />
        <cfargument name="index_record" type="boolean" default=true />

        <cfset var stModel = this.codeSchema[arguments.table_name] />

        <cfreturn variables.recordWriter.save(
            stModel = stModel,
            data = arguments.data,
            returnFormat = arguments.returnFormat,
            index_record = arguments.index_record
        ) />

    </cffunction>

</cfcomponent>
