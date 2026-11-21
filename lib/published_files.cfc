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
          syncRecord, and syncAll does every record and repairs the store. moo_published_file records what is published
          where.

          Each address goes through its row, whose path is its state:
            publish:   claim the row (path empty; the unique object_key decides the owner), copy, then set path and etag
            unpublish: empty the path (pages stop linking), delete the copy, then delete the row
          A failure at any step leaves the row, with an empty path, for the next sync to finish: no public copy is ever
          without its row. Every row write after the claim is guarded by the owner.
          =============================================================================================================== --->

    <cffunction name="syncRecord" access="public" returntype="struct" output="false"
        hint="Puts one record's published files in step with it: publishes what its publishing fields should have published (new or replaced files) and unpublishes what they no longer should (a removed file, a changed address, publish.when false, the record deleted), copying only what changed. Returns { published, unpublished, kept, taken, failed }: taken counts addresses another record holds, failed the addresses that failed (each logged), left for the next sync. Does nothing while moo_published_file isn't in the database yet. db.save and db.delete call it.">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfset var result = emptyResult() />
        <cfif NOT trackingTableExists() OR NOT isRecordId(arguments.id)>
            <cfreturn result />
        </cfif>
        <cflock name="moopa_published_#lCase(arguments.table_name)#_#lCase(arguments.id)#" type="exclusive" timeout="60">
            <cfset result = reconcileRecord(lCase(arguments.table_name), lCase(arguments.id)) />
        </cflock>
        <cfreturn result />
    </cffunction>

    <cffunction name="syncAll" access="public" returntype="struct" output="false"
        hint="Every publishing table's files in step with every record, and the store with moo_published_file: first what a deleted record, or a field or table that no longer publishes, left behind; then each record (syncRecord); then, under each publishing field's literal folder (/datasheets/ for /datasheets/{slug}.pdf), a copy that is missing or not the one recorded is published again, and a copy no row accounts for is deleted. A record that fails is logged and counted, and the rest go on. Returns the totals { published, unpublished, kept, taken, failed, repaired, removed }. Run it once when a table first publishes, and on a schedule.">
        <cfset var totals = emptyResult() />
        <cfset var publishing = application.lib.db.getPublishing() />
        <cfset var tableName = "" />
        <cfset var q = "" />

        <cfset totals.repaired = 0 />
        <cfset totals.removed = 0 />
        <cfif NOT trackingTableExists()>
            <cfreturn totals />
        </cfif>

        <!--- 1. Left behind: rows of a table that no longer publishes, or of a record that is gone. First, so a record
                 waiting for one of their addresses gets it in this run. --->
        <cfquery name="q">
            SELECT DISTINCT published.table_name, published.record_id::text AS record_id
            FROM moo_published_file AS published
            WHERE published.table_name NOT IN (<cfqueryparam cfsqltype="varchar" list="true" value="#listAppend(structKeyList(publishing), '-')#" />)
            <cfloop collection="#publishing#" item="tableName">
                OR (published.table_name = <cfqueryparam cfsqltype="varchar" value="#tableName#" />
                    AND NOT EXISTS (SELECT 1 FROM #tableName# AS live WHERE live.id = published.record_id))
            </cfloop>
        </cfquery>
        <cfloop query="q">
            <cfset addTotals(totals, safeSync(q.table_name, q.record_id)) />
        </cfloop>

        <!--- 2. Every record that publishes, or has published, something. --->
        <cfloop collection="#publishing#" item="tableName">
            <!--- A field without when publishes every record; otherwise only records with a when true, or with rows. Worked
                  out before the query: no method calls inside a cfquery body. --->
            <cfset local.conditions = [] />
            <cfset local.always = false />
            <cfloop collection="#publishing[tableName]#" item="local.fieldName">
                <cfif len(publishing[tableName][local.fieldName].when)>
                    <cfset arrayAppend(local.conditions, publishing[tableName][local.fieldName].when & " IS TRUE") />
                <cfelse>
                    <cfset local.always = true />
                </cfif>
            </cfloop>
            <cfquery name="q">
                SELECT id::text AS id FROM #tableName#
                <cfif NOT local.always>
                    WHERE #arrayToList(local.conditions, " OR ")# OR
                    id IN (SELECT record_id FROM moo_published_file WHERE table_name = <cfqueryparam cfsqltype="varchar" value="#tableName#" />)
                </cfif>
                ORDER BY id
            </cfquery>
            <cfloop query="q">
                <cfset addTotals(totals, safeSync(tableName, q.id)) />
            </cfloop>
        </cfloop>

        <!--- 3. The store against the rows, under each publishing field's literal folder. --->
        <cfset sweep(publishing, totals) />
        <cfreturn totals />
    </cffunction>

    <!--- syncRecord, with a failure logged and counted rather than thrown, for syncAll. --->
    <cffunction name="safeSync" access="private" returntype="struct" output="false">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfset var result = emptyResult() />
        <cftry>
            <cfset result = syncRecord(arguments.table_name, arguments.id) />
            <cfcatch>
                <cfset result.failed = 1 />
                <cfset logFailure(cfcatch, "published_files.syncAll #arguments.table_name# #arguments.id#") />
            </cfcatch>
        </cftry>
        <cfreturn result />
    </cffunction>

    <cffunction name="reconcileRecord" access="private" returntype="struct" output="false">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />

        <cfset var result = emptyResult() />
        <cfset var wanted = wantedFor(arguments.table_name, arguments.id) />
        <cfset var mine = {} />
        <cfset var q = "" />
        <cfset var slot = "" />
        <cfset var entry = {} />
        <cfset var row = {} />

        <cfquery name="q">
            SELECT object_key, site, address, path, field, moo_file_id::text AS moo_file_id FROM moo_published_file
            WHERE table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" />
            AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
        </cfquery>
        <cfloop query="q">
            <cfset mine[slotFor(q.object_key)] = { "key": q.object_key, "site": q.site, "address": q.address, "path": q.path, "field": q.field, "file_id": q.moo_file_id } />
        </cfloop>

        <!--- Gone first, so an address this record moves between its own files is free. --->
        <cfloop collection="#mine#" item="slot">
            <cfif structKeyExists(wanted, slot)>
                <cfcontinue />
            </cfif>
            <cftry>
                <cfset retire(mine[slot], arguments.table_name, arguments.id) />
                <cfset result.unpublished++ />
                <cfcatch>
                    <cfset result.failed++ />
                    <cfset logFailure(cfcatch, "published_files unpublish #mine[slot].key#") />
                </cfcatch>
            </cftry>
        </cfloop>

        <cfloop collection="#wanted#" item="slot">
            <cfset entry = wanted[slot] />
            <cfif structKeyExists(mine, slot) AND len(mine[slot].path) AND compare(mine[slot].path, entry.path) EQ 0>
                <!--- The same copy: only which file and field it is for may have changed. --->
                <cfif compare(mine[slot].file_id, entry.file_id) NEQ 0 OR compare(mine[slot].field, entry.field) NEQ 0>
                    <cfquery>
                        UPDATE moo_published_file
                        SET moo_file_id = <cfqueryparam cfsqltype="other" value="#entry.file_id#" />, field = <cfqueryparam cfsqltype="varchar" value="#entry.field#" />
                        WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#entry.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
                    </cfquery>
                </cfif>
                <cfset result.kept++ />
                <cfcontinue />
            </cfif>
            <cftry>
                <cfif placeCopy(entry, arguments.table_name, arguments.id, structKeyExists(mine, slot))>
                    <cfset result.published++ />
                <cfelse>
                    <cfset result.taken++ />
                </cfif>
                <cfcatch>
                    <cfset result.failed++ />
                    <cfset logFailure(cfcatch, "published_files publish #entry.key#") />
                </cfcatch>
            </cftry>
        </cfloop>

        <cfreturn result />
    </cffunction>

    <!--- Publishes one address for a record: claims its row (or, already this record's, empties its path), copies, then
          sets path and etag. False when another record holds the address. --->
    <cffunction name="placeCopy" access="private" returntype="boolean" output="false">
        <cfargument name="entry" type="struct" required="true" />
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfargument name="held" type="boolean" required="true" />
        <cfset var claimed = "" />
        <cfset var etag = "" />

        <cfif arguments.held>
            <cfquery>
                UPDATE moo_published_file SET path = '', last_updated_at = now()
                WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.entry.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
            </cfquery>
        <cfelse>
            <cfquery name="claimed">
                INSERT INTO moo_published_file (object_key, site, address, table_name, record_id, field, moo_file_id, path, etag)
                VALUES (
                    <cfqueryparam cfsqltype="varchar" value="#arguments.entry.key#" />,
                    <cfqueryparam cfsqltype="varchar" value="#arguments.entry.site#" />,
                    <cfqueryparam cfsqltype="varchar" value="#arguments.entry.address#" />,
                    <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" />,
                    <cfqueryparam cfsqltype="other" value="#arguments.id#" />,
                    <cfqueryparam cfsqltype="varchar" value="#arguments.entry.field#" />,
                    <cfqueryparam cfsqltype="other" value="#arguments.entry.file_id#" />,
                    '', ''
                )
                ON CONFLICT (object_key) DO NOTHING
                RETURNING object_key
            </cfquery>
            <cfif NOT claimed.recordCount>
                <!--- Another record's. --->
                <cfreturn false />
            </cfif>
        </cfif>

        <cfset etag = application.lib.s3_client.copyObject(application.lib.s3_client.defaultStore(), arguments.entry.path, arguments.entry.key) />
        <cfquery>
            UPDATE moo_published_file
            SET path = <cfqueryparam cfsqltype="varchar" value="#arguments.entry.path#" />,
                etag = <cfqueryparam cfsqltype="varchar" value="#etag#" />,
                moo_file_id = <cfqueryparam cfsqltype="other" value="#arguments.entry.file_id#" />,
                field = <cfqueryparam cfsqltype="varchar" value="#arguments.entry.field#" />,
                last_updated_at = now()
            WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.entry.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
        </cfquery>
        <cfreturn true />
    </cffunction>

    <!--- Unpublishes one of a record's addresses: empties its path, deletes the copy, then the row. --->
    <cffunction name="retire" access="private" returntype="void" output="false">
        <cfargument name="row" type="struct" required="true" />
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfquery>
            UPDATE moo_published_file SET path = '', last_updated_at = now()
            WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.row.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
        </cfquery>
        <cfset application.lib.s3_client.deleteObject(application.lib.s3_client.defaultStore(), arguments.row.key) />
        <cfquery>
            DELETE FROM moo_published_file WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.row.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
        </cfquery>
    </cffunction>

    <!--- The store against the rows, folder by folder: a row whose copy is missing, or isn't the copy it recorded (its
          etag), is published again; a copy no row accounts for is deleted. Only under a publishing field's literal folder
          (never the whole site), so a file published by hand elsewhere is left alone. --->
    <cffunction name="sweep" access="private" returntype="void" output="false">
        <cfargument name="publishing" type="struct" required="true" />
        <cfargument name="totals" type="struct" required="true" />
        <cfset var folders = {} />
        <cfset var tableName = "" />
        <cfset var fieldName = "" />
        <cfset var setting = {} />
        <cfset var prefix = "" />
        <cfset var stored = {} />
        <cfset var object = {} />
        <cfset var q = "" />
        <cfset var slot = "" />
        <cfset var store = application.lib.s3_client.defaultStore() />

        <cfloop collection="#arguments.publishing#" item="tableName">
            <cfloop collection="#arguments.publishing[tableName]#" item="fieldName">
                <cfset setting = arguments.publishing[tableName][fieldName] />
                <cfif len(setting.folder) GT 1>
                    <cfset folders[slotFor(variables.PREFIX & "/" & setting.site & setting.folder)] = variables.PREFIX & "/" & setting.site & setting.folder />
                </cfif>
            </cfloop>
        </cfloop>

        <cfloop collection="#folders#" item="local.folderSlot">
            <cfset prefix = folders[local.folderSlot] />
            <cftry>
                <cfset stored = {} />
                <cfloop array="#application.lib.s3_client.listObjects(store, prefix)#" item="object">
                    <cfset stored[slotFor(object.key)] = object />
                </cfloop>
                <cfquery name="q">
                    SELECT object_key, path, etag, table_name, record_id::text AS record_id FROM moo_published_file
                    WHERE left(object_key, <cfqueryparam cfsqltype="integer" value="#len(prefix)#" />) = <cfqueryparam cfsqltype="varchar" value="#prefix#" />
                </cfquery>
                <cfloop query="q">
                    <cfset slot = slotFor(q.object_key) />
                    <cfif len(q.path) AND (NOT structKeyExists(stored, slot) OR (len(q.etag) AND compare(stored[slot].etag, q.etag) NEQ 0))>
                        <cftry>
                            <cfset repairCopy(q.object_key, q.path, q.table_name, q.record_id) />
                            <cfset arguments.totals.repaired++ />
                            <cfcatch>
                                <cfset arguments.totals.failed++ />
                                <cfset logFailure(cfcatch, "published_files repair #q.object_key#") />
                            </cfcatch>
                        </cftry>
                    </cfif>
                    <cfset structDelete(stored, slot) />
                </cfloop>
                <!--- What is left has no row: nothing accounts for it. --->
                <cfloop collection="#stored#" item="slot">
                    <cfset application.lib.s3_client.deleteObject(store, stored[slot].key) />
                    <cfset arguments.totals.removed++ />
                </cfloop>
                <cfcatch>
                    <cfset arguments.totals.failed++ />
                    <cfset logFailure(cfcatch, "published_files sweep #prefix#") />
                </cfcatch>
            </cftry>
        </cfloop>
    </cffunction>

    <cffunction name="repairCopy" access="private" returntype="void" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfargument name="path" type="string" required="true" />
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfset var etag = "" />
        <cflock name="moopa_published_#arguments.table_name#_#arguments.id#" type="exclusive" timeout="60">
            <cfset etag = application.lib.s3_client.copyObject(application.lib.s3_client.defaultStore(), arguments.path, arguments.key) />
            <cfquery>
                UPDATE moo_published_file SET etag = <cfqueryparam cfsqltype="varchar" value="#etag#" />, last_updated_at = now()
                WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
                AND path = <cfqueryparam cfsqltype="varchar" value="#arguments.path#" />
            </cfquery>
        </cflock>
    </cffunction>

    <!--- What a record's publishing fields should have published, by slot (slotFor its store key): { key, site, address,
          field, file_id, path }. Nothing for a record that is gone, or whose publish.when is not true. Fields are taken in
          name order and files in their order, so who gets a contested address is always the same. --->
    <cffunction name="wantedFor" access="private" returntype="struct" output="false">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />

        <cfset var wanted = {} />
        <cfset var fields = application.lib.db.getPublishing()[arguments.table_name] ?: {} />
        <cfset var fieldName = "" />
        <cfset var setting = {} />
        <cfset var columns = [] />
        <cfset var column = "" />
        <cfset var q = "" />
        <cfset var files = "" />
        <cfset var record = {} />
        <cfset var address = "" />
        <cfset var candidate = "" />
        <cfset var key = "" />
        <cfset var n = 0 />

        <cfif structIsEmpty(fields)>
            <cfreturn wanted />
        </cfif>
        <cfloop collection="#fields#" item="fieldName">
            <cfloop array="#fields[fieldName].columns#" item="column">
                <cfif NOT arrayFindNoCase(columns, column)>
                    <cfset arrayAppend(columns, column) />
                </cfif>
            </cfloop>
        </cfloop>
        <!--- Only the columns the addresses and conditions use. --->
        <cfquery name="q">
            SELECT row_to_json(record)::text AS data FROM (
                SELECT id<cfloop array="#columns#" item="column">, #column#</cfloop> FROM #arguments.table_name#
                WHERE id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
            ) AS record
        </cfquery>
        <cfif NOT q.recordCount>
            <cfreturn wanted />
        </cfif>
        <cfset record = deserializeJSON(q.data) />

        <cfloop list="#listSort(structKeyList(fields), 'text')#" item="fieldName">
            <cfset setting = fields[fieldName] />
            <cfif len(setting.when) AND NOT (isBoolean(record[setting.when] ?: "") AND record[setting.when])>
                <cfcontinue />
            </cfif>
            <cfquery name="files">
                SELECT moo_file.id::text AS file_id, moo_file.name, moo_file.path
                FROM #setting.bridge# AS bridge
                JOIN moo_file ON moo_file.id = bridge.foreign_id
                WHERE bridge.primary_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
                ORDER BY bridge.sequence, moo_file.id
            </cfquery>
            <cfloop query="files">
                <cfif NOT len(files.path)>
                    <cfcontinue />
                </cfif>
                <cfset address = addressFor(setting.address, record, files.name) />
                <cfif NOT len(address)>
                    <cfcontinue />
                </cfif>
                <!--- An address this record already wants (two files of one name, say): -2, -3 before the extension. A
                      field that publishes only its first file stops instead. --->
                <cfset candidate = address />
                <cfset n = 1 />
                <cfloop condition="structKeyExists(wanted, slotFor(keyOrEmpty(setting.site, candidate)))">
                    <cfset n++ />
                    <cfset candidate = numbered(address, n) />
                </cfloop>
                <cfif setting.first AND n GT 1>
                    <cfbreak />
                </cfif>
                <cfset key = keyOrEmpty(setting.site, candidate) />
                <cfif NOT len(key)>
                    <cfcontinue />
                </cfif>
                <cfset wanted[slotFor(key)] = { "key": key, "site": setting.site, "address": candidate, "field": fieldName, "file_id": files.file_id, "path": files.path } />
                <cfif setting.first>
                    <cfbreak />
                </cfif>
            </cfloop>
        </cfloop>
        <cfreturn wanted />
    </cffunction>

    <!--- objectKey(), or "" for an address that can't be one (too long, say). --->
    <cffunction name="keyOrEmpty" access="private" returntype="string" output="false">
        <cfargument name="site" type="string" required="true" />
        <cfargument name="address" type="string" required="true" />
        <cfset var key = "" />
        <cftry>
            <cfset key = objectKey(arguments.site, arguments.address) />
            <cfcatch type="published_files.invalid">
                <cfset key = "" />
            </cfcatch>
        </cftry>
        <cfreturn key />
    </cffunction>

    <!--- A store key as a struct key: CFML's struct keys ignore case and store keys don't, so keys are compared as hex. --->
    <cffunction name="slotFor" access="private" returntype="string" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfreturn "k" & binaryEncode(charsetDecode(arguments.key, "utf-8"), "hex") />
    </cffunction>

    <cffunction name="isRecordId" access="private" returntype="boolean" output="false">
        <cfargument name="id" type="string" required="true" />
        <cfreturn reFind("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", arguments.id) GT 0 />
    </cffunction>

    <!--- Whether moo_published_file is in the database (a project that publishes has synced its schema). Remembered once
          it is. --->
    <cffunction name="trackingTableExists" access="private" returntype="boolean" output="false">
        <cfset var q = "" />
        <cfif variables.trackingTableKnown ?: false>
            <cfreturn true />
        </cfif>
        <cfquery name="q">
            SELECT to_regclass('moo_published_file') IS NOT NULL AS present
        </cfquery>
        <cfif q.present EQ true>
            <cfset variables.trackingTableKnown = true />
            <cfreturn true />
        </cfif>
        <cfreturn false />
    </cffunction>

    <cffunction name="emptyResult" access="private" returntype="struct" output="false">
        <cfreturn { "published": 0, "unpublished": 0, "kept": 0, "taken": 0, "failed": 0 } />
    </cffunction>

    <cffunction name="addTotals" access="private" returntype="void" output="false">
        <cfargument name="totals" type="struct" required="true" />
        <cfargument name="one" type="struct" required="true" />
        <cfloop list="published,unpublished,kept,taken,failed" item="local.count">
            <cfset arguments.totals[local.count] += arguments.one[local.count] ?: 0 />
        </cfloop>
    </cffunction>

    <!--- core.logError, and if even that fails, the engine's log: a failure to publish is never the caller's. --->
    <cffunction name="logFailure" access="public" returntype="void" output="false">
        <cfargument name="error" type="any" required="true" />
        <cfargument name="where" type="string" required="true" />
        <cftry>
            <cfset application.lib.core.logError(arguments.error, arguments.where) />
            <cfcatch>
                <cflog file="moopa" type="error" text="#arguments.where#: #arguments.error.message ?: ''#" />
            </cfcatch>
        </cftry>
    </cffunction>

    <!--- An address template filled in for a record and a file. --->
    <cffunction name="addressFor" access="public" returntype="string" output="false"
        hint="A publish.address template filled in for a record (a struct of its columns) and a file name: {field} is the record's value and {name} the file's name without its extension, both made readable (lowercase letters and digits, dashes between: 'Front View (2)' is front-view-2); {ext} is the file's extension in lowercase. Empty when any placeholder comes out empty.">
        <cfargument name="template" type="string" required="true" />
        <cfargument name="record" type="struct" required="true" />
        <cfargument name="fileName" type="string" required="true" />

        <cfset var address = arguments.template />
        <cfset var placeholder = "" />
        <cfset var name = "" />
        <cfset var value = "" />
        <cfset var fileName = trim(arguments.fileName) />
        <cfset var hasExtension = reFind("\.[A-Za-z0-9]+$", fileName) GT 0 />

        <cfloop array="#reMatch('\{[a-z_][a-z0-9_]*\}', arguments.template)#" item="placeholder">
            <cfset name = mid(placeholder, 2, len(placeholder) - 2) />
            <cfif name EQ "ext">
                <cfset value = hasExtension ? lCase(listLast(fileName, ".")) : "" />
            <cfelseif name EQ "name">
                <cfset value = readable(hasExtension ? reReplace(fileName, "\.[A-Za-z0-9]+$", "") : fileName) />
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
        <cfset var text = left(reReplace(lCase(trim(arguments.value)), "[^a-z0-9]+", "-", "all"), 120) />
        <cfreturn reReplace(text, "^-+|-+$", "", "all") />
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
