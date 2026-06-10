<cfcomponent displayName="db_relationship_writer" output="false" hint="Persists relationship payloads for db.save without embedding bridge-table writes in the CRUD facade.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>

    <cffunction name="saveManyToManyFields" access="public" returntype="array" output="false" hint="Replace many-to-many bridge rows for every relationship field present in the payload.">
        <cfargument name="tableDef" type="struct" required="true" />
        <cfargument name="data" type="struct" required="true" />
        <cfargument name="recordId" type="string" required="true" />

        <cfset var sqlResults = [] />
        <cfset var dataFieldName = "" />
        <cfset var dataFieldValue = "" />
        <cfset var fieldDef = {} />
        <cfset var sql = "" />

        <cfloop collection="#arguments.data#" item="dataFieldValue" index="dataFieldName">
            <cfif NOT structKeyExists(arguments.tableDef.fields, dataFieldName)>
                <cfcontinue />
            </cfif>

            <cfset fieldDef = arguments.tableDef.fields[dataFieldName] />

            <cfif (fieldDef.type ?: "") NEQ "many_to_many">
                <cfcontinue />
            </cfif>

            <cfset sql = saveManyToManyField(fieldDef, dataFieldValue, arguments.recordId) />
            <cfset arrayAppend(sqlResults, sql) />
        </cfloop>

        <cfreturn sqlResults />
    </cffunction>

    <cffunction name="saveManyToManyField" access="private" returntype="any" output="false" hint="Replace one many-to-many bridge field with the supplied ordered foreign ids.">
        <cfargument name="fieldDef" type="struct" required="true" />
        <cfargument name="values" type="array" required="true" />
        <cfargument name="recordId" type="string" required="true" />

        <cfset var item = "" />
        <cfset var seq = 0 />
        <cfset var foreignId = "" />

        <cfquery name="local.qBridge" result="local.sql">
            DELETE FROM #arguments.fieldDef.bridgingTableName#
            WHERE primary_id = <cfqueryparam cfsqltype="other" value="#arguments.recordId#" />;

            <cfloop array="#arguments.values#" item="item" index="seq">
                <cfif isStruct(item)>
                    <cfset foreignId = item.id />
                <cfelse>
                    <cfset foreignId = item />
                </cfif>

                INSERT INTO #arguments.fieldDef.bridgingTableName# (primary_id, foreign_id, sequence)
                VALUES (
                    <cfqueryparam cfsqltype="other" value="#arguments.recordId#" />,
                    <cfqueryparam cfsqltype="other" value="#foreignId#" />,
                    <cfqueryparam cfsqltype="integer" value="#seq#" />
                );
            </cfloop>
        </cfquery>

        <cfreturn local.sql />
    </cffunction>

</cfcomponent>
