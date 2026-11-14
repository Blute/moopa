#!/usr/bin/env bash
#
# Regression harness for application.cfc's _assertModernLocalMode(): Moopa starts in modern local
# mode and refuses to start in classic (docs/local-mode.md).
# Runs scripts/local_mode_test/{modern,classic}/run.cfm on the RustCFML command line, each under an
# Application.cfc that sets that mode; no database needed.
#
# Run from Moopa's root, with rustcfml on PATH or RUSTCFML set to the binary:
#   bash scripts/test_local_mode.sh

set -euo pipefail

engine="${RUSTCFML:-$(command -v rustcfml || true)}"
if [ -z "$engine" ] || [ ! -x "$engine" ]; then
  echo "rustcfml not found: put it on PATH or set RUSTCFML to the binary" >&2
  exit 2
fi

"$engine" scripts/local_mode_test/modern/run.cfm
"$engine" scripts/local_mode_test/classic/run.cfm
