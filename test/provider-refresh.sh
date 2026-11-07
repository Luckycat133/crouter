#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
"${NODE_BIN:-node}" "$ROOT_DIR/test/provider-config.js"
