#!/bin/sh
# Real gateway child processes and loopback fixtures; no credentials or inference.
set -eu
ROOT_DIR=${ROOT_DIR:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}
TEST_SHELL=${TEST_SHELL:-sh}
export ROOT_DIR TEST_SHELL
exec "${NODE_BIN:-node}" --test "$ROOT_DIR/test/gateway-cancellation.test.js"
