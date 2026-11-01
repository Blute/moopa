# Search

`application.lib.db.search()` returns a table's records filtered by text, ids or field values; `application.lib.db.idsInSearchTerm()` returns only the ids that match a search term. How a table becomes searchable (`searchable_fields`, the generated `search_text` column, `pg_trgm`) is in the `moopa-search` skill (`.agents/skills/moopa-search`).

## db.search() arguments

| Argument | Default | What it does |
|---|---|---|
| `table_name` | required | The table. |
| `field_list` | `*` | Fields to return. |
| `q` | `""` | Search text. On a table with searchable fields it matches `search_text` with `pg_trgm` (`<%`); on any other table it matches `label` with `ILIKE`. |
| `where` | `{}` | Field filters: `{ status: "active" }`, or `{ total: { operator: ">", value: 100 } }` (`IN`, `LIKE`, `<`, `>`, `<=`, `>=`, `<>`). |
| `ids` | `[]` | Only these records. |
| `exclude_ids` | `""` | Never these records (a list). |
| `offset`, `limit` | none, `250` | Paging. |
| `select_append` | `""` | Extra SELECT expressions, such as a subquery. |
| `sql_type` | `condensed` | How linked (foreign key) fields come back; see below. |
| `returnFormat` | `json` | `json` text, or `cfml` arrays and structs. |

## Linked records: sql_type

`sql_type` works as it does for `db.read()` and `db.select()`:

- `condensed` (the default): a linked record is `{ id, label }`, or the linked table's fields marked `condensed: true`.
- `simple`: a linked record is just its id, as stored. Many-to-many and relation fields have no simple form, so they are left out.
- `expanded`: a linked record is an object of the linked table's fields (sensitive fields left out).

A linked table's `expand_fields`, and a link's `expand: "condensed"`, narrow what a link carries in search results exactly as they do for reads; see "What a link carries" in the `moopa-table-definitions` skill.

A page that shows linked records' detail from search results asks for `sql_type="expanded"` instead of reading each record again. An unknown `sql_type` throws.

```cfml
<cfset orders = application.lib.db.search(
    table_name = "customer_order",
    field_list = "id,order_number,customer_id",
    q = url.q,
    sql_type = "expanded",
    returnFormat = "cfml"
) />
<!--- orders[1].customer_id.email is the customer's email --->
```

## Order

- **Text search** (`q` on a table with searchable fields): best match first, by `word_similarity(q, search_text)`. Equal scores are common (every whole-word match scores 1.00), so tied records come back in primary-key order (`id` for most tables, every key column in turn for a composite key). That order is stable, not meaningful: the same search returns the same order every time, and pages neither skip nor repeat a record. The table's `order_by` plays no part in text-search ranking; sort the results yourself if a page needs another order among equal matches.
- **`ids` with more than one id**: the order of `ids`.
- **Otherwise** (no `q`, or `q` on a table with no searchable fields): the table's `order_by`.

`idsInSearchTerm(table_name, term, limit=20)` orders its ids the same way as a text search, so its first N ids are the ids of `db.search()` with the same `q` and `limit=N`. When nothing matches, or the table has no searchable fields, it returns one id that matches no record, so the result is safe to put straight into `id IN (...)`.

## Testing

`bash scripts/test_db_search.sh`, from Moopa's root, checks the order and `sql_type` against a throwaway PostgreSQL in Docker and a RustCFML binary (`RUSTCFML=/path/to/rustcfml` when it is not on `PATH`). It prints `PASS` and the number of checks, or each failed check.

## Upgrading

Nothing to do. Before this, text-search results with equal scores came back in whatever order PostgreSQL produced; they now come back in primary-key order. Results with different scores keep their order, searches without `q` still follow the table's `order_by`, and `sql_type` defaults to what `db.search()` always returned.
