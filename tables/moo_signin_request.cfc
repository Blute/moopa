<cfcomponent>

    <!---
        A passwordless sign-in: someone asks to sign in with their email, and a link
        emailed to them approves it from any device. Issued, approved and used only
        through application.lib.signin.

        status
          pending   asked for; waiting for the emailed link to be approved
          approved  approved from the emailed link; the asking browser may sign in
          denied    turned down from the emailed link ("Not me")
          used      the asking browser has signed in
        A row past expires_at is over, whatever its status.

        profile_id is empty when nobody can sign in with that email: the row is kept
        (no email is sent) so the asking page behaves the same either way and does not
        reveal which addresses have an account.

        approve_token_hash is the SHA-256 of the token in the emailed link and
        browser_token_hash of the secret held in the asking browser's session. Neither
        secret is stored.
    --->

    <cffunction name="init">

        <cfset this.definition =
        [
            "name": "moo_signin_request",
            "title": "Sign-in Request",
            "title_plural": "Sign-in Requests",
            "label_generation_expression": "email || ' ' || status",
            "searchable_fields": "email",
            "order_by": "created_at desc",

            "fields": [
                "app_name": {
                    "type": "varchar",
                    "nullable": false,
                    "html": {
                        "control": "text",
                        "label": "App"
                    }
                },
                "email": {
                    "type": "varchar",
                    "nullable": false,
                    "index": true,
                    "html": {
                        "control": "text",
                        "label": "Email"
                    }
                },
                "profile_id": {
                    "type": "uuid",
                    "nullable": true,
                    "foreign_key_table": "moo_profile",
                    "foreign_key_onDelete": "CASCADE",
                    "html": {
                        "control": "combobox",
                        "label": "Profile"
                    }
                },
                "status": {
                    "type": "varchar",
                    "nullable": false,
                    "html": {
                        "control": "text",
                        "label": "Status"
                    }
                },
                "approve_token_hash": {
                    "type": "varchar",
                    "nullable": false,
                    "html": {
                        "hidden": true
                    }
                },
                "browser_token_hash": {
                    "type": "varchar",
                    "nullable": false,
                    "html": {
                        "hidden": true
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
                "request_ip": {
                    "type": "varchar",
                    "nullable": true,
                    "html": {
                        "control": "text",
                        "label": "Request IP"
                    }
                },
                "request_user_agent": {
                    "type": "text",
                    "nullable": true,
                    "html": {
                        "control": "textarea",
                        "label": "Request User Agent"
                    }
                },
                "request_place": {
                    "type": "varchar",
                    "nullable": true,
                    "html": {
                        "control": "text",
                        "label": "Request Place"
                    }
                },
                "decided_at": {
                    "type": "timestamptz",
                    "nullable": true,
                    "html": {
                        "control": "datetime",
                        "label": "Approved or Declined At"
                    }
                },
                "decide_ip": {
                    "type": "varchar",
                    "nullable": true,
                    "html": {
                        "control": "text",
                        "label": "Approved or Declined From IP"
                    }
                },
                "decide_user_agent": {
                    "type": "text",
                    "nullable": true,
                    "html": {
                        "control": "textarea",
                        "label": "Approved or Declined User Agent"
                    }
                },
                "used_at": {
                    "type": "timestamptz",
                    "nullable": true,
                    "html": {
                        "control": "datetime",
                        "label": "Signed In At"
                    }
                }
            ],

            "indexes": [
                "idx_moo_signin_request_approve_token_hash": {
                    "type": "btree",
                    "fields": "approve_token_hash",
                    "unique": true
                }
            ]
        ]

        />

        <cfreturn this>
    </cffunction>

</cfcomponent>
