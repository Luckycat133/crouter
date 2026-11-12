#!/bin/sh
# Surface routing contract: Token Plan and pay-as-you-go credentials must stay
# bound to their own endpoint, auth header, and optional upstream model.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node)}

_json=$(
  CR_PLAN_URL="https://plan.example/anthropic" \
  CR_PLAN_TYPE="bearer" \
  CR_PLAN_TOKENS="plan-a plan-b" \
  CR_PLAN_MODEL="plan-model" \
  CR_PLAN_MODEL_OPUS="plan-opus" \
  CR_PLAN_MODEL_HAIKU="plan-haiku" \
  CR_API_URL="https://api.example/anthropic" \
  CR_API_TYPE="x-api-key" \
  CR_API_TOKENS="api-a" \
  CR_API_MODEL="api-model" \
  CR_API_MODEL_OPUS="api-opus" \
  CR_API_MODEL_HAIKU="api-haiku" \
  CR_MODEL="logical-model" \
  CR_MODEL_OPUS="logical-opus" \
  CR_MODEL_SONNET="logical-sonnet" \
  CR_MODEL_HAIKU="logical-haiku" \
  CR_MODEL_SUBAGENT="logical-subagent" \
  CROUTER_ALLOW_PAID_FALLBACK=1 \
  CROUTER_ALLOW_CROSS_MODEL_FALLBACK=1 \
    "$NODE_BIN" "$ROOT_DIR/lib/route-build.js" surface-candidates
)

SURFACE_JSON=$_json "$NODE_BIN" - <<'NODE'
const assert = require('assert');
const candidates = JSON.parse(process.env.SURFACE_JSON);
assert.deepStrictEqual(candidates, [
  {
    url: 'https://plan.example/anthropic',
    type: 'bearer',
    token: 'plan-a',
    model_map: {
      'logical-model': 'plan-model',
      'logical-opus': 'plan-opus',
      'logical-sonnet': 'plan-model',
      'logical-haiku': 'plan-haiku',
      'logical-subagent': 'plan-model',
    },
    label: 'token-plan-1',
  },
  {
    url: 'https://plan.example/anthropic',
    type: 'bearer',
    token: 'plan-b',
    model_map: {
      'logical-model': 'plan-model',
      'logical-opus': 'plan-opus',
      'logical-sonnet': 'plan-model',
      'logical-haiku': 'plan-haiku',
      'logical-subagent': 'plan-model',
    },
    label: 'token-plan-2',
  },
  {
    url: 'https://api.example/anthropic',
    type: 'x-api-key',
    token: 'api-a',
    model_map: {
      'logical-model': 'api-model',
      'logical-opus': 'api-opus',
      'logical-sonnet': 'api-model',
      'logical-haiku': 'api-haiku',
      'logical-subagent': 'api-model',
    },
    label: 'api-key-1',
  },
]);
NODE

_route=$(
  CR_PREFIX="demo" \
  CR_MODELS="logical-model" \
  CR_SURFACE_CANDIDATES="$_json" \
  CR_API_URL="https://api.example/anthropic" \
    "$NODE_BIN" "$ROOT_DIR/lib/route-build.js" candidates
)

ROUTE_JSON=$_route "$NODE_BIN" - <<'NODE'
const assert = require('assert');
const route = JSON.parse(process.env.ROUTE_JSON);
assert.strictEqual(route.prefix, 'demo');
assert.strictEqual(route.models[0], 'logical-model');
assert.deepStrictEqual(route.candidates.map((candidate) => ({
  url: candidate.url,
  type: candidate.auth.type,
  token: candidate.auth.token,
  model_map: candidate.model_map,
})), [
  {
    url: 'https://plan.example/anthropic',
    type: 'bearer',
    token: 'plan-a',
    model_map: {'logical-model': 'plan-model', 'logical-opus': 'plan-opus', 'logical-sonnet': 'plan-model', 'logical-haiku': 'plan-haiku', 'logical-subagent': 'plan-model'},
  },
  {
    url: 'https://plan.example/anthropic',
    type: 'bearer',
    token: 'plan-b',
    model_map: {'logical-model': 'plan-model', 'logical-opus': 'plan-opus', 'logical-sonnet': 'plan-model', 'logical-haiku': 'plan-haiku', 'logical-subagent': 'plan-model'},
  },
  {
    url: 'https://api.example/anthropic',
    type: 'x-api-key',
    token: 'api-a',
    model_map: {'logical-model': 'api-model', 'logical-opus': 'api-opus', 'logical-sonnet': 'api-model', 'logical-haiku': 'api-haiku', 'logical-subagent': 'api-model'},
  },
]);
NODE

printf 'ok    surface candidates keep keys bound to URL/auth/tier model maps\n'
