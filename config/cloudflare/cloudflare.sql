-- Developer note:
-- We sign asset URLs in PostgreSQL so signed URLs are produced in SELECT queries,
-- which avoids CFML recordset loops before sending responses to the browser.
-- Assets are served through a Cloudflare Worker to keep storage private while still
-- allowing signed access. Signatures are deterministic for a given key/options/expiry
-- window (for example EOW), so refreshes within that window reuse the same URL and
-- cache instead of forcing repeat downloads.
--
-- In Neon pooled mode, custom startup parameters are restricted, so we cannot rely on
-- persistent app.* settings via connection startup options. This script stores signing
-- config in DB-backed private settings and resolves values inside signed_asset_url().
--
-- Optional one-time seed values:
-- INSERT INTO app_private_setting(key, value) VALUES
--   ('cloudflare_assets_signing_key_b64', '<key>'),
--   ('cloudflare_assets_base_url', 'https://assets.your_domain.com')
-- ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = now();


CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS app_private_setting (
    key text PRIMARY KEY,
    value text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- REVOKE ALL ON app_private_setting FROM PUBLIC;

CREATE OR REPLACE FUNCTION app_private_setting_get(p_key text)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, pg_catalog
AS $$
SELECT s.value
FROM app_private_setting s
WHERE s.key = p_key
LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION signed_url_expiry(expiry_type text)
RETURNS bigint
LANGUAGE plpgsql
AS $$
DECLARE
    ts timestamptz := now();
    result timestamptz;
    exp text := upper(btrim(coalesce(expiry_type, '')));
BEGIN
    CASE exp
        WHEN 'MINUTE', 'N', 'EOMIN' THEN
            result := date_trunc('minute', ts) + interval '1 minute' - interval '1 second';
        WHEN 'HOUR', 'H', 'EOH' THEN
            result := date_trunc('hour', ts) + interval '1 hour' - interval '1 second';
        WHEN 'DAY', 'D', 'EOD' THEN
            result := date_trunc('day', ts) + interval '1 day' - interval '1 second';
        WHEN 'WEEK', 'W', 'EOW' THEN
            result := date_trunc('week', ts) + interval '1 week' - interval '1 second';
        WHEN 'MONTH', 'M', 'EOM' THEN
            result := date_trunc('month', ts) + interval '1 month' - interval '1 second';
        WHEN 'YEAR', 'Y', 'EOY' THEN
            result := date_trunc('year', ts) + interval '1 year' - interval '1 second';
        WHEN 'NEVER', 'NONE', 'INFINITE', 'INF', 'PERMANENT' THEN
            RETURN 253402300799;
        ELSE
            RAISE EXCEPTION 'Invalid expiry type: %', expiry_type;
    END CASE;

    RETURN extract(epoch from result)::bigint;
END;
$$;

CREATE OR REPLACE FUNCTION signed_url_query(p_options text, p_exp bigint)
RETURNS text
LANGUAGE sql
AS $$
WITH
opts AS (
  SELECT
    split_part(pair, '=', 1) AS key,
    CASE
      WHEN position('=' IN pair) > 0 THEN substring(pair FROM position('=' IN pair) + 1)
      ELSE ''
    END AS value
  FROM unnest(string_to_array(coalesce(p_options, ''), '&')) AS pair
  WHERE split_part(pair, '=', 1) <> ''
),
with_exp AS (
  SELECT key, value FROM opts
  UNION ALL
  SELECT 'exp' AS key, p_exp::text AS value
),
escaped AS (
  SELECT
    key,
    replace(replace(replace(coalesce(value,''), '%','%25'), '&','%26'), '=','%3D') AS value
  FROM with_exp
)
SELECT string_agg(key || '=' || value, '&' ORDER BY key)
FROM escaped;
$$;

CREATE OR REPLACE FUNCTION uri_encode_path(p_input text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    raw_bytes bytea := convert_to(coalesce(p_input, ''), 'utf8');
    out text := '';
    i integer;
    b integer;
BEGIN
    IF octet_length(raw_bytes) = 0 THEN
        RETURN out;
    END IF;

    FOR i IN 0..octet_length(raw_bytes) - 1 LOOP
        b := get_byte(raw_bytes, i);

        IF (b BETWEEN 48 AND 57)
           OR (b BETWEEN 65 AND 90)
           OR (b BETWEEN 97 AND 122)
           OR b IN (45, 46, 95, 126, 47) THEN
            out := out || chr(b);
        ELSE
            out := out || '%' || lpad(upper(to_hex(b)), 2, '0');
        END IF;
    END LOOP;

    RETURN out;
END;
$$;


CREATE OR REPLACE FUNCTION signed_asset_url(
    p_r2_key text,
    p_expiry_type text,
    p_kind text DEFAULT 'a',
    p_options text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
    kind text;
    clean_key text;
    base_url text;
    signing_key_b64 text;
    exp_unix bigint;
    query_no_sig text;
    path_raw text;
    path_encoded text;
    canonical text;
    sig_hex text;
    signing_key bytea;
BEGIN
    -- SAFETY: if key missing, return NULL instead of error
    IF p_r2_key IS NULL OR btrim(p_r2_key) = '' THEN
        RETURN NULL;
    END IF;

    kind := lower(coalesce(p_kind, 'a'));
    kind := CASE kind
        WHEN 'a' THEN 'a'
        WHEN 'asset' THEN 'a'
        WHEN 'i' THEN 'i'
        WHEN 'image' THEN 'i'
        WHEN 'v' THEN 'v'
        WHEN 'video' THEN 'v'
        ELSE 'a'
    END;

    clean_key := ltrim(p_r2_key, '/');
    path_raw := '/' || kind || '/' || clean_key;
    path_encoded := '/' || kind || '/' || uri_encode_path(clean_key);

    base_url := nullif(current_setting('app.assets_base_url', true), '');
    IF base_url IS NULL THEN
        base_url := app_private_setting_get('cloudflare_assets_base_url');
        IF base_url IS NULL OR btrim(base_url) = '' THEN
            RAISE EXCEPTION 'Missing app.assets_base_url and app_private_setting.cloudflare_assets_base_url';
        END IF;
        PERFORM set_config('app.assets_base_url', base_url, true);
    END IF;
    base_url := regexp_replace(base_url, '/+$', '');

    exp_unix := signed_url_expiry(p_expiry_type);
    query_no_sig := signed_url_query(p_options, exp_unix);

    canonical := path_raw || '?' || query_no_sig;

    signing_key_b64 := nullif(current_setting('app.signing_key_b64', true), '');
    IF signing_key_b64 IS NULL THEN
        signing_key_b64 := app_private_setting_get('cloudflare_assets_signing_key_b64');
        IF signing_key_b64 IS NULL OR btrim(signing_key_b64) = '' THEN
            RAISE EXCEPTION 'Missing app.signing_key_b64 and app_private_setting.cloudflare_assets_signing_key_b64';
        END IF;
        PERFORM set_config('app.signing_key_b64', signing_key_b64, true);
    END IF;

    signing_key := decode(signing_key_b64, 'base64');

    sig_hex := encode(
        hmac(convert_to(canonical, 'utf8'), signing_key, 'sha256'),
        'hex'
    );

    RETURN base_url || path_encoded || '?' || query_no_sig || '&sig=' || sig_hex;
END;
$$;
