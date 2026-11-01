<cfcomponent>

    <!--- Fixture for scripts/test_db_search.sh: a searchable table whose own order_by is rank. --->
    <cffunction name="init">

        <cfset this.definition = {
            "title": "Probe item",
            "label_generation_expression": "COALESCE(name::text, id::text)",
            "order_by": "rank asc",
            "searchable_fields": "name",
            "fields": {
                "name": {},
                "rank": { "type": "int4" },
                "owner_id": { "type": "uuid", "foreign_key_table": "probe_owner" }
            }
        } />

        <cfreturn this>
    </cffunction>

</cfcomponent>
