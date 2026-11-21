#!/usr/bin/env bash
#
# Regression harness for a table definition's publish settings (internal/db/publish_config.cfc) and
# the addresses lib/published_files.cfc makes from them (addressFor).
# Runs scripts/publish_config_test/run.cfm on the RustCFML command line; no database needed.
#
# Run from Moopa's root, with rustcfml on PATH or RUSTCFML set to the binary:
#   bash scripts/test_publish_config.sh

set -euo pipefail

engine="${RUSTCFML:-$(command -v rustcfml || true)}"
if [ -z "$engine" ] || [ ! -x "$engine" ]; then
  echo "rustcfml not found: put it on PATH or set RUSTCFML to the binary" >&2
  exit 2
fi

"$engine" scripts/publish_config_test/run.cfm
