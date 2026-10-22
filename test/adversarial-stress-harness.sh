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

# Test the contracts owned by this repository. The optional, gitignored
# Antigravity proxy is installed separately; importing it would make this
# offline suite depend on a personal checkout and may contact its upstream.
TEST_SHELL=${TEST_SHELL:-sh}
export ROOT_DIR

echo "=== STRESS TEST 1: Antigravity Provider Model Contract ==="
"$TEST_SHELL" -eu <<'SH_ANTIGRAV'
. "$ROOT_DIR/lib/provider.sh"
PROVIDERS_DIR="$ROOT_DIR/providers"
load_provider antigravity
[ "$MODEL" = gemini-3.8-flash ]
for model in "$MODEL_OPUS" "$MODEL_SONNET" "$MODEL_HAIKU" "$MODEL_SUBAGENT"; do
  [ "$model" = "$MODEL" ]
done
for alias in gemini-3.8-flash-tiered gemini-3.7-flash gemini-3.7-flash-tiered; do
  case " $MODEL_ALIASES " in
    *" $alias "*) : ;;
    *) printf 'FAIL  missing Antigravity alias: %s\n' "$alias" >&2; exit 1 ;;
  esac
done
[ "$AUTH_MODE" = static ]
[ "$AUTH_REFERENCE" = local-antigravity-proxy ]
SH_ANTIGRAV
pass "Antigravity exposes canonical tier models and explicit aliases"

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

# Exercise the actual gateway and keypool binaries below, not a copied
# candidateModel implementation that could drift from production.
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

grep -q '^CROUTER_GATEWAY_LISTENING_PORT=' "$TMP_DIR/gateway.out" || {
  printf 'FAIL  gateway failed to start\n' >&2; exit 1;
}

# Test mapped model: testprov/gemini-3.8-flash
CODE1=$(curl --max-time 5 -sS -o "$TMP_DIR/res1.json" -w '%{http_code}' -X POST "http://127.0.0.1:$GW_PORT/v1/messages" \
  -H 'authorization: Bearer gw-secret' \
  -H 'content-type: application/json' \
  -d '{"model":"testprov/gemini-3.8-flash","messages":[]}')

# Test unmapped unexpected model: testprov/unknown-random-model -> should gracefully fall back to default-fallback-model
CODE2=$(curl --max-time 5 -sS -o "$TMP_DIR/res2.json" -w '%{http_code}' -X POST "http://127.0.0.1:$GW_PORT/v1/messages" \
  -H 'authorization: Bearer gw-secret' \
  -H 'content-type: application/json' \
  -d '{"model":"testprov/unknown-random-model","messages":[]}')

# Test malformed JSON body -> should return 400 invalid_request
CODE3=$(curl --max-time 5 -sS -o "$TMP_DIR/res3.json" -w '%{http_code}' -X POST "http://127.0.0.1:$GW_PORT/v1/messages" \
  -H 'authorization: Bearer gw-secret' \
  -H 'content-type: application/json' \
  -d '{"model": bad json')

# Test model without prefix -> should return 400 unknown_model
CODE4=$(curl --max-time 5 -sS -o "$TMP_DIR/res4.json" -w '%{http_code}' -X POST "http://127.0.0.1:$GW_PORT/v1/messages" \
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

[ -n "$POOL_PORT" ] || { cat "$TMP_DIR/pool.err" >&2; exit 1; }

KP_CODE1=$(curl --max-time 5 -sS -o "$TMP_DIR/kp_res1.json" -w '%{http_code}' -X POST "http://127.0.0.1:$POOL_PORT/v1/messages" \
  -H 'anthropic-auth-token: local-token' \
  -H 'content-type: application/json' \
  -d '{"model":"gemini-3.8-flash","messages":[]}')

KP_CODE2=$(curl --max-time 5 -sS -o "$TMP_DIR/kp_res2.json" -w '%{http_code}' -X POST "http://127.0.0.1:$POOL_PORT/v1/messages" \
  -H 'anthropic-auth-token: local-token' \
  -H 'content-type: application/json' \
  -d '{"model":"unexpected-edge-case-model","messages":[]}')

KP_CODE3=$(curl --max-time 5 -sS -o "$TMP_DIR/kp_res3.json" -w '%{http_code}' -X POST "http://127.0.0.1:$POOL_PORT/v1/messages" \
  -H 'anthropic-auth-token: local-token' \
  -H 'content-type: application/json' \
  -d '{"model":"__proto__","messages":[]}')

KP_CODE4=$(curl --max-time 5 -sS -o "$TMP_DIR/kp_res4.json" -w '%{http_code}' -X POST "http://127.0.0.1:$POOL_PORT/v1/messages" \
  -H 'anthropic-auth-token: local-token' \
  -H 'content-type: application/json' \
  -d 'invalid body')

if [ "$KP_CODE1" = "200" ] && [ "$KP_CODE2" = "200" ] && [ "$KP_CODE3" = "200" ] && [ "$KP_CODE4" = "400" ]; then
  pass "Live Keypool-proxy translates mapped models, gracefully falls back on unexpected & __proto__ models, and returns 400 on invalid JSON"
else
  fail "Live Keypool-proxy failed: KP_CODE1=$KP_CODE1 KP_CODE2=$KP_CODE2 KP_CODE3=$KP_CODE3 KP_CODE4=$KP_CODE4"
fi

# Verify forwarded bodies and credential binding, not merely HTTP status.
"$NODE_BIN" - "$REQUEST_LOG" <<'NODE_SEEN'
const assert = require('assert');
const fs = require('fs');
const seen = fs.readFileSync(process.argv[2], 'utf8').trim().split('\n').map(JSON.parse);
assert.deepStrictEqual(seen.map(entry => entry.model), [
  'gemini-3.8-flash-tiered', 'default-fallback-model',
  'gemini-3.8-flash-tiered', 'pool-default-fallback', 'pool-default-fallback',
]);
for (const [index, entry] of seen.entries()) {
  assert.strictEqual(entry.path, '/v1/messages');
  assert.strictEqual(entry.headers.authorization, index < 2 ? 'Bearer test-token' : 'Bearer pool-token');
  assert.strictEqual(entry.headers['anthropic-auth-token'], undefined);
}
NODE_SEEN
pass "Actual proxies preserve model mapping, fallback and upstream credential binding"

# Prototype-property names must hit the actual gateway fallback path too.
for model in __proto__ constructor toString valueOf hasOwnProperty; do
  code=$(curl --max-time 5 -sS -o "$TMP_DIR/prototype.json" -w '%{http_code}' \
    "http://127.0.0.1:$GW_PORT/v1/messages" \
    -H 'authorization: Bearer gw-secret' -H 'content-type: application/json' \
    -d "{\"model\":\"testprov/$model\",\"messages\":[]}")
  [ "$code" = 200 ] || { fail "Gateway prototype model $model returned $code"; continue; }
  "$NODE_BIN" - "$TMP_DIR/prototype.json" <<'NODE_PROTO'
const assert = require('assert');
const fs = require('fs');
assert.strictEqual(JSON.parse(fs.readFileSync(process.argv[2], 'utf8')).receivedModel, 'default-fallback-model');
NODE_PROTO
done
pass "Gateway prototype-property models use the candidate fallback"

echo "=== STRESS TEST 3: Moonshot Context Override Logic ==="

"$ROOT_DIR/bin/crouter" provider show moonshot > "$TMP_DIR/moonshot-show.out"
if grep -q 'context:     262144 tokens' "$TMP_DIR/moonshot-show.out"; then
  pass "Moonshot default model k3-256k retains 262144 context tokens"
else
  fail "Moonshot default context did not show 262144 tokens"
fi

# Adversarial context override verification in subshell
"$TEST_SHELL" -c '
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

"$TEST_SHELL" -c '
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
