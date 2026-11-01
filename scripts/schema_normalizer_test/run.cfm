<cfsilent>
<!---
    Regression harness for internal/db/schema_normalizer.cfc: what an expanded link carries
    from the table it links to (sensitive, expand_fields, and a field's expand: "condensed").
    Normalizes fixture table definitions, no database needed, and checks the generated SQL.

    Run from Moopa's root:
        bash scripts/test_schema_normalizer.sh
--->
<cfscript>
    results = [];
    failures = 0;

    function check(required string label, required boolean ok, string detail = "") {
        arrayAppend(results, (arguments.ok ? "PASS  " : "FAIL  ") & arguments.label & (arguments.ok OR !len(arguments.detail) ? "" : chr(10) & "      " & arguments.detail));
        if (!arguments.ok) failures++;
    }

    function has(required string sql, required string fragment) {
        return findNoCase(arguments.fragment, arguments.sql) GT 0;
    }

    function squash(required string sql) {
        return trim(reReplace(arguments.sql, "\s+", " ", "all"));
    }

    // A person table holding private fields, and three tables that link to it: booking by a uuid
    // foreign key, team by a many_to_many list, and person (back) by a relation to note.
    function fixture(struct personExtra = {}, struct bookingFieldExtra = {}) {
        var definitions = {
            "person": {
                "fields": {
                    "name": { "type": "varchar" },
                    "email": { "type": "varchar", "condensed": true },
                    "date_of_birth": { "type": "date" },
                    "medical_notes": { "type": "text" },
                    "tax_file_number": { "type": "varchar", "sensitive": true },
                    "notes": { "type": "relation", "foreign_key_table": "person_note", "foreign_key_field": "person_id" }
                }
            },
            "person_note": {
                "fields": {
                    "person_id": { "type": "uuid", "foreign_key_table": "person" },
                    "body": { "type": "text" },
                    "private_body": { "type": "text" }
                }
            },
            "booking": {
                "fields": {
                    "person_id": { "type": "uuid", "foreign_key_table": "person" },
                    "backup_person_id": { "type": "uuid", "foreign_key_table": "person" }
                }
            },
            "team": {
                "fields": {
                    "members": { "type": "many_to_many", "foreign_key_table": "person" }
                }
            }
        };
        structAppend(definitions.person, arguments.personExtra, true);
        structAppend(definitions.booking.fields.person_id, arguments.bookingFieldExtra, true);
        return definitions;
    }

    function normalized(struct definitions) {
        return createObject("component", "moopa.internal.db.schema_normalizer").init().normalize(arguments.definitions, {});
    }

    function normalizeError(struct definitions) {
        try {
            normalized(arguments.definitions);
        } catch (any e) {
            return e.message;
        }
        return "";
    }

    projection = createObject("component", "moopa.internal.db.projection_builder").init();

    // 1. No new options: links carry every non-sensitive field, as before.
    schema = normalized(fixture());
    fk = schema.booking.fields.person_id.sql_select_expanded;
    m2m = schema.team.fields.members.sql_select_expanded;
    check("default: a uuid link carries the private fields", has(fk, "'date_of_birth', date_of_birth") AND has(fk, "'medical_notes', medical_notes"), squash(fk));
    check("default: a uuid link leaves out a sensitive field", !has(fk, "tax_file_number"), squash(fk));
    check("default: a many_to_many link carries the private fields", has(m2m, "'date_of_birth', person.date_of_birth"), squash(m2m));
    check("default: a many_to_many link leaves out a sensitive field", !has(m2m, "tax_file_number"), squash(m2m));
    check("default: _expand_fields is empty", (schema.person._expand_fields ?: "") EQ "", schema.person._expand_fields ?: "");
    check("default: a uuid link stays expanded", fk NEQ schema.booking.fields.person_id.sql_select_condensed);
    check("default: a condensed uuid link carries id and the condensed fields", has(schema.booking.fields.person_id.sql_select_condensed, "json_build_object('id',id,'email',email)"), squash(schema.booking.fields.person_id.sql_select_condensed));
    check("default: a condensed many_to_many link carries id and the condensed fields", has(schema.team.fields.members.sql_select_condensed, "jsonb_build_object('id',id,'email',email)"), squash(schema.team.fields.members.sql_select_condensed));
    check("default: a condensed relation carries id and label", has(squash(schema.person.fields.notes.sql_select_condensed), "SELECT id,label FROM person_note"), squash(schema.person.fields.notes.sql_select_condensed));

    // 2. expand_fields on the linked table: links carry only the listed fields, plus id.
    schema = normalized(fixture({ "expand_fields": " label, name ,email,name,tax_file_number" }));
    fk = schema.booking.fields.person_id.sql_select_expanded;
    m2m = schema.team.fields.members.sql_select_expanded;
    check("expand_fields: cached trimmed, deduplicated, with id first", (schema.person._expand_fields ?: "") EQ "id,label,name,email,tax_file_number", schema.person._expand_fields ?: "");
    check("expand_fields: a uuid link carries the listed fields and id", has(fk, "'id', id::text") AND has(fk, "'label', label") AND has(fk, "'name', name") AND has(fk, "'email', email"), squash(fk));
    check("expand_fields: a uuid link leaves out unlisted fields", !has(fk, "date_of_birth") AND !has(fk, "medical_notes") AND !has(fk, "created_at") AND !has(fk, "created_by"), squash(fk));
    check("expand_fields: a many_to_many link carries the listed fields", has(m2m, "'name', person.name") AND has(m2m, "'id', person.id::text"), squash(m2m));
    check("expand_fields: a many_to_many link leaves out unlisted fields", !has(m2m, "date_of_birth") AND !has(m2m, "medical_notes"), squash(m2m));
    check("expand_fields: a listed sensitive field is still left out", !has(fk, "tax_file_number") AND !has(m2m, "tax_file_number"), squash(fk));
    check("expand_fields: a condensed link carries a listed condensed field", has(schema.booking.fields.person_id.sql_select_condensed, "json_build_object('id',id,'email',email)"), squash(schema.booking.fields.person_id.sql_select_condensed));
    direct = projection.select(tableDef = schema.person, sql_type = "expanded");
    check("expand_fields: a direct read of the table still has every non-sensitive field", has(direct, "person.date_of_birth AS date_of_birth") AND has(direct, "person.medical_notes AS medical_notes") AND !has(direct, "tax_file_number"), direct);

    // 3. expand_fields on the far side of a relation.
    definitions = fixture();
    definitions.person_note.expand_fields = "person_id,body";
    schema = normalized(definitions);
    rel = schema.person.fields.notes.sql_select_expanded;
    check("expand_fields: a relation carries the listed fields", has(rel, "person_note.body AS body") AND has(rel, "person_note.id::text as id"), squash(rel));
    check("expand_fields: a relation leaves out unlisted fields", !has(rel, "private_body") AND !has(rel, "AS created_at"), squash(rel));
    definitions = fixture();
    schema = normalized(definitions);
    check("default: a relation carries every field", has(schema.person.fields.notes.sql_select_expanded, "person_note.private_body AS private_body"), squash(schema.person.fields.notes.sql_select_expanded));

    // 3b. expand_fields also bounds condensed links: a condensed: true field outside the list
    // stays out; id and label always pass.
    definitions = fixture({ "expand_fields": "id,name" }, { "expand": "condensed" });
    definitions.person.fields.medical_notes.condensed = true;
    definitions.person.fields.label = { "type": "varchar", "condensed": true };
    definitions.person_note.expand_fields = "body";
    definitions.person_note.fields.body.condensed = true;
    definitions.person_note.fields.private_body.condensed = true;
    schema = normalized(definitions);
    fk = schema.booking.fields.backup_person_id.sql_select_condensed;
    m2m = schema.team.fields.members.sql_select_condensed;
    rel = schema.person.fields.notes.sql_select_condensed;
    check("expand_fields: a condensed uuid link leaves out unlisted condensed fields", !has(fk, "email") AND !has(fk, "medical_notes"), squash(fk));
    check("expand_fields: a condensed uuid link keeps id and label", has(fk, "json_build_object('id',id,'label',label)"), squash(fk));
    check("expand_fields: a condensed many_to_many link leaves out unlisted condensed fields", !has(m2m, "email") AND !has(m2m, "medical_notes"), squash(m2m));
    check("expand_fields: a condensed many_to_many link keeps id and label", has(m2m, "jsonb_build_object('id',id,'label',label)"), squash(m2m));
    check("expand_fields: a condensed relation leaves out unlisted condensed fields", !has(rel, "private_body"), squash(rel));
    check("expand_fields: a condensed relation keeps id and listed condensed fields", has(squash(rel), "SELECT id,body FROM person_note"), squash(rel));
    read = projection.select(tableDef = schema.booking, sql_type = "expanded");
    forced = schema.booking.fields.person_id.sql_select_expanded;
    check("expand_fields: a forced-condensed link in an expanded read leaves out unlisted condensed fields", !has(forced, "email") AND !has(forced, "medical_notes") AND has(forced, "json_build_object('id',id,'label',label)"), squash(forced));
    check("expand_fields: an expanded read of the linking table carries neither", !has(read, "email") AND !has(read, "medical_notes") AND !has(read, "date_of_birth"), squash(read));

    // 4. expand_fields is checked at startup.
    message = normalizeError(fixture({ "expand_fields": "id,name,birthday" }));
    check("expand_fields: an unknown field fails naming table and field", message EQ "Table person expand_fields references unknown field: birthday", message);
    message = normalizeError(fixture({ "expand_fields": " , " }));
    check("expand_fields: an empty list fails", message EQ "Table person expand_fields is empty. List the fields a link may carry, or remove expand_fields.", message);
    message = normalizeError(fixture({ "expand_fields": ["id", "name"] }));
    check("expand_fields: an array fails", message EQ "Table person expand_fields must be a comma-separated list of field names", message);

    // 5. expand: "condensed" on a uuid link.
    schema = normalized(fixture({}, { "expand": "condensed" }));
    fk = schema.booking.fields.person_id;
    check("expand condensed: the expanded projection is the condensed one", fk.sql_select_expanded EQ fk.sql_select_condensed, squash(fk.sql_select_expanded));
    check("expand condensed: it carries id and the condensed fields only", has(fk.sql_select_expanded, "'id',id") AND has(fk.sql_select_expanded, "'email',email") AND !has(fk.sql_select_expanded, "date_of_birth"), squash(fk.sql_select_expanded));
    check("expand condensed: another link on the table stays expanded", has(schema.booking.fields.backup_person_id.sql_select_expanded, "'date_of_birth', date_of_birth"), squash(schema.booking.fields.backup_person_id.sql_select_expanded));
    read = projection.select(tableDef = schema.booking, sql_type = "expanded");
    check("expand condensed: an expanded read of the linking table uses it", has(read, "json_build_object('id',id,'email',email)") AND has(read, "'date_of_birth', date_of_birth"), squash(read));

    // 6. expand is checked at startup.
    message = normalizeError(fixture({}, { "expand": "expanded" }));
    check("expand: a value other than condensed fails", message EQ "Table booking field person_id expand must be ""condensed""", message);
    definitions = fixture();
    definitions.person.fields.name.expand = "condensed";
    message = normalizeError(definitions);
    check("expand: a field that is not a uuid link fails", message EQ "Table person field name declares expand, which only a uuid field with a foreign_key_table supports", message);
    definitions = fixture();
    definitions.team.fields.members.expand = "condensed";
    message = normalizeError(definitions);
    check("expand: a many_to_many field fails", message EQ "Table team field members declares expand, which only a uuid field with a foreign_key_table supports", message);

    output = arrayToList(results, chr(10)) & chr(10) & chr(10) & (failures ? "#failures# of #arrayLen(results)# checks failed" : "All #arrayLen(results)# checks passed") & chr(10);
</cfscript>
</cfsilent><cfoutput>#output#</cfoutput><cfif failures><cfthrow message="#failures# schema normalizer checks failed" /></cfif>
