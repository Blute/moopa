#!/usr/bin/env bash
#
# Regression harness for scripts/assert-route-links.py, the check that every package's
# route_links.json lists exactly its route files and links only to routes its apps serve. Feeds
# the check fixture code trees and checks which it refuses. Route URLs here follow Moopa's own
# derivation (internal/routing/route_url.cfc): .cfc dropped, a trailing /index dropped,
# routes/index.cfc is /. If that file changes how it derives a URL, this harness and the script
# change with it.
#
# Run from Moopa's root:
#   bash scripts/test_assert_route_links.sh

set -euo pipefail

check="$PWD/scripts/assert-route-links.py"
tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
failures=0

# expect <pass|refuse> <label> [<expected output fragment>] [<target>]: runs the check on
# $tmpdir/code, or on <target> under $tmpdir.
expect() {
  local outcome="$1" label="$2" fragment="${3:-}" target="$tmpdir/${4:-code}"
  if python3 "$check" "$target" > "$tmpdir/out" 2>&1; then
    actual="pass"
  else
    actual="refuse"
  fi

  if [ "$actual" != "$outcome" ]; then
    printf 'FAIL  %s (expected %s, got %s)\n' "$label" "$outcome" "$actual"
    sed 's/^/      /' "$tmpdir/out"
    failures=$((failures + 1))
  elif [ -n "$fragment" ] && ! grep -qF -- "$fragment" "$tmpdir/out"; then
    printf 'FAIL  %s (output lacks "%s")\n' "$label" "$fragment"
    sed 's/^/      /' "$tmpdir/out"
    failures=$((failures + 1))
  else
    printf 'PASS  %s\n' "$label"
  fi
}

# tree: a fresh project code tree with two apps, shared routes and Moopa's System routes, which
# Hub serves from the framework.
tree() {
  rm -rf "$tmpdir/code"
  local c="$tmpdir/code"
  mkdir -p "$c/apps/hub/routes/rea/[account_id]" "$c/apps/www/routes" "$c/shared/routes/login" "$c/moopa/routes/sysadmin"
  touch "$c/apps/hub/routes/index.cfc" \
        "$c/apps/hub/routes/rea/accounts.cfc" \
        "$c/apps/hub/routes/rea/[account_id]/account.cfc" \
        "$c/apps/hub/routes/rea/[account_id]/index.cfc" \
        "$c/apps/www/routes/about.cfc" \
        "$c/shared/routes/logout.cfc" \
        "$c/shared/routes/login/index.cfc" \
        "$c/moopa/routes/sysadmin/roles.cfc"
}

links() { printf '%s\n' "$2" > "$tmpdir/code/$1/route_links.json"; }

good_hub='{
  "/": ["/rea/accounts"],
  "/rea/[account_id]": [],
  "/rea/[account_id]/account": ["/logout", "/rea/accounts", "/sysadmin/roles"],
  "/rea/accounts": ["/rea/[account_id]/account"]
}'

tree
expect pass "no route_links.json anywhere: nothing to check"

tree; links apps/hub "$good_hub"
expect pass "every hub route listed; links to its own, shared and Moopa's System routes"

tree; links apps/hub '{"/": [], "/rea/[account_id]": [], "/rea/[account_id]/account": [], "/rea/accounts": []}'
links apps/www '{"/about": ["/sysadmin/roles"]}'
expect refuse "an app other than Hub linking to a System page" "/about links to /sysadmin/roles, which is not a route every app loading apps/www serves"

tree; links apps/hub '{"/": [], "/rea/[account_id]": [], "/rea/accounts": []}'
expect refuse "a route file with no entry" "apps/hub: /rea/[account_id]/account is a route file but has no entry (unmapped)"

tree; links apps/hub "$good_hub"; rm "$tmpdir/code/apps/hub/routes/rea/accounts.cfc"
expect refuse "an entry whose route file was deleted" "apps/hub: /rea/accounts has an entry but no route file in apps/hub"

tree; links apps/hub '{"/": [], "/rea/[account_id]": [], "/rea/[account_id]/account": [], "/rea/accounts": [], "/sysadmin/roles": []}'
expect refuse "listing one of Moopa's System routes" "/sysadmin/roles has an entry but no route file in apps/hub"

tree; ln -s ../../../moopa/routes/sysadmin "$tmpdir/code/apps/hub/routes/sysadmin"
expect refuse "a leftover link to Moopa's System routes" "apps/hub: /sysadmin/roles is under /sysadmin, which is Moopa's"

tree; mkdir -p "$tmpdir/code/apps/hub/routes/sysadmin"; touch "$tmpdir/code/apps/hub/routes/sysadmin/audit.cfc"
expect refuse "a project route under /sysadmin" "apps/hub: /sysadmin/audit is under /sysadmin, which is Moopa's"

tree; touch "$tmpdir/code/shared/routes/sysadmin.cfc"
expect refuse "a shared route at /sysadmin itself" "shared: /sysadmin is under /sysadmin, which is Moopa's"

tree; mkdir -p "$tmpdir/code/apps/hub/routes/sysadmins"; touch "$tmpdir/code/apps/hub/routes/sysadmins/list.cfc"
expect pass "a route that only starts with the same letters as /sysadmin"

tree; links apps/hub '{"/": ["/about"], "/rea/[account_id]": [], "/rea/[account_id]/account": [], "/rea/accounts": []}'
expect refuse "a link to another app's route" "/ links to /about, which is not a route every app loading apps/hub serves"

tree; links apps/hub '{"/": ["/rea/42/account"], "/rea/[account_id]": [], "/rea/[account_id]/account": [], "/rea/accounts": []}'
expect refuse "a link written as a URL rather than its route" "/ links to /rea/42/account"

tree; links apps/hub '{"/rea/accounts": [], "/": [], "/rea/[account_id]": [], "/rea/[account_id]/account": []}'
expect refuse "keys out of order" "keys are not in sorted order"

tree; links apps/hub '{"/": ["/rea/accounts", "/logout"], "/rea/[account_id]": [], "/rea/[account_id]/account": [], "/rea/accounts": []}'
expect refuse "links out of order" "/ links are not sorted and unique"

tree; links apps/hub '{"/": [], "/rea/[account_id]": [], "/rea/[account_id]/account": [], "/rea/accounts": ["/rea/accounts"]}'
expect refuse "a route linking to itself" "/rea/accounts links to itself"

tree; links apps/hub '{"/": [], "/": []}'
expect refuse "a key written twice" "lists / twice"

tree; links apps/hub '{"/": "/rea/accounts"}'
expect refuse "a route mapped to something other than an array" "must map to an array"

tree; links apps/hub '{ not json'
expect refuse "a file that is not JSON" "is not valid JSON"

tree; links shared '{"/login": ["/"], "/logout": []}'
expect refuse "a shared route linking to a route only one app serves" "/login links to /, which is not a route every app loading shared serves"

tree; links shared '{"/login": ["/logout"], "/logout": []}'
expect pass "a shared route linking to a shared route"

tree; links shared '{"/login": ["/sysadmin/roles"], "/logout": []}'
expect refuse "a shared route linking to a System page only Hub serves" "/login links to /sysadmin/roles"

tree; links moopa '{"/sysadmin/roles": []}'
expect pass "Moopa's own file, checked from its checkout" "" "code/moopa"

tree; links moopa '{"/sysadmin/roles": ["/rea/accounts"]}'
expect refuse "Moopa linking outside its own routes" "moopa: /sysadmin/roles links to /rea/accounts" "code/moopa"

tree; links apps/hub '{"/rea/accounts": ["/rea/[account_id]/account", "/rea/[account_id]/account", "/rea/accounts"], "/": ["/rea/accounts"], "/rea/[account_id]/account": ["/sysadmin/roles", "/rea/accounts", "/logout"], "/rea/[account_id]": []}'
if python3 "$check" --format "$tmpdir/code" > "$tmpdir/out" 2>&1 \
   && [ "$(cat "$tmpdir/code/apps/hub/route_links.json")" = "$(printf '%s' "$good_hub" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), indent=2))')" ]; then
  printf 'PASS  %s\n' "--format sorts, de-duplicates and drops self-links, then passes"
else
  printf 'FAIL  %s\n' "--format sorts, de-duplicates and drops self-links, then passes"
  sed 's/^/      /' "$tmpdir/out"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  printf '\n%d case(s) failed\n' "$failures"
  exit 1
fi
printf '\nAll cases passed\n'
