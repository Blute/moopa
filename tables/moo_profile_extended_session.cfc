<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "title": "Profile Extended Login",
            "item_label_template": "`${item.name}`",
            "fields": {
                "profile_id": {
                    "type": "uuid",
                    "foreign_key_table": "moo_profile",
                    "foreign_key_field": "id",
                    "foreign_key_onDelete" : "CASCADE"
                },
                "device_id":{
                    "index":true
                },
                "expiration": {
                    "type": "timestamptz"
                }

            }
          }

        />

        <cfreturn this>
    </cffunction>

</cfcomponent>
