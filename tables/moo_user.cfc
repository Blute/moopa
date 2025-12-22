<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        [
            "title": "User",
            "title_plural": "Users",

            "label_generation_expression": "COALESCE(email::text, id::text)",
            "fields": [
              "username": {},
              "full_name": {},
              "authentication_service": {},
              "profile_id": {
                "type": "uuid",
                "nullable": true,
                "foreign_key_table": "moo_profile"
              },
              "email": {
                "html": {
                  "type": "email",
                  "label": "Email"
                }
              },
              "password": {
                "type": "varchar",
                "max_length": 255,
                "nullable": false,
                "html": {
                  "type": "password"
                }
              },
              "is_active": {
                "type": "bool",
                "default": true
              },
              "last_login": {
                "type": "timestamptz",
                "nullable": true
              }
            ],


            "indexes": [
              "idx_moo_user_find": {
                "type": "btree",
                "fields": "username,authentication_service",
                "unique": true
              }
            ]
          ]

        />

        <cfreturn this>
    </cffunction>

</cfcomponent>
