<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "title": "Role",
            "title_plural": "Roles",
            "item_label_template": "`${item.name}`",
            "label_generation_expression": "COALESCE(name::text, id::text)",
            "order_by": "name asc",
            "searchable_fields": "name",
            "fields": {
                "name": {}
            }
          }

        />

        <cfreturn this>
    </cffunction>

</cfcomponent>
