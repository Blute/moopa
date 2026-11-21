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
            "moo_file": { "fields": { "name": { "type": "varchar" }, "path": { "type": "varchar" } } }
        })
    };
    application.lib.published_files = createObject("component", "moopa.lib.published_files").init();
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
    check("...and the others are still published", liveBody("/datasheets/zulu.pdf") EQ "zulu sheet");

    // 7. The sweep: a missing or replaced copy is published again; a copy nothing accounts for under a publishing
    //    folder is deleted; anything outside those folders is left alone.
    store.deleteObject(store.defaultStore(), "public/www/datasheets/zulu.pdf");
    store.put("public/www/datasheets/stray.pdf", "stray");
    store.put("public/www/brochures/by-hand.pdf", "by hand");
    store.setEtag("public/www/datasheets/alpha.pdf", "not-the-recorded-one");
    r = files.syncAll();
    check("sweep: a missing copy is published again", liveBody("/datasheets/zulu.pdf") EQ "zulu sheet");
    check("...as is one that isn't the recorded copy", r.repaired EQ 2, "repaired #r.repaired#");
    check("...a stray under a publishing folder is removed", NOT live("/datasheets/stray.pdf") AND r.removed EQ 1, "removed #r.removed#");
    check("...a file published by hand elsewhere is left alone", live("/brochures/by-hand.pdf"));

    // 8. A transaction that rolls back takes the row, not the copy: the next syncAll removes the copy.
    tx = newProduct("rolled", false);
    txSheet = newFile("tx.pdf", "tx sheet");
    attach(tx, "datasheet", [txSheet]);
    transaction {
        setProduct(tx, { is_published: true });
        files.syncRecord("product", tx);
        transaction action="rollback";
    }
    check("rolled back: the copy outlived its row", live("/datasheets/rolled.pdf") AND rowPath("/datasheets/rolled.pdf") EQ "(no row)");
    r = files.syncAll();
    check("...syncAll removes it", NOT live("/datasheets/rolled.pdf") AND r.removed EQ 1, "removed #r.removed#");

    // 9. Unpublishing the record takes its files down.
    setProduct(after, { is_published: false });
    r = files.syncRecord("product", after);
    check("when false: unpublished", summary(r) EQ "p0 u1 k0 t0 f0" AND NOT live("/datasheets/zulu.pdf"), summary(r));

    // 10. A slug change moves the addresses.
    setProduct(rival, { slug: "bravo" });
    r = files.syncRecord("product", rival);
    check("a new slug moves the address", liveBody("/datasheets/bravo.pdf") EQ "rival sheet" AND NOT live("/datasheets/alpha.pdf") AND rowPath("/datasheets/alpha.pdf") EQ "(no row)", summary(r));

    // 11. Ids: only the database's own spelling.
    check("a 35-character CFML id is no record", summary(files.syncRecord("product", createUUID())) EQ "p0 u0 k0 t0 f0");

    output = arrayToList(request.results, chr(10)) & chr(10) & chr(10) & (request.failures ? "#request.failures# of #arrayLen(request.results)# checks failed" : "All #arrayLen(request.results)# checks passed") & chr(10);
</cfscript>
</cfsilent><cfoutput>#output#</cfoutput><cfif request.failures><cfthrow message="#request.failures# published files checks failed" /></cfif>
