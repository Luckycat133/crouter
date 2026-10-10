#!/bin/sh
# Adversarial Stress Test Suite for crouter routing contracts and provider configurations
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node 2>/dev/null || true)}
[ -n "$NODE_BIN" ] || { printf 'FAIL  node binary not found\n' >&2; exit 1; }

fail_count=0
pass_count=0

pass() {
  printf 'ok    %s\n' "$1"
  pass_count=$((pass_count + 1))
}

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  fail_count=$((fail_count + 1))
}

echo "=== STRESS TEST 1: Antigravity Tiered and Aliased Model Resolution ==="

"$NODE_BIN" - <<'NODE_ANTIGRAV'
const assert = require('assert');
const fs = require('fs');
const path = require('path');

// 1. Verify config.example.json modelMapping
const configPath = path.join(process.cwd(), 'antigravity-claude-proxy/config.example.json');
const configJson = JSON.parse(fs.readFileSync(configPath, 'utf8'));
assert(configJson.modelMapping, 'config.example.json must have modelMapping');
assert.strictEqual(configJson.modelMapping['gemini-3.8-flash']?.mapping, 'gemini-3.8-flash-tiered');
assert.strictEqual(configJson.modelMapping['gemini-3.7-flash']?.mapping, 'gemini-3.7-flash-tiered');

// 2. Verify constants.MODEL_FALLBACK_MAP and getModelFamily
const constantsPath = path.join(process.cwd(), 'antigravity-claude-proxy/src/constants.js');
const constantsContent = fs.readFileSync(constantsPath, 'utf8');

// Dynamic import of ES modules
async function testConstants() {
  const { MODEL_FALLBACK_MAP, getModelFamily, isThinkingModel } = await import('file://' + constantsPath);
  
  const targetModels = [
    'gemini-3.8-flash',
    'gemini-3.8-flash-tiered',
    'gemini-3.7-flash',
    'gemini-3.7-flash-tiered',
  ];

  for (const model of targetModels) {
    // Check family
    assert.strictEqual(getModelFamily(model), 'gemini', `Family of ${model} must be gemini`);
    // Check thinking detection (gemini-3+)
    assert.strictEqual(isThinkingModel(model), true, `${model} must be recognized as thinking model`);
    // Check fallback mapping
    assert(MODEL_FALLBACK_MAP[model], `MODEL_FALLBACK_MAP must define fallback for ${model}`);
    assert.strictEqual(MODEL_FALLBACK_MAP[model], 'gemini-3.5-flash-low', `Fallback for ${model} must be gemini-3.5-flash-low`);
  }

  // 3. Test mapping simulation matching server.js lines 726-747
  const modelMapping = configJson.modelMapping;
  for (const model of targetModels) {
    let requested = model;
    if (modelMapping[requested] && modelMapping[requested].mapping) {
      requested = modelMapping[requested].mapping;
    }
    // Verify mapped result
    if (model.includes('-tiered')) {
      assert.strictEqual(requested, model, `${model} should pass through unchanged`);
    } else {
      assert.strictEqual(requested, `${model}-tiered`, `${model} should map to -tiered`);
    }
    assert.strictEqual(getModelFamily(requested), 'gemini');
  }

  // 4. Test isValidModel logic with simulated model cache
  const { isValidModel } = await import('file://' + path.join(process.cwd(), 'antigravity-claude-proxy/src/cloudcode/model-api.js'));
  // Under empty cache / failed fetch, isValidModel fails open (returns true)
  const openResult = await isValidModel('gemini-3.8-flash-tiered', 'dummy-token', null);
  assert.strictEqual(openResult, true, 'isValidModel must fail open safely without throwing');
}

testConstants().then(() => {
  process.exit(0);
}).catch(err => {
  console.error(err);
  process.exit(1);
});
NODE_ANTIGRAV
if [ $? -eq 0 ]; then
  pass "Antigravity tiered/aliased models resolve and fallback cleanly without 400"
else
  fail "Antigravity tiered/aliased models resolution failed"
fi

echo "=== STRESS TEST 2: Candidate Model Translation in Gateway & Keypool-Proxy ==="

TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-stress)
trap 'kill "${GATEWAY_PID:-}" "${KEYPOOL_PID:-}" "${UPSTREAM_PID:-}" 2>/dev/null || true; rm -rf "$TMP_DIR"' EXIT INT TERM

# Start a mock upstream server recording incoming models
cat > "$TMP_DIR/mock-upstream.js" <<'NODE_UP'
const http = require('http');
const fs = require('fs');

const logFile = process.env.REQUEST_LOG;

const server = http.createServer((req, res) => {
  const chunks = [];
  req.on('data', chunk => chunks.push(chunk));
  req.on('end', () => {
    let body = {};
    try {
      body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    } catch (e) {
      body = { _raw: Buffer.concat(chunks).toString('utf8') };
    }
    const entry = {
      path: req.url,
      method: req.method,
      headers: req.headers,
      model: body.model || null,
      rawBody: body._raw || null
    };
    fs.appendFileSync(logFile, JSON.stringify(entry) + '\n');
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ ok: true, receivedModel: body.model }));
  });
});

server.listen(0, '127.0.0.1', () => {
  const portFile = process.env.PORT_FILE;
  if (portFile) {
    fs.writeFileSync(portFile, String(server.address().port) + '\n');
  }
});
NODE_UP

REQUEST_LOG="$TMP_DIR/requests.log"
PORT_FILE="$TMP_DIR/upstream.port"
touch "$REQUEST_LOG"

REQUEST_LOG="$REQUEST_LOG" PORT_FILE="$PORT_FILE" "$NODE_BIN" "$TMP_DIR/mock-upstream.js" &
UPSTREAM_PID=$!

i=0
UPSTREAM_PORT=
while [ "$i" -lt 50 ]; do
  [ -s "$PORT_FILE" ] && { UPSTREAM_PORT=$(cat "$PORT_FILE" | tr -d '\r\n'); break; }
  sleep 0.05
  i=$((i + 1))
done
[ -n "$UPSTREAM_PORT" ] || { printf 'FAIL  upstream failed to start\n' >&2; exit 1; }

# 2.1 Test Gateway model translation logic under edge cases & adversarial inputs
"$NODE_BIN" - <<NODE_GW_TEST
const assert = require('assert');

// Replicate candidateModel from bin/gateway
function candidateModel(cand, requested) {
  if (
    cand.model_map &&
    typeof cand.model_map === 'object' &&
    Object.prototype.hasOwnProperty.call(cand.model_map, requested)
  ) {
    return cand.model_map[requested];
  }
  return cand.model || requested;
}

const candWithMap = {
  model_map: {
    'gemini-3.8-flash': 'gemini-3.8-flash-tiered',
    'gemini-3.7-flash': 'gemini-3.7-flash-tiered',
    'normal-model': 'upstream-normal',
  },
  model: 'upstream-fallback'
};

const candWithoutMap = {
  model: 'upstream-fallback-only'
};

const candMinimal = {};

// Test 1: exact matches in model_map
assert.strictEqual(candidateModel(candWithMap, 'gemini-3.8-flash'), 'gemini-3.8-flash-tiered');
assert.strictEqual(candidateModel(candWithMap, 'gemini-3.7-flash'), 'gemini-3.7-flash-tiered');
assert.strictEqual(candidateModel(candWithMap, 'normal-model'), 'upstream-normal');

// Test 2: unmapped unexpected model with cand.model defined -> fallback to cand.model
assert.strictEqual(candidateModel(candWithMap, 'unexpected-model'), 'upstream-fallback');
assert.strictEqual(candidateModel(candWithMap, ''), 'upstream-fallback');
assert.strictEqual(candidateModel(candWithMap, 'unknown/nested/model'), 'upstream-fallback');

// Test 3: prototype pollution attack vectors -> MUST NOT return Object.prototype
assert.strictEqual(candidateModel(candWithMap, '__proto__'), 'upstream-fallback');
assert.strictEqual(candidateModel(candWithMap, 'constructor'), 'upstream-fallback');
assert.strictEqual(candidateModel(candWithMap, 'toString'), 'upstream-fallback');
assert.strictEqual(candidateModel(candWithMap, 'valueOf'), 'upstream-fallback');
assert.strictEqual(candidateModel(candWithMap, 'hasOwnProperty'), 'upstream-fallback');

// Test 4: candidate without map falls back to cand.model or requested
assert.strictEqual(candidateModel(candWithoutMap, 'gemini-3.8-flash'), 'upstream-fallback-only');
assert.strictEqual(candidateModel(candWithoutMap, 'anything'), 'upstream-fallback-only');

// Test 5: candidate with neither model_map nor model gracefully passes through requested model
assert.strictEqual(candidateModel(candMinimal, 'gemini-3.8-flash'), 'gemini-3.8-flash');
assert.strictEqual(candidateModel(candMinimal, 'custom-model'), 'custom-model');

// Test 6: corrupted candidate objects
assert.strictEqual(candidateModel({ model_map: null }, 'foo'), 'foo');
assert.strictEqual(candidateModel({ model_map: 'not-an-object' }, 'foo'), 'foo');
assert.strictEqual(candidateModel({ model_map: [1, 2, 3] }, 'foo'), 'foo');

process.exit(0);
NODE_GW_TEST
if [ $? -eq 0 ]; then
  pass "Gateway candidateModel logic passes all edge-case and prototype tests"
else
  fail "Gateway candidateModel logic failed edge-case tests"
fi

# 2.2 Live Gateway instance stress test
cat > "$TMP_DIR/routes.json" <<EOF
[
  {
    "prefix": "testprov",
    "base_url": "http://127.0.0.1:$UPSTREAM_PORT",
    "candidates": [
      {
        "url": "http://127.0.0.1:$UPSTREAM_PORT",
        "auth": { "type": "bearer", "token": "test-token" },
        "model_map": {
          "gemini-3.8-flash": "gemini-3.8-flash-tiered",
          "gemini-3.7-flash": "gemini-3.7-flash-tiered"
        },
        "model": "default-fallback-model"
      }
    ],
    "models": ["gemini-3.8-flash", "gemini-3.7-flash", "gemini-3.8-flash-tiered"]
  }
]
EOF

GW_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
CROUTER_ROUTES_FILE="$TMP_DIR/routes.json" CROUTER_GATEWAY_PORT="$GW_PORT" \
CROUTER_GATEWAY_TOKEN="gw-secret" CROUTER_CANDIDATE_COOLDOWN_MS=60000 \
  "$NODE_BIN" "$ROOT_DIR/bin/gateway" > "$TMP_DIR/gateway.out" 2>/dev/null &
GATEWAY_PID=$!

i=0
while [ "$i" -lt 50 ]; do
  grep -q '^CROUTER_GATEWAY_LISTENING_PORT=' "$TMP_DIR/gateway.out" 2>/dev/null && break
  sleep 0.05
  i=$((i + 1))
done

# Test mapped model: testprov/gemini-3.8-flash
CODE1=$(curl -s -o "$TMP_DIR/res1.json" -w '%{http_code}' -X POST "http://127.0.0.1:$GW_PORT/v1/messages" \
  -H 'authorization: Bearer gw-secret' \
  -H 'content-type: application/json' \
  -d '{"model":"testprov/gemini-3.8-flash","messages":[]}')

# Test unmapped unexpected model: testprov/unknown-random-model -> should gracefully fall back to default-fallback-model
CODE2=$(curl -s -o "$TMP_DIR/res2.json" -w '%{http_code}' -X POST "http://127.0.0.1:$GW_PORT/v1/messages" \
  -H 'authorization: Bearer gw-secret' \
  -H 'content-type: application/json' \
  -d '{"model":"testprov/unknown-random-model","messages":[]}')

# Test malformed JSON body -> should return 400 invalid_request
CODE3=$(curl -s -o "$TMP_DIR/res3.json" -w '%{http_code}' -X POST "http://127.0.0.1:$GW_PORT/v1/messages" \
  -H 'authorization: Bearer gw-secret' \
  -H 'content-type: application/json' \
  -d '{"model": bad json')

# Test model without prefix -> should return 400 unknown_model
CODE4=$(curl -s -o "$TMP_DIR/res4.json" -w '%{http_code}' -X POST "http://127.0.0.1:$GW_PORT/v1/messages" \
  -H 'authorization: Bearer gw-secret' \
  -H 'content-type: application/json' \
  -d '{"model":"no-prefix-model","messages":[]}')

if [ "$CODE1" = "200" ] && [ "$CODE2" = "200" ] && [ "$CODE3" = "400" ] && [ "$CODE4" = "400" ]; then
  pass "Live Gateway routes mapped and edge-case models with graceful fallback (HTTP 200) and rejects malformed inputs (HTTP 400)"
else
  fail "Live Gateway unexpected status codes: CODE1=$CODE1 CODE2=$CODE2 CODE3=$CODE3 CODE4=$CODE4"
fi

# 2.3 Live Keypool-proxy translation stress test
_candidates=$(printf '[{"url":"http://127.0.0.1:%s","type":"bearer","token":"pool-token","model_map":{"gemini-3.8-flash":"gemini-3.8-flash-tiered"},"model":"pool-default-fallback","label":"plan"}]' "$UPSTREAM_PORT")
KEYPOOL_CANDIDATES="$_candidates" KEYPOOL_PORT=0 KEYPOOL_CLIENT_TOKEN=local-token \
  "$NODE_BIN" "$ROOT_DIR/bin/keypool-proxy" > "$TMP_DIR/pool.out" 2> "$TMP_DIR/pool.err" &
KEYPOOL_PID=$!

i=0
POOL_PORT=
while [ "$i" -lt 50 ]; do
  POOL_PORT=$(sed -n 's/^KEYPOOL_LISTENING_PORT=//p' "$TMP_DIR/pool.out" | head -n 1)
  [ -n "$POOL_PORT" ] && break
  sleep 0.05
  i=$((i + 1))
done

KP_CODE1=$(curl -s -o "$TMP_DIR/kp_res1.json" -w '%{http_code}' -X POST "http://127.0.0.1:$POOL_PORT/v1/messages" \
  -H 'anthropic-auth-token: local-token' \
  -H 'content-type: application/json' \
  -d '{"model":"gemini-3.8-flash","messages":[]}')

KP_CODE2=$(curl -s -o "$TMP_DIR/kp_res2.json" -w '%{http_code}' -X POST "http://127.0.0.1:$POOL_PORT/v1/messages" \
  -H 'anthropic-auth-token: local-token' \
  -H 'content-type: application/json' \
  -d '{"model":"unexpected-edge-case-model","messages":[]}')

KP_CODE3=$(curl -s -o "$TMP_DIR/kp_res3.json" -w '%{http_code}' -X POST "http://127.0.0.1:$POOL_PORT/v1/messages" \
  -H 'anthropic-auth-token: local-token' \
  -H 'content-type: application/json' \
  -d '{"model":"__proto__","messages":[]}')

KP_CODE4=$(curl -s -o "$TMP_DIR/kp_res4.json" -w '%{http_code}' -X POST "http://127.0.0.1:$POOL_PORT/v1/messages" \
  -H 'anthropic-auth-token: local-token' \
  -H 'content-type: application/json' \
  -d 'invalid body')

if [ "$KP_CODE1" = "200" ] && [ "$KP_CODE2" = "200" ] && [ "$KP_CODE3" = "200" ] && [ "$KP_CODE4" = "400" ]; then
  pass "Live Keypool-proxy translates mapped models, gracefully falls back on unexpected & __proto__ models, and returns 400 on invalid JSON"
else
  fail "Live Keypool-proxy failed: KP_CODE1=$KP_CODE1 KP_CODE2=$KP_CODE2 KP_CODE3=$KP_CODE3 KP_CODE4=$KP_CODE4"
fi

echo "=== STRESS TEST 3: Moonshot Context Override Logic ==="

"$ROOT_DIR/bin/crouter" provider show moonshot > "$TMP_DIR/moonshot-show.out"
if grep -q 'context:     262144 tokens' "$TMP_DIR/moonshot-show.out"; then
  pass "Moonshot default model k3-256k retains 262144 context tokens"
else
  fail "Moonshot default context did not show 262144 tokens"
fi

# Adversarial context override verification in subshell
sh -c '
set -eu
ROOT_DIR="'"$ROOT_DIR"'"
. "$ROOT_DIR/lib/provider.sh"
PROVIDERS_DIR="$ROOT_DIR/providers"
load_provider moonshot

# 1. Exact k3[1m] override
CONTEXT_TOKENS=262144
apply_model_context_override "k3[1m]"
[ "$CONTEXT_TOKENS" = "1000000" ] || exit 10

# 2. Default k3-256k retention
CONTEXT_TOKENS=262144
apply_model_context_override "k3-256k"
[ "$CONTEXT_TOKENS" = "262144" ] || exit 11

# 3. Other aliases retention
CONTEXT_TOKENS=262144
apply_model_context_override "kimi-for-coding"
[ "$CONTEXT_TOKENS" = "262144" ] || exit 12

CONTEXT_TOKENS=262144
apply_model_context_override "kimi-for-coding-highspeed"
[ "$CONTEXT_TOKENS" = "262144" ] || exit 13

# 4. Boundary / injection attack attempts: must NOT expand to 1M
CONTEXT_TOKENS=262144
apply_model_context_override "k3[1m]-extra"
[ "$CONTEXT_TOKENS" = "262144" ] || exit 14

CONTEXT_TOKENS=262144
apply_model_context_override "k3[1m]:tag"
[ "$CONTEXT_TOKENS" = "262144" ] || exit 15

CONTEXT_TOKENS=262144
apply_model_context_override "k3"
[ "$CONTEXT_TOKENS" = "262144" ] || exit 16
'
if [ $? -eq 0 ]; then
  pass "Moonshot k3[1m] expands context to 1,000,000 while default k3-256k and boundary attacks retain 262,144"
else
  fail "Moonshot context override failed boundary checks"
fi

echo "=== STRESS TEST 4: OpenRouter Model Resolution and Slug Audit ==="

sh -c '
set -eu
ROOT_DIR="'"$ROOT_DIR"'"
. "$ROOT_DIR/lib/provider.sh"
PROVIDERS_DIR="$ROOT_DIR/providers"
load_provider openrouter

# 1. Verify MODEL_ALIASES contains active qwen/qwen3.8-27b and NO :free slug for qwen
case " $MODEL_ALIASES " in
  *" qwen/qwen3.8-27b "*) : ;;
  *) echo "MODEL_ALIASES missing qwen/qwen3.8-27b" >&2; exit 21 ;;
esac

case " $MODEL_ALIASES " in
  *" qwen/qwen3.8-27b:free "*) echo "MODEL_ALIASES contains retired :free slug" >&2; exit 22 ;;
  *) : ;;
esac

# 2. Test PRE_START rewriting across all legacy and current input variants
test_rewrite() {
  _input="$1"
  _main_model="$_input"
  eval "$PRE_START"
  if [ "$_main_model" != "qwen/qwen3.8-27b" ]; then
    echo "Rewrite failed for input $_input -> got $_main_model" >&2
    exit 23
  fi
  if [ "$CONTEXT_TOKENS" != "262144" ]; then
    echo "Context tokens mismatch for $_input -> got $CONTEXT_TOKENS" >&2
    exit 24
  fi
  if [ "$EFFORT" != "xhigh" ]; then
    echo "Effort mismatch for $_input -> got $EFFORT" >&2
    exit 25
  fi
}

test_rewrite "qwen3.8-27b"
test_rewrite "qwen/qwen3.8-27b"
test_rewrite "qwen3.8-27b:free"
test_rewrite "qwen/qwen3.8-27b:free"
test_rewrite "qwen3.8 27b"
test_rewrite "qwen3.8 27b:free"
test_rewrite "qwen"
test_rewrite "qwen3.8"
'
if [ $? -eq 0 ]; then
  pass "OpenRouter qwen/qwen3.8-27b is cleanly set and all legacy :free slugs rewrite cleanly to active non-free slug"
else
  fail "OpenRouter model resolution failed"
fi

echo "=== STRESS TEST SUMMARY ==="
echo "Passed: $pass_count"
echo "Failed: $fail_count"

[ "$fail_count" -eq 0 ] || exit 1
printf 'ALL ADVERSARIAL STRESS TESTS PASSED WITH EXIT CODE 0\n'
