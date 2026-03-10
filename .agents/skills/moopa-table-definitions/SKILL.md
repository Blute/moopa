---
name: moopa-table-definitions
description: Generate Moopa table definition CFC files for database schema and UI form controls. Use when creating new database tables, adding fields to existing tables, defining foreign keys, indexes, or when working with cf_table_controls for form rendering.
---

# Moopa Table Definitions

Table definitions in Moopa serve dual purposes:
1. **Database schema** - Synced to PostgreSQL via `/schema/` route
2. **UI form controls** - Rendered via `<cf_table_controls>` tag

## Table Definition Structure

Table definitions live in `code/project/tables/{table_name}.cfc`:

```cfml
<cfcomponent>
    <cffunction name="init">
        <cfset this.definition = [
            "title": "Display Name",
            "title_plural": "Display Names",
            
            "label_generation_expression": "COALESCE(name::text, id::text)",
            "searchable_fields": "name,email",
            "order_by": "name asc",
            
            "fields": [
                "field_name": {
                    "type": "varchar",
                    "max_length": 255,
                    "nullable": true,
                    "default": "'value'",
                    "index": true,
                    "html": {
                        "control": "text",
                        "label": "Field Label"
                    }
                }
            ]
        ] />
        <cfreturn this>
    </cffunction>
</cfcomponent>
```

## Table-Level Properties

| Property | Required | Description |
|----------|----------|-------------|
| `title` | Yes | Singular display name |
| `title_plural` | Yes | Plural display name |
| `label_generation_expression` | No | PostgreSQL expression for record labels in comboboxes |
| `searchable_fields` | No | Comma-separated field list for full-text search (preferred over per-field `searchable: true`) |
| `order_by` | No | Default sort order |

## Field Types

### Core PostgreSQL Types

| Type | PostgreSQL | Default HTML Control |
|------|------------|---------------------|
| `varchar` | varchar(max_length) | text |
| `text` | text | textarea |
| `int2` | smallint | number |
| `int4` | integer | number |
| `int8` | bigint | number |
| `bool` / `boolean` | boolean | switch |
| `date` | date | date |
| `timestamptz` | timestamp with timezone | datetime |
| `uuid` | uuid | combobox (if foreign_key_table) |
| `jsonb` | jsonb | textarea |
| `numeric` | numeric(precision, scale) | number |
| `geometry` | PostGIS geometry | text |
| `tsvector` | full-text search vector | (hidden) |

**Important:** Use `int4` for integers, NOT `int`. The framework only recognizes `int2`, `int4`, `int8`.

### Special Types

| Type | Description |
|------|-------------|
| `many_to_many` | Creates bridge table automatically |

## Field Properties

```cfml
"field_name": {
    "type": "varchar",           // Required: PostgreSQL type
    "max_length": 255,           // For varchar/text
    "precision": 10,             // For numeric
    "scale": 2,                  // For numeric
    "nullable": true,            // Default: true
    "default": "'value'",        // SQL expression (note: strings need quotes)
    "index": true,               // Create btree index on this field
    "generation_expression": "", // For generated columns
    "foreign_key_table": "",     // Creates FK constraint
    "html": { ... }              // UI control settings
}
```

## HTML Control Settings

The `html` block configures how fields render in forms:

```cfml
"html": {
    "control": "text",          // Control type (see list below)
    "label": "Field Label",     // Display label
    "placeholder": "",          // Input placeholder
    "hidden": false,            // Hide from forms
    "options": [],              // For combobox with static options
    "list_items": []            // For list/select controls
}
```

### Available Controls

| Control | Use Case | Notes |
|---------|----------|-------|
| `text` | Short text | Default for varchar |
| `textarea` | Long text | Default for text |
| `email` | Email addresses | Adds validation |
| `tel` | Phone numbers | |
| `url` | URLs | Adds validation |
| `number` | Numeric input | |
| `currency` | Money fields | |
| `percentage` | Percentages | |
| `date` | Date picker | Quick options dropdown |
| `datetime` | Date + time | |
| `dob` | Date of birth | Specialized date picker |
| `checkbox` | Boolean toggle | |
| `switch` | Boolean toggle | DaisyUI toggle style |
| `list` | Static dropdown | Uses `list_items` |
| `combobox` | Searchable dropdown | For FK or static `options` |
| `file` | File upload | Works with moo_file |
| `address` | Address picker | Google Places integration |

### Static Options (combobox)

```cfml
"html": {
    "control": "combobox",
    "label": "Status",
    "options": [
        {"value": "active", "label": "Active"},
        {"value": "inactive", "label": "Inactive"}
    ]
}
```

### Static Options (list)

```cfml
"html": {
    "control": "list",
    "label": "Status",
    "list_items": [
        {"value": "active", "name": "Active"},
        {"value": "inactive", "name": "Inactive"}
    ]
}
```

## Foreign Keys

```cfml
"agency_id": {
    "type": "uuid",
    "nullable": false,
    "foreign_key_table": "rea_agency",
    "html": {
        "control": "combobox",
        "label": "Agency"
    }
}
```

The combobox automatically calls `search.agency_id` endpoint for options, which you implement in the route CFC.

## Many-to-Many Relationships

```cfml
"roles": {
    "type": "many_to_many",
    "foreign_key_table": "moo_role"
}
```

This auto-creates a bridge table `{table_name}_roles` with proper FK constraints.

## Generated Columns

```cfml
"formatted_address": {
    "type": "text",
    "generation_expression": "address->>'formatted_address'",
    "searchable": true,
    "html": {
        "hidden": true
    }
}
```

## Indexes

### Simple Single-Field Indexes

For single-field btree indexes, use `index: true` on the field:

```cfml
"email": {
    "type": "varchar",
    "max_length": 255,
    "index": true,              // Creates btree index automatically
    "html": { ... }
}
```

### Composite or Special Indexes

Use the `indexes` block only for composite indexes or non-btree types:

```cfml
"indexes": [
    "idx_table_name_status": {
        "type": "btree",
        "fields": "name,status"  // Composite index
    },
    "idx_table_search": {
        "type": "gin",           // Special index type
        "fields": "to_tsvector('english', name || ' ' || description)"
    }
]
```

## Using in Forms

### cf_table_controls

Renders multiple fields from table definition:

```cfml
<cf_table_controls 
    table_name="rea_agent" 
    fields="first_name,last_name,email" 
    model_record="current_record" />
```

With overrides:

```cfml
<cf_table_controls 
    table_name="rea_agent" 
    fields="agency_id,status" 
    model_record="current_record"
    config={
        agency_id: {route: "/hub/rea/agents"},
        status: {placeholder: "Select status..."}
    } />
```

### Layout Options

```cfml
<cf_table_controls 
    table_name="rea_agent" 
    fields="name,email" 
    model_record="current_record"
    label_position="left"
    class="fieldset mb-4" />
```

## Complete Example

```cfml
<cfcomponent>
    <cffunction name="init">
        <cfset this.definition = [
            "title": "Product",
            "title_plural": "Products",
            
            "label_generation_expression": "COALESCE(name::text, sku::text, id::text)",
            "searchable_fields": "name,sku,description",
            "order_by": "name asc",
            
            "fields": [
                "category_id": {
                    "type": "uuid",
                    "nullable": false,
                    "index": true,
                    "foreign_key_table": "product_category",
                    "html": {
                        "control": "combobox",
                        "label": "Category"
                    }
                },
                "name": {
                    "type": "varchar",
                    "max_length": 255,
                    "nullable": false,
                    "html": {
                        "control": "text",
                        "label": "Product Name"
                    }
                },
                "sku": {
                    "type": "varchar",
                    "max_length": 50,
                    "nullable": true,
                    "index": true,
                    "html": {
                        "control": "text",
                        "label": "SKU"
                    }
                },
                "description": {
                    "type": "text",
                    "nullable": true,
                    "html": {
                        "control": "textarea",
                        "label": "Description"
                    }
                },
                "price": {
                    "type": "numeric",
                    "precision": 10,
                    "scale": 2,
                    "default": "0",
                    "html": {
                        "control": "currency",
                        "label": "Price"
                    }
                },
                "stock_quantity": {
                    "type": "int4",
                    "default": "0",
                    "html": {
                        "control": "number",
                        "label": "Stock Quantity"
                    }
                },
                "is_active": {
                    "type": "bool",
                    "default": "true",
                    "index": true,
                    "html": {
                        "control": "switch",
                        "label": "Active"
                    }
                },
                "image_id": {
                    "type": "uuid",
                    "nullable": true,
                    "foreign_key_table": "moo_file",
                    "html": {
                        "control": "file",
                        "label": "Product Image"
                    }
                },
                "tags": {
                    "type": "many_to_many",
                    "foreign_key_table": "product_tag",
                    "html": {
                        "control": "combobox"
                    }
                },
                "status": {
                    "type": "varchar",
                    "max_length": 20,
                    "default": "'draft'",
                    "index": true,
                    "html": {
                        "control": "list",
                        "label": "Status",
                        "list_items": [
                            {"value": "draft", "name": "Draft"},
                            {"value": "published", "name": "Published"},
                            {"value": "archived", "name": "Archived"}
                        ]
                    }
                }
            ]
        ] />
        <cfreturn this>
    </cffunction>
</cfcomponent>
```

## Syncing Schema

Visit `/schema/` to compare code definitions with database and generate ALTER statements. The framework reads all CFC files in `code/project/tables/` and `code/moopa/tables/` and compares with the live database.

## Naming Conventions

- Table names: `snake_case`, singular or plural consistent with domain
- Field names: `snake_case`
- Foreign keys: `{related_table}_id` (e.g., `agency_id`)
- Indexes: `idx_{table}_{field}` or `idx_{table}_{purpose}`
- Bridge tables (many-to-many): `{table}_{relationship}` (auto-generated)

## Tips

1. Always include `id`, `created_at`, `updated_at` fields (added automatically by framework)
2. Use `label_generation_expression` for meaningful combobox labels
3. Use `index: true` on individual fields for simple btree indexes
4. Use `indexes` block only for composite indexes or special index types (gin, gist)
5. Prefer `searchable_fields` at table level over `searchable: true` on individual fields
6. Default values use SQL syntax: strings need quotes `"'value'"`, booleans are `"true"/"false"`
7. Use `int4` for integers, NOT `int` - the framework only recognizes `int2`, `int4`, `int8`
8. Use `timestamptz` for timestamps (not `timestamp`)
