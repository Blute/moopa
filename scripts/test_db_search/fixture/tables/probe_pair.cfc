<cfcomponent>

    <!--- Fixture for scripts/test_db_search.sh: a searchable table keyed on two columns, with an
          ordinary id column that is not unique, so only the primary key breaks ties. --->
    <cffunction name="init">

        <cfset this.definition = {
            "title": "Probe pair",
            "label_generation_expression": "COALESCE(name::text, id::text)",
            "order_by": "name asc",
            "searchable_fields": "name",
            "primary_keys": ["group_code", "item_code"],
            "fields": {
                "id": { "type": "uuid" },
                "group_code": {},
                "item_code": {},
                "name": {}
            }
        } />

        <cfreturn this>
    </cffunction>

</cfcomponent>
