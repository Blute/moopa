-- Data for scripts/test_db_search.sh. Columns follow what Moopa's schema normaliser generates for
-- fixture/tables/*.cfc (system fields, label, search_text). Every probe_item name except
-- "widgets galore" contains the whole word "widget", so a search for "widget" scores them all
-- 1.00 and only the primary key orders them. Rows go in out of key order, and some have no
-- owner, so a search that does not break ties on the key returns an order the harness refuses.
-- probe_pair is keyed on (group_code, item_code); its id column is the same on every row.
-- probe_vendor declares expand_fields "name", so a link to it carries only id and name.
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE probe_owner (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name varchar,
    email varchar,
    label varchar GENERATED ALWAYS AS (COALESCE(name::text, id::text)) STORED,
    created_at timestamptz DEFAULT now(),
    last_updated_at timestamptz DEFAULT now(),
    created_by uuid,
    last_updated_by uuid
);

CREATE TABLE probe_vendor (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name varchar,
    email varchar,
    notes text,
    label varchar GENERATED ALWAYS AS (COALESCE(name::text, id::text)) STORED,
    created_at timestamptz DEFAULT now(),
    last_updated_at timestamptz DEFAULT now(),
    created_by uuid,
    last_updated_by uuid
);

CREATE TABLE probe_item (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name varchar,
    rank int4,
    owner_id uuid REFERENCES probe_owner (id),
    vendor_id uuid REFERENCES probe_vendor (id),
    label varchar GENERATED ALWAYS AS (COALESCE(name::text, id::text)) STORED,
    created_at timestamptz DEFAULT now(),
    last_updated_at timestamptz DEFAULT now(),
    created_by uuid,
    last_updated_by uuid,
    search_text text GENERATED ALWAYS AS (COALESCE(name::text, '')) STORED
);

INSERT INTO probe_owner (id, name, email) VALUES
    ('00000000-0000-0000-0000-0000000000a1', 'Alpha', 'alpha@example.com'),
    ('00000000-0000-0000-0000-0000000000b2', 'Bravo', 'bravo@example.com');

INSERT INTO probe_vendor (id, name, email, notes) VALUES
    ('00000000-0000-0000-0000-0000000000d1', 'Delta Supplies', 'delta@example.com', 'Private note');

INSERT INTO probe_item (id, name, rank, owner_id) VALUES
    ('00000000-0000-0000-0000-000000000005', 'widgets galore', 0, '00000000-0000-0000-0000-0000000000a1'),
    ('00000000-0000-0000-0000-000000000004', 'widget four',    2, NULL),
    ('00000000-0000-0000-0000-000000000001', 'widget one',     3, '00000000-0000-0000-0000-0000000000a1'),
    ('00000000-0000-0000-0000-000000000003', 'widget three',   2, '00000000-0000-0000-0000-0000000000b2'),
    ('00000000-0000-0000-0000-000000000006', 'widget six',     1, '00000000-0000-0000-0000-0000000000b2'),
    ('00000000-0000-0000-0000-000000000002', 'widget two',     1, NULL);

CREATE TABLE probe_pair (
    id uuid,
    group_code varchar NOT NULL,
    item_code varchar NOT NULL,
    name varchar,
    label varchar GENERATED ALWAYS AS (COALESCE(name::text, id::text)) STORED,
    created_at timestamptz DEFAULT now(),
    last_updated_at timestamptz DEFAULT now(),
    created_by uuid,
    last_updated_by uuid,
    search_text text GENERATED ALWAYS AS (COALESCE(name::text, '')) STORED,
    PRIMARY KEY (group_code, item_code)
);

INSERT INTO probe_pair (id, group_code, item_code, name) VALUES
    ('00000000-0000-0000-0000-0000000000cc', 'b', '2', 'gadget'),
    ('00000000-0000-0000-0000-0000000000cc', 'a', '2', 'gadget'),
    ('00000000-0000-0000-0000-0000000000cc', 'b', '1', 'gadget'),
    ('00000000-0000-0000-0000-0000000000cc', 'a', '3', 'gadget'),
    ('00000000-0000-0000-0000-0000000000cc', 'a', '1', 'gadget');

UPDATE probe_item SET vendor_id = '00000000-0000-0000-0000-0000000000d1'
WHERE id = '00000000-0000-0000-0000-000000000001';
