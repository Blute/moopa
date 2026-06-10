<!---
    Cloudflare signed assets — setup guide

    ARCHITECTURE
    All media lives in a PRIVATE Cloudflare R2 bucket. Nothing is served from R2
    directly. A Cloudflare Worker (config/init/cloudflare-signed-assets-worker.js)
    fronts the bucket on a dedicated hostname (e.g. https://assets.example.com) and
    only serves requests carrying a valid HMAC-SHA256 signature and unexpired `exp`.

    URLs are signed by ONE canonical implementation: the PostgreSQL function
    signed_asset_url() (created by config/init/cloudflare.sql). SELECT queries call
    it to emit ready-to-use URLs straight from the database; this CFC is a thin
    wrapper that delegates one-off CFML signing to that same function. Do not
    re-implement signing in CFML — signer and Worker must agree byte-for-byte on
    the canonical string (path + '?' + sorted query without sig).

    Expiry types are period-aligned (EOD = end of *this* day, EOM = end of *this*
    month, etc.), so every URL signed within the same window is identical —
    page refreshes reuse browser/edge cache instead of generating new URLs.
    Worker route prefixes: /a/* raw asset, /i/* image transform, /m/* PDF-to-
    markdown, /v/* Cloudflare Stream redirect.

    KEY VERSIONING (kid)
    Signed URLs carry a kid=<id> param identifying which key signed them. The
    Worker verifies kid-carrying URLs against its SIGNING_KEYS_JSON keyring and
    URLs without kid against the legacy SIGNING_KEY_B64 secret. This separates
    planned rotation (add a new kid, old URLs keep verifying) from revocation
    (delete a kid from the keyring and its URLs die immediately) — important
    because 'NEVER' URLs are persisted to the database and shared externally.

    SETUP — signing config lives in the database + Worker. No app env vars.

    1. Generate a signing key:
         openssl rand -base64 32

    2. Database (run once per environment):
       - Apply config/init/cloudflare.sql (creates app_private_setting table and
         the signed_asset_url / signed_url_expiry / signed_url_query functions).
       - Seed the settings the function reads:
           INSERT INTO app_private_setting(key, value) VALUES
             ('cloudflare_assets_signing_key_b64', '<key from step 1>'),
             ('cloudflare_assets_signing_kid', 'v1'),
             ('cloudflare_assets_base_url', 'https://assets.example.com')
           ON CONFLICT (key) DO UPDATE
             SET value = EXCLUDED.value, updated_at = now();

    3. Cloudflare dashboard:
       - R2: create the bucket. Keep it private — no public access, no custom
         domain on the bucket itself.
       - Workers & Pages: create a Worker from
         config/init/cloudflare-signed-assets-worker.js, then under
         Settings > Domains & Routes add the asset hostname (the zone must be
         on Cloudflare). This hostname is your cloudflare_assets_base_url.
       - Worker Settings > Bindings:
           ASSETS_BUCKET  -> R2 bucket binding (the bucket above)
           AI             -> Workers AI binding (only needed for /m/* PDF-to-markdown)
       - Worker Settings > Variables and Secrets:
           SIGNING_KEYS_JSON      (type: Secret) -> {"v1": "<key from step 1>"}
           SIGNING_KEY_B64        (type: Secret) -> same key from step 1; verifies
                                                    URLs signed without a kid and is
                                                    used for the Worker's internal
                                                    /i/* -> /a/* source fetch
           CF_STREAM_BASE_URL     (type: Var)    -> https://customer-<code>.cloudflarestream.com
                                                    (Stream > copy your customer subdomain;
                                                    only needed for /v/*)
           MAX_MARKDOWN_PDF_BYTES (type: Var, optional) -> /m/* size cap, default 25 MiB
       - Images > Transformations: enable for the zone serving the Worker
         (required for /i/* resizing).

    4. Verify:
         SELECT signed_asset_url('some/key.jpg', 'EOD', 'i', 'width=100');
         curl -I "<that url>"          -- expect 200 with image content type
       401 = key mismatch (or kid missing from SIGNING_KEYS_JSON). 403 = expired
       exp. /i/* not transforming = Images Transformations not enabled on the zone.

    ROTATING THE KEY
      1. Generate a new key (step 1 above).
      2. Worker: add it to SIGNING_KEYS_JSON under the next kid, e.g.
         {"v1": "<old>", "v2": "<new>"}.
      3. Database: update cloudflare_assets_signing_key_b64 to the new key and
         cloudflare_assets_signing_kid to 'v2'.
      Existing URLs (including persisted 'NEVER' URLs) keep verifying via their
      kid. To retire an old key, first re-sign persisted URLs — signing lives in
      Postgres, so that is a single UPDATE calling signed_asset_url() — then
      remove the kid from SIGNING_KEYS_JSON.
      If a key is COMPROMISED, remove its kid immediately (and if it is the
      legacy key, replace SIGNING_KEY_B64): all URLs signed with it stop working.

    USAGE
      application.lib.cloudflare.signed_asset_url(path, 'EOD', 'i', 'width=500')
    Expiry guidance: NEVER for public/persisted URLs (logos, agent photos,
    stored thumbnails), EOM for URLs embedded in emails, EOD for private
    in-session content. In SELECT queries, call the SQL function directly
    instead of looping over a recordset in CFML.
--->
<cfcomponent displayname="Cloudflare" hint="Cloudflare Assets signed URLs — delegates to the PostgreSQL signed_asset_url() function so there is a single signing implementation">

    <cffunction name="init" access="public" returntype="any" output="false">
        <cfreturn this />
    </cffunction>


    <cffunction name="signed_asset_url" access="public" returntype="string" output="false">
        <cfargument name="key" type="any" required="false" default="" />
        <cfargument name="expiry_type" type="string" required="true" />
        <cfargument name="kind" type="string" required="false" default="a" />
        <cfargument name="options" type="any" required="false" default="" />

        <cfset var qSign = "" />
        <cfset var cleanKey = "" />
        <cfset var optionString = normalize_options_string(arguments.options) />

        <cfif isNull(arguments.key)>
            <cfreturn "" />
        </cfif>

        <cfset cleanKey = trim(toString(arguments.key)) />

        <cfif !len(cleanKey)>
            <cfreturn "" />
        </cfif>

        <cfquery name="qSign">
            SELECT signed_asset_url(
                <cfqueryparam cfsqltype="cf_sql_varchar" value="#cleanKey#" />,
                <cfqueryparam cfsqltype="cf_sql_varchar" value="#arguments.expiry_type#" />,
                <cfqueryparam cfsqltype="cf_sql_varchar" value="#arguments.kind#" />,
                <cfqueryparam cfsqltype="cf_sql_varchar" value="#optionString#" null="#!len(optionString)#" />
            ) AS url
        </cfquery>

        <cfreturn qSign.url ?: "" />
    </cffunction>


    <cffunction name="normalize_options_string" access="private" returntype="string" output="false">
        <cfargument name="options" type="any" required="false" default="" />

        <cfset var parts = [] />
        <cfset var k = "" />

        <cfif isSimpleValue(arguments.options)>
            <cfreturn trim(toString(arguments.options ?: "")) />
        </cfif>

        <cfif isStruct(arguments.options)>
            <cfloop collection="#arguments.options#" item="k">
                <cfif len(trim(k))>
                    <cfset arrayAppend(parts, trim(k) & "=" & toString(arguments.options[k] ?: "")) />
                </cfif>
            </cfloop>
        </cfif>

        <cfreturn arrayToList(parts, "&") />
    </cffunction>

</cfcomponent>
