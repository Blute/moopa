<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "title": "SAAS API Connection",
            "title_plural": "SAAS API Connections",
            "item_label_template": "`${item.name}`",
            "label_generation_expression": "COALESCE(name::text || '(' || key::text || ')', id::text)",
            "order_by": "name asc",
            "searchable_fields": "name",
            "fields": {
                "name": {},
                "key": { "index": true },
                "json_token": { "type" : "jsonb" }
            }
          }

        />

        <cfreturn this>
    </cffunction>

</cfcomponent>
