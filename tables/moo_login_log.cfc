<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "title": "Login Log",
            "title_plural": "Login Logs",
            "item_label_template": "`${item.mobile}`",
            "label_generation_expression": "COALESCE(mobile::text, id::text)",
            "order_by": "created_at desc",
            "searchable_fields": "mobile",
            "fields": {
                "mobile": {},
                "status": {},
                "stay_logged_in": {"type":"bool", "default": false},
                "auto_login": {"type":"bool", "default": false}
            },
            "indexes": [
              "idx_moo_login_log_find": {
                "type": "btree",
                "fields": "mobile,status",
                "unique": false
              },
              "idx_moo_login_log_created_at": {
                "type": "btree",
                "fields": "created_at",
                "unique": false
              }
            ]
          }

        />

        <cfreturn this>
    </cffunction>

</cfcomponent>
