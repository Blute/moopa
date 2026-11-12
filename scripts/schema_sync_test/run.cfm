<cfsilent>
<!---
    Regression harness for lib/schemaSync.cfc's normalizeExpression(): a table definition's column
    default or generation expression and the one Postgres stored (pg_get_expr) compare equal when
    they mean the same, so the Schema page never proposes a change that is already made, and still
    differ when they don't. The stored forms are what Postgres 18 returns. No database needed.

    Run from Moopa's root:
        bash scripts/test_schema_sync.sh
--->
<cfscript>
    results = [];
    failures = 0;
    sync = createObject("component", "moopa.lib.schemaSync").init();

    function check(required string label, required boolean ok, string detail = "") {
        arrayAppend(results, (arguments.ok ? "PASS  " : "FAIL  ") & arguments.label & (arguments.ok OR !len(arguments.detail) ? "" : chr(10) & "      " & arguments.detail));
        if (!arguments.ok) failures++;
    }

    function same(required string label, required string definition, required string stored) {
        var a = sync.normalizeExpression(arguments.definition);
        var b = sync.normalizeExpression(arguments.stored);
        check(arguments.label, a EQ b, "definition: " & a & "  stored: " & b);
    }

    function differs(required string label, required string definition, required string stored) {
        var a = sync.normalizeExpression(arguments.definition);
        var b = sync.normalizeExpression(arguments.stored);
        check(arguments.label, a NEQ b, "both: " & a);
    }

    // 1. A function named by a keyword: Postgres double-quotes it.
    same("left() is stored as ""left""()",
        "left(COALESCE(lookup_key::text, id::text), 255)",
        '"left"(COALESCE(lookup_key, (id)::text), 255)');
    same("right() is stored as ""right""()",
        "right(code, 4)",
        '"right"((code)::text, 4)');

    // 2. Casts and parentheses Postgres adds around a concatenation.
    same("a concatenated label",
        "COALESCE(name::text, '') || ' ' || COALESCE(email::text, '')",
        "((COALESCE((name)::text, ''::text) || ' '::text) || COALESCE((email)::text, ''::text))");
    same("a label from one column",
        "COALESCE(email::text, id::text)",
        "COALESCE((email)::text, (id)::text)");

    // 3. TRIM(x) is stored as TRIM(BOTH FROM x).
    same("TRIM is stored as TRIM(BOTH FROM",
        "TRIM(name)",
        "TRIM(BOTH FROM name)");

    // 4. Defaults.
    same("a jsonb default", "'[]'", "'[]'::jsonb");
    same("a function default", "gen_random_uuid()", "gen_random_uuid()");
    same("a default written over several lines", "jsonb_build_object(" & chr(10) & "    'a', 1" & chr(13) & chr(10) & ")", "jsonb_build_object('a', 1)");

    // 5. Real differences still show.
    differs("a different length", "left(COALESCE(lookup_key::text, id::text), 200)", '"left"(COALESCE(lookup_key, (id)::text), 255)');
    differs("a different column", "COALESCE(email::text, id::text)", "COALESCE((name)::text, (id)::text)");
    differs("a different default", "'[""a""]'", "'[""a"", ""b""]'::jsonb");
    differs("a default where none is stored", "now()", "");

    output = arrayToList(results, chr(10)) & chr(10) & chr(10) & (failures ? "#failures# of #arrayLen(results)# checks failed" : "All #arrayLen(results)# checks passed") & chr(10);
</cfscript>
</cfsilent><cfoutput>#output#</cfoutput><cfif failures><cfthrow message="#failures# schema sync checks failed" /></cfif>
