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
        <cfif compare(left(source, len(variables.PREFIX) + 1), variables.PREFIX & "/") EQ 0>
            <cfthrow type="published_files.invalid" message="published_files: publish a stored file, not a published copy (#source#)" />
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
        hint="Puts one record's published files in step with it: publishes what its publishing fields should have published (new or replaced files) and unpublishes what they no longer should (a removed file, a changed address, publish.when false, the record deleted), copying only what changed. Returns { published, unpublished, kept, taken, skipped, failed, deferred }: taken counts addresses another record holds, skipped files no address could be made for, failed the addresses that failed (each logged, left for the next sync). deferred is 1 when nothing was done: inside a caller's transaction (it could roll back), or when other publishing work kept the lock for longer than waitSeconds (logged). The next save, or syncAll, does it: publishing and unpublishing are eventual. Never throws. Does nothing while moo_published_file isn't in the database yet. db.save and db.delete call it.">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfargument name="waitSeconds" type="any" required="false" default="" hint="Whole seconds to wait for other publishing work to finish, 0 to 3600; anything else throws published_files.invalid. Left out: 5, unless an earlier sync in this request has just been deferred (then 0, until one gets the lock)." />
        <cfargument name="outsideTransaction" type="boolean" required="false" default="false" hint="The caller has just checked it isn't in a transaction (db.save): not checked again." />
        <cfset var outcome = { "result": emptyResult(), "failures": [] } />
        <cfset var byDefault = NOT len(trim(arguments.waitSeconds)) />
        <cfset var wait = 5 />
        <cfif byDefault>
            <cfset wait = (request.moopaPublishingBusy ?: false) ? 0 : 5 />
        <cfelseif isValid("integer", arguments.waitSeconds) AND arguments.waitSeconds GTE 0 AND arguments.waitSeconds LTE 3600 AND NOT find(".", arguments.waitSeconds)>
            <cfset wait = int(arguments.waitSeconds) />
        <cfelse>
            <cfthrow type="published_files.invalid" message="published_files: waitSeconds is whole seconds, 0 to 3600, not '#arguments.waitSeconds#'" />
        </cfif>
        <cftry>
            <cfif len(canonicalId(arguments.id)) AND trackingTableExists()>
                <cfif NOT arguments.outsideTransaction AND inTransaction()>
                    <cfset outcome.result.deferred = 1 />
                <cfelse>
                    <cfset outcome = syncLocked(lCase(arguments.table_name), canonicalId(arguments.id), wait, true) />
                    <cfif outcome.result.deferred>
                        <cfif byDefault AND wait GT 0>
                            <cfset request.moopaPublishingBusy = true />
                        </cfif>
                        <cflog file="moopa" type="warning" text="published_files: other publishing work held the lock; #arguments.table_name# #arguments.id# deferred to the next sync" />
                    </cfif>
                </cfif>
            </cfif>
            <cfcatch>
                <cfset outcome = { "result": emptyResult(), "failures": [ { "error": cfcatch, "where": "published_files.syncRecord #arguments.table_name# #arguments.id#" } ] } />
                <cfset outcome.result.failed = 1 />
            </cfcatch>
        </cftry>
        <cfset logFailures(outcome.failures) />
        <cfreturn outcome.result />
    </cffunction>

    <!--- One record's sync under the publishing lock: { result, failures }; the failures are logged by the caller, after the
          lock is released. A save's sync (queued) first queues behind this instance's other saves on a named lock, holding
          no connection, then waits in Postgres's own queue for the publishing lock, in turn with every other instance and
          with syncAll, for what is left of waitSeconds; syncAll waits in that queue directly. Still busy then: deferred. --->
    <cffunction name="syncLocked" access="private" returntype="struct" output="false">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfargument name="waitSeconds" type="numeric" required="true" />
        <cfargument name="queued" type="boolean" required="true" />
        <cfset var outcome = { "result": emptyResult(), "failures": [] } />
        <cfset var started = getTickCount() />
        <cfset var entered = false />
        <cfif NOT arguments.queued>
            <cfreturn lockedReconcile(arguments.table_name, arguments.id, arguments.waitSeconds * 1000) />
        </cfif>
        <cfif arguments.waitSeconds LTE 0>
            <!--- No waiting: the lock now, or deferred. --->
            <cfreturn lockedReconcile(arguments.table_name, arguments.id, 0) />
        </cfif>
        <!--- Per application: on an engine where named locks span applications, two apps don't queue behind each other. --->
        <cflock name="moopa_published_files_queue_#application.applicationName ?: ''#" type="exclusive" timeout="#max(1, ceiling(arguments.waitSeconds))#" throwontimeout="false">
            <cfset entered = true />
            <!--- What is left of the wait; nothing left: the lock now, or deferred. --->
            <cfset outcome = lockedReconcile(arguments.table_name, arguments.id, max(0, int(arguments.waitSeconds * 1000 - (getTickCount() - started)))) />
        </cflock>
        <cfif NOT entered>
            <cfset outcome.result.deferred = 1 />
        </cfif>
        <cfreturn outcome />
    </cffunction>

    <!--- reconcileRecord in a transaction of its own holding the publishing lock, waiting for it at most waitMs (0: only if
          it is free now). { result, failures }, result.deferred = 1 when the lock didn't come. --->
    <cffunction name="lockedReconcile" access="private" returntype="struct" output="false">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfargument name="waitMs" type="numeric" required="true" />
        <cfset var outcome = { "result": emptyResult(), "failures": [] } />
        <cfset var got = false />
        <cftransaction>
            <cfset got = takeLock(arguments.waitMs) />
            <cfif got>
                <!--- The lock came: the request's saves may wait for it again. --->
                <cfset request.moopaPublishingBusy = false />
                <cfset outcome = reconcileRecord(arguments.table_name, arguments.id) />
            </cfif>
        </cftransaction>
        <cfif NOT got>
            <cfset outcome = { "result": emptyResult(), "failures": [] } />
            <cfset outcome.result.deferred = 1 />
        </cfif>
        <cfreturn outcome />
    </cffunction>

    <cffunction name="syncAll" access="public" returntype="struct" output="false"
        hint="Every publishing table's files in step with every record, and the store with moo_published_file: first what a deleted record, or a field or table that no longer publishes, left behind; then each record (syncRecord); then, under each publishing field's literal prefix (/datasheets/ for /datasheets/{slug}.pdf), a copy that is missing or not the one recorded is published again, and a copy this library made that no row accounts for is deleted. A record or table that fails is logged and counted, and the rest go on; if the publishing lock stays busy for a minute the run stops there (deferred). Returns the totals { published, unpublished, kept, taken, skipped, failed, deferred, repaired, removed }. Not inside a transaction (deferred). Run it once when a table first publishes, and on a schedule.">
        <cfset var totals = emptyResult() />
        <cfset var publishing = application.lib.db.getPublishing() />
        <cfset var tableName = "" />
        <cfset var q = "" />
        <cfset var synced = {} />

        <cfset totals.repaired = 0 />
        <cfset totals.removed = 0 />
        <cfif NOT trackingTableExists()>
            <cfreturn totals />
        </cfif>
        <cfif inTransaction()>
            <cfset totals.deferred = 1 />
            <cfreturn totals />
        </cfif>
        <cfset totals.byRecord = {} />

        <!--- 1. Left behind: rows of a table that no longer publishes, of a field that no longer does, or of a record that
                 is gone. First, so a record waiting for one of their addresses gets it in this run. Table by table, so
                 one that fails (not in the database yet, say) doesn't stop the others. --->
        <cftry>
            <cfquery name="q">
                SELECT DISTINCT table_name, record_id::text AS record_id FROM moo_published_file
                WHERE table_name NOT IN (<cfqueryparam cfsqltype="varchar" list="true" value="#listAppend(structKeyList(publishing), '-none-')#" />)
            </cfquery>
            <cfloop query="q">
                <cfif NOT runRecord(totals, q.table_name, q.record_id, synced)><cfreturn finishTotals(totals) /></cfif>
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
                    <cfif NOT runRecord(totals, tableName, q.record_id, synced)><cfreturn finishTotals(totals) /></cfif>
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
                    <cfif NOT runRecord(totals, tableName, q.id, synced)><cfreturn finishTotals(totals) /></cfif>
                </cfloop>
                <cfcatch>
                    <cfset totals.failed++ />
                    <cfset logFailure(cfcatch, "published_files.syncAll #tableName#") />
                </cfcatch>
            </cftry>
        </cfloop>

        <!--- 3. The store against the rows, under each publishing field's literal prefix. --->
        <cfset sweep(publishing, totals) />
        <cfreturn finishTotals(totals) />
    </cffunction>

    <!--- One record of syncAll: synced at most once per run once it has nothing taken or failed (a record that found its
          address taken is tried again when step 2 reaches it, by when another record may have let go of it). False when the
          publishing lock stayed busy: the run stops. --->
    <cffunction name="runRecord" access="private" returntype="boolean" output="false">
        <cfargument name="totals" type="struct" required="true" />
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfargument name="synced" type="struct" required="true" />
        <cfset var id = canonicalId(arguments.id) />
        <cfset var mark = lCase(arguments.table_name) & ":" & id />
        <cfset var outcome = {} />
        <cfif NOT len(id) OR structKeyExists(arguments.synced, mark)>
            <cfreturn true />
        </cfif>
        <cftry>
            <cfset outcome = syncLocked(lCase(arguments.table_name), id, 60, false) />
            <cfcatch>
                <cfset outcome = { "result": emptyResult(), "failures": [ { "error": cfcatch, "where": "published_files.syncAll #arguments.table_name# #id#" } ] } />
                <cfset outcome.result.failed = 1 />
            </cfcatch>
        </cftry>
        <cfset logFailures(outcome.failures) />
        <cfif outcome.result.deferred>
            <cfset arguments.totals.deferred = 1 />
            <cfreturn false />
        </cfif>
        <!--- A record run again in step 2: what it published or unpublished adds up; kept, taken, skipped and failed are its
              last run's. --->
        <cfif structKeyExists(arguments.totals.byRecord, mark)>
            <cfset outcome.result.published += arguments.totals.byRecord[mark].published />
            <cfset outcome.result.unpublished += arguments.totals.byRecord[mark].unpublished />
        </cfif>
        <cfset arguments.totals.byRecord[mark] = outcome.result />
        <cfif NOT outcome.result.taken AND NOT outcome.result.failed>
            <cfset arguments.synced[mark] = true />
        </cfif>
        <cfreturn true />
    </cffunction>

    <!--- One record's addresses, under the publishing lock: { result, failures }. Each address in a savepoint of its own;
          once its claim or its unlink is made, a second savepoint after it (checkpoint), so a failure (in the store, or a
          statement that would otherwise abort the whole transaction) undoes only what came after it. The address is then
          counted as failed, and the other addresses go on. --->
    <cffunction name="reconcileRecord" access="private" returntype="struct" output="false">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />

        <cfset var outcome = { "result": emptyResult(), "failures": [] } />
        <cfset var wanted = wantedFor(arguments.table_name, arguments.id, outcome.result) />
        <cfset var mine = {} />
        <cfset var q = "" />
        <cfset var slot = "" />
        <cfset var entry = {} />
        <cfset var done = "" />
        <cfset var sp = {} />

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
            <cfset sp = beginAddress() />
            <cftry>
                <cfset done = retire(mine[slot].key, arguments.table_name, arguments.id, sp) ? "unpublished" : "" />
                <cfquery>RELEASE SAVEPOINT moopa_published_address</cfquery>
                <cfif len(done)>
                    <cfset outcome.result[done]++ />
                </cfif>
                <cfcatch>
                    <cfset abandonAddress(sp, cfcatch) />
                    <cfset outcome.result.failed++ />
                    <cfset arrayAppend(outcome.failures, { "error": cfcatch, "where": "published_files unpublish #mine[slot].key#" }) />
                </cfcatch>
            </cftry>
        </cfloop>

        <cfloop collection="#wanted#" item="slot">
            <cfset entry = wanted[slot] />
            <cfset sp = beginAddress() />
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
                    <cfset done = "kept" />
                <cfelse>
                    <cfset done = placeCopy(entry, arguments.table_name, arguments.id, sp) ? "published" : "taken" />
                </cfif>
                <cfquery>RELEASE SAVEPOINT moopa_published_address</cfquery>
                <cfset outcome.result[done]++ />
                <cfcatch>
                    <cfset abandonAddress(sp, cfcatch) />
                    <cfset outcome.result.failed++ />
                    <cfset arrayAppend(outcome.failures, { "error": cfcatch, "where": "published_files publish #entry.key#" }) />
                </cfcatch>
            </cftry>
        </cfloop>

        <cfreturn outcome />
    </cffunction>

    <!--- An address's savepoint; returns its state, which checkpoint and abandonAddress are given. --->
    <cffunction name="beginAddress" access="private" returntype="struct" output="false">
        <cfquery>SAVEPOINT moopa_published_address</cfquery>
        <cfreturn { "checkpointed": false } />
    </cffunction>

    <!--- Keeps what this address has done so far (its claim, or its unlink) even if what follows fails: that is what the
          next sync finishes from. A savepoint inside the address's own. --->
    <cffunction name="checkpoint" access="private" returntype="void" output="false">
        <cfargument name="sp" type="struct" required="true" />
        <cfquery>SAVEPOINT moopa_published_after</cfquery>
        <cfset arguments.sp.checkpointed = true />
    </cffunction>

    <!--- After a failure: back to the latest savepoint, then both released (releasing the outer one releases the inner). The
          failure goes to the engine's log first, so it isn't lost if the rollback fails too. --->
    <cffunction name="abandonAddress" access="private" returntype="void" output="false">
        <cfargument name="sp" type="struct" required="true" />
        <cfargument name="error" type="any" required="true" />
        <cflog file="moopa" type="error" text="published_files: #arguments.error.message ?: ''#" />
        <cfif arguments.sp.checkpointed>
            <cfquery>ROLLBACK TO SAVEPOINT moopa_published_after</cfquery>
        <cfelse>
            <cfquery>ROLLBACK TO SAVEPOINT moopa_published_address</cfquery>
        </cfif>
        <cfquery>RELEASE SAVEPOINT moopa_published_address</cfquery>
    </cffunction>

    <!--- Publishes one address for a record, under the publishing lock. The row is the record's before anything is copied:
          if it is already, its path is emptied (pages stop linking it during the copy); if not, it is claimed, the unique
          object_key settling it against any other record. After the copy, path and etag are set. False when another
          record holds the address. --->
    <cffunction name="placeCopy" access="private" returntype="boolean" output="false">
        <cfargument name="entry" type="struct" required="true" />
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfargument name="sp" type="struct" required="true" />
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
        <cfset checkpoint(arguments.sp) />

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
        <cfif NOT settled.recordCount>
            <!--- The row was claimed under the lock a moment ago: nothing else can have taken it. --->
            <cfthrow type="published_files.lost" message="published_files: the row for #arguments.entry.key# went while it was published" />
        </cfif>
        <cfreturn true />
    </cffunction>

    <!--- Unpublishes one of a record's addresses: empties its path (only while it is the record's), deletes the copy, then
          the row. False, touching nothing in the store, when the row is no longer the record's. --->
    <cffunction name="retire" access="private" returntype="boolean" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfargument name="sp" type="struct" required="true" />
        <cfset var owned = "" />
        <cfquery name="owned">
            UPDATE moo_published_file SET path = '', last_updated_at = now()
            WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
            RETURNING object_key
        </cfquery>
        <cfif NOT owned.recordCount>
            <cfreturn false />
        </cfif>
        <cfset checkpoint(arguments.sp) />
        <cfset application.lib.s3_client.deleteObject(application.lib.s3_client.defaultStore(), arguments.key) />
        <cfquery>
            DELETE FROM moo_published_file
            WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
            AND path = ''
        </cfquery>
        <cfreturn true />
    </cffunction>

    <!--- The store against the rows, prefix by prefix: a row whose copy is missing, or isn't the copy it recorded (its
          etag), is published again; a copy no row accounts for is deleted, but only one this library made (its mark), so
          a file published by hand is never touched. Only under a publishing field's literal prefix, never the whole site.
          Each repair and removal is decided again under the publishing lock. --->
    <cffunction name="sweep" access="private" returntype="void" output="false">
        <cfargument name="publishing" type="struct" required="true" />
        <cfargument name="totals" type="struct" required="true" />
        <cfset var prefixes = [] />
        <cfset var unique = [] />
        <cfset var tableName = "" />
        <cfset var fieldName = "" />
        <cfset var prefix = "" />
        <cfset var stored = {} />
        <cfset var object = {} />
        <cfset var q = "" />
        <cfset var slot = "" />
        <cfset var done = "" />
        <cfset var store = application.lib.s3_client.defaultStore() />

        <!--- Each field's prefix once, and none inside another (it is listed with it). --->
        <cfloop collection="#arguments.publishing#" item="tableName">
            <cfloop collection="#arguments.publishing[tableName]#" item="fieldName">
                <cfset arrayAppend(prefixes, variables.PREFIX & "/" & arguments.publishing[tableName][fieldName].site & arguments.publishing[tableName][fieldName].prefix) />
            </cfloop>
        </cfloop>
        <cfset arraySort(prefixes, "text") />
        <cfloop array="#prefixes#" item="prefix">
            <cfif arrayLen(unique) AND compare(left(prefix, len(unique[arrayLen(unique)])), unique[arrayLen(unique)]) EQ 0>
                <cfcontinue />
            </cfif>
            <cfset arrayAppend(unique, prefix) />
        </cfloop>

        <cfloop array="#unique#" item="prefix">
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
                            <cfset done = underLock("repair", { "key": q.object_key, "path": q.path, "table_name": q.table_name, "id": q.record_id }) />
                            <cfif done EQ "busy">
                                <cfset arguments.totals.deferred = 1 />
                                <cfreturn />
                            </cfif>
                            <cfif done EQ "yes">
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
                        <cfset done = underLock("remove", { "key": stored[slot].key }) />
                        <cfif done EQ "busy">
                            <cfset arguments.totals.deferred = 1 />
                            <cfreturn />
                        </cfif>
                        <cfif done EQ "yes">
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

    <!--- A sweep step under the publishing lock, waiting in Postgres's queue for up to a minute: "yes" (done), "no" (nothing
          to do, now), "busy" (the lock didn't come). --->
    <cffunction name="underLock" access="private" returntype="string" output="false">
        <cfargument name="step" type="string" required="true" />
        <cfargument name="args" type="struct" required="true" />
        <cfset var answer = "busy" />
        <cftransaction>
            <cfif takeLock(60000)>
                <cfif arguments.step EQ "repair">
                    <cfset answer = repairCopy(arguments.args.key, arguments.args.path, arguments.args.table_name, arguments.args.id) ? "yes" : "no" />
                <cfelse>
                    <cfset answer = removeStray(arguments.args.key) ? "yes" : "no" />
                </cfif>
            </cfif>
        </cftransaction>
        <cfreturn answer />
    </cffunction>

    <!--- Deletes a copy no row accounted for when the sweep listed it, under the publishing lock (underLock): only if no
          record holds its address now, and only if this library made it (its mark). True when it was deleted. --->
    <cffunction name="removeStray" access="private" returntype="boolean" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfset var held = "" />
        <cfset var head = {} />
        <cfquery name="held">
            SELECT 1 FROM moo_published_file WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.key#" />
        </cfquery>
        <cfif held.recordCount>
            <cfreturn false />
        </cfif>
        <cfset head = application.lib.s3_client.headObject(application.lib.s3_client.defaultStore(), arguments.key) />
        <cfif NOT head.exists OR NOT structKeyExists(head.metadata, structKeyList(variables.MARK))>
            <cfreturn false />
        </cfif>
        <cfset application.lib.s3_client.deleteObject(application.lib.s3_client.defaultStore(), arguments.key) />
        <cfreturn true />
    </cffunction>

    <!--- Copies a row's file to its address again, under the publishing lock (underLock), if the row is still the record's
          with that path and the copy there is still missing or not the recorded one (an earlier sweep may have repaired
          it). True when it was repaired. --->
    <cffunction name="repairCopy" access="private" returntype="boolean" output="false">
        <cfargument name="key" type="string" required="true" />
        <cfargument name="path" type="string" required="true" />
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfset var still = "" />
        <cfset var head = {} />
        <cfset var etag = "" />
        <cfquery name="still">
            SELECT etag FROM moo_published_file
            WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
            AND path = <cfqueryparam cfsqltype="varchar" value="#arguments.path#" />
        </cfquery>
        <cfif NOT still.recordCount>
            <cfreturn false />
        </cfif>
        <cfset head = application.lib.s3_client.headObject(application.lib.s3_client.defaultStore(), arguments.key) />
        <cfif head.exists AND len(still.etag) AND compare(head.etag, still.etag) EQ 0>
            <cfreturn false />
        </cfif>
        <cfset etag = application.lib.s3_client.copyObject(application.lib.s3_client.defaultStore(), arguments.path, arguments.key, variables.MARK) />
        <cfquery>
            UPDATE moo_published_file SET etag = <cfqueryparam cfsqltype="varchar" value="#etag#" />, last_updated_at = now()
            WHERE object_key = <cfqueryparam cfsqltype="varchar" value="#arguments.key#" /> AND table_name = <cfqueryparam cfsqltype="varchar" value="#arguments.table_name#" /> AND record_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
        </cfquery>
        <cfreturn true />
    </cffunction>

    <!--- What a record's publishing fields should have published, by slot (slotFor its store key): { key, site, address,
          field, file_id, path }. The record and every publishing field's files are read in one statement, so they are one
          moment's state: a save landing in between can't pair one state's when with another's files. Nothing for a record
          that is gone, or whose publish.when is not true. Fields are taken in name order and files in their order, so who
          gets a contested address is always the same. A file no address can be made for (an empty value, too long) is
          counted in result.skipped. --->
    <cffunction name="wantedFor" access="private" returntype="struct" output="false">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="id" type="string" required="true" />
        <cfargument name="result" type="struct" required="true" />

        <cfset var wanted = {} />
        <cfset var fields = application.lib.db.getPublishing()[arguments.table_name] ?: {} />
        <cfset var fieldNames = listToArray(listSort(structKeyList(fields), "text")) />
        <cfset var fieldName = "" />
        <cfset var setting = {} />
        <cfset var columns = [] />
        <cfset var column = "" />
        <cfset var q = "" />
        <cfset var state = {} />
        <cfset var record = {} />
        <cfset var file = {} />
        <cfset var address = "" />
        <cfset var candidate = "" />
        <cfset var key = "" />
        <cfset var n = 0 />

        <cfif structIsEmpty(fields)>
            <cfreturn wanted />
        </cfif>
        <cfloop array="#fieldNames#" item="fieldName">
            <cfloop array="#fields[fieldName].columns#" item="column">
                <cfif column NEQ "id" AND NOT arrayFindNoCase(columns, column)>
                    <cfset arrayAppend(columns, column) />
                </cfif>
            </cfloop>
        </cfloop>
        <!--- Only the columns the addresses and conditions use, and each field's files, in its order, as one row per field
              gathered into one object (json_object_agg: no limit on how many fields). row_to_json(published_record.*) is the
              row even when the table has a column of the alias's name. Names come from the table definitions, checked at
              start. --->
        <cfquery name="q">
            SELECT json_build_object(
                'record', (SELECT row_to_json(published_record.*) FROM (SELECT id<cfloop array="#columns#" item="column">, #column#</cfloop> FROM #arguments.table_name# WHERE id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />) AS published_record),
                'files', (SELECT json_object_agg(per_field.field_name, per_field.files) FROM (
                    <cfloop from="1" to="#arrayLen(fieldNames)#" index="local.i">
                        <cfif local.i GT 1>UNION ALL</cfif>
                        SELECT '#fieldNames[local.i]#' AS field_name, COALESCE((
                            SELECT json_agg(json_build_object('file_id', moo_file.id::text, 'name', moo_file.name, 'path', moo_file.path) ORDER BY bridge.sequence, moo_file.id)
                            FROM #fields[fieldNames[local.i]].bridge# AS bridge
                            JOIN moo_file ON moo_file.id = bridge.foreign_id
                            WHERE bridge.primary_id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
                        ), '[]'::json) AS files
                    </cfloop>
                ) AS per_field)
            )::text AS data
        </cfquery>
        <cfset state = deserializeJSON(q.data) />
        <cfif NOT isStruct(state.record ?: "")>
            <cfreturn wanted />
        </cfif>
        <cfset record = state.record />

        <cfloop array="#fieldNames#" item="fieldName">
            <cfset setting = fields[fieldName] />
            <cfif len(setting.when) AND NOT (isBoolean(record[setting.when] ?: "") AND record[setting.when])>
                <cfcontinue />
            </cfif>
            <cfloop array="#state.files[fieldName] ?: []#" item="file">
                <cfset address = len(file.path ?: "") ? addressFor(setting.address, record, file.name ?: "") : "" />
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
                <cfset wanted[slotFor(key)] = { "key": key, "site": setting.site, "address": candidate, "field": fieldName, "file_id": file.file_id, "path": file.path } />
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

    <cffunction name="inTransaction" access="public" returntype="boolean" output="false"
        hint="Whether this request is inside a database transaction (isWithinTransaction() isn't on every engine): there two statements share one virtual transaction, outside it each has its own. Takes no transaction id.">
        <cfset var first = "" />
        <cfset var second = "" />
        <cfquery name="first">SELECT virtualtransaction AS id FROM pg_locks WHERE pid = pg_backend_pid() AND locktype = 'virtualxid'</cfquery>
        <cfquery name="second">SELECT virtualtransaction AS id FROM pg_locks WHERE pid = pg_backend_pid() AND locktype = 'virtualxid'</cfquery>
        <cfreturn first.recordCount AND second.recordCount AND compare(first.id, second.id) EQ 0 />
    </cffunction>

    <!--- The publishing lock, for the rest of the current transaction, read committed (so what is read after it is what the
          last holder committed). waitMs under 1: only if it is free now. Otherwise waits in Postgres's queue for it, at
          most waitMs; false when it didn't come (the transaction is then failed, and rolls back with nothing done). The
          wait applies to taking the lock alone: lock_timeout is back to what the connection had for the work that
          follows, so a row lock met there is that work's to wait for or fail on, never "busy". --->
    <cffunction name="takeLock" access="private" returntype="boolean" output="false">
        <cfargument name="waitMs" type="numeric" required="true" />
        <cfset var got = "" />
        <cfset var prior = "" />
        <cfset var waitMs = int(arguments.waitMs) />
        <cfquery>SET TRANSACTION ISOLATION LEVEL READ COMMITTED</cfquery>
        <cfif waitMs LT 1>
            <cfquery name="got">SELECT pg_try_advisory_xact_lock(hashtext(<cfqueryparam cfsqltype="varchar" value="#variables.LOCK_NAME#" />)) AS got</cfquery>
            <cfreturn got.got EQ true />
        </cfif>
        <cfquery name="prior">SELECT current_setting('lock_timeout') AS setting</cfquery>
        <cfquery>SET LOCAL lock_timeout = '#min(waitMs, 3600000)#ms'</cfquery>
        <cftry>
            <cfquery>SELECT pg_advisory_xact_lock(hashtext(<cfqueryparam cfsqltype="varchar" value="#variables.LOCK_NAME#" />))</cfquery>
            <cfcatch>
                <cfif isLockTimeout(cfcatch)>
                    <cfreturn false />
                </cfif>
                <cfrethrow />
            </cfcatch>
        </cftry>
        <!--- Back to what the connection had (its session's or role's setting), for the rest of this transaction. --->
        <cfquery>SELECT set_config('lock_timeout', <cfqueryparam cfsqltype="varchar" value="#prior.setting#" />, true)</cfquery>
        <cfreturn true />
    </cffunction>

    <cffunction name="isLockTimeout" access="private" returntype="boolean" output="false">
        <cfargument name="error" type="any" required="true" />
        <cfreturn findNoCase("lock timeout", (arguments.error.message ?: "") & " " & (arguments.error.detail ?: "")) GT 0
            OR (arguments.error.sqlState ?: "") EQ "55P03" />
    </cffunction>

    <!--- syncAll's totals: each record's last result added up, with the sweep's own counts. --->
    <cffunction name="finishTotals" access="private" returntype="struct" output="false">
        <cfargument name="totals" type="struct" required="true" />
        <cfset var result = duplicate(arguments.totals) />
        <cfset structDelete(result, "byRecord") />
        <cfloop collection="#arguments.totals.byRecord ?: {}#" item="local.mark">
            <cfset addTotals(result, arguments.totals.byRecord[local.mark]) />
        </cfloop>
        <cfreturn result />
    </cffunction>

    <cffunction name="addTotals" access="private" returntype="void" output="false">
        <cfargument name="totals" type="struct" required="true" />
        <cfargument name="one" type="struct" required="true" />
        <cfloop list="published,unpublished,kept,taken,skipped,failed" item="local.count">
            <cfset arguments.totals[local.count] += arguments.one[local.count] ?: 0 />
        </cfloop>
        <cfif (arguments.one.deferred ?: 0) GT 0>
            <cfset arguments.totals.deferred = 1 />
        </cfif>
    </cffunction>

    <cffunction name="logFailures" access="private" returntype="void" output="false">
        <cfargument name="failures" type="array" required="true" />
        <cfloop array="#arguments.failures#" item="local.failure">
            <cfset logFailure(local.failure.error, local.failure.where) />
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
