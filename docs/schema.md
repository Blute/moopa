# The Schema page

System → Schema (`/sysadmin/schema/`, Hub only) lists the SQL that would bring the database in line with the table definitions. Moopa never runs it: a sysadmin selects statements, reviews them and copies the script.

The statements come from the project's own Hub library, `application.lib.schemaSync.compareDatabaseSchema(application.lib.db.codeSchema)`. It returns an array of structs, in the order they must run:

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

## Upgrading an existing app

A Moopa from before `destructive` existed did not need it. A project's `schemaSync.compareDatabaseSchema` must now set `"destructive": true` or `"destructive": false` on every statement it returns, by the rule above; until it does, the Schema page fails with `moopa.schema.destructiveMissing`.
