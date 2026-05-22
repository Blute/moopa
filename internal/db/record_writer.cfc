<cfcomponent displayName="record_writer" output="false" hint="Internal db.save implementation for direct column writes and relationship bridge writes.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfargument name="writeMapper" required="true" />
        <cfargument name="relationshipWriter" required="true" />
        <cfargument name="returnFormatter" required="true" />

        <cfset variables.writeMapper = arguments.writeMapper />
        <cfset variables.relationshipWriter = arguments.relationshipWriter />
        <cfset variables.returnFormatter = arguments.returnFormatter />

        <cfreturn this />
    </cffunction>

    <cffunction name="save" access="public" returntype="any" output="false" hint="Create or update one record and persist any many-to-many fields.">
        <cfargument name="stModel" type="struct" required="true" />
        <cfargument name="data" default="#structNew()#" />
        <cfargument name="returnFormat" type="string" required="false" default="json" />
        <cfargument name="index_record" type="boolean" default="true" />

        <cfset var result = {
            id : (arguments.data.id ?: ""),
            sql_statements : []
        } />
        <cfset var stDataFields = variables.writeMapper.getWritableFields(arguments.stModel, arguments.data) />
        <cfset var sqlResult = "" />
        <cfset var relationshipSql = "" />

        <cfif shouldUpdateRecord(stDataFields, arguments.data)>
            <cfset sqlResult = updateRecord(arguments.stModel, stDataFields) />
            <cfset arrayAppend(result.sql_statements, sqlResult) />
        <cfelse>
            <cfset sqlResult = insertRecord(arguments.stModel, stDataFields, arguments.data) />
            <cfset result.id = sqlResult.id />
            <cfset arrayAppend(result.sql_statements, sqlResult) />
        </cfif>

        <cfloop array="#variables.relationshipWriter.saveManyToManyFields(arguments.stModel, arguments.data, result.id)#" item="relationshipSql">
            <cfset arrayAppend(result.sql_statements, relationshipSql) />
        </cfloop>

        <cfreturn variables.returnFormatter.formatCFML(result, arguments.returnFormat) />
    </cffunction>

    <cffunction name="shouldUpdateRecord" access="private" returntype="boolean" output="false" hint="Preserve db.save's id-based update heuristic unless the payload explicitly marks a new record.">
        <cfargument name="stDataFields" type="struct" required="true" />
        <cfargument name="data" required="true" />

        <cfreturn len(arguments.stDataFields.id ?: "") AND NOT (arguments.data.is_new_record ?: false) />
    </cffunction>

    <cffunction name="updateRecord" access="private" returntype="struct" output="false" hint="Update direct table columns for an existing record.">
        <cfargument name="stModel" type="struct" required="true" />
        <cfargument name="stDataFields" type="struct" required="true" />

        <cfset var model_field = {} />
        <cfset var stParams = {} />
        <cfset var sqlResult = {} />
        <cfset var bFirst = true />
        <cfset var profileId = getCurrentProfileId() />

        <cfquery name="local.qUpdate" result="sqlResult">
            UPDATE #arguments.stModel.table_name#
            SET last_updated_at = now(),

            <cfif len(profileId)>
                last_updated_by = <cfqueryparam cfsqltype="other" value="#profileId#" />
            <cfelse>
                last_updated_by = <cfqueryparam cfsqltype="other" value="" null="true" />
            </cfif>

            <cfloop collection="#arguments.stDataFields#" item="data_field" index="data_field_name">
                <cfset model_field = arguments.stModel.fields[data_field_name] />

                <cfif variables.writeMapper.isPersistedColumn(model_field)>
                    ,
                    <cfset stParams = variables.writeMapper.buildQueryParam(model_field, data_field, true) />
                    #data_field_name# = <cfqueryparam attributeCollection="#stParams#" />
                </cfif>
            </cfloop>
            WHERE
                <cfset bFirst = true />
                <cfloop array="#arguments.stModel.primary_keys#" item="pk_name">
                    <cfif NOT bFirst>AND</cfif><cfset bFirst = false />

                    <cfset stParams = {
                        cfsqltype: "other",
                        value: arguments.stDataFields[pk_name],
                        null: false
                    } />
                    #pk_name# = <cfqueryparam attributeCollection="#stParams#" />
                </cfloop>
        </cfquery>

        <cfreturn sqlResult />
    </cffunction>

    <cffunction name="insertRecord" access="private" returntype="struct" output="false" hint="Insert direct table columns for a new record.">
        <cfargument name="stModel" type="struct" required="true" />
        <cfargument name="stDataFields" type="struct" required="true" />
        <cfargument name="data" required="true" />

        <cfset var model_field = {} />
        <cfset var stParams = {} />
        <cfset var sqlResult = {} />
        <cfset var profileId = getCurrentProfileId() />

        <cfif structIsEmpty(arguments.data)>
            <cfquery name="local.qCreate" result="sqlResult">
                INSERT INTO #arguments.stModel.table_name# DEFAULT VALUES;
            </cfquery>
        <cfelse>
            <cfquery name="local.qCreate" result="sqlResult">
                INSERT INTO #arguments.stModel.table_name# (
                    created_by

                    <cfloop collection="#arguments.stDataFields#" item="data_field" index="data_field_name">
                        <cfif structKeyExists(arguments.stModel.fields, data_field_name)>
                            <cfset model_field = arguments.stModel.fields[data_field_name] />
                            <cfif variables.writeMapper.isPersistedColumn(model_field)>
                                , #data_field_name#
                            </cfif>
                        </cfif>
                    </cfloop>

                    <cfif len(arguments.stDataFields.id ?: "")>
                        , id
                    </cfif>
                )
                VALUES (
                    <cfif len(profileId)>
                        <cfqueryparam cfsqltype="other" value="#profileId#" />
                    <cfelse>
                        <cfqueryparam cfsqltype="other" value="" null="true" />
                    </cfif>

                    <cfloop collection="#arguments.stDataFields#" item="data_field" index="data_field_name">
                        <cfif structKeyExists(arguments.stModel.fields, data_field_name)>
                            <cfset model_field = arguments.stModel.fields[data_field_name] />

                            <cfif variables.writeMapper.isPersistedColumn(model_field)>
                                ,
                                <cfset stParams = variables.writeMapper.buildQueryParam(model_field, data_field, false) />
                                <cfqueryparam attributeCollection="#stParams#" />
                            </cfif>
                        </cfif>
                    </cfloop>

                    <cfif len(arguments.stDataFields.id ?: "")>
                        ,
                        <cfqueryparam cfsqltype="other" value="#arguments.stDataFields.id#" />
                    </cfif>
                )
            </cfquery>
        </cfif>

        <cfreturn sqlResult />
    </cffunction>

    <cffunction name="getCurrentProfileId" access="private" returntype="string" output="false" hint="Return the current authenticated profile id when save runs in a request with a session.">
        <cfif isDefined("session.auth.profile.id")>
            <cfreturn trim(session.auth.profile.id ?: "") />
        </cfif>

        <cfreturn "" />
    </cffunction>

</cfcomponent>
