-- Data for scripts/test_db_search.sh. Columns follow what Moopa's schema normaliser generates for
-- fixture/tables/*.cfc (system fields, label, search_text). Every probe_item name except
-- "widgets galore" contains the whole word "widget", so a search for "widget" scores them all
-- 1.00. Rows go in out of rank and id order, so a search that does not break ties returns them in
-- an order the harness refuses.
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

CREATE TABLE probe_item (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name varchar,
    rank int4,
    owner_id uuid REFERENCES probe_owner (id),
    label varchar GENERATED ALWAYS AS (COALESCE(name::text, id::text)) STORED,
    created_at timestamptz DEFAULT now(),
    last_updated_at timestamptz DEFAULT now(),
    created_by uuid,
    last_updated_by uuid,
    search_text text GENERATED ALWAYS AS (COALESCE(name::text, '')) STORED
);

INSERT INTO probe_owner (id, name, email) VALUES
    ('00000000-0000-0000-0000-0000000000a1', 'Alpha', 'alpha@example.com');

INSERT INTO probe_item (id, name, rank, owner_id) VALUES
    ('00000000-0000-0000-0000-000000000005', 'widgets galore', 0, '00000000-0000-0000-0000-0000000000a1'),
    ('00000000-0000-0000-0000-000000000004', 'widget four',    2, '00000000-0000-0000-0000-0000000000a1'),
    ('00000000-0000-0000-0000-000000000001', 'widget one',     3, '00000000-0000-0000-0000-0000000000a1'),
    ('00000000-0000-0000-0000-000000000003', 'widget three',   2, '00000000-0000-0000-0000-0000000000a1'),
    ('00000000-0000-0000-0000-000000000006', 'widget six',     1, '00000000-0000-0000-0000-0000000000a1'),
    ('00000000-0000-0000-0000-000000000002', 'widget two',     1, '00000000-0000-0000-0000-0000000000a1');
