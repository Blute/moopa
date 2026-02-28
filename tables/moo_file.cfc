<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "title": "File",
            "title_plural": "Files",
            "item_label_template": "`${item.path}`",
            "fields": {
                "name": {},
                "size": { "type" : "int8" },
                "path": { "max_length": 2048 },
                "thumbnail": { "max_length": 2048 },
                "temp_upload_link": {},
                "metadata": { "type":"jsonb" }
            }
          }

        />

        <cfreturn this>
    </cffunction>





    <!---
    <cfreturn application.lib.db.getService(table_name="moo_file").uploadFileToServerWithProgress(request.data) />
     --->
    <cffunction name="uploadFileToServerWithProgress">

        <cfargument name="data" type="struct" required="true" />


        <!--- Calling without the ID will generate the record for us to the call the function again sending the actual file --->
        <cfif !len(arguments.data.file_id?:'')>

            <cfset res = {} />

            <cfset file_extension = lCase(listLast(arguments.data.file_name,".")) />
            <cfif !listFindNoCase("JPG,JPEG,PNG,GIF,WEBP,SVG,TIFF,BMP,HEIF,PDF,MOV,MP4,AVI,MKV,WEBM", file_extension)>
                <cfset file_extension = "default" />
            </cfif>

            <cfset safe_filename = application.lib.core.sanitize_s3_key(arguments.data.file_name) />
            <cfset new_path = "/moo_file/#dateFormat(now(),'yyyy-mm')#/#createUniqueId()#/#safe_filename#" />
            <cfset new_thumbnail = '/_static/icons/fa/#file_extension#.svg' />


            <cfset new_file = application.lib.db.save(
                table_name : 'moo_file',
                data : {
                    name : arguments.data.file_name,
                    size : arguments.data.file_size,
                    thumbnail: new_thumbnail,
                    path : new_path
                },
                returnAsCFML:true
            ) />
            <cfset res.file = application.lib.db.read( table_name : 'moo_file', id : new_file.id, returnAsCFML=true ) />


            <cfset res.presignedURL = s3generatePresignedUrl(
                bucket= '#server.system.environment.S3_bucket#',
                objectName = new_path,
                httpMethod = "PUT",
                expireDate = dateAdd('n', 5, now())
            ) />


            <cfreturn res />
        </cfif>


        <cfset new_file = application.lib.db.read( table_name : 'moo_file', id : arguments.data.file_id, returnAsCFML:true ) />

        <cfset file_extension = lCase(listLast(new_file.name,".")) />

        <cfif listFindNoCase(
            "JPG,JPEG,PNG,GIF,WEBP,SVG,TIFF,BMP,HEIF",
            file_extension
        )>
            <cfset thumbnail_url = application.lib.cloudflare.signed_asset_url(
                key = new_file.path,
                expiry_type = "NEVER",
                kind = "i",
                options = { width = 300, height = 300, fit = "cover" }
            ) />

            <cfset save_data = application.lib.db.save(
                    table_name : 'moo_file',
                    data : {
                        id : arguments.data.file_id,
                        thumbnail: thumbnail_url
                    },
                    returnAsCFML:true
                ) />

            <cfset new_file = application.lib.db.read( table_name : 'moo_file', id : arguments.data.file_id, returnAsCFML:true ) />
        </cfif>


        <cfreturn new_file>
    </cffunction>


</cfcomponent>
