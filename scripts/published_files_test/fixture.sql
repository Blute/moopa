-- Tables for the published files harness: a product whose datasheet and pictures publish, Moopa's moo_file, and
-- moo_published_file as tables_published/moo_published_file.cfc makes it (the columns the library uses).
CREATE TABLE moo_file (id uuid PRIMARY KEY, name varchar(255), path varchar(2048));
CREATE TABLE product (id uuid PRIMARY KEY, slug varchar(200), is_published boolean NOT NULL DEFAULT false);
CREATE TABLE product_datasheet (primary_id uuid REFERENCES product(id) ON DELETE CASCADE, foreign_id uuid, sequence integer);
CREATE TABLE product_images (primary_id uuid REFERENCES product(id) ON DELETE CASCADE, foreign_id uuid, sequence integer);
CREATE TABLE moo_published_file (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    object_key varchar(1024) NOT NULL UNIQUE,
    site varchar(63) NOT NULL,
    address varchar(1024) NOT NULL,
    table_name varchar(63) NOT NULL,
    record_id uuid NOT NULL,
    field varchar(63) NOT NULL,
    moo_file_id uuid NOT NULL,
    path varchar(2048) NOT NULL,
    etag varchar(200),
    created_at timestamptz DEFAULT now(),
    last_updated_at timestamptz DEFAULT now()
);
