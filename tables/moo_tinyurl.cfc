<cfcomponent>

    <cffunction name="init">

        <cfset this.definition =
        {
            "title": "Tiny URL",
            "searchable_fields": "code",
            "fields": {
                "code": { "searchable":true },
                "url": {},
            }
          }

        />

        <cfreturn this>
    </cffunction>






    <cffunction name="GenerateTinyURL" returntype="string" access="public" output="false">
        <cfargument name="redirect_url" />
        <!--- Define a string of possible characters --->
        <cfset var characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" />
        <cfset var shortIdLength = 8 />
        <cfset var code = "" />

        <!--- Generate the code by selecting random characters from the characters string --->
        <cfloop index="i" from="1" to="#shortIdLength#">
            <cfset code &= Mid(characters, RandRange(1, Len(characters)), 1) />
        </cfloop>

        <cfset save_moo_route = application.lib.db.save(
                table_name = "moo_tinyurl",
                data = {
                    code="#code#",
                    url="#redirect_url#"
                }
            ) />


        <cfreturn "https://#cgi.server_name#/t/#code#" />
    </cffunction>

    

</cfcomponent>
