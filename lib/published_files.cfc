<cfcomponent displayname="published_files" output="false"
    hint="Files published at a fixed address on one of the project's own sites, such as /datasheets/product.pdf on its public website, answered there without a signature by the signed assets Worker (docs/object-storage.md: Published files). publish() copies a stored file (a moo_file's path) inside the default store to public/<site>/<address>; publishing again at the same address replaces it, so the address never changes. unpublish() removes it. The copy is the project's to remove: deleting the original leaves it published. The bucket is the record of what is published: there is no table, and nothing here runs unless a project calls it.">

    <!--- Every published file's key starts with this, then the site. The Worker reads the same prefix. --->
    <cfset variables.PREFIX = "public" />

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>

    <cffunction name="publish" access="public" returntype="string" output="false"
        hint="Publishes the stored file at path (a moo_file's path) at address on site, replacing whatever was published there. The copy is made inside the store (one CopyObject: up to 5 GB). Returns the address. Throws published_files.invalid for a bad site or address, and s3.request.failed when the file isn't in the store.">
        <cfargument name="site" type="string" required="true" hint="The site's name, as the Worker's PUBLIC_SITES names it for its hostname, e.g. www." />
        <cfargument name="address" type="string" required="true" hint="The path on the site, e.g. /datasheets/product.pdf: segments of letters, digits, dot, dash and underscore." />
        <cfargument name="path" type="string" required="true" hint="The stored file's key, e.g. a moo_file's path." />

        <cfset var target = objectKey(arguments.site, arguments.address) />
        <cfset var source = reReplace(trim(arguments.path), "^/+", "") />
        <cfif NOT len(source)>
            <cfthrow type="published_files.invalid" message="published_files: publish needs the stored file's path" />
        </cfif>
        <!--- Keys are case-sensitive; EQ is not. Publishing a published file at its own address copies nothing, but it
              must be there. --->
        <cfif compare(source, target) EQ 0>
            <cfif NOT application.lib.s3_client.objectExists(application.lib.s3_client.defaultStore(), source)>
                <cfthrow type="s3.request.failed" message="published_files: nothing is stored at #source#" />
            </cfif>
            <cfreturn normalAddress(arguments.address) />
        </cfif>
        <cfset application.lib.s3_client.copyObject(application.lib.s3_client.defaultStore(), source, target) />
        <cfreturn normalAddress(arguments.address) />
    </cffunction>

    <cffunction name="unpublish" access="public" returntype="void" output="false"
        hint="Removes the file published at address on site. Removing an address with nothing published succeeds. The Worker and browsers may answer their copy for a few minutes more (it is kept for five).">
        <cfargument name="site" type="string" required="true" />
        <cfargument name="address" type="string" required="true" />
        <cfset application.lib.s3_client.deleteObject(application.lib.s3_client.defaultStore(), objectKey(arguments.site, arguments.address)) />
    </cffunction>

    <cffunction name="isPublished" access="public" returntype="boolean" output="false"
        hint="Whether a file is published at address on site, asking the store.">
        <cfargument name="site" type="string" required="true" />
        <cfargument name="address" type="string" required="true" />
        <cfreturn application.lib.s3_client.objectExists(application.lib.s3_client.defaultStore(), objectKey(arguments.site, arguments.address)) />
    </cffunction>

    <cffunction name="list" access="public" returntype="array" output="false"
        hint="What is published on site, under an address prefix when one is given (e.g. /datasheets/): [{ address, size, last_modified }].">
        <cfargument name="site" type="string" required="true" />
        <cfargument name="under" type="string" required="false" default="/" hint="An address prefix, starting with /." />

        <cfset var sitePrefix = sitePrefixFor(arguments.site) />
        <cfset var under = trim(arguments.under) />
        <cfif left(under, 1) NEQ "/" OR find("..", under) OR reFind("[^A-Za-z0-9._/-]", under)>
            <cfthrow type="published_files.invalid" message="published_files: list's under must be an address prefix starting with /, not '#arguments.under#'" />
        </cfif>
        <cfset var found = [] />
        <cfloop array="#application.lib.s3_client.listObjects(application.lib.s3_client.defaultStore(), sitePrefix & mid(under, 2, len(under)))#" item="local.object">
            <cfset arrayAppend(found, {
                "address": "/" & mid(local.object.key, len(sitePrefix) + 1, len(local.object.key)),
                "size": local.object.size,
                "last_modified": local.object.last_modified
            }) />
        </cfloop>
        <cfreturn found />
    </cffunction>

    <cffunction name="objectKey" access="public" returntype="string" output="false"
        hint="The store key a published address is kept at: public/<site>/<address without its leading slash>. Throws published_files.invalid for a bad site or address.">
        <cfargument name="site" type="string" required="true" />
        <cfargument name="address" type="string" required="true" />
        <cfset var address = normalAddress(arguments.address) />
        <cfset var key = sitePrefixFor(arguments.site) & mid(address, 2, len(address)) />
        <cfif len(key) GT 1024>
            <cfthrow type="published_files.invalid" message="published_files: '#left(arguments.address, 100)#…' is too long (a key is at most 1024 bytes)" />
        </cfif>
        <cfreturn key />
    </cffunction>

    <!--- public/<site>/, for a site name the Worker accepts: lowercase letters, digits and dashes. --->
    <cffunction name="sitePrefixFor" access="private" returntype="string" output="false">
        <cfargument name="site" type="string" required="true" />
        <!--- A whole-string character check first: on Lucee, $ also matches before a trailing newline. --->
        <cfif reFind("[^a-z0-9-]", arguments.site) OR NOT reFind("^[a-z0-9][a-z0-9-]{0,62}$", arguments.site)>
            <cfthrow type="published_files.invalid" message="published_files: '#arguments.site#' is not a site name (lowercase letters, digits and dashes)" />
        </cfif>
        <cfreturn variables.PREFIX & "/" & arguments.site & "/" />
    </cffunction>

    <!--- An address the Worker can answer, as given, or throws: a leading slash, then segments of letters, digits, dot,
          dash and underscore, none empty, "." or "..". The same rule as the Worker's publishedAddress(). --->
    <cffunction name="normalAddress" access="private" returntype="string" output="false">
        <cfargument name="address" type="string" required="true" />
        <cfset var address = trim(arguments.address) />
        <cfset var segment = "" />
        <cfif left(address, 1) NEQ "/" OR len(address) LT 2>
            <cfthrow type="published_files.invalid" message="published_files: an address starts with / and names a file, not '#arguments.address#'" />
        </cfif>
        <!--- A whole-string character check first: on Lucee, $ also matches before a trailing newline. --->
        <cfif reFind("[^A-Za-z0-9._/-]", address)>
            <cfthrow type="published_files.invalid" message="published_files: '#arguments.address#' is not an address (letters, digits, dot, dash, underscore and /)" />
        </cfif>
        <cfif find("//", address) OR right(address, 1) EQ "/">
            <cfthrow type="published_files.invalid" message="published_files: '#arguments.address#' is not an address (an empty segment, or no file name)" />
        </cfif>
        <cfloop list="#mid(address, 2, len(address))#" delimiters="/" item="segment">
            <cfif NOT reFind("^[A-Za-z0-9._-]{1,200}$", segment) OR segment EQ "." OR segment EQ "..">
                <cfthrow type="published_files.invalid" message="published_files: '#arguments.address#' is not an address (segments of letters, digits, dot, dash and underscore)" />
            </cfif>
        </cfloop>
        <cfreturn address />
    </cffunction>

</cfcomponent>
