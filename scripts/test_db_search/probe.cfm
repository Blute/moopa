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

    application.moopa_packages = [{ path: "/db_search_fixture" }];
    db = createObject("component", "/moopa/lib/db").init();
    fields = "id,name,rank,owner_id";
    ownerId = "00000000-0000-0000-0000-0000000000a1";

    // Text search: every whole-word match scores 1.00, so the table's order_by (rank asc) and then
    // id decide among them. "widgets galore" scores lower and still comes last despite rank 0.
    expectedNames = ["widget two", "widget six", "widget three", "widget four", "widget one", "widgets galore"];
    found = db.search(table_name = "probe_item", field_list = fields, q = "widget", returnFormat = "cfml");
    check("search q=widget orders by score, then order_by, then id", names(found), expectedNames);

    // The same call again returns the same order.
    check("search q=widget repeats", names(db.search(table_name = "probe_item", field_list = fields, q = "widget", returnFormat = "cfml")), expectedNames);

    // Pages put together equal the whole list: no row skipped or repeated across pages.
    paged = [];
    for (offset in [0, 2, 4]) {
        arrayAppend(paged, names(db.search(table_name = "probe_item", field_list = fields, q = "widget", offset = offset, limit = 2, returnFormat = "cfml")), true);
    }
    check("search q=widget paged by 2", paged, expectedNames);

    // idsInSearchTerm uses the same order.
    termIds = [];
    for (id in db.idsInSearchTerm(table_name = "probe_item", term = "widget")) {
        arrayAppend(termIds, lCase(id));
    }
    check("idsInSearchTerm widget", termIds, [
        "00000000-0000-0000-0000-000000000002",
        "00000000-0000-0000-0000-000000000006",
        "00000000-0000-0000-0000-000000000003",
        "00000000-0000-0000-0000-000000000004",
        "00000000-0000-0000-0000-000000000001",
        "00000000-0000-0000-0000-000000000005"
    ]);
    check("idsInSearchTerm matches search", termIds, ids(found));

    // Without q the table's own order_by applies, as before.
    ranks = [];
    for (record in db.search(table_name = "probe_item", field_list = fields, returnFormat = "cfml")) {
        arrayAppend(ranks, record.rank);
    }
    check("search without q orders by order_by", ranks, [0, 1, 1, 2, 2, 3]);

    // sql_type: default and condensed give the linked record as {id, label}; simple gives the id;
    // expanded gives the linked record's fields.
    defaultRecord = db.search(table_name = "probe_item", field_list = fields, ids = ["00000000-0000-0000-0000-000000000001"], returnFormat = "cfml")[1];
    condensedRecord = db.search(table_name = "probe_item", field_list = fields, ids = ["00000000-0000-0000-0000-000000000001"], sql_type = "condensed", returnFormat = "cfml")[1];
    simpleRecord = db.search(table_name = "probe_item", field_list = fields, ids = ["00000000-0000-0000-0000-000000000001"], sql_type = "simple", returnFormat = "cfml")[1];
    expandedRecord = db.search(table_name = "probe_item", field_list = fields, ids = ["00000000-0000-0000-0000-000000000001"], sql_type = "expanded", returnFormat = "cfml")[1];

    check("default owner_id is {id, label}", [lCase(defaultRecord.owner_id.id), defaultRecord.owner_id.label, structKeyExists(defaultRecord.owner_id, "email")], [ownerId, "Alpha", false]);
    check("sql_type=condensed equals the default", serializeJSON(condensedRecord), serializeJSON(defaultRecord));
    check("sql_type=simple owner_id is the id", [isSimpleValue(simpleRecord.owner_id), lCase(simpleRecord.owner_id)], [true, ownerId]);
    check("sql_type=expanded owner_id has the owner's fields", [isStruct(expandedRecord.owner_id), expandedRecord.owner_id.email ?: ""], [true, "alpha@example.com"]);

    // sql_type with q: the projection changes, the order does not.
    check("sql_type=expanded with q keeps the order", names(db.search(table_name = "probe_item", field_list = fields, q = "widget", sql_type = "expanded", returnFormat = "cfml")), expectedNames);

    // An unknown sql_type fails loudly instead of selecting nothing.
    threw = false;
    try {
        db.search(table_name = "probe_item", field_list = fields, q = "widget", sql_type = "full", returnFormat = "cfml");
    } catch (any e) {
        threw = findNoCase("sql_type", e.message) GT 0;
    }
    check("unknown sql_type throws", threw, true);

    // The tie-break terms themselves.
    builder = createObject("component", "/moopa/internal/db/projection_builder").init();
    try {
        check("tie-break: order_by then id", builder.searchTieBreak({ order_by: "name asc", fields: { id: {} } }), "name asc,id");
        check("tie-break: no order_by", builder.searchTieBreak({ order_by: "", fields: { id: {} } }), "id");
        check("tie-break: no id field", builder.searchTieBreak({ order_by: "name asc", fields: {} }), "name asc");
    } catch (any e) {
        checks++;
        arrayAppend(failures, "tie-break: #e.message#");
    }
</cfscript>
<cfif arrayLen(failures)>
    <cfoutput>FAIL #arrayLen(failures)# of #checks##chr(10)##arrayToList(failures, chr(10))##chr(10)#</cfoutput>
<cfelse>
    <cfoutput>PASS #checks# checks#chr(10)#</cfoutput>
</cfif>
