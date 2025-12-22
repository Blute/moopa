<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "title": "File",
            "title_plural": "Files",
            "item_label_template": "`${item.path}`",
            "label_generation_expression": "COALESCE(path::text, id::text)",
            "searchable_fields": "path",
            "fields": {
                "name": {},
                "size": { "type" : "int8" },
                "path": {},
                "thumbnail": {},
                "temp_upload_link": {},
                "metadata": { "type":"jsonb" }
            }
          }

        />

        <cfreturn this>
    </cffunction>

</cfcomponent>
