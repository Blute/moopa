<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "name": "moo_profile_auth",
            "title": "Profile Auth Identity",
            "title_plural": "Profile Auth Identities",
            "item_label_template": "`${item.provider}: ${item.provider_subject}`",
            "label_generation_expression": "COALESCE(provider::text, '') || ': ' || COALESCE(provider_subject::text, id::text)",
            "fields": {
                "app_name": {
                    "type": "varchar",
                    "searchable": true
                },
                "profile_id": {
                    "type": "uuid",
                    "foreign_key_table": "moo_profile",
                    "foreign_key_onDelete": "CASCADE"
                },
                "provider": {
                    "type": "varchar",
                    "searchable": true
                },
                "provider_subject": {
                    "type": "varchar",
                    "searchable": true
                },
                "provider_payload": {
                    "type": "jsonb",
                    "html": {
                        "hidden": true
                    }
                },
                "secret_payload": {
                    "type": "jsonb",
                    "html": {
                        "hidden": true
                    }
                },
                "last_login_at": {
                    "type": "timestamptz",
                    "nullable": true,
                    "html": {
                        "type": "datetime"
                    }
                }
            },
            "indexes": {
                "idx_moo_profile_auth_identity": {
                    "type": "btree",
                    "fields": "app_name,provider,provider_subject",
                    "unique": true
                },
                "idx_moo_profile_auth_profile": {
                    "type": "btree",
                    "fields": "profile_id"
                }
            }
        }
        />

        <cfreturn this>
    </cffunction>

</cfcomponent>
