<cfcomponent displayName="projection_builder" output="false" hint="Build SQL SELECT and ORDER BY fragments from normalized table metadata.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>

    <cffunction name="select" access="public" returntype="string" output="false" hint="Return a comma-delimited SQL SELECT fragment for a table definition.">
        <cfargument name="tableDef" type="struct" required="true" />
        <cfargument name="field_list" type="string" default="" hint="List of fields to include" />
        <cfargument name="exclude_list" type="string" default="" hint="List of fields to exclude" />
        <cfargument name="sql_type" type="string" default="condensed" hint="simple,expanded,condensed" />
        <cfargument name="sql_table_name" type="string" default="#arguments.tableDef.table_name#" />
        <cfargument name="include_sensitive" type="boolean" default="false" hint="Include fields marked sensitive: true" />

        <cfset var field_list_to_loop = getFieldsToProject(
            tableDef = arguments.tableDef,
            field_list = arguments.field_list,
            exclude_list = arguments.exclude_list,
            include_sensitive = arguments.include_sensitive
        ) />
        <cfset var return_select_fields = "" />
        <cfset var field_sql = "" />
        <cfset var field_name = "" />

        <cftry>
            <cfloop list="#field_list_to_loop#" item="field_name">
                <cfset field_sql = getFieldProjection(arguments.tableDef, field_name, arguments.sql_type) />

                <cfif len(trim(field_sql))>
                    <cfif arguments.sql_table_name NEQ arguments.tableDef.table_name>
                        <!--- I need to convert #arguments.tableDef.table_name#.id to #arguments.sql_table_name#.id --->
                        <cfset field_sql = replaceNoCase(trim(field_sql), "#arguments.tableDef.table_name#.", "#arguments.sql_table_name#.", "one ") />
                    </cfif>
                    <cfset return_select_fields = listAppend(return_select_fields, field_sql) />
                </cfif>
            </cfloop>

            <cfcatch type="any">
                <cfdump var="#cfcatch#" expand="true">
                <cfdump var="#arguments.tableDef.fields#" expand="true">
                <cfabort>
            </cfcatch>
        </cftry>

        <cfreturn return_select_fields />
    </cffunction>

    <cffunction name="orderBy" access="public" returntype="string" output="false" hint="Return the default ORDER BY clause for a table definition.">
        <cfargument name="tableDef" type="struct" required="true" />

        <cfset var order_by = "" />

        <cfif len(trim(arguments.tableDef.order_by))>
            <cfset order_by = arguments.tableDef.order_by />
        </cfif>

        <cfreturn "ORDER BY #order_by#" />
    </cffunction>

    <cffunction name="getFieldsToProject" access="private" returntype="string" output="false" hint="Resolve include/exclude/sensitive field lists for select().">
        <cfargument name="tableDef" type="struct" required="true" />
        <cfargument name="field_list" type="string" default="" />
        <cfargument name="exclude_list" type="string" default="" />
        <cfargument name="include_sensitive" type="boolean" default="false" />

        <cfset var field_list_to_loop = "" />
        <cfset var allFields = "" />
        <cfset var exclude_field = "" />
        <cfset var explicit_field_list = false />
        <cfset var sensitive_fields = "" />
        <cfset var sensitive_field = "" />
        <cfset var pos = 0 />

        <cfif arguments.field_list EQ "*">
            <cfset field_list_to_loop = structKeyList(arguments.tableDef.fields) />
        <cfelseif len(trim(arguments.field_list))>
            <cfset field_list_to_loop = arguments.field_list />
        <cfelse>
            <!--- Default behavior: all fields except created_by and last_updated_by --->
            <cfset allFields = structKeyList(arguments.tableDef.fields) />
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
        <cfset explicit_field_list = len(trim(arguments.field_list)) AND arguments.field_list NEQ "*" />
        <cfif !arguments.include_sensitive AND !explicit_field_list>
            <cfset sensitive_fields = arguments.tableDef._sensitive_fields ?: "" />
            <cfif len(sensitive_fields)>
                <cfloop list="#sensitive_fields#" item="sensitive_field">
                    <cfset pos = listFindNoCase(field_list_to_loop, sensitive_field) />
                    <cfif pos GT 0>
                        <cfset field_list_to_loop = listDeleteAt(field_list_to_loop, pos) />
                    </cfif>
                </cfloop>
            </cfif>
        </cfif>

        <cfreturn field_list_to_loop />
    </cffunction>

    <cffunction name="getFieldProjection" access="private" returntype="string" output="false" hint="Return the field projection string for the requested SQL projection mode.">
        <cfargument name="tableDef" type="struct" required="true" />
        <cfargument name="field_name" type="string" required="true" />
        <cfargument name="sql_type" type="string" required="true" />

        <cfset var field_sql = "" />

        <cfswitch expression="#arguments.sql_type#">
            <cfcase value="simple">
                <cfif len(trim(arguments.tableDef.fields[arguments.field_name].sql_select_simple ?: ""))>
                    <cfset field_sql = arguments.tableDef.fields[arguments.field_name].sql_select_simple />
                </cfif>
            </cfcase>
            <cfcase value="expanded">
                <cfif len(trim(arguments.tableDef.fields[arguments.field_name].sql_select_expanded ?: ""))>
                    <cfset field_sql = arguments.tableDef.fields[arguments.field_name].sql_select_expanded />
                </cfif>
            </cfcase>
            <cfcase value="condensed">
                <cfif len(trim(arguments.tableDef.fields[arguments.field_name].sql_select_condensed ?: ""))>
                    <cfset field_sql = arguments.tableDef.fields[arguments.field_name].sql_select_condensed />
                </cfif>
            </cfcase>
        </cfswitch>

        <cfreturn field_sql />
    </cffunction>

</cfcomponent>
