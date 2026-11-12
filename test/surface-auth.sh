#!/bin/sh
# Shell-side surface resolution must preserve plan/API separation before the
# candidate JSON reaches either local proxy.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node)}
LIB_DIR="$ROOT_DIR/lib"
BIN_DIR="$ROOT_DIR/bin"
PROVIDER_NAME=demo
AUTH_MODE=surfaces
BASE_URL=https://plan.example/anthropic
MODEL=logical-model
MODEL_OPUS=logical-opus
MODEL_SONNET=logical-model
MODEL_HAIKU=logical-haiku
MODEL_SUBAGENT=logical-haiku
PLAN_URL=https://plan.example/anthropic
PLAN_AUTH_TYPE=bearer
PLAN_KEY_ENV=DEMO_PLAN_KEY
PLAN_KEYS="demo-plan-1 demo-plan-2"
PLAN_MODEL=plan-model
PLAN_MODEL_OPUS=plan-opus
PLAN_MODEL_SONNET=plan-model
PLAN_MODEL_HAIKU=plan-haiku
PLAN_MODEL_SUBAGENT=plan-haiku
API_URL=https://api.example/anthropic
API_AUTH_TYPE=x-api-key
API_KEY_ENV=DEMO_API_KEY
API_KEYS="demo-api-1"
API_MODEL=api-model
API_MODEL_OPUS=api-opus
API_MODEL_SONNET=api-model
API_MODEL_HAIKU=api-haiku
API_MODEL_SUBAGENT=api-haiku
LOG_DIR=
ROOT_DIR=$ROOT_DIR
USER=${USER:-test}

die() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
info() { :; }
# ac76035 requires explicit authorization before a plan surface is allowed to
# fall back to the pay-as-you-go API surface, and a second opt-in when the
# upstream model maps differ (docs/provider-refresh-2026-11-07.md). This case
# asserts both surfaces stay bound to their own endpoint, so authorize both.
export CROUTER_ALLOW_PAID_FALLBACK=1
export CROUTER_ALLOW_CROSS_MODEL_FALLBACK=1
export DEMO_PLAN_KEY=plan-env
export DEMO_API_KEY=api-env
. "$ROOT_DIR/lib/auth.sh"
kc_get() {
  case $1 in
    demo-plan-1) printf plan-one ;;
    demo-plan-2) printf plan-two ;;
    demo-api-1) printf api-one ;;
  esac
}

resolve_surface_tokens
[ "$_PLAN_TOKENS" = "plan-env plan-one plan-two" ] || {
  printf 'FAIL  wrong plan token pool\n' >&2; exit 1;
}
[ "$_API_TOKENS" = "api-env api-one" ] || {
  printf 'FAIL  wrong API token pool\n' >&2; exit 1;
}
[ "$_PLAN_FIRST_TOKEN" = plan-env ] && [ "$_API_FIRST_TOKEN" = api-env ] || {
  printf 'FAIL  first surface tokens not exposed for session assets\n' >&2; exit 1;
}
[ "$_SURFACE_COUNT" -eq 5 ] || {
  printf 'FAIL  wrong surface candidate count: %s\n' "$_SURFACE_COUNT" >&2; exit 1;
}

_json=$(build_surface_candidates)
SURFACE_JSON=$_json "$NODE_BIN" - <<'NODE'
const assert = require('assert');
const candidates = JSON.parse(process.env.SURFACE_JSON);
assert.deepStrictEqual(candidates.map((c) => [c.label, c.url, c.type, c.token, c.model_map]), [
  ['token-plan-1', 'https://plan.example/anthropic', 'bearer', 'plan-env', {
    'logical-model': 'plan-model', 'logical-opus': 'plan-opus', 'logical-haiku': 'plan-haiku',
  }],
  ['token-plan-2', 'https://plan.example/anthropic', 'bearer', 'plan-one', {
    'logical-model': 'plan-model', 'logical-opus': 'plan-opus', 'logical-haiku': 'plan-haiku',
  }],
  ['token-plan-3', 'https://plan.example/anthropic', 'bearer', 'plan-two', {
    'logical-model': 'plan-model', 'logical-opus': 'plan-opus', 'logical-haiku': 'plan-haiku',
  }],
  ['api-key-1', 'https://api.example/anthropic', 'x-api-key', 'api-env', {
    'logical-model': 'api-model', 'logical-opus': 'api-opus', 'logical-haiku': 'api-haiku',
  }],
  ['api-key-2', 'https://api.example/anthropic', 'x-api-key', 'api-one', {
    'logical-model': 'api-model', 'logical-opus': 'api-opus', 'logical-haiku': 'api-haiku',
  }],
]);
NODE

[ "$(surface_state)" = plan+api ] || {
  printf 'FAIL  surface state does not report plan+api\n' >&2; exit 1;
}

# Every declared Keychain service is an optional credential source. A provider
# with both surfaces must still launch when only one environment credential is
# configured and none of its Keychain items exist.
kc_get() { return 1; }
unset DEMO_API_KEY
export DEMO_PLAN_KEY=plan-env-only
resolve_surface_tokens
[ "$_PLAN_TOKENS" = plan-env-only ] && [ -z "$_API_TOKENS" ] && [ "$_SURFACE_COUNT" -eq 1 ] || {
  printf 'FAIL  plan-only environment credential was not accepted\n' >&2; exit 1;
}

unset DEMO_PLAN_KEY
export DEMO_API_KEY=api-env-only
resolve_surface_tokens
[ -z "$_PLAN_TOKENS" ] && [ "$_API_TOKENS" = api-env-only ] && [ "$_SURFACE_COUNT" -eq 1 ] || {
  printf 'FAIL  API-only environment credential was not accepted\n' >&2; exit 1;
}

unset DEMO_API_KEY
if (resolve_surface_tokens) >/dev/null 2>&1; then
  printf 'FAIL  direct surface resolution accepted an empty credential set\n' >&2
  exit 1
fi

printf 'ok    shell surface resolution preserves plan/API binding\n'
