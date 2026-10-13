<cfcomponent>

    <!---
        A single-use, short-lived grant that signs a browser in as target_profile_id.
        Issued and consumed only through application.lib.login_grant.

        kind says what the grant is for. The framework defines one kind:
          impersonation  a user signs in as someone else; impersonator_profile_id is who
        A project may issue grants of its own kinds (lower-case slugs); those never have
        an impersonator.

        The token is a live credential until used or expired: it is never part of the
        label, and its field is hidden.

        Invariant (enforced by lib.login_grant; a project may also add it as a CHECK
        constraint, which table definitions can't express):
          impersonator_profile_id is set exactly when kind = 'impersonation'
    --->

    <cffunction name="init">

        <cfset this.definition =
        [
            "name": "moo_login_grant",
            "title": "Login Grant",
            "title_plural": "Login Grants",
            "label_generation_expression": "kind::text || ' grant ' || id::text",
            "searchable_fields": "",
            "order_by": "created_at desc",

            "fields": [
                "kind": {
                    "type": "varchar",
                    "nullable": false,
                    "html": {
                        "control": "text",
                        "label": "Kind"
                    }
                },
                "token": {
                    "type": "varchar",
                    "nullable": false,
                    "html": {
                        "hidden": true
                    }
                },
                "target_profile_id": {
                    "type": "uuid",
                    "nullable": false,
                    "foreign_key_table": "moo_profile",
                    "foreign_key_onDelete": "CASCADE",
                    "html": {
                        "control": "combobox",
                        "label": "Target Profile"
                    }
                },
                "impersonator_profile_id": {
                    "type": "uuid",
                    "nullable": true,
                    "foreign_key_table": "moo_profile",
                    "foreign_key_onDelete": "CASCADE",
                    "html": {
                        "control": "combobox",
                        "label": "Impersonator Profile"
                    }
                },
                "expires_at": {
                    "type": "timestamptz",
                    "nullable": false,
                    "index": true,
                    "html": {
                        "control": "datetime",
                        "label": "Expires At"
                    }
                },
                "consumed_at": {
                    "type": "timestamptz",
                    "nullable": true,
                    "html": {
                        "control": "datetime",
                        "label": "Consumed At"
                    }
                },
                "request_ip": {
                    "type": "varchar",
                    "nullable": true,
                    "html": {
                        "control": "text",
                        "label": "Request IP"
                    }
                },
                "consume_ip": {
                    "type": "varchar",
                    "nullable": true,
                    "html": {
                        "control": "text",
                        "label": "Consume IP"
                    }
                },
                "user_agent": {
                    "type": "text",
                    "nullable": true,
                    "html": {
                        "control": "textarea",
                        "label": "User Agent"
                    }
                }
            ],

            "indexes": [
                "idx_moo_login_grant_token": {
                    "type": "btree",
                    "fields": "token",
                    "unique": true
                }
            ]
        ]

        />

        <cfreturn this>
    </cffunction>

</cfcomponent>
