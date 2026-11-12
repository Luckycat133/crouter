#!/bin/sh
# Compatibility keypools must bind each secret to its declared endpoint; a
# keys-by-URLs Cartesian product can leak a plan key to the pay-as-you-go API.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LIB_DIR="$ROOT_DIR/lib"
NODE_BIN=${NODE_BIN:-$(command -v node)}
BASE_URL=https://api.example/anthropic
PLUS_URL=https://plan.example/anthropic
_AUTH_SCHEME=bearer
_plus_pool="plan-a plan-b"
_main_pool="api-a"
. "$ROOT_DIR/lib/auth.sh"

# Since ac76035 a plan surface suppresses the pay-as-you-go API surface unless
# the paid fallback is authorized explicitly (docs/provider-refresh-2026-11-07.md).
# Authorize it here so this case still proves that each secret stays bound to
# its own declared endpoint.
CROUTER_ALLOW_PAID_FALLBACK=1
export CROUTER_ALLOW_PAID_FALLBACK

_json=$(build_legacy_keypool_candidates)
LEGACY_JSON=$_json "$NODE_BIN" - <<'NODE'
const assert = require('assert');
const candidates = JSON.parse(process.env.LEGACY_JSON);
assert.deepStrictEqual(candidates.map(({url, type, token}) => ({url, type, token})), [
  {url: 'https://plan.example/anthropic', type: 'bearer', token: 'plan-a'},
  {url: 'https://plan.example/anthropic', type: 'bearer', token: 'plan-b'},
  {url: 'https://api.example/anthropic', type: 'bearer', token: 'api-a'},
]);
NODE

printf 'ok    legacy keypools keep keys bound to their declared endpoint\n'
