<cfcomponent displayName="schemaSync" hint="The statements that bring the database in line with the table definitions (compareDatabaseSchema), for the Schema page (docs/schema.md). It reads the catalogue and builds SQL text; it never changes the database.">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>

    <cffunction name="normalizeExpression" returntype="string" access="public" output="false"
                hint="A column default or generation expression reduced to the shape both sides share, so a definition's expression and the one Postgres stored compare equal when they mean the same. Postgres adds casts (::text) and parentheses, double-quotes a function or column whose name is a keyword (left(...) is stored as ""left""(...)), and writes TRIM(x) as TRIM(BOTH FROM x); casts, parentheses, double quotes and whitespace are removed from both sides.">
        <cfargument name="expression" type="string" required="true" />

        <cfset var normalized = reReplace(arguments.expression, '::[a-zA-Z0-9_ ]*|[()"\s]', "", "all") />
        <cfreturn replaceNoCase(normalized, "TRIMBOTHFROM", "TRIM", "all") />
    </cffunction>

    <cffunction name="loadDatabaseSchema" returntype="struct" access="public" output="false" hint="Loads database schema metadata for all tables in the current schema in one pass.">
        <cfset var schema = { "tables": {} } />
        <cfset var tableName = "" />
        <cfset var columns = [] />
        <cfset var indexes = [] />
        <cfset var foreignKeys = [] />
        <cfset var primaryKeys = [] />
        <cfset var qSchema = "" />
        <cfset var column = {} />
        <cfset var indexRow = {} />
        <cfset var foreignKey = {} />
        <cfset var primaryKey = {} />

        <cfquery name="qSchema">
        WITH columns_meta AS (
          SELECT
            c.relname AS table_name,
            a.attnum AS ordinal_position,
            a.attname AS column_name,
            t.typname as data_type,
            CASE
                WHEN t.typname IN ('varchar','bpchar') AND a.atttypmod > 4 THEN a.atttypmod - 4
            END AS character_maximum_length,
            CASE
                WHEN t.typname = 'numeric' AND a.atttypmod <> -1 THEN ((a.atttypmod - 4) >> 16) & 65535
                WHEN t.typname = 'int2' THEN 16
                WHEN t.typname = 'int4' THEN 32
                WHEN t.typname = 'int8' THEN 64
                WHEN t.typname = 'float4' THEN 24
                WHEN t.typname = 'float8' THEN 53
            END AS numeric_precision,
            CASE
                WHEN t.typname = 'numeric' AND a.atttypmod <> -1 THEN (a.atttypmod - 4) & 65535
                WHEN t.typname IN ('int2','int4','int8') THEN 0
            END AS numeric_scale,
            NOT a.attnotnull AS is_nullable,
            -- Both expressions as Postgres stored them: compareDatabaseSchema puts them and the
            -- definitions' through normalizeExpression() before comparing.
            CASE
                WHEN a.attgenerated = '' AND d.adbin IS NOT NULL THEN pg_get_expr(d.adbin, d.adrelid)
                ELSE ''
            END AS column_default,
            CASE
                WHEN a.attgenerated = 's' THEN 'ALWAYS'
                ELSE 'NEVER'
            END AS is_generated,
            CASE
                WHEN a.attgenerated = 's' AND d.adbin IS NOT NULL THEN pg_get_expr(d.adbin, d.adrelid)
                ELSE ''
            END AS generation_expression,
            -- The columns a generated column reads, from the dependency catalogue Postgres enforces
            -- (ALTER COLUMN TYPE on any of them is refused until the generated column is dropped).
            COALESCE((
                SELECT string_agg(ra.attname, ',' ORDER BY ra.attname)
                FROM pg_depend dep
                JOIN pg_attribute ra ON ra.attrelid = dep.refobjid AND ra.attnum = dep.refobjsubid
                WHERE a.attgenerated = 's'
                  AND dep.classid = 'pg_attrdef'::regclass AND dep.objid = d.oid
                  AND dep.refclassid = 'pg_class'::regclass AND dep.refobjid = a.attrelid
                  AND dep.refobjsubid > 0 AND dep.refobjsubid <> a.attnum
            ), '') AS generation_depends_on
          FROM pg_attribute a
          JOIN pg_class c ON c.oid = a.attrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_type t ON t.oid = a.atttypid
          LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
          WHERE c.relkind IN ('r','p')
            AND n.nspname = current_schema()
            AND a.attnum > 0
            AND NOT a.attisdropped
        ),
        indexes_meta AS (
          SELECT
              t.relname AS table_name,
              i.relname AS name,
              string_agg(
                  a.attname || CASE WHEN (ix.indoption[array_position(ix.indkey, a.attnum)] & 1) = 1 THEN ' desc' ELSE '' END,
                  ', ' ORDER BY array_position(ix.indkey, a.attnum)
              ) AS fields,
              ix.indisunique AS unique,
              am.amname AS type,
              pg_get_indexdef(i.oid) AS indexdef,
              COALESCE(pg_get_expr(ix.indpred, ix.indrelid), '') AS "where"
          FROM
              pg_class t
          JOIN
              pg_index ix ON t.oid = ix.indrelid
          JOIN
              pg_class i ON ix.indexrelid = i.oid
          JOIN
              pg_namespace n ON n.oid = t.relnamespace
          JOIN
              pg_attribute a ON a.attrelid = t.oid AND a.attnum = ANY(ix.indkey)
          LEFT JOIN
              pg_constraint c ON c.conrelid = ix.indrelid AND c.conname = i.relname AND c.contype = 'p'
          JOIN
              pg_am am ON i.relam = am.oid
          WHERE
              t.relkind = 'r'
              AND n.nspname = current_schema()
              AND c.conname IS NULL
          GROUP BY
              t.relname, i.relname, ix.indisunique, am.amname, i.oid, ix.indpred, ix.indrelid
        ),
        foreign_keys_meta AS (
          -- Composite foreign keys aggregate to comma-separated column lists (no spaces),
          -- matching the table-definition declaration format, e.g. field_name "owner_id,id".
          SELECT
              c.conname as name,
              src.relname as table_name,
              string_agg(src_col.attname, ',' ORDER BY cols.ord) as field_name,
              tgt.relname AS foreign_key_table,
              string_agg(tgt_col.attname, ',' ORDER BY cols.ord) AS foreign_key_field,
              CASE c.confupdtype
                  WHEN 'a' THEN 'NO ACTION'
                  WHEN 'r' THEN 'RESTRICT'
                  WHEN 'c' THEN 'CASCADE'
                  WHEN 'n' THEN 'SET NULL'
                  WHEN 'd' THEN 'SET DEFAULT'
              END AS "onUpdate",
              CASE c.confdeltype
                  WHEN 'a' THEN 'NO ACTION'
                  WHEN 'r' THEN 'RESTRICT'
                  WHEN 'c' THEN 'CASCADE'
                  WHEN 'n' THEN 'SET NULL'
                  WHEN 'd' THEN 'SET DEFAULT'
              END AS "onDelete"
            FROM
              pg_constraint c
              JOIN pg_class src ON src.oid = c.conrelid
              JOIN pg_namespace src_ns ON src_ns.oid = src.relnamespace
              JOIN pg_class tgt ON tgt.oid = c.confrelid
              JOIN LATERAL unnest(c.conkey, c.confkey) WITH ORDINALITY AS cols(src_attnum, tgt_attnum, ord) ON true
              JOIN pg_attribute src_col ON src_col.attrelid = src.oid AND src_col.attnum = cols.src_attnum
              JOIN pg_attribute tgt_col ON tgt_col.attrelid = tgt.oid AND tgt_col.attnum = cols.tgt_attnum
          WHERE
              c.contype = 'f'
              AND src_ns.nspname = current_schema()
          GROUP BY
              c.conname, src.relname, tgt.relname, c.confupdtype, c.confdeltype
        ),
        primary_keys_meta AS (
          SELECT
              n.nspname AS table_schema,
              c.relname AS table_name,
              con.conname as primary_key_name,
              string_agg(att.attname, ',' ORDER BY cols.ord) as primary_key_columns
          FROM
              pg_constraint con
          JOIN
              pg_class c ON c.oid = con.conrelid
          JOIN
              pg_namespace n ON n.oid = c.relnamespace
          JOIN
              LATERAL unnest(con.conkey) WITH ORDINALITY AS cols(attnum, ord) ON true
          JOIN
              pg_attribute att ON att.attrelid = c.oid AND att.attnum = cols.attnum
          WHERE
              con.contype = 'p'
              AND n.nspname = current_schema()
          GROUP BY
              n.nspname,
              c.relname,
              con.conname
        )
        SELECT
            COALESCE((SELECT jsonb_agg(to_jsonb(columns_meta) ORDER BY table_name, ordinal_position) FROM columns_meta), '[]'::jsonb)::text AS columns_json,
            COALESCE((SELECT jsonb_agg(to_jsonb(indexes_meta) ORDER BY table_name, name) FROM indexes_meta), '[]'::jsonb)::text AS indexes_json,
            COALESCE((SELECT jsonb_agg(to_jsonb(foreign_keys_meta) ORDER BY table_name, name) FROM foreign_keys_meta), '[]'::jsonb)::text AS foreign_keys_json,
            COALESCE((SELECT jsonb_agg(to_jsonb(primary_keys_meta) ORDER BY table_name, primary_key_name) FROM primary_keys_meta), '[]'::jsonb)::text AS primary_keys_json;
        </cfquery>

        <cfset columns = deserializeJSON(qSchema.columns_json) />
        <cfset indexes = deserializeJSON(qSchema.indexes_json) />
        <cfset foreignKeys = deserializeJSON(qSchema.foreign_keys_json) />
        <cfset primaryKeys = deserializeJSON(qSchema.primary_keys_json) />

        <cfloop array="#columns#" item="column">
            <cfset tableName = column.table_name />
            <cfif NOT structKeyExists(schema.tables, tableName)>
                <cfset schema.tables[tableName] = { "columns": [], "indexes": {}, "foreign_keys": {}, "primary_key": {} } />
            </cfif>
            <cfset arrayAppend(schema.tables[tableName].columns, column) />
        </cfloop>

        <cfloop array="#indexes#" item="indexRow">
            <cfset tableName = indexRow.table_name />
            <cfif NOT structKeyExists(schema.tables, tableName)>
                <cfset schema.tables[tableName] = { "columns": [], "indexes": {}, "foreign_keys": {}, "primary_key": {} } />
            </cfif>
            <cfset schema.tables[tableName].indexes[indexRow.name] = indexRow />
        </cfloop>

        <cfloop array="#foreignKeys#" item="foreignKey">
            <cfset tableName = foreignKey.table_name />
            <cfif NOT structKeyExists(schema.tables, tableName)>
                <cfset schema.tables[tableName] = { "columns": [], "indexes": {}, "foreign_keys": {}, "primary_key": {} } />
            </cfif>
            <cfset schema.tables[tableName].foreign_keys[foreignKey.name] = foreignKey />
        </cfloop>

        <cfloop array="#primaryKeys#" item="primaryKey">
            <cfset tableName = primaryKey.table_name />
            <cfif NOT structKeyExists(schema.tables, tableName)>
                <cfset schema.tables[tableName] = { "columns": [], "indexes": {}, "foreign_keys": {}, "primary_key": {} } />
            </cfif>
            <cfset schema.tables[tableName].primary_key = primaryKey />
        </cfloop>

        <cfreturn schema />
    </cffunction>

      <cffunction name="normalizeIndexPredicate" returntype="string" access="public" hint="Normalizes a partial-index WHERE predicate for equality comparison. Postgres canonicalises predicates (adds parens + type casts e.g. ((status)::text = 'open'::text)), so code-declared forms like ""status = 'open'"" need to be reduced to the same shape before diffing.">
        <cfargument name="expr" type="string" required="true" />
        <cfset var s = lcase(trim(arguments.expr)) />
        <!--- Strip PG type casts like ::text, ::varchar(20), ::int4, ::numeric(10,2) --->
        <cfset s = reReplace(s, "::[a-z0-9_]+(\s*\([0-9, ]+\))?", "", "all") />
        <!--- Drop all parens and whitespace — partial predicates we support are simple equality/boolean checks where paren nesting is not semantically meaningful. --->
        <cfset s = reReplace(s, "[()\s]+", "", "all") />
        <cfreturn s />
      </cffunction>


  <cffunction name="compareDatabaseSchema" returntype="array"
              hint="The statements that bring the database in line with the table definitions, in run order. Each carries destructive (Moopa's System → Schema page hides those by default): true only for dropping a column the definitions no longer declare, which loses its data. Everything else is false, including dropping an index, foreign key or default and retyping a column, and dropping a generated column the same script adds back.">
    <cfargument name="codeSchema" type="struct" required="true">

    <cfset var result = []>
    <cfset var dbSchema = loadDatabaseSchema() />
    <cfset var dbTableSchema = {} />

    <cfloop collection="#arguments.codeSchema#" item="code_table_schema" index="table_name">

      <!--- Check if table exists --->
      <cfset dbTableSchema = structKeyExists(dbSchema.tables, table_name)
          ? dbSchema.tables[table_name]
          : { "columns": [], "indexes": {}, "foreign_keys": {}, "primary_key": {} } />
      <cfset db_table_columns = dbTableSchema.columns>

      <cfif !arrayLen(db_table_columns)>

        <cfset sql = createTableFromCodeSchema(code_table_schema) />
        <cfset result = result.merge(sql) />

      <cfelse>
        <!--- Check columns, constraints, and indexes --->

        <!--- Generated columns cannot be altered in place: a changed expression, or a type change on any
              column they reference (SQLSTATE 0A000), means drop-then-recreate. Per-table state keeps each
              such column scheduled once and tells the index pass which of its indexes to build again. --->
        <cfset local.generatedRecreate = { "columns": {}, "indexes": {} } />



        <!--- Check columns --->
        <cfloop collection="#code_table_schema.fields#" item="code_field_schema" index="field_name">

          <cfset found_column_in_db = ArrayFilter(db_table_columns, function(column) { return column.column_name == field_name; })>

          <cfif !arrayLen(found_column_in_db)>
            <cfif !listFindNoCase("many_to_many,relation",code_field_schema.type)>
                <!--- A required column with no default cannot land on a populated table in one
                      statement: Postgres refuses ADD COLUMN ... NOT NULL when existing rows have
                      nothing to hold (SQLSTATE 23502). It is added nullable here; once the data
                      pass has filled every row, the next comparison sees code NOT NULL against a
                      nullable column and proposes SET NOT NULL through the ordinary nullability
                      branch below. A generated column computes its own value and is exempt. --->
                <cfset local.deferNotNull = !(code_field_schema.is_nullable ?: true)
                    AND !len(code_field_schema.default ?: '')
                    AND !len(code_field_schema.generation_expression ?: '') />
                <cfset columnDef = getColumnDef(code_field_schema, local.deferNotNull) />
                <cfset ArrayAppend(result, {
                "table_name": table_name,
                "priority": 10,
                "type": "ADD COLUMN",
                "destructive": false,
                "title": "ADD COLUMN: #table_name#.#field_name#" & (local.deferNotNull ? " (added nullable — fill every row, then re-run: the next pass proposes SET NOT NULL)" : ""),
                "statement": "ALTER TABLE " & table_name & " ADD COLUMN " & columnDef
                })>
            </cfif>
          <cfelse>
            <cfset column_in_db = found_column_in_db[1] />
            <!--- Check for altered columns --->
            <cfset altered = false>

            <cfif findNoCase('serial', code_field_schema.type)>
                <!---
                Once deployed we assume serials have been setup correctly. If not, you will need to drop the column and add again or convince me to write the sql to handle
                This is becuase you really need to know what your doing with existing values in the column and needs more thought than just "change to serial"
                --->

                <cfcontinue>
            </cfif>

            <!--- Check for altered data type. The target type carries its
                  modifiers — TYPE varchar without a length would silently drop
                  the cap on a text→varchar(N) change. --->
            <cfif code_field_schema.type neq column_in_db.data_type>
              <cfset local.alterTypeSpec = code_field_schema.type />
              <cfif code_field_schema.type EQ "varchar" AND len(code_field_schema.max_length ?: "")>
                  <cfset local.alterTypeSpec = "varchar(#code_field_schema.max_length#)" />
              <cfelseif code_field_schema.type EQ "numeric" AND len(code_field_schema.precision ?: "")>
                  <cfset local.alterTypeSpec = "numeric(#code_field_schema.precision#, #code_field_schema.scale ?: 0#)" />
              </cfif>
              <cfset arrayAppend(result, alterColumnType(table_name, field_name, local.alterTypeSpec, 11, code_table_schema, db_table_columns, dbTableSchema.indexes, local.generatedRecreate), true) />
            </cfif>




            <!--- Check for altered default value --->

            <cfset simplifyExpression = normalizeExpression(code_field_schema.default ?: '') />
            <cfset simplifyDBExpression = normalizeExpression(column_in_db.column_default) />

            <cfif simplifyExpression neq simplifyDBExpression>
                <cfif len(trim(code_field_schema.default ?: ''))>
                    <cfset ArrayAppend(result, {
                      "table_name": table_name,
                      "priority": 1,
                      "type": "ALTER COLUMN",
                      "destructive": false,
                      "title": "ALTER COLUMN: #table_name#.#field_name#",
                      "statement": "ALTER TABLE #table_name# ALTER COLUMN #field_name# SET DEFAULT #code_field_schema.default#;",
                      "hint": "default: #code_field_schema.default# simplified into: #simplifyExpression# NEQ #column_in_db.column_default#"
                    })>
                <cfelse>
                    <!--- The definition declares no default and the database still carries one:
                          drop it, rather than emitting SET DEFAULT with nothing after it. --->
                    <cfset ArrayAppend(result, {
                      "table_name": table_name,
                      "priority": 1,
                      "type": "ALTER COLUMN",
                      "destructive": false,
                      "title": "ALTER COLUMN: #table_name#.#field_name# (drop default)",
                      "statement": "ALTER TABLE #table_name# ALTER COLUMN #field_name# DROP DEFAULT;",
                      "hint": "code declares no default; database has: #column_in_db.column_default#"
                    })>
                </cfif>
            </cfif>

            <!--- Check for altered nullable property --->

            <cfif code_field_schema.is_nullable neq column_in_db.is_nullable>

                <cfif code_field_schema.is_nullable>
                    <!--- Code wants nullable: DROP NOT NULL to allow nulls --->
                    <cfset ArrayAppend(result, {
                        "table_name": table_name,
                        "priority": 1,
                        "type": "ALTER COLUMN",
                        "destructive": false,
                        "title": "ALTER COLUMN: #table_name#.#field_name#",
                        "statement": "ALTER TABLE #table_name# ALTER COLUMN #field_name# DROP NOT NULL;"
                    })>
                <cfelse>
                    <!--- Code wants NOT NULL: SET NOT NULL to disallow nulls --->
                    <cfset ArrayAppend(result, {
                        "table_name": table_name,
                        "priority": 1,
                        "type": "ALTER COLUMN",
                        "destructive": false,
                        "title": "ALTER COLUMN: #table_name#.#field_name#",
                        "statement": "ALTER TABLE #table_name# ALTER COLUMN #field_name# SET NOT NULL;"
                      })>
                </cfif>
            </cfif>



            <!--- Now check for length — only against a same-typed DB column: a
                  cross-type change is the data-type branch's job (which carries
                  the modifiers), and the DB-side length metadata is NULL for
                  other types (e.g. character_maximum_length on text). --->
            <cfif code_field_schema.type EQ "numeric" AND column_in_db.data_type EQ "numeric">
                <cfif code_field_schema.precision NEQ column_in_db.numeric_precision OR code_field_schema.scale NEQ column_in_db.numeric_scale>
                    <cfset arrayAppend(result, alterColumnType(table_name, field_name, "numeric(#code_field_schema.precision#, #code_field_schema.scale#)", 1, code_table_schema, db_table_columns, dbTableSchema.indexes, local.generatedRecreate), true) />
                </cfif>
            </cfif>

            <cfif code_field_schema.type EQ "varchar" AND column_in_db.data_type EQ "varchar">
                <cfif code_field_schema.max_length NEQ (column_in_db.character_maximum_length ?: "")>
                    <cfset arrayAppend(result, alterColumnType(table_name, field_name, "varchar(#code_field_schema.max_length#)", 1, code_table_schema, db_table_columns, dbTableSchema.indexes, local.generatedRecreate), true) />
                </cfif>
            </cfif>




            <!--- GENERATED COLUMNS CAN NOT BE ALTERED. WE NEED TO DROP AND ADD A GENERATED COLUMN IN THE NEXT REFRESH. --->
            <cfset simplifyExpression = normalizeExpression(code_field_schema.generation_expression ?: '') />
            <cfset simplifyDbExpression = normalizeExpression(column_in_db.generation_expression) />

            <cfif simplifyExpression neq simplifyDbExpression>
                <cfset genMismatches = [{
                    "param": "generation_expression",
                    "db": simplifyDbExpression,
                    "code": simplifyExpression
                }] />
                <cfset arrayAppend(result, recreateGeneratedColumn(table_name, field_name, code_table_schema, dbTableSchema.indexes, local.generatedRecreate, genMismatches), true) />
            </cfif>


          </cfif>


        </cfloop>

        <!--- Check for additional columns --->
        <cfloop array="#db_table_columns#" item="column_in_db" index="i">
          <cfif NOT structKeyExists(code_table_schema.fields, column_in_db.column_name)>
            <cfset ArrayAppend(result, {
              "table_name": table_name,
              "priority": 6,
              "type": "DROP COLUMN",
              "destructive": true,
              "title": "DROP COLUMN: #table_name#.#column_in_db.column_name#",
              "statement": "ALTER TABLE " & table_name & " DROP COLUMN " & column_in_db.column_name & ";"
            })>
          </cfif>
        </cfloop>




        <!--- Now check for keys, indexes and foreign keys --->
        <!--- <cfset db_primary_keys = getTablePrimaryKeys(table_name)> --->
        <cfset db_indexes = dbTableSchema.indexes>
        <cfset db_foreign_keys = dbTableSchema.foreign_keys>
        <cfset db_primary_key = dbTableSchema.primary_key>


        <!--- Now check for Foreign Keys --->

        <cfloop collection="#code_table_schema.indexes#" item="code_index" index="code_index_name">
            <cfset drop_index = false>
            <cfset create_index = false>
            <cfset index_mismatches = [] />
            <cftry>
            <!--- An index dropped ahead of a generated-column recreate is gone by the time this runs: build it again. --->
            <cfset found_index_in_db = structKeyExists(db_indexes,code_index_name) AND NOT structKeyExists(local.generatedRecreate.indexes, code_index_name)>


            <cfif !(found_index_in_db)>
                <!--- We need to create the index --->
                <cfset create_index = true>
            <cfelse>
                <!--- We need to check to make sure everything matches. If it doesnt match, lets drop it and mark to create --->
                <!--- Only compare keys that exist in DB: fields, type, unique, where (not name, comment) --->
                <cfset params_to_compare = "fields,type,unique,where" />

                <cfloop list="#params_to_compare#" item="code_index_param" index="i">

                    <cfif code_index_param EQ "where">
                        <!--- Normalise both sides through the partial-predicate canoniser so ("status = 'open'" vs "((status)::text = 'open'::text)") compares equal. --->
                        <cfset codeIndexFieldList = normalizeIndexPredicate(code_index.where ?: '') />
                        <cfset dbIndexFieldList = normalizeIndexPredicate(db_indexes[code_index_name].where ?: '') />
                    <cfelse>
                        <cfset codeIndexFieldList = listSort(lcase(reReplace(code_index[code_index_param], "\s+", "", "ALL")),"textnocase") />
                        <cfset dbIndexFieldList = listSort(lcase(reReplace((db_indexes[code_index_name][code_index_param]?:''), "\s+", "", "ALL")),"textnocase") />
                    </cfif>

                    <cfif codeIndexFieldList NEQ dbIndexFieldList>
                        <cfset arrayAppend(index_mismatches, {
                            "param": code_index_param,
                            "code": codeIndexFieldList,
                            "db": dbIndexFieldList
                        }) />
                        <cfset drop_index = true>
                        <cfset create_index = true>
                    </cfif>
                </cfloop>


            </cfif>

                <cfcatch>
                    <cfthrow message="Schema sync failed reconciling index #code_index_name# on #table_name#: #cfcatch.message#" detail="#cfcatch.detail ?: ''#" />
                </cfcatch>
            </cftry>

            <cfif create_index>

                <cfset index_field_list = code_index.fields />
                <cfif code_index.type EQ "gin">
                    <cfset index_field_list = ListMap(index_field_list, function(term) { return term & " gin_trgm_ops"; })>
                </cfif>

                <!--- Build the WITH clause if index has options --->
                <cfset with_clause = "" />
                <cfif len(code_index.with_options?:'')>
                    <cfset with_clause = " WITH (#code_index.with_options#)" />
                </cfif>

                <!--- Build the WHERE clause for partial indexes --->
                <cfset where_clause = "" />
                <cfif len(code_index.where?:'')>
                    <cfset where_clause = " WHERE (#code_index.where#)" />
                </cfif>

                <!--- A changed index is dropped with the other drops and created with the other creates, never as
                      one combined statement: its new definition may name a column this same pass only adds (priority
                      10) or retypes (priority 8), so the CREATE must wait until every column change has run. --->
                <cfif drop_index>
                    <cfset arrayAppend(result, {
                        "table_name": "#table_name#",
                        "priority": 5,
                        "type": "DROP INDEX",
                        "destructive": false,
                        "title": "DROP INDEX #code_index.name# (definition changed — rebuilt below)",
                        "statement": "DROP INDEX #code_index.name#",
                        "mismatches": index_mismatches
                    }) />
                </cfif>

                <cfset arrayAppend(result, {
                    "table_name": "#table_name#",
                    "priority": 14,
                    "type": "CREATE INDEX",
                    "destructive": false,
                    "title": "CREATE INDEX #code_index.name#" & (drop_index ? " (rebuilt)" : ""),
                    "statement": "CREATE #code_index.unique ? "UNIQUE" : ""# INDEX #code_index.name# ON #table_name# USING #code_index.type# (#index_field_list#)#with_clause##where_clause#",
                    "mismatches": index_mismatches
                }) />
            </cfif>
        </cfloop>



        <!--- Check for additional indexes --->
        <cfloop collection="#db_indexes#" item="db_index" index="db_index_name">
            <cftry>
            <cfif NOT structKeyExists(code_table_schema.indexes, db_index_name)>
                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 4,
                    "type": "DROP INDEX",
                    "destructive": false,
                    "title": "DROP INDEX #table_name#.#db_index_name#",
                    "statement": 'DROP INDEX #db_index_name#'
                } />

                <cfset arrayAppend(result, sqlStatement) />
            </cfif>
            <cfcatch>
                <cfthrow message="Schema sync failed reconciling database index #db_index_name# on #table_name#: #cfcatch.message#" detail="#cfcatch.detail ?: ''#" />
            </cfcatch>
            </cftry>
        </cfloop>


        <!--- PRIMARY KEY --->
        <cfif arrayLen(code_table_schema.primary_keys)>
            <cfset drop_pk = false>
            <cfset create_pk = false>

            <cfset code_pk_name = "#table_name#_pkey" />

            <cfif structIsEmpty(db_primary_key)>
                <!--- NO PRIMARY KEY AT ALL --->
                <cfset create_pk = true>

            <cfelseif db_primary_key.primary_key_name EQ code_pk_name>
                <!--- We have the correct primary key name--->

                <cfif db_primary_key.primary_key_columns NEQ arrayToList(code_table_schema.primary_keys)>
                    <!--- PRIMARY KEY IS DIFFERENT --->
                    <cfset drop_pk = true>
                    <cfset create_pk = true>
                </cfif>
            <cfelse>
                <!--- INCORRECT PRIMARY KEY CONSTRAINT NAME --->
                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 13,
                    "type": "RENAME PRIMARY KEY",
                    "destructive": false,
                    "title": "RENAME PRIMARY KEY #table_name#.#db_primary_key.primary_key_name#",
                    "statement": 'ALTER TABLE #table_name# RENAME CONSTRAINT #db_primary_key.primary_key_name# TO #code_pk_name#'
                } />

                <cfset arrayAppend(result, sqlStatement) />


            </cfif>

            <cfif drop_pk>
                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 1,
                    "type": "DROP PRIMARY KEY",
                    "destructive": false,
                    "title": "DROP PRIMARY KEY #table_name#.#db_primary_key.primary_key_name#",
                    "statement": 'ALTER TABLE #table_name# DROP CONSTRAINT #db_primary_key.primary_key_name#'
                } />

                <cfset arrayAppend(result, sqlStatement) />
            </cfif>

            <cfif create_pk>

                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 12,
                    "type": "ADD PRIMARY KEY",
                    "destructive": false,
                    "title": "ADD PRIMARY KEY #table_name#.#code_pk_name#",
                    "statement": 'ALTER TABLE #table_name# ADD CONSTRAINT #code_pk_name# PRIMARY KEY (#arrayToList(code_table_schema.primary_keys)#)'
                } />

                <cfset arrayAppend(result, sqlStatement) />
            </cfif>

        </cfif>



        <!--- FOREIGN KEYS --->
        <cfloop collection="#code_table_schema.foreign_keys#" item="code_fk" index="code_fk_name">

          <cfset drop_fk = false>
          <cfset create_fk = false>

          <cfset found_fk_in_db = structKeyExists(db_foreign_keys,code_fk_name)>

          <cfif !(found_fk_in_db)>
            <!--- We need to create the foregin key --->
            <cfset create_fk = true>
          <cfelse>
            <!--- We need to check to make sure everything matches. If it doesnt match, lets drop it and mark to create.
                  Whitespace is stripped so a composite column list declared as "owner_id, id" still matches the
                  database's "owner_id,id" representation. --->
            <cfloop list="#structKeyList(code_fk)#" item="code_fk_param" index="i">
                <cfif reReplace(code_fk[code_fk_param], "\s+", "", "ALL") NEQ reReplace((db_foreign_keys[code_fk_name][code_fk_param]?:''), "\s+", "", "ALL")>
                    <cfset drop_fk = true>
                    <cfset create_fk = true>
                </cfif>
            </cfloop>


          </cfif>


          <cfif create_fk>
            <!--- The constraint is named by its table-definition key (identical to the legacy
                  fk_<table>_<field> convention for field-level FKs). Column lists are emitted
                  per-column so composite foreign keys generate valid DDL. --->
            <cfset fk_source_columns = reReplace(code_fk.field_name, "\s+", "", "ALL") />
            <cfset fk_target_columns = listQualify(reReplace(code_fk.foreign_key_field, "\s+", "", "ALL"), '"') />
            <cfif drop_fk>
                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 3,
                    "type": "DROP/ADD CONSTRAINT",
                    "destructive": false,
                    "title": "DROP/ADD CONSTRAINT #table_name#.#code_fk_name#",
                    "statement": 'ALTER TABLE #table_name# DROP CONSTRAINT #code_fk_name#, ADD CONSTRAINT #code_fk_name# FOREIGN KEY (#fk_source_columns#) REFERENCES "#code_fk.foreign_key_table#" (#fk_target_columns#) ON DELETE #code_fk.onDelete# ON UPDATE #code_fk.onUpdate#'
                } />
                <cfset arrayAppend(result, sqlStatement) />
            <cfelse>
                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 15,
                    "type": "ADD CONSTRAINT",
                    "destructive": false,
                    "title": "ADD CONSTRAINT #table_name#.#code_fk_name#",
                    "statement": 'ALTER TABLE #table_name# ADD CONSTRAINT #code_fk_name# FOREIGN KEY (#fk_source_columns#) REFERENCES "#code_fk.foreign_key_table#" (#fk_target_columns#) ON DELETE #code_fk.onDelete# ON UPDATE #code_fk.onUpdate#'
                } />
                <cfset arrayAppend(result, sqlStatement) />
            </cfif>

          </cfif>
        </cfloop>


        <!--- Check for additional foreign keys --->
        <cfloop collection="#db_foreign_keys#" item="db_fk" index="db_fk_name">
            <cfif NOT structKeyExists(code_table_schema.foreign_keys, db_fk_name)>
                <cfset sqlStatement = {
                    "table_name": "#table_name#",
                    "priority": 2,
                    "type": "DROP CONSTRAINT",
                    "destructive": false,
                    "title": "DROP CONSTRAINT #table_name#.#db_fk_name#",
                    "statement": 'ALTER TABLE #table_name# DROP CONSTRAINT #db_fk_name#'
                } />

                <cfset arrayAppend(result, sqlStatement) />
            </cfif>
          </cfloop>




      </cfif>



    </cfloop>


    <cfif arrayLen(result)>
        <cfset arraySort(result, sortByPriority ) />
    </cfif>

    <cfreturn result>
  </cffunction>





    <cffunction name="generatedColumnsDependingOn" returntype="array" access="private" output="false"
                hint="Names of the database generated columns that read the given column, per generation_depends_on (the pg_depend catalogue, loaded with the column metadata). Postgres refuses ALTER COLUMN TYPE on a column a generated column reads (SQLSTATE 0A000) until that generated column is dropped.">
        <cfargument name="column_name" type="string" required="true" />
        <cfargument name="db_table_columns" type="array" required="true" />

        <cfset var dependents = [] />
        <cfset var column_in_db = {} />

        <cfloop array="#arguments.db_table_columns#" item="column_in_db">
            <cfif listFindNoCase(column_in_db.generation_depends_on, arguments.column_name)>
                <cfset arrayAppend(dependents, column_in_db.column_name) />
            </cfif>
        </cfloop>

        <cfreturn dependents />
    </cffunction>

    <cffunction name="recreateGeneratedColumn" returntype="array" access="private" output="false"
                hint="Statements that drop a generated column and add it back from its code definition — the only way to change its expression or the type of a column it references. Every code-declared index over it is dropped first and marked so the index pass builds it again; a generated column code no longer declares is left to the additional-columns pass, which drops it for good. Scheduled at most once per table pass.">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="column_name" type="string" required="true" />
        <cfargument name="code_table_schema" type="struct" required="true" />
        <cfargument name="db_indexes" type="struct" required="true" />
        <cfargument name="recreate" type="struct" required="true" hint="Per-table state: columns already scheduled, indexes dropped for the index pass to recreate." />
        <cfargument name="mismatches" type="array" required="false" default="#[]#" />

        <cfset var statements = [] />
        <cfset var db_index = {} />
        <cfset var db_index_name = "" />
        <cfset var index_column = "" />

        <cfif structKeyExists(arguments.recreate.columns, arguments.column_name)
              OR NOT structKeyExists(arguments.code_table_schema.fields, arguments.column_name)>
            <cfreturn statements />
        </cfif>
        <cfset arguments.recreate.columns[arguments.column_name] = true />

        <cfloop collection="#arguments.db_indexes#" item="db_index" index="db_index_name">
            <cfif NOT structKeyExists(arguments.code_table_schema.indexes, db_index_name)>
                <cfcontinue />
            </cfif>
            <cfloop list="#db_index.fields#" item="index_column">
                <!--- DB index fields read "col" or "col desc". --->
                <cfif listFirst(trim(index_column), " ") EQ arguments.column_name>
                    <cfset arguments.recreate.indexes[db_index_name] = true />
                    <cfset arrayAppend(statements, {
                        "table_name": arguments.table_name,
                        "priority": 4,
                        "type": "DROP INDEX",
                        "destructive": false,
                        "title": "DROP INDEX: #db_index_name# (before recreating generated column #arguments.column_name#)",
                        "statement": "DROP INDEX IF EXISTS #db_index_name#;"
                    }) />
                    <cfbreak />
                </cfif>
            </cfloop>
        </cfloop>

        <cfset arrayAppend(statements, {
            "table_name": arguments.table_name,
            "priority": 6,
            "type": "DROP COLUMN",
            "destructive": false,
            "title": "DROP COLUMN: #arguments.table_name#.#arguments.column_name# (generated — added back below)",
            "statement": "ALTER TABLE #arguments.table_name# DROP COLUMN #arguments.column_name#;",
            "mismatches": arguments.mismatches
        }) />

        <cfset arrayAppend(statements, {
            "table_name": arguments.table_name,
            "priority": 10,
            "type": "ADD COLUMN",
            "destructive": false,
            "title": "ADD COLUMN: #arguments.table_name#.#arguments.column_name#",
            "statement": "ALTER TABLE #arguments.table_name# ADD COLUMN " & getColumnDef(arguments.code_table_schema.fields[arguments.column_name]),
            "mismatches": arguments.mismatches
        }) />

        <cfreturn statements />
    </cffunction>

    <cffunction name="alterColumnType" returntype="array" access="private" output="false"
                hint="ALTER COLUMN TYPE for one column. When a generated column references it Postgres refuses the change (SQLSTATE 0A000, cannot alter type of a column used by a generated column), so every dependent generated column is scheduled for drop-then-recreate and the ALTER slots between the drop (priority 6) and the add (priority 10).">
        <cfargument name="table_name" type="string" required="true" />
        <cfargument name="field_name" type="string" required="true" />
        <cfargument name="type_spec" type="string" required="true" />
        <cfargument name="priority" type="numeric" required="true" hint="Priority when nothing depends on the column." />
        <cfargument name="code_table_schema" type="struct" required="true" />
        <cfargument name="db_table_columns" type="array" required="true" />
        <cfargument name="db_indexes" type="struct" required="true" />
        <cfargument name="recreate" type="struct" required="true" />

        <cfset var statements = [] />
        <cfset var dependents = generatedColumnsDependingOn(arguments.field_name, arguments.db_table_columns) />
        <cfset var dependent = "" />
        <cfset var priority = arguments.priority />
        <cfset var title = "ALTER COLUMN: #arguments.table_name#.#arguments.field_name#" />

        <cfif arrayLen(dependents)>
            <cfloop array="#dependents#" item="dependent">
                <cfset arrayAppend(statements, recreateGeneratedColumn(arguments.table_name, dependent, arguments.code_table_schema, arguments.db_indexes, arguments.recreate), true) />
            </cfloop>
            <cfset priority = 8 />
            <cfset title &= " (after dropping generated #arrayToList(dependents, ', ')#)" />
        </cfif>

        <cfset arrayAppend(statements, {
            "table_name": arguments.table_name,
            "priority": priority,
            "type": "ALTER COLUMN",
            "destructive": false,
            "title": title,
            "statement": "ALTER TABLE #arguments.table_name# ALTER COLUMN #arguments.field_name# TYPE #arguments.type_spec#;"
        }) />

        <cfreturn statements />
    </cffunction>

    <cffunction name="sortByPriority" returntype="numeric" access="private">
        <cfargument name="a" type="struct" required="true">
        <cfargument name="b" type="struct" required="true">

        <cfscript>
            if (a.priority < b.priority) {
                return -1;
            } else if (a.priority > b.priority) {
                return 1;
            } else {
                return 0;
            }
        </cfscript>
    </cffunction>




    <cffunction name="getColumnDef" returnType="string">
        <cfargument name="field" type="struct" required="true">
        <cfargument name="defer_not_null" type="boolean" required="false" default="false"
                    hint="True when the caller is adding this column to an existing table: the NOT NULL clause is left off so the ADD succeeds on populated rows, and the nullability comparison on the next pass tightens it. CREATE TABLE never defers — a new table has no rows to refuse it.">

        <cfset columnDef = '"#field.name#" #field.type#'>

        <!--- Handle geometry type specifications --->
        <cfif field.type EQ "geometry" AND structKeyExists(field, "geometry_type") AND structKeyExists(field, "srid")>
            <cfset columnDef &= "(#field.geometry_type#, #field.srid#)">
        <cfelseif (field.max_length?:0) GT 0 >
            <cfset columnDef &= " (#field.max_length#)">
        <cfelseif (field.precision?:0) GT 0 >
            <cfset columnDef &= " (#field.precision#,#(field.scale?:0)#)">
        </cfif>

        <!--- Setting as type serial will handle this --->
        <cfif !findNoCase("serial",field.type)>
            <cfif len(field.default?:'')>
                <cfset columnDef &= " DEFAULT #field.default#">
            </cfif>

            <cfif !(field.is_nullable?:true) AND !arguments.defer_not_null>
                <cfset columnDef &= " NOT NULL">
            </cfif>
        </cfif>

        <cfif len(field.generation_expression?:'')>
            <cfset columnDef &= " GENERATED ALWAYS AS (#field.generation_expression#) STORED">
        </cfif>

        <!--- Add CHECK constraints if specified --->
        <cfif len(field.check?:'')>
            <cfset columnDef &= " CHECK (#field.check#)">
        </cfif>

        <cfreturn columnDef />
    </cffunction>



    <cffunction name="createTableFromCodeSchema" returnType="array">
        <cfargument name="codeSchema" type="struct" required="true">

        <cfset newTableName = "#arguments.codeSchema.table_name#" />

        <cfset sql = [] />

        <cfset columnDefinitions = [] />

        <cfloop collection="#arguments.codeSchema.fields#" item="field" index="field_name">

            <cfif !listFindNoCase("many_to_many,relation",field.type)>
                <cfset columnDef = getColumnDef(field) />

                <cfset arrayAppend(columnDefinitions, columnDef)>
            </cfif>
        </cfloop>

        <cfif arrayLen(arguments.codeSchema.primary_keys)>
            <cfset arrayAppend(columnDefinitions, "PRIMARY KEY (#arrayToList(arguments.codeSchema.primary_keys)#)")>
        </cfif>




        <!--- Build and execute CREATE TABLE statement --->
        <cfset sqlStatement = {
                                    "table_name": "#newTableName#",
                                    "priority": 7,
                                    "type": "CREATE TABLE",
                                    "destructive": false,
                                    "title": "CREATE TABLE #newTableName#",
                                    "statement": 'CREATE TABLE "#newTableName#" (#arrayToList(columnDefinitions, ", ")#)'
                                } />

        <cfset arrayAppend(sql, sqlStatement) />


        <!--- Create indexes --->
        <cfloop collection="#arguments.codeSchema.indexes#" item="index" index="i">
            <cfset index_field_list = index.fields />
            <cfif index.type EQ "gin">
                <cfset index_field_list = ListMap(index_field_list, function(term) { return term & " gin_trgm_ops"; })>
            </cfif>
            <cfset where_clause = "" />
            <cfif len(index.where?:'')>
                <cfset where_clause = " WHERE (#index.where#)" />
            </cfif>
            <cfset sqlStatement = {
                "table_name": "#newTableName#",
                "priority": 8,
                "type": "CREATE INDEX (New Table)",
                "destructive": false,
                "title": "CREATE INDEX (New Table) #index.name#",
                "statement": "CREATE #index.unique ? "UNIQUE" : ""# INDEX #index.name# ON #newTableName# USING #index.type# (#index_field_list#)#where_clause#"
            } />
            <cfset arrayAppend(sql, sqlStatement) />
        </cfloop>


        <cfloop collection="#arguments.codeSchema.foreign_keys#" item="fk" index="i">

            <cfset sqlStatement = {
                "table_name": "#newTableName#",
                "priority": 9,
                "type": "ADD CONSTRAINT (New Table)",
                "destructive": false,
                "title": "ADD CONSTRAINT (New Table) #newTableName#.#i#",
                "statement": 'ALTER TABLE #newTableName# ADD CONSTRAINT #i# FOREIGN KEY (#reReplace(fk.field_name, "\s+", "", "ALL")#) REFERENCES "#fk.foreign_key_table#" (#listQualify(reReplace(fk.foreign_key_field, "\s+", "", "ALL"), '"')#) ON DELETE #fk.onDelete ?: "NO ACTION"# ON UPDATE #fk.onUpdate ?: "NO ACTION"#'
            } />
            <cfset arrayAppend(sql, sqlStatement) />


        </cfloop>


        <cfreturn sql />
    </cffunction>

</cfcomponent>
