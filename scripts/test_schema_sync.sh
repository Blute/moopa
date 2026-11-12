#!/usr/bin/env bash
#
# Regression harness for lib/schemaSync.cfc's normalizeExpression(): a definition's column default or
# generation expression and the form Postgres stored compare equal when they mean the same.
# Runs scripts/schema_sync_test/run.cfm on the RustCFML command line; no database needed.
#
# Run from Moopa's root, with rustcfml on PATH or RUSTCFML set to the binary:
#   bash scripts/test_schema_sync.sh

set -euo pipefail

engine="${RUSTCFML:-$(command -v rustcfml || true)}"
if [ -z "$engine" ] || [ ! -x "$engine" ]; then
  echo "rustcfml not found: put it on PATH or set RUSTCFML to the binary" >&2
  exit 2
fi

"$engine" scripts/schema_sync_test/run.cfm
