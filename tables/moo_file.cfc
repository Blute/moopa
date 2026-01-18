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
        Sanitizes a filename for safe use as an S3 object key.
        Removes or replaces characters that could cause issues per AWS S3 documentation.
    --->
    <cffunction name="sanitize_s3_key" access="public" returntype="string">
        <cfargument name="filename" type="string" required="true" />

        <cfset sanitized = arguments.filename />

        <!--- Characters to avoid: \ { } ^ % ` ] " > [ ~ < # | --->
        <cfset sanitized = reReplace(sanitized, '[\\{}\^%`\]"><\[~##\|]', '_', 'all') />

        <!--- Characters that require special handling: & $ @ = ; : + , ? / --->
        <cfset sanitized = reReplace(sanitized, '[&\$@=;:\+,\?/]', '_', 'all') />

        <!--- Replace whitespace with underscore --->
        <cfset sanitized = reReplace(sanitized, '\s+', '_', 'all') />

        <!--- Replace ASCII control characters (00-1F hex and 7F) --->
        <cfset sanitized = reReplace(sanitized, '[\x00-\x1F\x7F]', '_', 'all') />

        <!--- Replace non-printable ASCII (128-255 decimal) --->
        <cfset sanitized = reReplace(sanitized, '[\x80-\xFF]', '_', 'all') />

        <!--- Collapse multiple underscores into one --->
        <cfset sanitized = reReplace(sanitized, '_+', '_', 'all') />

        <!--- Trim leading/trailing underscores --->
        <cfset sanitized = reReplace(sanitized, '^_+|_+$', '', 'all') />

        <!--- If filename is now empty (edge case), generate a fallback --->
        <cfif not len(sanitized)>
            <cfset sanitized = 'file' />
        </cfif>

        <cfreturn sanitized />
    </cffunction>


    <!---
    <cfreturn application.lib.db.getService(table_name="moo_file").uploadFileToServerWithProgress(request.data) />
     --->
    <cffunction name="uploadFileToServerWithProgress">

        <cfargument name="data" type="struct" required="true" />


        <!--- Calling without the ID will generate the record for us to the call the function again sending the actual file --->
        <cfif !len(arguments.data.file_id?:'')>

            <cfset res = {} />

            <cfset file_extension = listLast(arguments.data.file_name,".") />

            <cfset safe_filename = sanitize_s3_key(arguments.data.file_name) />
            <cfset new_path = "/moo_file/#dateFormat(now(),'yyyy-mm')#/#createUniqueId()#/#safe_filename#" />
            <cfset new_thumbnail = application.lib.imagekit.url(file_path='/icons/square-o/#file_extension#.svg', expiry=0, params={width=100, height=100}) />


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

        <cfset file_extension = listLast(new_file.name,".") />

        <cfif listFindNoCase(
            "JPG,JPEG,PNG,GIF,WEBP,SVG,TIFF,BMP,HEIF,PDF,MOV,MP4,AVI,MKV,WEBM",
            file_extension
        )>
            <cfset save_data = application.lib.db.save(
                    table_name : 'moo_file',
                    data : {
                        id : arguments.data.file_id,
                        thumbnail: application.lib.imagekit.url(file_path=new_file.path, expiry=0, params={width=300, height=300}, thumbnail=true)
                    },
                    returnAsCFML:true
                ) />


            <cfset new_file = application.lib.db.read( table_name : 'moo_file', id : arguments.data.file_id, returnAsCFML:true ) />
        </cfif>


        <cfreturn new_file>
    </cffunction>


</cfcomponent>
