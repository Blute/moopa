<cfcomponent displayName="db_write_mapper" output="false" hint="Maps table metadata and incoming CFML values into writable fields and cfqueryparam attributes.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>

    <cffunction name="getWritableFields" access="public" returntype="struct" output="false" hint="Filter incoming data to fields the table can write, preserving existing db.save input coercions.">
        <cfargument name="tableDef" type="struct" required="true" />
        <cfargument name="data" type="struct" required="true" />

        <cfset var writableFields = {} />
        <cfset var fieldName = "" />
        <cfset var fieldDef = {} />
        <cfset var value = "" />

        <cfloop collection="#arguments.data#" item="value" index="fieldName">
            <cfif NOT structKeyExists(arguments.tableDef.fields, fieldName)>
                <cfcontinue />
            </cfif>

            <cfset fieldDef = arguments.tableDef.fields[fieldName] />

            <cfif len(fieldDef.generation_expression ?: "")>
                <cfcontinue />
            </cfif>

            <cfif findNoCase("serial", fieldDef.type ?: "")>
                <cfcontinue />
            </cfif>

            <cfif isNull(arguments.data[fieldName])>
                <cfset writableFields[fieldName] = "" />
                <cfcontinue />
            </cfif>

            <cfset writableFields[fieldName] = arguments.data[fieldName] />

            <!--- Existing db.save contract accepts expanded FK structs and writes the configured FK value. --->
            <cfif len(fieldDef.foreign_key_field ?: "") AND isStruct(writableFields[fieldName])>
                <cfif isEmpty(writableFields[fieldName])>
                    <cfset writableFields[fieldName] = "" />
                <cfelse>
                    <cfset writableFields[fieldName] = writableFields[fieldName][fieldDef.foreign_key_field] />
                </cfif>
            </cfif>
        </cfloop>

        <cfreturn writableFields />
    </cffunction>

    <cffunction name="isPersistedColumn" access="public" returntype="boolean" output="false" hint="True when a field is stored directly on the table by insert/update.">
        <cfargument name="fieldDef" type="struct" required="true" />

        <cfreturn NOT (arguments.fieldDef.is_system ?: false)
            AND (arguments.fieldDef.type ?: "") NEQ "many_to_many"
            AND (arguments.fieldDef.type ?: "") NEQ "relation" />
    </cffunction>

    <cffunction name="buildQueryParam" access="public" returntype="struct" output="false" hint="Build cfqueryparam attributes for a field/value pair.">
        <cfargument name="fieldDef" type="struct" required="true" />
        <cfargument name="value" type="any" required="true" />
        <cfargument name="trimSimpleValues" type="boolean" required="false" default="false" />

        <cfset var params = {
            cfsqltype: "varchar",
            value: arguments.value,
            null: false
        } />
        <cfset var fieldType = arguments.fieldDef.type ?: "varchar" />

        <cfif (arguments.fieldDef.is_nullable ?: false) AND isSimpleValue(params.value) AND NOT len(params.value)>
            <cfset params.null = true />
        </cfif>

        <cfswitch expression="#fieldType#">
            <cfcase value="timestamptz">
                <cfset params.cfsqltype = "timestamp" />
            </cfcase>
            <cfcase value="date">
                <cfset params.cfsqltype = "date" />
            </cfcase>
            <cfcase value="bool">
                <cfset params.cfsqltype = "boolean" />
            </cfcase>
            <cfcase value="jsonb">
                <cfset params.cfsqltype = "other" />
                <cfif NOT isSimpleValue(params.value)>
                    <cfset params.value = serializeJSON(params.value) />
                </cfif>

                <cfif NOT len(trim(params.value))>
                    <cfset params.value = "" />
                    <cfset params.null = true />
                </cfif>
            </cfcase>
            <cfcase value="uuid">
                <cfset params.cfsqltype = "other" />
                <cfif NOT len(trim(arguments.value))>
                    <cfset params.value = "" />
                    <cfset params.null = true />
                </cfif>
            </cfcase>
            <cfcase value="int2,int4,int8,smallserial,serial,bigserial,numeric">
                <cfset params.cfsqltype = "numeric" />
            </cfcase>
            <cfdefaultcase>
                <cfset params.cfsqltype = fieldType />

                <cfif arguments.trimSimpleValues AND isSimpleValue(params.value)>
                    <cfset params.value = trim(params.value) />
                </cfif>
            </cfdefaultcase>
        </cfswitch>

        <cfif isNull(arguments.value)>
            <cfset params.value = "" />
            <cfset params.null = true />
        </cfif>

        <cfreturn params />
    </cffunction>

</cfcomponent>
