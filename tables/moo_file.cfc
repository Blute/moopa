<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "title": "File",
            "title_plural": "Files",
            "item_label_template": "`${item.path}`",
            "fields": {
                "name": { "condensed": true },
                "size": { "type" : "int8", "condensed": true },
                "path": { "max_length": 2048, "condensed": true },
                "thumbnail": { "max_length": 2048, "condensed": true },
                "temp_upload_link": {},
                "metadata": { "type":"jsonb" }
            }
          }

        />

        <cfreturn this>
    </cffunction>

    <!--- Files are uploaded through application.lib.file_upload (start, finish), which checks them at both ends. --->

</cfcomponent>
