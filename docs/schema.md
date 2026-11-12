# The Schema page

System → Schema (`/sysadmin/schema/`, Hub only) lists the SQL that would bring the database in line with the table definitions. Moopa never runs it: a sysadmin selects statements, reviews them and copies the script.

The statements come from Moopa's own library, `application.lib.schemaSync.compareDatabaseSchema(application.lib.db.codeSchema)` (`lib/schemaSync.cfc`). It reads the database's catalogue and builds SQL text; it never changes the database. It returns an array of structs, in the order they must run:

| Key | Required | Meaning |
|---|---|---|
| `table_name` | yes | The table the statement changes |
| `priority` | yes | Run order; the array is already sorted by it |
| `title` | yes | A short label, such as `DROP COLUMN: orders.notes` |
| `statement` | yes | The SQL, without a trailing semicolon or with one |
| `destructive` | yes | `true` or `false`; see below |
| `mismatches` | no | `[{ param, db, code }]`, shown as a diff when the definition and the database disagree |

## Destructive statements

A statement is **destructive** when it drops a column the table definitions no longer declare, losing the data in it. Nothing else is: dropping an index, a foreign key or a default, and retyping a column, are not, and neither is dropping a generated column that the same script adds back to change its expression.

The page hides destructive statements until the sysadmin turns on **Show destructive**, and hiding them again clears them from the selection, so the script that is copied never drops a column nobody saw. On a database several branches share, the definitions on one branch do not declare the columns another branch has added, so they show here as drops: they stay out of the way unless asked for.

The page refuses to render when a statement has no boolean `destructive`, naming the statement, rather than guessing which statements are safe.

## Comparing expressions

A column default or a generated column's expression is compared after both sides go through `normalizeExpression()`: Postgres stores an expression rewritten (casts and parentheses added, a function or column named by a keyword double-quoted, so `left(...)` comes back as `"left"(...)`, and `TRIM(x)` as `TRIM(BOTH FROM x)`), so casts, parentheses, double quotes and whitespace are removed from both, and `TRIM(BOTH FROM` reads as `TRIM(`. A generated column whose expression still differs is dropped and added back, because Postgres cannot alter one in place. An expression the page keeps proposing after it has been run is a difference this normalising misses: fix it here, with a check in `scripts/schema_sync_test/run.cfm`.

## Upgrading an existing app

`schemaSync` used to be each project's own Hub library (`code/apps/hub/lib/schemaSync.cfc`). It is Moopa's now, so **delete the project's copy** when moving to this Moopa: two libraries of one name stop the app starting (`Duplicate library 'schemaSync'`). Nothing that calls `application.lib.schemaSync` changes.
