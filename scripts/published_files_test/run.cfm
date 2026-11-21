<cfsilent>
<!---
    Regression harness for publishing a table's files (lib/published_files.cfc: syncRecord, syncAll) against PostgreSQL
    (scripts/published_files_test/fixture.sql) and an in-memory store with failures on demand (stub_store.cfc). What a
    save, a failure, a retry, a contested address, a rolled-back transaction and the sweep leave in the rows and the
    store.

    Run from Moopa's root:
        bash scripts/test_published_files.sh
--->
<cfscript>
    request.results = [];
    request.failures = 0;

    function check(required string label, required boolean ok, string detail = "") {
        arrayAppend(request.results, (arguments.ok ? "PASS  " : "FAIL  ") & arguments.label & (arguments.ok OR !len(arguments.detail) ? "" : chr(10) & "      " & arguments.detail));
        if (!arguments.ok) request.failures++;
    }

    application.lib = {
        "s3_client": createObject("component", "stub_store").init(),
        "core": createObject("component", "stub_core").init(),
        "db": createObject("component", "stub_db").init({
            "product": { "fields": {
                "slug": { "type": "varchar" },
                "is_published": { "type": "bool" },
                "datasheet": { "type": "many_to_many", "foreign_key_table": "moo_file", "publish": { "site": "www", "address": "/datasheets/{slug}.pdf", "when": "is_published" } },
                "images": { "type": "many_to_many", "foreign_key_table": "moo_file", "publish": { "site": "www", "address": "/images/{slug}/{name}.{ext}", "when": "is_published" } }
            } },
            "ghost": { "fields": {
                "slug": { "type": "varchar" },
                "files": { "type": "many_to_many", "foreign_key_table": "moo_file", "publish": { "site": "www", "address": "/ghosts/{slug}/{name}.{ext}" } }
            } },
            "moo_file": { "fields": { "name": { "type": "varchar" }, "path": { "type": "varchar" } } }
        })
    };
    // ghost publishes in the definitions but isn't in the database (its schema not applied): it must not stop the rest.
    application.lib.published_files = createObject("component", "exposed_files").init();
    store = application.lib.s3_client;
    files = application.lib.published_files;

    function newFile(required string name, required string body) {
        var id = lCase(createGUID());
        var path = "moo_file/2026-11/" & id & "/" & arguments.name;
        application.lib.s3_client.put(path, arguments.body);
        queryExecute("INSERT INTO moo_file (id, name, path) VALUES (:id::uuid, :name, :path)", { id: id, name: arguments.name, path: path });
        return id;
    }
    function newProduct(required string slug, boolean published = false) {
        var id = lCase(createGUID());
        queryExecute("INSERT INTO product (id, slug, is_published) VALUES (:id::uuid, :slug, :published)", { id: id, slug: arguments.slug, published: { value: arguments.published, cfsqltype: "boolean" } });
        return id;
    }
    function attach(required string product, required string field, required array fileIds) {
        queryExecute("DELETE FROM product_#arguments.field# WHERE primary_id = :id::uuid", { id: arguments.product });
        for (var i = 1; i <= arrayLen(arguments.fileIds); i++) {
            queryExecute("INSERT INTO product_#arguments.field# (primary_id, foreign_id, sequence) VALUES (:p::uuid, :f::uuid, :s)", { p: arguments.product, f: arguments.fileIds[i], s: i });
        }
    }
    function setProduct(required string product, required struct values) {
        if (structKeyExists(arguments.values, "slug")) queryExecute("UPDATE product SET slug = :v WHERE id = :id::uuid", { v: arguments.values.slug, id: arguments.product });
        if (structKeyExists(arguments.values, "is_published")) queryExecute("UPDATE product SET is_published = :v WHERE id = :id::uuid", { v: { value: arguments.values.is_published, cfsqltype: "boolean" }, id: arguments.product });
    }
    // Rows as { address: path }; path "" while publishing or unpublishing.
    function rows() {
        var q = queryExecute("SELECT address, path FROM moo_published_file ORDER BY address");
        var out = {};
        for (var r in q) out[r.address] = r.path;
        return out;
    }
    function rowPath(required string address) {
        var q = queryExecute("SELECT path FROM moo_published_file WHERE address = :a", { a: arguments.address });
        return q.recordCount ? q.path : "(no row)";
    }
    function live(required string address) {
        return application.lib.s3_client.has("public/www" & arguments.address);
    }
    function liveBody(required string address) {
        return application.lib.s3_client.body("public/www" & arguments.address);
    }
    function summary(required struct r) {
        return "p#r.published# u#r.unpublished# k#r.kept# t#r.taken# f#r.failed#";
    }
    function marked(required string address) {
        return structKeyExists(application.lib.s3_client.headObject({}, "public/www" & arguments.address).metadata, "moopa-published");
    }

    // 1. A product's files publish once it is published, at readable addresses.
    sheet1 = newFile("Alpha Datasheet.pdf", "sheet one");
    front = newFile("Front.JPG", "front one");
    front2 = newFile("front.jpg", "front two");
    alpha = newProduct("alpha");
    attach(alpha, "datasheet", [sheet1]);
    attach(alpha, "images", [front, front2]);
    r = files.syncRecord("product", alpha);
    check("unpublished: nothing", structIsEmpty(rows()) AND summary(r) EQ "p0 u0 k0 t0 f0", summary(r));
    setProduct(alpha, { is_published: true });
    r = files.syncRecord("product", alpha);
    check("published: three addresses", summary(r) EQ "p3 u0 k0 t0 f0", summary(r));
    check("...the datasheet by the slug", liveBody("/datasheets/alpha.pdf") EQ "sheet one" AND len(rowPath("/datasheets/alpha.pdf")));
    check("...pictures by name, the second of one name numbered", live("/images/alpha/front.jpg") AND live("/images/alpha/front-2.jpg"));
    check("...each with the etag of its copy", queryExecute("SELECT count(*) AS n FROM moo_published_file WHERE coalesce(etag, '') = ''").n EQ 0);
    check("...and marked as this library's copy", marked("/datasheets/alpha.pdf") AND marked("/images/alpha/front.jpg"));
    r = files.syncRecord("product", alpha);
    check("nothing changed: nothing copied", summary(r) EQ "p0 u0 k3 t0 f0", summary(r));

    // 2. A failed copy leaves the row unlinked (empty path) for the next sync, and nothing else is held up.
    sheet2 = newFile("v2.pdf", "sheet two");
    attach(alpha, "datasheet", [sheet2]);
    store.failCopyTo = "public/www/datasheets/alpha.pdf";
    r = files.syncRecord("product", alpha);
    check("a failed copy is counted, not thrown", summary(r) EQ "p0 u0 k2 t0 f1", summary(r));
    check("...and its row is left unlinked", rowPath("/datasheets/alpha.pdf") EQ "");
    check("...and logged", arrayLen(application.lib.core.logged) EQ 1);
    store.failCopyTo = "";
    r = files.syncRecord("product", alpha);
    check("...the next sync publishes it", summary(r) EQ "p1 u0 k2 t0 f0" AND liveBody("/datasheets/alpha.pdf") EQ "sheet two" AND len(rowPath("/datasheets/alpha.pdf")), summary(r));

    // 3. A failed unpublish keeps the row, so the copy is never left public with nothing to remove it.
    store.failDeleteOf = "public/www/images/alpha/front-2.jpg";
    attach(alpha, "images", [front]);
    r = files.syncRecord("product", alpha);
    check("a failed unpublish is counted", summary(r) EQ "p0 u0 k2 t0 f1", summary(r));
    check("...its row stays, unlinked", rowPath("/images/alpha/front-2.jpg") EQ "" AND live("/images/alpha/front-2.jpg"));
    store.failDeleteOf = "";
    r = files.syncRecord("product", alpha);
    check("...the next sync removes copy and row", summary(r) EQ "p0 u1 k2 t0 f0" AND NOT live("/images/alpha/front-2.jpg") AND rowPath("/images/alpha/front-2.jpg") EQ "(no row)", summary(r));

    // 4. An address belongs to the first record to publish it.
    rival = newProduct("alpha", true);
    rivalSheet = newFile("rival.pdf", "rival sheet");
    attach(rival, "datasheet", [rivalSheet]);
    r = files.syncRecord("product", rival);
    check("a contested address stays its owner's", summary(r) EQ "p0 u0 k0 t1 f0" AND liveBody("/datasheets/alpha.pdf") EQ "sheet two", summary(r));

    // 5. syncAll: what a record deleted by SQL left behind goes first, so a waiting record gets its address in one run.
    queryExecute("DELETE FROM product WHERE id = :id::uuid", { id: alpha });
    r = files.syncAll();
    check("syncAll: the deleted record's files are unpublished", NOT live("/images/alpha/front.jpg") AND rowPath("/images/alpha/front.jpg") EQ "(no row)");
    check("...and the waiting record gets the address in the same run", liveBody("/datasheets/alpha.pdf") EQ "rival sheet", summary(r));

    // 6. One bad record doesn't stop syncAll.
    broken = newProduct("broken", true);
    missing = lCase(createGUID());
    queryExecute("INSERT INTO moo_file (id, name, path) VALUES (:id::uuid, 'gone.pdf', 'moo_file/none/gone.pdf')", { id: missing });
    attach(broken, "datasheet", [missing]);
    after = newProduct("zulu", true);
    zuluSheet = newFile("z.pdf", "zulu sheet");
    attach(after, "datasheet", [zuluSheet]);
    r = files.syncAll();
    check("syncAll: a record whose file is missing is counted", r.failed GTE 1, summary(r));
    check("...as is a publishing table not in the database, without stopping the rest", r.failed GTE 2, summary(r));
    check("...and the others are still published", liveBody("/datasheets/zulu.pdf") EQ "zulu sheet");

    // 7. The sweep: a missing or replaced copy is published again; a copy nothing accounts for under a publishing
    //    folder is deleted; anything outside those folders is left alone.
    store.deleteObject(store.defaultStore(), "public/www/datasheets/zulu.pdf");
    store.put("public/www/datasheets/stray.pdf", "stray", { "moopa-published": "1" });
    store.put("public/www/datasheets/by-hand.pdf", "by hand, in a publishing folder");
    store.put("public/www/brochures/by-hand.pdf", "by hand");
    store.setEtag("public/www/datasheets/alpha.pdf", "not-the-recorded-one");
    r = files.syncAll();
    check("sweep: a missing copy is published again", liveBody("/datasheets/zulu.pdf") EQ "zulu sheet");
    check("...as is one that isn't the recorded copy", r.repaired EQ 2, "repaired #r.repaired#");
    check("...a marked stray under a publishing prefix is removed", NOT live("/datasheets/stray.pdf") AND r.removed EQ 1, "removed #r.removed#");
    check("...an unmarked file there (published by hand) is left alone", live("/datasheets/by-hand.pdf"));
    check("...and so is a file published by hand elsewhere", live("/brochures/by-hand.pdf"));

    // 8. Inside a caller's transaction nothing is published (it could roll back); the next sync outside one does it.
    tx = newProduct("rolled", false);
    txSheet = newFile("tx.pdf", "tx sheet");
    attach(tx, "datasheet", [txSheet]);
    transaction {
        setProduct(tx, { is_published: true });
        inside = files.syncRecord("product", tx);
        insideAll = files.syncAll();
        transaction action="rollback";
    }
    check("in a transaction: deferred, nothing published", inside.deferred EQ 1 AND inside.published EQ 0 AND NOT live("/datasheets/rolled.pdf") AND rowPath("/datasheets/rolled.pdf") EQ "(no row)");
    check("...syncAll too", insideAll.deferred EQ 1);
    transaction {
        setProduct(tx, { is_published: true });
        files.syncRecord("product", tx);
    }
    r = files.syncRecord("product", tx);
    check("...committed, the next sync publishes it", liveBody("/datasheets/rolled.pdf") EQ "tx sheet" AND r.deferred EQ 0, summary(r));
    // A copy left without a row (a crash between copy and commit) is a marked stray: syncAll removes it.
    store.put("public/www/datasheets/crashed.pdf", "crashed", { "moopa-published": "1" });
    r = files.syncAll();
    check("...a marked copy left without its row is removed", NOT live("/datasheets/crashed.pdf") AND r.removed EQ 1, "removed #r.removed#");

    // 9. Unpublishing the record takes its files down.
    setProduct(after, { is_published: false });
    r = files.syncRecord("product", after);
    check("when false: unpublished", summary(r) EQ "p0 u1 k0 t0 f0" AND NOT live("/datasheets/zulu.pdf"), summary(r));

    // 10. A slug change moves the addresses.
    setProduct(rival, { slug: "bravo" });
    r = files.syncRecord("product", rival);
    check("a new slug moves the address", liveBody("/datasheets/bravo.pdf") EQ "rival sheet" AND NOT live("/datasheets/alpha.pdf") AND rowPath("/datasheets/alpha.pdf") EQ "(no row)", summary(r));

    // 11. Ids: the database's spelling, or its 32-digit form; nothing else.
    check("a 35-character CFML id is no record", summary(files.syncRecord("product", createUUID())) EQ "p0 u0 k0 t0 f0");
    compactProduct = newProduct("charlie", true);
    attach(compactProduct, "datasheet", [newFile("c.pdf", "charlie sheet")]);
    r = files.syncRecord("product", uCase(replace(compactProduct, "-", "", "all")));
    check("a 32-digit id is the record", liveBody("/datasheets/charlie.pdf") EQ "charlie sheet", summary(r));

    // 12. State a concurrent save left behind: nothing in the store is touched on a stale read.
    queryExecute("UPDATE product SET is_published = false WHERE id = :id::uuid", { id: compactProduct });
    stalePath = queryExecute("SELECT path FROM moo_published_file WHERE address = '/datasheets/charlie.pdf'").path;
    files.syncRecord("product", compactProduct);
    check("a repair from a stale read doesn't bring an unpublished copy back", NOT files.callRepair("public/www/datasheets/charlie.pdf", stalePath, "product", compactProduct) AND NOT live("/datasheets/charlie.pdf"));
    check("a stale retire leaves another record's copy alone", NOT files.callRetire("public/www/datasheets/bravo.pdf", "product", compactProduct) AND liveBody("/datasheets/bravo.pdf") EQ "rival sheet");
    check("a marked copy whose address a record holds is not a stray", NOT files.callRemoveStray("public/www/datasheets/bravo.pdf") AND live("/datasheets/bravo.pdf"));
    queryExecute("INSERT INTO moo_published_file (object_key, site, address, table_name, record_id, field, moo_file_id, path, etag) VALUES ('public/www/datasheets/claimed.pdf', 'www', '/datasheets/claimed.pdf', 'product', :id::uuid, 'datasheet', :id::uuid, '', '')", { id: rival });
    store.put("public/www/datasheets/claimed.pdf", "being published", { "moopa-published": "1" });
    check("...nor is one whose address is being claimed", NOT files.callRemoveStray("public/www/datasheets/claimed.pdf") AND live("/datasheets/claimed.pdf"));
    queryExecute("DELETE FROM moo_published_file WHERE address = '/datasheets/claimed.pdf'");

    // 13. A field that no longer publishes: its rows go in syncAll's first step.
    queryExecute("INSERT INTO moo_published_file (object_key, site, address, table_name, record_id, field, moo_file_id, path, etag) VALUES ('public/www/old/bravo.pdf', 'www', '/old/bravo.pdf', 'product', :id::uuid, 'brochure', :id::uuid, 'x', 'x')", { id: rival });
    store.put("public/www/old/bravo.pdf", "old brochure", { "moopa-published": "1" });
    r = files.syncAll();
    check("a retired field's copy and row are removed", NOT live("/old/bravo.pdf") AND rowPath("/old/bravo.pdf") EQ "(no row)");

    // 13b. Publishing by hand from a published copy is refused: the copy would keep its mark.
    try {
        files.publish("www", "/brochures/alias.pdf", "public/www/datasheets/bravo.pdf");
        aliasRefused = false;
    } catch (any e) {
        aliasRefused = e.type EQ "published_files.invalid";
    }
    check("publishing by hand from a published copy is refused", aliasRefused AND NOT live("/brochures/alias.pdf"));

    // 15. A statement that fails for one address (here: the store's etag too long to record) is rolled back to that
    //     address's savepoint: the record's other addresses still commit.
    echo = newProduct("echo", true);
    attach(echo, "datasheet", [newFile("e.pdf", "echo sheet")]);
    attach(echo, "images", [newFile("one.jpg", "one"), newFile("two.jpg", "two")]);
    store.longEtagFor = "public/www/images/echo/one.jpg";
    r = files.syncRecord("product", echo);
    store.longEtagFor = "";
    check("a statement failing for one address fails only that address", r.failed EQ 1 AND r.published EQ 2, summary(r));
    check("...the others are recorded", len(rowPath("/datasheets/echo.pdf")) AND len(rowPath("/images/echo/two.jpg")));
    check("...the failed one is left claimed and unlinked, for the next sync", rowPath("/images/echo/one.jpg") EQ "");
    r = files.syncRecord("product", echo);
    check("...which finishes it", r.published EQ 1 AND len(rowPath("/images/echo/one.jpg")), summary(r));

    // 16. While another operation holds the publishing lock, a sync waits the time it is given, then defers.
    thread name="holder" action="run" {
        transaction {
            queryExecute("SELECT pg_advisory_xact_lock(hashtext('moopa_published_files'))");
            sleep(3000);
        }
    }
    sleep(500);
    started = getTickCount();
    r = files.syncRecord("product", echo, 1);
    waited = getTickCount() - started;
    thread action="join" name="holder";
    check("a busy lock defers the sync after waitSeconds", r.deferred EQ 1 AND waited LT 2500, "deferred #r.deferred#, waited #waited# ms");
    r = files.syncRecord("product", echo);
    check("...and the next sync goes ahead", r.deferred EQ 0 AND r.kept EQ 3, summary(r));
    // A row lock met after the publishing lock is the work's failure, never "busy": the lock's wait doesn't outlive it.
    thread name="rowholder" action="run" {
        transaction {
            queryExecute("SELECT 1 FROM moo_published_file WHERE address = '/datasheets/echo.pdf' FOR UPDATE");
            sleep(2500);
        }
    }
    sleep(300);
    queryExecute("UPDATE product SET slug = 'echo-two' WHERE id = :id::uuid", { id: echo });
    started = getTickCount();
    r = files.syncRecord("product", echo, 1);
    rowWaited = getTickCount() - started;
    thread action="join" name="rowholder";
    check("...a row lock after the publishing lock waits for the row, not the lock's time", r.deferred EQ 0 AND r.failed EQ 0 AND rowWaited GTE 1500, "#summary(r)# waited #rowWaited# ms");
    r = files.syncRecord("product", echo);

    // 16b. waitSeconds is whole seconds, 0 to 3600.
    for (bad in [0.1, -1, 3601, "soon", [5], { "s": 5 }]) {
        try {
            files.syncRecord("product", echo, bad);
            badRefused = false;
        } catch (any e) {
            badRefused = e.type EQ "published_files.invalid";
        }
        check("waitSeconds #isSimpleValue(bad) ? bad : (isArray(bad) ? "(an array)" : "(a struct)")# is refused", badRefused);
    }
    // The lock_timeout the connection had is back after the lock is taken (here 250ms, set for this transaction).
    transaction {
        queryExecute("SET LOCAL lock_timeout = '250ms'");
        files.callTakeLock(2000);
        afterLock = queryExecute("SELECT current_setting('lock_timeout') AS s").s;
    }
    check("the connection's own lock_timeout is back after the lock", afterLock EQ "250ms", afterLock);

    // 17. A repair whose copy an earlier sweep already put right does nothing.
    echoKey = "public/www/datasheets/echo-two.pdf";
    echoPath = queryExecute("SELECT path FROM moo_published_file WHERE object_key = :k", { k: echoKey }).path;
    check("a repair of a copy that is already right does nothing", len(echoPath) AND NOT files.callRepair(echoKey, echoPath, "product", echo));

    // 14. A file no address can be made for is counted.
    nameless = newProduct("delta", true);
    attach(nameless, "images", [newFile("!!!.jpg", "no name")]);
    r = files.syncRecord("product", nameless);
    check("a file with no readable name is skipped, and counted", r.skipped EQ 1 AND r.published EQ 0, "skipped #r.skipped#");

    output = arrayToList(request.results, chr(10)) & chr(10) & chr(10) & (request.failures ? "#request.failures# of #arrayLen(request.results)# checks failed" : "All #arrayLen(request.results)# checks passed") & chr(10);
</cfscript>
</cfsilent><cfoutput>#output#</cfoutput><cfif request.failures><cfthrow message="#request.failures# published files checks failed" /></cfif>
