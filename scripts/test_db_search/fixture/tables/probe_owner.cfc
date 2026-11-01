<cfcomponent>

    <!--- Fixture for scripts/test_db_search.sh: the table probe_item links to. --->
    <cffunction name="init">

        <cfset this.definition = {
            "title": "Probe owner",
            "label_generation_expression": "COALESCE(name::text, id::text)",
            "order_by": "name asc",
            "fields": {
                "name": {},
                "email": {}
            }
        } />

        <cfreturn this>
    </cffunction>

</cfcomponent>
