<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "title": "Signed-in device",
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
                },
                <!--- What and where the device was when it signed in: Sign-in activity lists the devices --->
                "user_agent": {
                    "type": "text",
                    "nullable": true
                },
                "place": {
                    "type": "varchar",
                    "nullable": true
                }

            }
          }

        />

        <cfreturn this>
    </cffunction>

</cfcomponent>
