<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "title": "Permission",
            "title_plural": "Permissions",
            "order_by": "role_id",
            "fields": {
                "route_id": {
                    "type": "uuid",
                    "foreign_key_table": "moo_route",
                    "foreign_key_field": "id",
                    "foreign_key_onDelete" : "CASCADE"
                },
                "endpoint_id": {
                    "type": "uuid",
                    "nullable": true,
                    "foreign_key_table": "moo_route_endpoint",
                    "foreign_key_field": "id",
                    "foreign_key_onDelete" : "CASCADE"
                },
                "role_id": {
                    "type": "uuid",
                    "foreign_key_table": "moo_role",
                    "foreign_key_field": "id",
                    "foreign_key_onDelete" : "CASCADE"
                },
                "profile_id": {
                    "type": "uuid",
                    "foreign_key_table": "moo_profile",
                    "foreign_key_field": "id",
                    "foreign_key_onDelete" : "CASCADE"
                },
                "is_granted": {
                    "type": "bool",
                    "default": false
                }
            }
        }/>

        <cfreturn this>
    </cffunction>

</cfcomponent>
