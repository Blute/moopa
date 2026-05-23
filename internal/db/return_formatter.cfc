<cfcomponent displayName="db_return_formatter" output="false" hint="Formats db facade return values without leaking serialization branching into CRUD methods.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>

    <cffunction name="normalizeReturnFormat" access="public" returntype="string" output="false" hint="Validate and normalize the db returnFormat argument.">
        <cfargument name="returnFormat" type="string" required="false" default="json" />

        <cfset var normalizedReturnFormat = lCase(trim(arguments.returnFormat)) />

        <cfif NOT listFindNoCase("json,cfml", normalizedReturnFormat)>
            <cfthrow type="moopa.db.invalidReturnFormat" message="Invalid returnFormat '#arguments.returnFormat#'. Use 'json' or 'cfml'." />
        </cfif>

        <cfreturn normalizedReturnFormat />
    </cffunction>

    <cffunction name="formatCFML" access="public" returntype="any" output="false" hint="Return a native CFML value or serialize it to JSON according to returnFormat.">
        <cfargument name="value" type="any" required="true" />
        <cfargument name="returnFormat" type="string" required="false" default="json" />

        <cfif normalizeReturnFormat(arguments.returnFormat) EQ "json">
            <cfreturn serializeJSON(arguments.value) />
        </cfif>

        <cfreturn arguments.value />
    </cffunction>

    <cffunction name="formatJSONText" access="public" returntype="any" output="false" hint="Return database-generated JSON text or deserialize it to CFML according to returnFormat.">
        <cfargument name="jsonText" type="string" required="true" />
        <cfargument name="returnFormat" type="string" required="false" default="json" />

        <cfif normalizeReturnFormat(arguments.returnFormat) EQ "json">
            <cfreturn arguments.jsonText />
        </cfif>

        <cftry>
            <cfreturn deserializeJSON(arguments.jsonText) />
            <cfcatch type="any">
                <cfthrow
                    type="moopa.db.invalidJSONResult"
                    message="Unable to deserialize database JSON result for returnFormat='cfml'."
                    detail="#cfcatch.message#" />
            </cfcatch>
        </cftry>
    </cffunction>

</cfcomponent>
