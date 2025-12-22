<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "title": "Error Log",
            "title_plural": "Error Logs",
            "item_label_template": "`${item.name}`",
            "label_generation_expression": "COALESCE(message::text, id::text)",
            "order_by": "created_at desc",
            "searchable_fields": "message",
            "fields": {
                "message": {},
                "line": {},
                "tag": {},
                "exception":
                {
                    "type": "jsonb"
                },
                "cgi_scope":
                {
                    "type": "jsonb"
                },
                "form_scope":
                {
                    "type": "jsonb"
                },
                "request_scope":
                {
                    "type": "jsonb"
                },
                "url_scope":
                {
                    "type": "jsonb"
                },
                "session_scope":
                {
                    "type": "jsonb"
                },
                "current_auth":
                {
                    "type": "jsonb"
                },
            }
          }

        />

        <cfreturn this>
    </cffunction>

</cfcomponent>
