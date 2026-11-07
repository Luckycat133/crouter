#!/bin/sh
# Offline package validation only. Does not source config/providers or use keys.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-node}
command -v "$NODE_BIN" >/dev/null 2>&1 || {
  printf '%s\n' 'FAIL development-skill: Node.js is required' >&2
  exit 1
}
"$NODE_BIN" "$ROOT_DIR/.agents/skills/crouter-development/scripts/validate.mjs"
"$NODE_BIN" "$ROOT_DIR/.agents/skills/crouter-development/scripts/validate.test.mjs"
