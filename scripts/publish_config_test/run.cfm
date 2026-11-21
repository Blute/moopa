<cfsilent>
<!---
    Regression harness for a table definition's publish settings (internal/db/publish_config.cfc) and the addresses
    lib/published_files.cfc makes from them (addressFor). Reads fixture table definitions through the schema normalizer,
    no database or store needed. The publishing itself (syncRecord, syncAll) needs both; docs/object-storage.md says how
    it was checked.

    Run from Moopa's root:
        bash scripts/test_publish_config.sh
--->
<cfscript>
    results = [];
    failures = 0;

    function check(required string label, required boolean ok, string detail = "") {
        arrayAppend(results, (arguments.ok ? "PASS  " : "FAIL  ") & arguments.label & (arguments.ok OR !len(arguments.detail) ? "" : chr(10) & "      " & arguments.detail));
        if (!arguments.ok) failures++;
    }

    config = createObject("component", "moopa.internal.db.publish_config").init();

    // A product with a datasheet and pictures, as a project declares it, normalized as Moopa does at start.
    function product(any datasheetPublish = { "site": "www", "address": "/datasheets/{slug}.pdf", "when": "is_published" }) {
        return createObject("component", "moopa.internal.db.schema_normalizer").init().normalize({
            "product": { "fields": {
                "slug": { "type": "varchar" },
                "name_en": { "type": "varchar" },
                "is_published": { "type": "bool" },
                "datasheet": { "type": "many_to_many", "foreign_key_table": "moo_file", "publish": arguments.datasheetPublish },
                "images": { "type": "many_to_many", "foreign_key_table": "moo_file", "publish": { "site": "www", "address": "/images/{slug}/{name}.{ext}" } },
                "files": { "type": "many_to_many", "foreign_key_table": "moo_file" }
            } },
            "moo_file": { "fields": { "name": { "type": "varchar" }, "path": { "type": "varchar" } } }
        }, {});
    }

    function invalid(any publish) {
        try {
            config.build(product(arguments.publish));
            return "";
        } catch (any error) {
            return error.type EQ "moopa.publish.invalid" ? error.message : error.type & ": " & error.message;
        }
    }

    // 1. Nothing publishes: no table, nothing to do (every project that doesn't use it).
    plain = createObject("component", "moopa.internal.db.schema_normalizer").init().normalize({
        "thing": { "fields": { "files": { "type": "many_to_many", "foreign_key_table": "moo_file" } } },
        "moo_file": { "fields": { "name": { "type": "varchar" } } }
    }, {});
    check("no publish setting: nothing publishes", NOT config.anyPublished(plain) AND structIsEmpty(config.build(plain)));

    // 2. A valid setting survives normalizing and is read.
    built = config.build(product());
    check("publishing fields are read, the others not", structKeyList(built) EQ "product" AND listSort(structKeyList(built.product), "text") EQ "datasheet,images");
    check("...with the bridging table Moopa made", built.product.datasheet.bridge EQ "product_datasheet" AND built.product.images.bridge EQ "product_images");
    check("...when", built.product.datasheet.when EQ "is_published" AND built.product.images.when EQ "");
    check("...an address without {name} publishes the first file only", built.product.datasheet.first AND NOT built.product.images.first);
    check("...a column whose name starts with name is not the file's {name}", config.build(product({ "site": "www", "address": "/datasheets/{name_en}.pdf" })).product.datasheet.first);

    // 3. Mistakes fail at start, naming the table and field.
    check("publish not a struct", invalid("x") CONTAINS "product.datasheet");
    check("a site with capitals", len(invalid({ "site": "WWW", "address": "/a.pdf" })));
    check("a site with a trailing newline", len(invalid({ "site": "www" & chr(10), "address": "/a.pdf" })));
    check("an address without a leading /", len(invalid({ "site": "www", "address": "a.pdf" })));
    check("an address ending in /", len(invalid({ "site": "www", "address": "/datasheets/" })));
    check("an address with a space", len(invalid({ "site": "www", "address": "/data sheets/{slug}.pdf" })));
    check("an address with a percent", len(invalid({ "site": "www", "address": "/d/%7Bslug%7D.pdf" })));
    check("a placeholder that is no column", invalid({ "site": "www", "address": "/d/{sku}.pdf" }) CONTAINS "{sku}");
    check("a placeholder that is a many_to_many field", len(invalid({ "site": "www", "address": "/d/{images}.pdf" })));
    check("when that is no column", invalid({ "site": "www", "address": "/a.pdf", "when": "live" }) CONTAINS "live");
    check("when that is not a bool column", len(invalid({ "site": "www", "address": "/a.pdf", "when": "slug" })));
    try {
        config.build({ "t": { "fields": { "slug": { "type": "varchar", "publish": { "site": "www", "address": "/a.pdf" } } } } });
        notFile = "";
    } catch (any error) {
        notFile = error.type;
    }
    check("a field that is not a file field", notFile EQ "moopa.publish.invalid");

    check("a misspelt key (wen) fails, rather than publishing always", invalid({ "site": "www", "address": "/a.pdf", "wen": "is_published" }) CONTAINS "wen");
    check("when as a list fails", len(invalid({ "site": "www", "address": "/a.pdf", "when": ["is_published"] })));
    check("when as a struct fails", len(invalid({ "site": "www", "address": "/a.pdf", "when": { "field": "is_published" } })));
    check("when empty fails", len(invalid({ "site": "www", "address": "/a.pdf", "when": " " })));
    check("an uppercase literal fails (one spelling per address)", len(invalid({ "site": "www", "address": "/Datasheets/{slug}.pdf" })));
    check("an empty segment fails", len(invalid({ "site": "www", "address": "/d//{slug}.pdf" })));
    check("a .. segment fails", len(invalid({ "site": "www", "address": "/d/../{slug}.pdf" })));
    check("a . segment fails", len(invalid({ "site": "www", "address": "/d/./{slug}.pdf" })));
    check("a segment over 200 characters fails", len(invalid({ "site": "www", "address": "/" & repeatString("a", 201) & "/{slug}.pdf" })));
    try {
        withJson = createObject("component", "moopa.internal.db.schema_normalizer").init().normalize({
            "product": { "fields": { "slug": { "type": "varchar" }, "meta": { "type": "jsonb" },
                "datasheet": { "type": "many_to_many", "foreign_key_table": "moo_file", "publish": { "site": "www", "address": "/d/{meta}.pdf" } } } },
            "moo_file": { "fields": { "name": { "type": "varchar" } } } }, {});
        config.build(withJson);
        jsonMessage = "";
    } catch (any error) {
        jsonMessage = error.type;
    }
    check("a jsonb column as a placeholder fails", jsonMessage EQ "moopa.publish.invalid");
    try {
        twice = createObject("component", "moopa.internal.db.schema_normalizer").init().normalize({
            "product": { "fields": { "slug": { "type": "varchar" },
                "a": { "type": "many_to_many", "foreign_key_table": "moo_file", "publish": { "site": "www", "address": "/d/{slug}.pdf" } },
                "b": { "type": "many_to_many", "foreign_key_table": "moo_file", "publish": { "site": "www", "address": "/d/{slug}.pdf" } } } },
            "moo_file": { "fields": { "name": { "type": "varchar" } } } }, {});
        config.build(twice);
        twiceMessage = "";
    } catch (any error) {
        twiceMessage = error.type;
    }
    check("two fields at the same addresses on one site fail", twiceMessage EQ "moopa.publish.invalid");

    // 4. What syncAll needs from a setting: the columns to read, and the literal prefix it sweeps.
    check("columns: the placeholders and when", arrayToList(built.product.datasheet.columns) EQ "slug,is_published" AND arrayToList(built.product.images.columns) EQ "slug");
    check("prefix: the literal start, before the first placeholder", built.product.datasheet.prefix EQ "/datasheets/" AND built.product.images.prefix EQ "/images/");
    check("prefix: a fixed address is its own", config.build(product({ "site": "www", "address": "/docs/terms.pdf" })).product.datasheet.prefix EQ "/docs/terms.pdf");
    check("prefix: part of a name", config.build(product({ "site": "www", "address": "/docs/product-{slug}.pdf" })).product.datasheet.prefix EQ "/docs/product-");
    check("a template without a literal folder fails (it could never be swept)", len(invalid({ "site": "www", "address": "/{slug}.pdf" })) AND len(invalid({ "site": "www", "address": "/terms-{slug}.pdf" })));
    check("a template making keys over 1024 bytes fails", len(invalid({ "site": "www", "address": "/d/" & repeatString("a/", 520) & "{slug}.pdf" })));

    // 5. Addresses made from a template, a record and a file name.
    files = createObject("component", "moopa.lib.published_files").init();
    check("{field}, {name} and {ext}", files.addressFor("/images/{slug}/{name}.{ext}", { "slug": "widget" }, "Front View.JPG") EQ "/images/widget/front-view.jpg");
    check("values made readable", files.addressFor("/p/{title}/{name}.{ext}", { "title": "Big Bin (2 m³)" }, "Photo ##1.png") EQ "/p/big-bin-2-m/photo-1.png");
    check("a file without an extension has no {ext}", files.addressFor("/p/{name}.{ext}", {}, "README") EQ "");
    check("an empty value gives no address", files.addressFor("/d/{slug}.pdf", { "slug": "" }, "x.pdf") EQ "");
    check("a missing value gives no address", files.addressFor("/d/{slug}.pdf", {}, "x.pdf") EQ "");
    check("a fixed address", files.addressFor("/datasheets/{slug}.pdf", { "slug": "tipper" }, "Anything.PDF") EQ "/datasheets/tipper.pdf");
    check("a file name with a trailing space", files.addressFor("/p/{name}.{ext}", {}, "Photo.JPG ") EQ "/p/photo.jpg");
    check("a long value ends without a dash", right(files.addressFor("/p/{title}.pdf", { "title": repeatString("a", 119) & " b" }, "x.pdf"), 5) NEQ "-.pdf");

    output = arrayToList(results, chr(10)) & chr(10) & chr(10) & (failures ? "#failures# of #arrayLen(results)# checks failed" : "All #arrayLen(results)# checks passed") & chr(10);
</cfscript>
</cfsilent><cfoutput>#output#</cfoutput><cfif failures><cfthrow message="#failures# published files checks failed" /></cfif>
