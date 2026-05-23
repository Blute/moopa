<cfcomponent displayName="new_object_factory" output="false" hint="Build default objects for db.getNewObject from normalized table metadata.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>

    <cffunction name="build" access="public" returntype="struct" output="false" hint="Return a new unsaved object with framework defaults and caller-provided data overlaid.">
        <cfargument name="tableDef" type="struct" required="true" />
        <cfargument name="data" type="struct" required="false" default="#structNew()#" />

        <cfset var stDefaultObject = getBlankObject(arguments.tableDef) />
        <cfset var databaseDefaults = getDatabaseDefaultObject(arguments.tableDef) />

        <cfset structAppend(stDefaultObject, databaseDefaults, true) />
        <cfset structAppend(stDefaultObject, arguments.data, true) />

        <cfreturn stDefaultObject />
    </cffunction>

    <cffunction name="getBlankObject" access="private" returntype="struct" output="false" hint="Build client-facing blank defaults by field type.">
        <cfargument name="tableDef" type="struct" required="true" />

        <cfset var stDefaultObject = {} />
        <cfset var field = {} />
        <cfset var field_name = "" />

        <cfloop collection="#arguments.tableDef.fields#" item="field" index="field_name">
            <cfif !(field.is_system ?: false)>
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
            </cfif>
        </cfloop>

        <cfreturn stDefaultObject />
    </cffunction>

    <cffunction name="getDatabaseDefaultObject" access="private" returntype="struct" output="false" hint="Evaluate table default SQL expressions through PostgreSQL and return them as a struct.">
        <cfargument name="tableDef" type="struct" required="true" />

        <cfset var dynamicSQL = "'is_new_record',true" />
        <cfset var defaultValue = "" />
        <cfset var databaseDefaults = {} />
        <cfset var field = {} />
        <cfset var field_name = "" />
        <cfset var column_name = "" />
        <cfset var column_value = "" />
        <cfset var qNewDBObject = "" />

        <cfloop collection="#arguments.tableDef.fields#" item="field" index="field_name">
            <cfif len(field.default ?: "") AND !(field.is_system ?: false)>
                <cfset defaultValue = field.default />

                <cfif field.type EQ "date">
                    <cfset defaultValue = "#defaultValue#::date" />
                </cfif>

                <cfif field.type EQ "uuid">
                    <cfset defaultValue = "#defaultValue#::text" />
                </cfif>

                <cfif field.type EQ "jsonb">
                    <cfset defaultValue = "#defaultValue#::jsonb" />
                </cfif>

                <!--- SELECT jsonb_build_object('lease_terms', '[]'::jsonb, 'title', 'test') as json_object --->
                <cfset dynamicSQL = listAppend(dynamicSQL, "'#field.name#', #defaultValue#") />
            </cfif>
        </cfloop>

        <cfif len(trim(dynamicSQL))>
            <cfquery name="qNewDBObject">
                SELECT jsonb_build_object(#preserveSingleQuotes(dynamicSQL)#) as json_object
            </cfquery>

            <cfloop collection="#deserializeJSON(qNewDBObject.json_object)#" item="column_value" index="column_name">
                <cfset databaseDefaults[column_name] = column_value />
            </cfloop>
        </cfif>

        <cfreturn databaseDefaults />
    </cffunction>

</cfcomponent>
