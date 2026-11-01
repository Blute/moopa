<!---
    Probe for scripts/test_db_search.sh: runs application.lib.db's search() and idsInSearchTerm()
    against the fixture tables and prints PASS, or FAIL with each failed check. The harness copies
    this file into a throwaway webroot beside a generated Application.cfc.
--->
<cfsetting enablecfoutputonly="true" />
<cfscript>
    failures = [];
    checks = 0;

    function check(required string label, required any actual, required any expected) {
        checks++;
        if (serializeJSON(arguments.actual) NEQ serializeJSON(arguments.expected)) {
            arrayAppend(failures, "#arguments.label#: expected #serializeJSON(arguments.expected)#, got #serializeJSON(arguments.actual)#");
        }
    }

    // Runs one group of checks; an error counts as a failure instead of stopping the probe.
    function attempt(required string label, required any body) {
        try {
            arguments.body();
        } catch (any e) {
            checks++;
            arrayAppend(failures, "#arguments.label#: threw #e.message#");
        }
    }

    function names(required array records) {
        var out = [];
        for (var record in arguments.records) {
            arrayAppend(out, record.name);
        }
        return out;
    }

    function ids(required array records) {
        var out = [];
        for (var record in arguments.records) {
            arrayAppend(out, lCase(record.id));
        }
        return out;
    }

    function lowerAll(required array values) {
        var out = [];
        for (var value in arguments.values) {
            arrayAppend(out, lCase(value));
        }
        return out;
    }

    application.moopa_packages = [{ path: "/db_search_fixture" }];
    db = createObject("component", "/moopa/lib/db").init();
    fields = "id,name,rank,owner_id";
    ownerId = "00000000-0000-0000-0000-0000000000a1";
    originalOrderBy = db.codeSchema.probe_item.order_by;

    // Text search: every whole-word match scores 1.00, so the primary key (id) decides among them;
    // the table's order_by (rank asc) does not. "widgets galore" scores lower and comes last.
    expectedNames = ["widget one", "widget two", "widget three", "widget four", "widget six", "widgets galore"];
    expectedIds = [
        "00000000-0000-0000-0000-000000000001",
        "00000000-0000-0000-0000-000000000002",
        "00000000-0000-0000-0000-000000000003",
        "00000000-0000-0000-0000-000000000004",
        "00000000-0000-0000-0000-000000000006",
        "00000000-0000-0000-0000-000000000005"
    ];

    attempt("search q=widget", function() {
        var found = db.search(table_name = "probe_item", field_list = fields, q = "widget", returnFormat = "cfml");
        check("search q=widget orders by score, then primary key", names(found), expectedNames);
        check("search q=widget repeats", names(db.search(table_name = "probe_item", field_list = fields, q = "widget", returnFormat = "cfml")), expectedNames);

        // Pages put together equal the whole list: no row skipped or repeated across pages.
        var paged = [];
        for (var offset in [0, 2, 4]) {
            arrayAppend(paged, names(db.search(table_name = "probe_item", field_list = fields, q = "widget", offset = offset, limit = 2, returnFormat = "cfml")), true);
        }
        check("search q=widget paged by 2", paged, expectedNames);
    });

    // idsInSearchTerm returns the same ids, in the same order, as the projected search, for any limit.
    attempt("idsInSearchTerm", function() {
        check("idsInSearchTerm widget", lowerAll(db.idsInSearchTerm(table_name = "probe_item", term = "widget")), expectedIds);
        for (var n = 1; n LTE 6; n++) {
            check(
                "idsInSearchTerm limit #n# equals search limit #n#",
                lowerAll(db.idsInSearchTerm(table_name = "probe_item", term = "widget", limit = n)),
                ids(db.search(table_name = "probe_item", field_list = fields, q = "widget", limit = n, returnFormat = "cfml"))
            );
        }
    });

    // A table's order_by that only the projected query can resolve, or that sorts a projected
    // alias differently from the raw column, plays no part in text-search order.
    orderByCases = [
        { label: "order_by names a select_append alias", order_by: "display_name asc", select_append: "upper(probe_item.name) AS display_name" },
        { label: "positional order_by", order_by: "2", select_append: "" },
        { label: "nullable foreign key order_by", order_by: "owner_id", select_append: "" }
    ];
    for (orderByCase in orderByCases) {
        db.codeSchema.probe_item.order_by = orderByCase.order_by;
        attempt(orderByCase.label, function() {
            var searched = db.search(table_name = "probe_item", field_list = fields, q = "widget", select_append = orderByCase.select_append, returnFormat = "cfml");
            check("#orderByCase.label#: search", ids(searched), expectedIds);
            check("#orderByCase.label#: idsInSearchTerm", lowerAll(db.idsInSearchTerm(table_name = "probe_item", term = "widget")), expectedIds);
            check("#orderByCase.label#: idsInSearchTerm limit 1", lowerAll(db.idsInSearchTerm(table_name = "probe_item", term = "widget", limit = 1)), [expectedIds[1]]);
            check("#orderByCase.label#: search limit 1", ids(db.search(table_name = "probe_item", field_list = fields, q = "widget", select_append = orderByCase.select_append, limit = 1, returnFormat = "cfml")), [expectedIds[1]]);
        });
    }
    db.codeSchema.probe_item.order_by = originalOrderBy;

    // Composite primary key with a non-unique id column: one row per page, every row once, in key order.
    attempt("composite primary key", function() {
        var pairFields = "group_code,item_code,name";
        var keys = [];
        for (var offset = 0; offset LT 6; offset++) {
            for (var record in db.search(table_name = "probe_pair", field_list = pairFields, q = "gadget", offset = offset, limit = 1, returnFormat = "cfml")) {
                arrayAppend(keys, record.group_code & record.item_code);
            }
        }
        check("composite primary key paged by 1", keys, ["a1", "a2", "a3", "b1", "b2"]);
    });

    // Without q the table's own order_by applies, as before.
    attempt("search without q", function() {
        var ranks = [];
        for (var record in db.search(table_name = "probe_item", field_list = fields, returnFormat = "cfml")) {
            arrayAppend(ranks, record.rank);
        }
        check("search without q orders by order_by", ranks, [0, 1, 1, 2, 2, 3]);
    });

    // sql_type: default and condensed give the linked record as {id, label}; simple gives the id;
    // expanded gives the linked record's fields.
    attempt("sql_type", function() {
        var one = ["00000000-0000-0000-0000-000000000001"];
        var defaultRecord = db.search(table_name = "probe_item", field_list = fields, ids = one, returnFormat = "cfml")[1];
        var condensedRecord = db.search(table_name = "probe_item", field_list = fields, ids = one, sql_type = "condensed", returnFormat = "cfml")[1];
        var simpleRecord = db.search(table_name = "probe_item", field_list = fields, ids = one, sql_type = "simple", returnFormat = "cfml")[1];
        var expandedRecord = db.search(table_name = "probe_item", field_list = fields, ids = one, sql_type = "expanded", returnFormat = "cfml")[1];

        check("default owner_id is {id, label}", [lCase(defaultRecord.owner_id.id), defaultRecord.owner_id.label, structKeyExists(defaultRecord.owner_id, "email")], [ownerId, "Alpha", false]);
        check("sql_type=condensed equals the default", serializeJSON(condensedRecord), serializeJSON(defaultRecord));
        check("sql_type=simple owner_id is the id", [isSimpleValue(simpleRecord.owner_id), lCase(simpleRecord.owner_id)], [true, ownerId]);
        check("sql_type=expanded owner_id has the owner's fields", [isStruct(expandedRecord.owner_id), expandedRecord.owner_id.email ?: ""], [true, "alpha@example.com"]);

        // sql_type with q: the projection changes, the order does not.
        check("sql_type=expanded with q keeps the order", names(db.search(table_name = "probe_item", field_list = fields, q = "widget", sql_type = "expanded", returnFormat = "cfml")), expectedNames);
    });

    // An unknown sql_type fails loudly instead of selecting nothing.
    threw = false;
    try {
        db.search(table_name = "probe_item", field_list = fields, q = "widget", sql_type = "full", returnFormat = "cfml");
    } catch (any e) {
        threw = findNoCase("sql_type", e.message) GT 0;
    }
    check("unknown sql_type throws", threw, true);

    // The tie-break terms themselves: primary key column(s), qualified with the table name.
    attempt("tie-break terms", function() {
        var builder = createObject("component", "/moopa/internal/db/projection_builder").init();
        check("tie-break: single key", builder.searchTieBreak({ table_name: "t", primary_keys: ["id"], order_by: "name asc" }), "t.id");
        check("tie-break: composite key", builder.searchTieBreak({ table_name: "t", primary_keys: ["a", "b"] }), "t.a,t.b");
        check("tie-break: no key", builder.searchTieBreak({ table_name: "t", primary_keys: [] }), "");
        check("tie-break: normalised probe_pair", builder.searchTieBreak(db.codeSchema.probe_pair), "probe_pair.group_code,probe_pair.item_code");
    });
</cfscript>
<cfif arrayLen(failures)>
    <cfoutput>FAIL #arrayLen(failures)# of #checks##chr(10)##arrayToList(failures, chr(10))##chr(10)#</cfoutput>
<cfelse>
    <cfoutput>PASS #checks# checks#chr(10)#</cfoutput>
</cfif>
