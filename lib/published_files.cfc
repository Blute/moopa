<cfcomponent displayname="published_files" output="false"
    hint="Files published at a fixed address on one of the project's own sites, such as /datasheets/product.pdf on its public website, answered there without a signature by the signed assets Worker (docs/object-storage.md: Published files). publish() copies a stored file (a moo_file's path) inside the default store to public/<site>/<address>; publishing again at the same address replaces it, so the address never changes. unpublish() removes it. The copy is the project's to remove: deleting the original leaves it published. publish() and unpublish() keep no record of their own: what is under public/ is what is published. A table definition can instead declare that a file field's files are published (publish: { site, address, when }); db.save and db.delete then keep them in step (syncRecord), recorded in moo_published_file, one operation at a time under a Postgres advisory lock, never inside a caller's transaction. Nothing here runs unless a project publishes.">

    <!--- Every published file's key starts with this, then the site. The Worker reads the same prefix. --->
    <cfset variables.PREFIX = "public" />
    <!--- The mark (user metadata) on every copy a publishing field makes: syncAll's sweep deletes only marked copies. --->
    <cfset variables.MARK = { "moopa-published": "1" } />
    <!--- The Postgres advisory lock every publishing operation holds, in a short transaction of its own: one at a time,
          across every instance of the app. --->
    <cfset variables.LOCK_NAME = "moopa_published_files" />

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
        <!--- A published copy carries the mark of the field that made it, which a copy of it would keep. --->
        <cfif left(source, len(variables.PREFIX) + 1) EQ variables.PREFIX & "/">
            <cfthrow type="published_files.invalid" message="published_files: publish a stored file, not a published copy (#source#)" />
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

          Every publishing operation (a record's sync, a repair, a stray's removal) runs in a short transaction of its own
          holding one Postgres advisory lock, so only one runs at a time across every instance, and what it reads stays
          true until it commits. Inside a caller's transaction nothing is published (it could roll back): the next save,
          or syncAll, does it.

          Each address goes through its row, whose path is its state:
            publish:   claim the row (path empty; the unique object_key decides the owner), copy, then set path and etag
            unpublish: empty the path (pages stop linking), delete the copy, then delete the row
          A failure leaves the store ahead of the rows at most (a copy without a row, which the sweep removes; a row
          without its copy, which the sweep repairs).
          =============================================================================================================== --->

    <cffunction name="syncRecord" access="public" returntype="struct" output="false"
        hint="Puts one record's published files in step with it: publishes what its publishing fields should have published (new or replaced files) and unpublishes what they no longer should (a removed file, a changed address, publish.when false, the record deleted), copying only what changed. Returns { published, unpublished, kept, taken, skipped, failed, deferred }: taken counts addresses another record holds, skipped files no address could be made for, failed the addresses that failed (each logged), deferred is 1 when called inside a transaction, where nothing is published (it could roll back; the next save or syncAll does it). Does nothing while moo_published_file isn't in the database yet. db.save and db.delete call it.">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfset var result = emptyResult() />
        <cfif NOT len(canonicalId(arguments.id)) OR NOT trackingTableExists()>
            <cfreturn result />
        </cfif>
        <cfif inTransaction()>
            <cfset result.deferred = 1 />
            <cfreturn result />
        </cfif>
        <cfreturn syncLocked(lCase(arguments.table_name), canonicalId(arguments.id)) />
    </cffunction>

    <!--- One record's sync, in its own transaction, holding the publishing lock. --->
    <cffunction name="syncLocked" access="private" returntype="struct" output="false">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfset var result = {} />
        <cftransaction>
            <cfset takeLock() />
            <cfset result = reconcileRecord(arguments.table_name, arguments.id) />
        </cftransaction>
        <cfreturn result />
    </cffunction>

    <cffunction name="syncAll" access="public" returntype="struct" output="false"
        hint="Every publishing table's files in step with every record, and the store with moo_published_file: first what a deleted record, or a field or table that no longer publishes, left behind; then each record (syncRecord); then, under each publishing field's literal prefix (/datasheets/ for /datasheets/{slug}.pdf), a copy that is missing or not the one recorded is published again, and a copy this library made that no row accounts for is deleted. A record or table that fails is logged and counted, and the rest go on. Each step holds the publishing lock only for itself. Returns the totals { published, unpublished, kept, taken, skipped, failed, deferred, repaired, removed }. Not inside a transaction (deferred). Run it once when a table first publishes, and on a schedule.">
        <cfset var totals = emptyResult() />
        <cfset var publishing = application.lib.db.getPublishing() />
        <cfset var tableName = "" />
        <cfset var q = "" />

        <cfset totals.repaired = 0 />
        <cfset totals.removed = 0 />
        <cfif NOT trackingTableExists()>
            <cfreturn totals />
        </cfif>
        <cfif inTransaction()>
            <cfset totals.deferred = 1 />
            <cfreturn totals />
        </cfif>
        <!--- Each record once, whichever step reaches it first. --->
        <cfset var synced = {} />

        <!--- 1. Left behind: rows of a table that no longer publishes, of a field that no longer does, or of a record that
                 is gone. First, so a record waiting for one of their addresses gets it in this run. Table by table, so
                 one that fails (not in the database yet, say) doesn't stop the others. --->
        <cftry>
            <cfquery name="q">
                SELECT DISTINCT table_name, record_id::text AS record_id FROM moo_published_file
                WHERE table_name NOT IN (<cfqueryparam cfsqltype="varchar" list="true" value="#listAppend(structKeyList(publishing), '-none-')#" />)
            </cfquery>
            <cfloop query="q">
                <cfset addTotals(totals, safeSync(q.table_name, q.record_id, synced)) />
            </cfloop>
            <cfcatch>
                <cfset totals.failed++ />
                <cfset logFailure(cfcatch, "published_files.syncAll leftovers") />
            </cfcatch>
        </cftry>
        <cfloop collection="#publishing#" item="tableName">
            <cftry>
                <cfquery name="q">
                    SELECT DISTINCT published.record_id::text AS record_id
                    FROM moo_published_file AS published
                    WHERE published.table_name = <cfqueryparam cfsqltype="varchar" value="#tableName#" />
                    AND (
                        published.field NOT IN (<cfqueryparam cfsqltype="varchar" list="true" value="#structKeyList(publishing[tableName])#" />)
                        OR NOT EXISTS (SELECT 1 FROM #tableName# AS live WHERE live.id = published.record_id)
                    )
                </cfquery>
                <cfloop query="q">
                    <cfset addTotals(totals, safeSync(tableName, q.record_id, synced)) />
                </cfloop>
                <cfcatch>
                    <cfset totals.failed++ />
                    <cfset logFailure(cfcatch, "published_files.syncAll leftovers of #tableName#") />
                </cfcatch>
            </cftry>
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
            <cftry>
                <cfquery name="q">
                    SELECT id::text AS id FROM #tableName#
                    <cfif NOT local.always>
                        WHERE #arrayToList(local.conditions, " OR ")# OR
                        id IN (SELECT record_id FROM moo_published_file WHERE table_name = <cfqueryparam cfsqltype="varchar" value="#tableName#" />)
                    </cfif>
                    ORDER BY id
                </cfquery>
                <cfloop query="q">
                    <cfset addTotals(totals, safeSync(tableName, q.id, synced)) />
                </cfloop>
                <cfcatch>
                    <cfset totals.failed++ />
                    <cfset logFailure(cfcatch, "published_files.syncAll #tableName#") />
                </cfcatch>
            </cftry>
        </cfloop>

        <!--- 3. The store against the rows, under each publishing field's literal prefix. --->
        <cfset sweep(publishing, totals) />
        <cfreturn totals />
    </cffunction>

    <!--- syncRecord, with a failure logged and counted rather than thrown, for syncAll. --->
    <cffunction name="safeSync" access="private" returntype="struct" output="false">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfargument name="synced" type="struct" required="true" hint="The records this run has synced: each once." />
        <cfset var result = emptyResult() />
        <cfset var id = canonicalId(arguments.id) />
        <cfset var mark = lCase(arguments.table_name) & ":" & id />
        <cfif NOT len(id) OR structKeyExists(arguments.synced, mark)>
            <cfreturn result />
        </cfif>
        <cfset arguments.synced[mark] = true />
        <cftry>
            <cfset result = syncLocked(lCase(arguments.table_name), id) />
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
        <cfset var wanted = wantedFor(arguments.table_name, arguments.id, result) />
        <cfset var mine = {} />
        <cfset var q = "" />
        <cfset var slot = "" />
        <cfset var entry = {} />

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
                <cfif retire(mine[slot].key, arguments.table_name, arguments.id)>
                    <cfset result.unpublished++ />
                </cfif>
                <cfcatch>
                    <cfset result.failed++ />
                    <cfset logFailure(cfcatch, "published_files unpublish #mine[slot].key#") />
                </cfcatch>
            </cftry>
        </cfloop>

        <cfloop collection="#wanted#" item="slot">
            <cfset entry = wanted[slot] />
            <cftry>
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
                <cfelseif placeCopy(entry, arguments.table_name, arguments.id)>
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

    <!--- Publishes one address for a record, under the publishing lock. The row is the record's before anything is copied:
          if it is already, its path is emptied (pages stop linking it during the copy); if not, it is claimed, the unique
          object_key settling it against any other record. After the copy, path and etag are set. False when another
          record holds the address. --->
    <cffunction name="placeCopy" access="private" returntype="boolean" output="false">
        <cfargument name="entry" type="struct" required="true" />
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfset var owned = "" />
        <cfset var claimed = "" />
        <cfset var etag = "" />
        <cfset var settled = "" />

        <cfquery name="owned">
            UPDATE moo_published_file SET path = '', last_updated_at = now()
            WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.entry.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
            RETURNING object_key
        </cfquery>
        <cfif NOT owned.recordCount>
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
                <cfreturn false />
            </cfif>
        </cfif>

        <cfset etag = application.lib.s3_client.copyObject(application.lib.s3_client.defaultStore(), arguments.entry.path, arguments.entry.key, variables.MARK) />
        <cfquery name="settled">
            UPDATE moo_published_file
            SET path = <cfqueryparam cfsqltype="varchar" value="#arguments.entry.path#" />,
                etag = <cfqueryparam cfsqltype="varchar" value="#etag#" />,
                moo_file_id = <cfqueryparam cfsqltype="other" value="#arguments.entry.file_id#" />,
                field = <cfqueryparam cfsqltype="varchar" value="#arguments.entry.field#" />,
                last_updated_at = now()
            WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.entry.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
            RETURNING object_key
        </cfquery>
        <cfreturn settled.recordCount GT 0 />
    </cffunction>

    <!--- Unpublishes one of a record's addresses: empties its path (only while it is the record's), deletes the copy, then
          the row. False, touching nothing in the store, when the row is no longer the record's. --->
    <cffunction name="retire" access="private" returntype="boolean" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfset var owned = "" />
        <cfquery name="owned">
            UPDATE moo_published_file SET path = '', last_updated_at = now()
            WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
            RETURNING object_key
        </cfquery>
        <cfif NOT owned.recordCount>
            <cfreturn false />
        </cfif>
        <cfset application.lib.s3_client.deleteObject(application.lib.s3_client.defaultStore(), arguments.key) />
        <cfquery>
            DELETE FROM moo_published_file
            WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
        </cfquery>
        <cfreturn true />
    </cffunction>

    <!--- The store against the rows, prefix by prefix: a row whose copy is missing, or isn't the copy it recorded (its
          etag), is published again; a copy no row accounts for is deleted, but only one this library made (its mark), so
          a file published by hand, or another environment's, is never touched. Only under a publishing field's literal
          prefix, never the whole site. --->
    <cffunction name="sweep" access="private" returntype="void" output="false">
        <cfargument name="publishing" type="struct" required="true" />
        <cfargument name="totals" type="struct" required="true" />
        <cfset var prefixes = [] />
        <cfset var tableName = "" />
        <cfset var fieldName = "" />
        <cfset var prefix = "" />
        <cfset var other = "" />
        <cfset var stored = {} />
        <cfset var object = {} />
        <cfset var q = "" />
        <cfset var slot = "" />
        <cfset var store = application.lib.s3_client.defaultStore() />

        <!--- Each field's prefix once, and none inside another (it is listed with it). --->
        <cfloop collection="#arguments.publishing#" item="tableName">
            <cfloop collection="#arguments.publishing[tableName]#" item="fieldName">
                <cfset arrayAppend(prefixes, variables.PREFIX & "/" & arguments.publishing[tableName][fieldName].site & arguments.publishing[tableName][fieldName].prefix) />
            </cfloop>
        </cfloop>
        <cfset arraySort(prefixes, "text") />
        <cfset local.kept = [] />
        <cfloop array="#prefixes#" item="prefix">
            <cfif arrayLen(local.kept) AND compare(left(prefix, len(local.kept[arrayLen(local.kept)])), local.kept[arrayLen(local.kept)]) EQ 0>
                <cfcontinue />
            </cfif>
            <cfset arrayAppend(local.kept, prefix) />
        </cfloop>

        <cfloop array="#local.kept#" item="prefix">
            <cftry>
                <!--- Listed before the rows are read: a copy published in between has its row by then. --->
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
                            <cfif repairCopy(q.object_key, q.path, q.table_name, q.record_id)>
                                <cfset arguments.totals.repaired++ />
                            </cfif>
                            <cfcatch>
                                <cfset arguments.totals.failed++ />
                                <cfset logFailure(cfcatch, "published_files repair #q.object_key#") />
                            </cfcatch>
                        </cftry>
                    </cfif>
                    <cfset structDelete(stored, slot) />
                </cfloop>
                <!--- What is left had no row when read. --->
                <cfloop collection="#stored#" item="slot">
                    <cftry>
                        <cfif removeStray(stored[slot].key)>
                            <cfset arguments.totals.removed++ />
                        </cfif>
                        <cfcatch>
                            <cfset arguments.totals.failed++ />
                            <cfset logFailure(cfcatch, "published_files remove #stored[slot].key#") />
                        </cfcatch>
                    </cftry>
                </cfloop>
                <cfcatch>
                    <cfset arguments.totals.failed++ />
                    <cfset logFailure(cfcatch, "published_files sweep #prefix#") />
                </cfcatch>
            </cftry>
        </cfloop>
    </cffunction>

    <!--- Deletes a copy no row accounted for when the sweep listed it, under the publishing lock: only if no record holds
          its address now, and only if this library made it (its mark). True when it was deleted. --->
    <cffunction name="removeStray" access="private" returntype="boolean" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfset var held = "" />
        <cfset var head = {} />
        <cfset var removed = false />
        <cftransaction>
            <cfset takeLock() />
            <cfquery name="held">
                SELECT 1 FROM moo_published_file WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.key#" />
            </cfquery>
            <cfif NOT held.recordCount>
                <cfset head = application.lib.s3_client.headObject(application.lib.s3_client.defaultStore(), arguments.key) />
                <cfif head.exists AND structKeyExists(head.metadata, structKeyList(variables.MARK))>
                    <cfset application.lib.s3_client.deleteObject(application.lib.s3_client.defaultStore(), arguments.key) />
                    <cfset removed = true />
                </cfif>
            </cfif>
        </cftransaction>
        <cfreturn removed />
    </cffunction>

    <!--- Copies a row's file to its address again, under the publishing lock, if the row is still the record's with that
          path (a save may have changed or unpublished it since the sweep read it). True when it was repaired. --->
    <cffunction name="repairCopy" access="private" returntype="boolean" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfargument name="path" type="string" required="true" />
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfset var still = "" />
        <cfset var etag = "" />
        <cfset var repaired = false />
        <cftransaction>
            <cfset takeLock() />
            <cfquery name="still">
                SELECT 1 FROM moo_published_file
                WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
                AND path = <cfqueryparam cfsqltype="varchar" value="#arguments.path#" />
            </cfquery>
            <cfif still.recordCount>
                <cfset etag = application.lib.s3_client.copyObject(application.lib.s3_client.defaultStore(), arguments.path, arguments.key, variables.MARK) />
                <cfquery>
                    UPDATE moo_published_file SET etag = <cfqueryparam cfsqltype="varchar" value="#etag#" />, last_updated_at = now()
                    WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
                </cfquery>
                <cfset repaired = true />
            </cfif>
        </cftransaction>
        <cfreturn repaired />
    </cffunction>

    <!--- What a record's publishing fields should have published, by slot (slotFor its store key): { key, site, address,
          field, file_id, path }. Nothing for a record that is gone, or whose publish.when is not true. Fields are taken in
          name order and files in their order, so who gets a contested address is always the same. A file no address can
          be made for (an empty value, too long) is counted in result.skipped. --->
    <cffunction name="wantedFor" access="private" returntype="struct" output="false">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfargument name="result" type="struct" required="true" />

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
                <cfif column NEQ "id" AND NOT arrayFindNoCase(columns, column)>
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
                <cfset address = len(files.path) ? addressFor(setting.address, record, files.name) : "" />
                <cfif NOT len(address)>
                    <cfset arguments.result.skipped++ />
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
                    <cfset arguments.result.skipped++ />
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

    <!--- A record id as the database writes it (lowercase, 8-4-4-4-12), from that or the 32-digit form; "" for anything
          else. --->
    <cffunction name="canonicalId" access="private" returntype="string" output="false">
        <cfargument name="id" type="string" required="true" />
        <cfset var id = lCase(arguments.id) />
        <!--- Length first: on Lucee, $ also matches before a trailing newline. --->
        <cfif len(id) EQ 36 AND reFind("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", id)>
            <cfreturn id />
        </cfif>
        <cfif len(id) EQ 32 AND NOT reFind("[^0-9a-f]", id)>
            <cfreturn mid(id, 1, 8) & "-" & mid(id, 9, 4) & "-" & mid(id, 13, 4) & "-" & mid(id, 17, 4) & "-" & mid(id, 21, 12) />
        </cfif>
        <cfreturn "" />
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
        <cfreturn { "published": 0, "unpublished": 0, "kept": 0, "taken": 0, "skipped": 0, "failed": 0, "deferred": 0 } />
    </cffunction>

    <!--- Whether this request is inside a transaction: there two statements share one transaction id, outside it each
          has its own (isWithinTransaction() isn't on every engine). --->
    <cffunction name="inTransaction" access="private" returntype="boolean" output="false">
        <cfset var first = "" />
        <cfset var second = "" />
        <cfquery name="first">SELECT txid_current()::text AS id</cfquery>
        <cfquery name="second">SELECT txid_current()::text AS id</cfquery>
        <cfreturn compare(first.id, second.id) EQ 0 />
    </cffunction>

    <!--- The publishing lock, for the rest of the current transaction; a wait over a minute fails (and is logged). --->
    <cffunction name="takeLock" access="private" returntype="void" output="false">
        <cfquery>SET LOCAL lock_timeout = '60s'</cfquery>
        <cfquery>SELECT pg_advisory_xact_lock(hashtext(<cfqueryparam cfsqltype="varchar" value="#variables.LOCK_NAME#" />))</cfquery>
    </cffunction>

    <cffunction name="addTotals" access="private" returntype="void" output="false">
        <cfargument name="totals" type="struct" required="true" />
        <cfargument name="one" type="struct" required="true" />
        <cfloop list="published,unpublished,kept,taken,skipped,failed,deferred" item="local.count">
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
