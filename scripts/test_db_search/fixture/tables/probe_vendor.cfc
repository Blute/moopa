<cfcomponent>

    <!--- Fixture for scripts/test_db_search.sh: a linked table whose expand_fields lets only name
          (plus id, always) through an expanded link; email and notes stay out. --->
    <cffunction name="init">

        <cfset this.definition = {
            "title": "Probe vendor",
            "label_generation_expression": "COALESCE(name::text, id::text)",
            "order_by": "name asc",
            "expand_fields": "name",
            "fields": {
                "name": {},
                "email": {},
                "notes": { "type": "text" }
            }
        } />

        <cfreturn this>
    </cffunction>

</cfcomponent>
