#!/usr/bin/env bash
#
# Regression harness for internal/db/schema_normalizer.cfc: what an expanded link carries from
# the table it links to (sensitive fields, a table's expand_fields, a field's expand: "condensed").
# Runs scripts/schema_normalizer_test/run.cfm on the RustCFML command line; no database needed.
#
# Run from Moopa's root, with rustcfml on PATH or RUSTCFML set to the binary:
#   bash scripts/test_schema_normalizer.sh

set -euo pipefail

engine="${RUSTCFML:-$(command -v rustcfml || true)}"
if [ -z "$engine" ] || [ ! -x "$engine" ]; then
  echo "rustcfml not found: put it on PATH or set RUSTCFML to the binary" >&2
  exit 2
fi

"$engine" scripts/schema_normalizer_test/run.cfm
