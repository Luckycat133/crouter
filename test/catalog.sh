#!/bin/sh
# New catalog/state/policy unit and loopback HTTP regressions. No real secrets.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"${NODE_BIN:-node}" --test "$ROOT_DIR/test/catalog.test.js" "$ROOT_DIR/test/route-policy.test.js"
