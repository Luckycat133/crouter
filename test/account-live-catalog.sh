#!/bin/sh
# Real loopback catalogs and isolated CLI consumers; no accounts or inference.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"${NODE_BIN:-node}" --test "$ROOT_DIR/test/account-live-catalog.test.js"
