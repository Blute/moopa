---
name: moopa-queries
description: Write PostgreSQL queries in Moopa that return JSON directly from the database. Use when building cfquery blocks, load/search endpoints, or when the user asks about queries, JSON aggregation, db.select(), or fetching data.
---

# Moopa Queries - JSON-First Database Access

## Core Philosophy: Let the Database Do the Work

Moopa LOVES returning JSON directly from queries because:
- Endpoints return JSON anyway, so skip the CFML serialization step
- PostgreSQL's JSON functions are fast and handle nested data elegantly
- One query = one JSON payload, ready for the frontend

**Never do this:**
```cfml
<cfquery name="q">SELECT * FROM users</cfquery>
<cfreturn serializeJSON(q)>  <!--- BAD: extra serialization step --->
```

**Always do this:**
```cfml
<cfquery name="q">
SELECT COALESCE(array_to_json(array_agg(row_to_json(data)))::text, '[]') AS recordset
FROM (SELECT id, name FROM users) AS data
</cfquery>
<cfreturn q.recordset>  <!--- GOOD: already JSON --->
```

**Note:** The `datasource` attribute is not required on `<cfquery>` tags. Moopa configures `this.datasource` in Application.cfc, so all queries use the default datasource automatically.

## Query Patterns

### Single Record → JSON Object
```cfml
<cfquery name="qData">
SELECT COALESCE(row_to_json(data)::text, '{}') as recordset
FROM (
    SELECT #application.lib.db.select(table_name="my_table")#
    FROM my_table
    WHERE id = <cfqueryparam cfsqltype="other" value="#arguments.id#" />
) AS data
</cfquery>
<cfreturn qData.recordset />
```

### Multiple Records → JSON Array
```cfml
<cfquery name="qData">
SELECT COALESCE(array_to_json(array_agg(row_to_json(data)))::text, '[]') AS recordset
FROM (
    SELECT #application.lib.db.select(table_name="my_table", field_list="id,name,status")#
    FROM my_table
    WHERE active = true
    ORDER BY name
    LIMIT 100
) AS data
</cfquery>
<cfreturn qData.recordset />
```

## The db.select() Helper

Generates SQL field lists from table schema. Handles foreign keys, computed columns, and JSON aggregation for many-to-many relations.

```cfml
#application.lib.db.select(table_name="my_table")#
<!--- Returns: my_table.id as id, my_table.name as name, ... --->

#application.lib.db.select(table_name="my_table", field_list="id,name,status")#
<!--- Returns only specified fields --->

#application.lib.db.select(table_name="my_table", exclude_list="created_at,updated_at")#
<!--- Returns all fields except specified --->
```

**Modes:**
- `expanded` (default): Full field expressions with joins/subqueries
- `simple`: Basic column references
- `condensed`: Minimal (id, label)

## Dynamic WHERE Clauses

Always use `WHERE 1=1` as base for conditional appending:

```cfml
<cfparam name="request.data.filter" default="#{}#" />

<cfquery name="qData">
SELECT COALESCE(array_to_json(array_agg(row_to_json(data)))::text, '[]') AS recordset
FROM (
    SELECT #application.lib.db.select(table_name="orders")#
    FROM orders
    WHERE 1=1
    
    <cfif len(request.data.filter.status?:'')>
        AND status = <cfqueryparam cfsqltype="varchar" value="#request.data.filter.status#" />
    </cfif>
    
    <cfif len(request.data.filter.customer_id?:'')>
        AND customer_id = <cfqueryparam cfsqltype="other" value="#request.data.filter.customer_id#" />
    </cfif>
    
    <cfif len(request.data.filter.date_from?:'') AND len(request.data.filter.date_to?:'')>
        AND order_date BETWEEN 
            <cfqueryparam cfsqltype="date" value="#request.data.filter.date_from#" />
            AND <cfqueryparam cfsqltype="date" value="#request.data.filter.date_to#" />
    </cfif>
    
    ORDER BY order_date DESC
    LIMIT 100
) AS data
</cfquery>
```

## Nested JSON with Subqueries

For related data, use subqueries with `jsonb_agg()`:

```cfml
<cfquery name="qData">
SELECT COALESCE(array_to_json(array_agg(row_to_json(data)))::text, '[]') AS recordset
FROM (
    SELECT 
        #application.lib.db.select(table_name="orders", field_list="id,order_date,total")#,
        
        <!--- Nested array of order items --->
        (SELECT COALESCE(jsonb_agg(items), '[]'::jsonb)
         FROM (
            SELECT #application.lib.db.select(table_name="order_items", field_list="id,product_id,quantity,price")#
            FROM order_items
            WHERE order_items.order_id = orders.id
         ) items
        ) as items,
        
        <!--- Single related object --->
        (SELECT row_to_json(c) 
         FROM (SELECT id, name, email FROM customers WHERE id = orders.customer_id) c
        ) as customer
        
    FROM orders
    WHERE orders.status = 'active'
) AS data
</cfquery>
```

## Adding Computed Columns

Add extra SELECT expressions alongside `db.select()`:

```cfml
<cfquery name="qData">
SELECT COALESCE(array_to_json(array_agg(row_to_json(data)))::text, '[]') AS recordset
FROM (
    SELECT #application.lib.db.select(table_name="sell_address", field_list="id,property_pid,formatted_address")#,
           
           <!--- Add computed columns --->
           (SELECT email FROM moo_profile WHERE moo_profile.id = sell_address.profile_id) as profile_email,
           
           <!--- Date formatting --->
           to_char(selected_at, 'YYYY-MM-DD HH24:MI') as formatted_date
           
    FROM sell_address
    ORDER BY selected_at DESC
) AS data
</cfquery>
```

## Using WITH Clauses for Complex Queries

```cfml
<cfquery name="qData">
WITH filtered AS (
    SELECT #application.lib.db.select(table_name="products")#
    FROM products
    WHERE 1=1
    <cfif len(request.data.filter.category?:'')>
        AND category = <cfqueryparam cfsqltype="varchar" value="#request.data.filter.category#" />
    </cfif>
),
counted AS (
    SELECT COUNT(*) as total FROM filtered
)
SELECT 
    COALESCE(array_to_json(array_agg(row_to_json(data)))::text, '[]') AS recordset,
    (SELECT total FROM counted) as total_count
FROM (
    SELECT * FROM filtered
    ORDER BY name
    LIMIT <cfqueryparam cfsqltype="integer" value="#request.data.limit ?: 50#" />
    OFFSET <cfqueryparam cfsqltype="integer" value="#request.data.offset ?: 0#" />
) AS data
</cfquery>

<cfreturn {
    "records": deserializeJSON(qData.recordset),
    "total": qData.total_count
} />
```

## Quick Reference: PostgreSQL JSON Functions

| Function | Purpose | Example |
|----------|---------|---------|
| `row_to_json(row)` | Row → JSON object | `row_to_json(data)` |
| `array_agg(value)` | Collect into array | `array_agg(row_to_json(data))` |
| `array_to_json(array)` | Array → JSON | `array_to_json(array_agg(...))` |
| `jsonb_agg(value)` | Collect into JSONB array | `jsonb_agg(items)` |
| `json_build_object(k,v,...)` | Build object from pairs | `json_build_object('id', id, 'name', name)` |
| `COALESCE(..., '[]')` | Handle NULL (empty array) | `COALESCE(array_to_json(...), '[]')` |

## cfqueryparam Type Reference

| Data Type | cfsqltype |
|-----------|-----------|
| UUID | `other` |
| String | `varchar` |
| Integer | `integer` |
| Boolean | `boolean` |
| Date | `date` |
| Timestamp | `timestamp` |
| Array (for IN) | `other` with `list="true"` |

## Security: Always Use cfqueryparam

```cfml
<!--- GOOD: Parameterized --->
AND id = <cfqueryparam cfsqltype="other" value="#request.data.id#" />

<!--- BAD: SQL injection risk --->
AND id = '#request.data.id#'
```

For IN clauses:
```cfml
AND id IN (<cfqueryparam cfsqltype="other" list="true" value="#arrayToList(ids)#" />)
```
