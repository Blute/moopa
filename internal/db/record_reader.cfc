<cfcomponent displayName="record_reader" output="false" hint="Internal read/search implementation for db facade methods.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfargument name="returnFormatter" required="true" />

        <cfset variables.returnFormatter = arguments.returnFormatter />

        <cfreturn this />
    </cffunction>

    <cffunction name="read" access="public" returntype="any" output="false" hint="Return one record as database-generated JSON text or CFML.">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="idValue" type="string" required="true" />
        <cfargument name="selectFields" type="string" required="true" />
        <cfargument name="orderBy" type="string" required="true" />
        <cfargument name="returnFormat" type="string" required="false" default="json" />

        <cfset var res = "{}" />
        <cfset var qData = "" />
        <cfset var qResult = "" />

        <cftry>
            <cfquery name="qData" result="qResult">
                SELECT COALESCE(row_to_json(data)::text, '{}') as recordset
                FROM (
                    SELECT #preserveSingleQuotes(arguments.selectFields)#
                    FROM #arguments.table_name#
                    WHERE id = <cfqueryparam cfsqltype="other" value="#arguments.idValue#" />
                    #preserveSingleQuotes(arguments.orderBy)#
                ) AS data
            </cfquery>
            <cfcatch type="any">
                <cfdump var="#cfcatch#" expand="true">
                <cfabort>
            </cfcatch>
        </cftry>

        <cfif len(qData.recordset)>
            <cfset res = qData.recordset />
        </cfif>

        <cfreturn variables.returnFormatter.formatJSONText(res, arguments.returnFormat) />
    </cffunction>

    <cffunction name="search" access="public" returntype="any" output="false" hint="Return records matching ids, search text, and field filters.">
        <cfargument name="tableDef" type="struct" required="true" />
        <cfargument name="searchableTables" type="struct" required="true" />
        <cfargument name="selectFields" type="string" required="true" />
        <cfargument name="orderBy" type="string" required="true" />
        <cfargument name="field_list" type="string" required="false" default="*" />
        <cfargument name="q" type="string" required="false" default="" />
        <cfargument name="where" type="struct" required="false" default="#structNew()#" />
        <cfargument name="ids" type="array" required="false" default="#arrayNew()#" />
        <cfargument name="exclude_ids" type="string" required="false" default="" />
        <cfargument name="offset" type="numeric" required="false" />
        <cfargument name="limit" type="string" required="false" default="250" />
        <cfargument name="select_append" type="string" required="false" default="" />
        <cfargument name="returnFormat" type="string" required="false" default="json" />

        <cfset var qData = "" />
        <cfset var orderedRecordset = [] />
        <cfset var tableName = arguments.tableDef.table_name />

        <cfquery name="qData">
            SELECT COALESCE(array_to_json(array_agg(row_to_json(data)))::text, '[]') AS recordset
            FROM (
                SELECT #preserveSingleQuotes(arguments.selectFields)#
                    <cfif len(arguments.select_append)>
                        , #preserveSingleQuotes(arguments.select_append)#
                    </cfif>
                FROM #tableName#
                WHERE 1 = 1

                <cfloop collection="#arguments.where#" item="field">
                    <cfset local.value = arguments.where[field] />

                    <cfif isStruct(local.value) AND structKeyExists(local.value, "operator")>
                        <cfset local.operator = local.value.operator />
                        <cfset local.sqlType = structKeyExists(local.value, "type") ? local.value.type : arguments.tableDef.fields[field].cfsqltype />

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
                        AND #field# = <cfqueryparam cfsqltype="#arguments.tableDef.fields[field].cfsqltype#" value="#local.value#" />
                    </cfif>
                </cfloop>

                <cfif len(arguments.q)>
                    <cfif structKeyExists(arguments.searchableTables, tableName)>
                        AND <cfqueryparam cfsqltype="varchar" value="#arguments.q#" /> <% search_text
                    <cfelse>
                        AND label ILIKE <cfqueryparam cfsqltype="varchar" value="%#arguments.q#%" />
                    </cfif>
                </cfif>

                <cfif arrayLen(arguments.ids)>
                    AND id in (<cfqueryparam cfsqltype="other" list="true" value="#arguments.ids#" />)
                </cfif>

                <cfif len(arguments.exclude_ids)>
                    AND id NOT IN (<cfqueryparam cfsqltype="other" list="true" value="#arguments.exclude_ids#" />)
                </cfif>

                <cfif len(arguments.q) AND structKeyExists(arguments.searchableTables, tableName)>
                    ORDER BY word_similarity(<cfqueryparam cfsqltype="varchar" value="#arguments.q#" />, search_text) DESC
                <cfelse>
                    #preserveSingleQuotes(arguments.orderBy)#
                </cfif>

                <cfif structKeyExists(arguments, "offset")>
                    OFFSET <cfqueryparam cfsqltype="numeric" value="#arguments.offset#" />
                </cfif>

                LIMIT <cfqueryparam cfsqltype="numeric" value="#arguments.limit#" />
            ) AS data
        </cfquery>

        <cfif arrayLen(arguments.ids) GT 1>
            <cfset orderedRecordset = sortRecordsetByIds(qData.recordset, arguments.ids) />
            <cfreturn variables.returnFormatter.formatCFML(orderedRecordset, arguments.returnFormat) />
        </cfif>

        <cfreturn variables.returnFormatter.formatJSONText(qData.recordset, arguments.returnFormat) />
    </cffunction>

    <cffunction name="idsInSearchTerm" access="public" returntype="array" output="false" hint="Return IDs matching a pg_trgm search term.">
        <cfargument name="table_name" required="true" />
        <cfargument name="term" required="true" />
        <cfargument name="limit" required="false" default="20" />
        <cfargument name="searchableTables" type="struct" required="true" />

        <cfset var search_ids = [] />
        <cfset var qSearchIds = "" />

        <cfif structKeyExists(arguments.searchableTables, arguments.table_name) AND len(arguments.term)>
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
            <cfset search_ids = ["607ceee8-2cc0-4f9a-bed8-9f2f3affc575"] />
        </cfif>

        <cfreturn search_ids />
    </cffunction>

    <cffunction name="sortRecordsetByIds" access="public" returntype="array" output="false">
        <cfargument name="recordset" required="true" />
        <cfargument name="ids" required="true" type="array" />

        <cfset var unorderedRecordset = [] />
        <cfset var orderedRecordset = [] />
        <cfset var id = "" />
        <cfset var record = {} />

        <cfif isJSON(arguments.recordset)>
            <cfset unorderedRecordset = deserializeJSON(arguments.recordset) />
        <cfelse>
            <cfset unorderedRecordset = arguments.recordset />
        </cfif>

        <cfif !arrayLen(arguments.ids ?: [])>
            <cfreturn unorderedRecordset />
        </cfif>

        <cfloop array="#arguments.ids#" item="id">
            <cfloop array="#unorderedRecordset#" item="record">
                <cfif record.id EQ id>
                    <cfset arrayAppend(orderedRecordset, record) />
                    <cfbreak />
                </cfif>
            </cfloop>
        </cfloop>

        <cfreturn orderedRecordset />
    </cffunction>

</cfcomponent>
