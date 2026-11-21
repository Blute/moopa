<cfcomponent displayname="published_files" output="false"
    hint="Files published at a fixed address on one of the project's own sites, such as /datasheets/product.pdf on its public website, answered there without a signature by the signed assets Worker (docs/object-storage.md: Published files). publish() copies a stored file (a moo_file's path) inside the default store to public/<site>/<address>; publishing again at the same address replaces it, so the address never changes. unpublish() removes it. The copy is the project's to remove: deleting the original leaves it published. publish() and unpublish() keep no record of their own: what is under public/ is what is published. A table definition can instead declare that a file field's files are published (publish: { site, address, when }); db.save and db.delete then keep them in step (syncRecord), recorded in moo_published_file. Nothing here runs unless a project publishes.">

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
        <cfif left(under, 1) NEQ "/" OR reFind("[^A-Za-z0-9._/-]", under) OR reFind("(^|/)\.\.?(/|$)", under) OR find("//", under)>
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

    <!--- ===============================================================================================================
          Publishing a table's files (docs/object-storage.md: Publishing a table's files). A many_to_many field of
          moo_file can declare publish: { site, address, when } in its table definition; db.save and db.delete then call
          syncRecord, and syncAll does every record. moo_published_file records what is published where.
          =============================================================================================================== --->

    <cffunction name="syncRecord" access="public" returntype="struct" output="false"
        hint="Puts one record's published files in step with it: publishes what its publishing fields should have published (new or replaced files), and unpublishes what they no longer should (a removed file, a changed address, publish.when false, the record deleted). Copies only what changed. Returns { published, unpublished, kept }. db.save and db.delete call it.">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfset var result = {} />
        <cflock name="moopa_published_files" type="exclusive" timeout="120">
            <cfset result = reconcileRecord(arguments.table_name, arguments.id) />
        </cflock>
        <cfreturn result />
    </cffunction>

    <cffunction name="syncAll" access="public" returntype="struct" output="false"
        hint="syncRecord for every record of every table that publishes files, then unpublishes what a deleted record or a field that no longer publishes left behind. Returns the totals { published, unpublished, kept }. For the first publishing of existing records, and on a schedule, to catch up after a failure.">
        <cfset var totals = { "published": 0, "unpublished": 0, "kept": 0 } />
        <cfset var publishing = application.lib.db.getPublishing() />
        <cfset var tableName = "" />
        <cfset var q = "" />

        <cflock name="moopa_published_files" type="exclusive" timeout="600">
            <cfloop collection="#publishing#" item="tableName">
                <cfquery name="q">
                    SELECT id::text AS id FROM #tableName#
                </cfquery>
                <cfloop query="q">
                    <cfset addTotals(totals, reconcileRecord(tableName, q.id)) />
                </cfloop>
            </cfloop>
            <!--- Rows no record or field accounts for any more. --->
            <cfif tableExists()>
                <cfquery name="q">
                    SELECT DISTINCT table_name, record_id::text AS record_id FROM moo_published_file
                </cfquery>
                <cfloop query="q">
                    <cfif NOT structKeyExists(publishing, q.table_name) OR NOT recordExists(q.table_name, q.record_id)>
                        <cfset addTotals(totals, reconcileRecord(q.table_name, q.record_id)) />
                    </cfif>
                </cfloop>
            </cfif>
        </cflock>
        <cfreturn totals />
    </cffunction>

    <cffunction name="reconcileRecord" access="private" returntype="struct" output="false">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />

        <cfset var result = { "published": 0, "unpublished": 0, "kept": 0 } />
        <cfset var wanted = wantedFor(arguments.table_name, arguments.id) />
        <cfset var current = {} />
        <cfset var q = "" />
        <cfset var key = "" />
        <cfset var entry = {} />
        <cfset var owner = "" />

        <cfif NOT isValid("uuid", arguments.id) AND NOT isValid("guid", arguments.id)>
            <cfreturn result />
        </cfif>
        <cfquery name="q">
            SELECT object_key, site, address, path FROM moo_published_file
            WHERE table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" />
            AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
        </cfquery>
        <cfloop query="q">
            <cfset current[q.object_key] = { "site": q.site, "address": q.address, "path": q.path } />
        </cfloop>

        <!--- Gone first: pages stop linking an address (its row) before its file goes. --->
        <cfloop collection="#current#" item="key">
            <cfif NOT structKeyExists(wanted, key)>
                <cfquery>
                    DELETE FROM moo_published_file WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#key#" />
                </cfquery>
                <cfset unpublish(current[key].site, current[key].address) />
                <cfset result.unpublished++ />
            </cfif>
        </cfloop>

        <!--- New or replaced: the file is copied first, then pages may link it (its row). --->
        <cfloop collection="#wanted#" item="key">
            <cfset entry = wanted[key] />
            <cfif structKeyExists(current, key) AND compare(current[key].path, entry.path) EQ 0>
                <cfset result.kept++ />
                <cfcontinue />
            </cfif>
            <!--- An address another record publishes stays that record's: the first to publish it keeps it. --->
            <cfquery name="owner">
                SELECT table_name, record_id::text AS record_id FROM moo_published_file
                WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#key#" />
            </cfquery>
            <cfif owner.recordCount AND (compare(owner.table_name, arguments.table_name) NEQ 0 OR compare(owner.record_id, lCase(arguments.id)) NEQ 0)>
                <cfcontinue />
            </cfif>
            <cfset publish(entry.site, entry.address, entry.path) />
            <cfquery>
                INSERT INTO moo_published_file (object_key, site, address, table_name, record_id, field, moo_file_id, path)
                VALUES (
                    <cfqueryparam cfsqltype="varchar" value="#key#" />,
                    <cfqueryparam cfsqltype="varchar" value="#entry.site#" />,
                    <cfqueryparam cfsqltype="varchar" value="#entry.address#" />,
                    <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" />,
                    <cfqueryparam cfsqltype="other" value="#arguments.id#" />,
                    <cfqueryparam cfsqltype="varchar" value="#entry.field#" />,
                    <cfqueryparam cfsqltype="other" value="#entry.file_id#" />,
                    <cfqueryparam cfsqltype="varchar" value="#entry.path#" />
                )
                ON CONFLICT (object_key) DO UPDATE SET
                    field = EXCLUDED.field, moo_file_id = EXCLUDED.moo_file_id, path = EXCLUDED.path
            </cfquery>
            <cfset result.published++ />
        </cfloop>

        <cfreturn result />
    </cffunction>

    <!--- What a record's publishing fields should have published, by store key: { site, address, field, file_id, path }.
          Nothing for a record that is gone, or whose publish.when is not true. --->
    <cffunction name="wantedFor" access="private" returntype="struct" output="false">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />

        <cfset var wanted = {} />
        <cfset var fields = application.lib.db.getPublishing()[arguments.table_name] ?: {} />
        <cfset var fieldName = "" />
        <cfset var setting = {} />
        <cfset var q = "" />
        <cfset var files = "" />
        <cfset var record = {} />
        <cfset var address = "" />
        <cfset var candidate = "" />
        <cfset var key = "" />
        <cfset var n = 0 />
        <cfset var taken = {} />

        <cfif structIsEmpty(fields) OR (NOT isValid("uuid", arguments.id) AND NOT isValid("guid", arguments.id))>
            <cfreturn wanted />
        </cfif>
        <cfquery name="q">
            SELECT row_to_json(record)::text AS data FROM #arguments.table_name# AS record
            WHERE id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
        </cfquery>
        <cfif NOT q.recordCount>
            <cfreturn wanted />
        </cfif>
        <cfset record = deserializeJSON(q.data) />

        <cfloop collection="#fields#" item="fieldName">
            <cfset setting = fields[fieldName] />
            <cfif len(setting.when) AND NOT (isBoolean(record[setting.when] ?: "") AND record[setting.when])>
                <cfcontinue />
            </cfif>
            <cfquery name="files">
                SELECT moo_file.id::text AS file_id, moo_file.name, moo_file.path
                FROM #setting.bridge# AS bridge
                JOIN moo_file ON moo_file.id = bridge.foreign_id
                WHERE bridge.primary_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
                ORDER BY bridge.sequence
            </cfquery>
            <cfloop query="files">
                <cfif NOT len(files.path)>
                    <cfcontinue />
                </cfif>
                <cfset address = addressFor(setting.address, record, files.name) />
                <cfif NOT len(address)>
                    <cfcontinue />
                </cfif>
                <!--- Two files of one record at one address: the later ones get -2, -3 before the extension. --->
                <cfset candidate = address />
                <cfset n = 1 />
                <cfloop condition="structKeyExists(taken, candidate)">
                    <cfset n++ />
                    <cfset candidate = numbered(address, n) />
                </cfloop>
                <cfif setting.first AND n GT 1>
                    <cfbreak />
                </cfif>
                <!--- A filled-in address that isn't one (too long, say) is skipped. --->
                <cftry>
                    <cfset key = objectKey(setting.site, candidate) />
                    <cfcatch type="published_files.invalid">
                        <cfset key = "" />
                    </cfcatch>
                </cftry>
                <cfif NOT len(key)>
                    <cfcontinue />
                </cfif>
                <cfset taken[candidate] = true />
                <cfset wanted[key] = { "site": setting.site, "address": candidate, "field": fieldName, "file_id": files.file_id, "path": files.path } />
                <cfif setting.first>
                    <cfbreak />
                </cfif>
            </cfloop>
        </cfloop>
        <cfreturn wanted />
    </cffunction>

    <!--- An address template filled in for a record and a file: {field} is the record's value, {name} the file's name
          without its extension, made readable (lowercase, dashes: "Front View (2)" is front-view-2), {ext} its
          extension in lowercase. "" when a placeholder comes out empty. --->
    <cffunction name="addressFor" access="public" returntype="string" output="false"
        hint="A publish.address template filled in for a record (a struct of its columns) and a file name: {field} is the record's value and {name} the file's name without its extension, both made readable (lowercase letters and digits, dashes between: 'Front View (2)' is front-view-2); {ext} is the file's extension in lowercase. Empty when any placeholder comes out empty.">
        <cfargument name="template" type="string" required="true" />
        <cfargument name="record" type="struct" required="true" />
        <cfargument name="fileName" type="string" required="true" />

        <cfset var address = arguments.template />
        <cfset var placeholder = "" />
        <cfset var name = "" />
        <cfset var value = "" />
        <cfset var hasExtension = reFind("\.[A-Za-z0-9]+$", arguments.fileName) GT 0 />

        <cfloop array="#reMatch('\{[a-z_][a-z0-9_]*\}', arguments.template)#" item="placeholder">
            <cfset name = mid(placeholder, 2, len(placeholder) - 2) />
            <cfif name EQ "ext">
                <cfset value = hasExtension ? lCase(listLast(arguments.fileName, ".")) : "" />
            <cfelseif name EQ "name">
                <cfset value = readable(hasExtension ? reReplace(arguments.fileName, "\.[A-Za-z0-9]+$", "") : arguments.fileName) />
            <cfelse>
                <cfset value = arguments.record[name] ?: "" />
                <cfset value = isSimpleValue(value) ? readable(value) : "" />
            </cfif>
            <cfif NOT len(value)>
                <cfreturn "" />
            </cfif>
            <cfset address = replace(address, placeholder, value, "all") />
        </cfloop>
        <cfreturn address />
    </cffunction>

    <cffunction name="readable" access="private" returntype="string" output="false">
        <cfargument name="value" type="string" required="true" />
        <cfset var text = reReplace(lCase(trim(arguments.value)), "[^a-z0-9]+", "-", "all") />
        <cfreturn left(reReplace(text, "^-+|-+$", "", "all"), 120) />
    </cffunction>

    <!--- /images/x/front.jpg numbered 2 is /images/x/front-2.jpg; without an extension, -2 goes on the end. --->
    <cffunction name="numbered" access="private" returntype="string" output="false">
        <cfargument name="address" type="string" required="true" />
        <cfargument name="n" type="numeric" required="true" />
        <cfset var last = listLast(arguments.address, "/") />
        <cfset var head = left(arguments.address, len(arguments.address) - len(last)) />
        <cfif find(".", last) GT 1>
            <cfreturn head & reReplace(last, "\.([^.]*)$", "-#arguments.n#.\1") />
        </cfif>
        <cfreturn arguments.address & "-" & arguments.n />
    </cffunction>

    <cffunction name="addTotals" access="private" returntype="void" output="false">
        <cfargument name="totals" type="struct" required="true" />
        <cfargument name="one" type="struct" required="true" />
        <cfset arguments.totals.published += arguments.one.published />
        <cfset arguments.totals.unpublished += arguments.one.unpublished />
        <cfset arguments.totals.kept += arguments.one.kept />
    </cffunction>

    <cffunction name="tableExists" access="private" returntype="boolean" output="false">
        <cfreturn structKeyExists(application.lib.db.codeSchema, "moo_published_file") />
    </cffunction>

    <cffunction name="recordExists" access="private" returntype="boolean" output="false">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfset var q = "" />
        <cfif NOT structKeyExists(application.lib.db.codeSchema, arguments.table_name)>
            <cfreturn false />
        </cfif>
        <cfquery name="q">
            SELECT 1 FROM #arguments.table_name# WHERE id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
        </cfquery>
        <cfreturn q.recordCount GT 0 />
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
