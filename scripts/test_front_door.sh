#!/usr/bin/env bash
#
# Regression harness for application.cfc's OnRequest: Moopa's ways in are exactly /index.cfm (the
# home page, always /) and /_moopa.cfm (the engine's fallback), and a visitor's ?route= never
# chooses the route on /index.cfm (docs/routing.md).
# Runs scripts/front_door_test/run.cfm on the RustCFML command line; no database needed.
#
# Run from Moopa's root, with rustcfml on PATH or RUSTCFML set to the binary:
#   bash scripts/test_front_door.sh

set -euo pipefail

engine="${RUSTCFML:-$(command -v rustcfml || true)}"
if [ -z "$engine" ] || [ ! -x "$engine" ]; then
  echo "rustcfml not found: put it on PATH or set RUSTCFML to the binary" >&2
  exit 2
fi

"$engine" scripts/front_door_test/run.cfm
