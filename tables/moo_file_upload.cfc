<cfcomponent>

    <!---
        An upload under way: a moo_file whose bytes the browser was given a presigned URL to PUT, and which
        application.lib.file_upload hasn't yet checked and finished. Written and read only through that lib.

        owner is whatever the caller vouches the upload belongs to (a profile, or a record the visitor owns): only an
        ask naming the same owner may finish or discard it. content_type and size are what the URL was signed for, so
        what the store holds must match them. A row left here past a day is an abandoned upload, which the lib's
        sweep() removes with its file and object.
    --->

    <cffunction name="init">

        <cfset this.definition =
        [
            "name": "moo_file_upload",
            "title": "File Upload",
            "title_plural": "File Uploads",
            "label_generation_expression": "'upload ' || id::text",
            "searchable_fields": "",
            "order_by": "created_at desc",

            "fields": [
                "file_id": {
                    "type": "uuid",
                    "nullable": false,
                    "foreign_key_table": "moo_file",
                    "foreign_key_onDelete": "CASCADE",
                    "html": {
                        "control": "combobox",
                        "label": "File"
                    }
                },
                "owner": {
                    "type": "varchar",
                    "nullable": false,
                    "index": true,
                    "html": {
                        "control": "text",
                        "label": "Owner"
                    }
                },
                "content_type": {
                    "type": "varchar",
                    "nullable": false,
                    "html": {
                        "control": "text",
                        "label": "Content Type"
                    }
                },
                "size": {
                    "type": "int8",
                    "nullable": false,
                    "html": {
                        "control": "number",
                        "label": "Size"
                    }
                }
            ],

            "indexes": [
                "idx_moo_file_upload_file_id": {
                    "type": "btree",
                    "fields": "file_id",
                    "unique": true
                },
                "idx_moo_file_upload_created_at": {
                    "type": "btree",
                    "fields": "created_at"
                }
            ]
        ]

        />

        <cfreturn this>
    </cffunction>

</cfcomponent>
