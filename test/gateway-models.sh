#!/bin/sh
# Loopback regression: GET /v1/models must carry per-model context_length and
# max_output_tokens (plus max_input_tokens for Anthropic compatibility), and
# models without known limits must not fabricate them. No credentials, no
# upstream network, no real Claude.
set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node 2>/dev/null || true)}
[ -n "$NODE_BIN" ] || { printf 'skip  node not available\n'; exit 0; }
command -v curl >/dev/null 2>&1 || { printf 'skip  curl not available\n'; exit 0; }
command -v python3 >/dev/null 2>&1 || { printf 'skip  python3 not available; cannot pick a free gateway port\n'; exit 0; }

TEST_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-gateway-models)
trap 'rm -rf "$TEST_DIR"' EXIT INT TERM
GATEWAY_PID=

cleanup() {
  [ -z "$GATEWAY_PID" ] || kill "$GATEWAY_PID" 2>/dev/null || true
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT INT TERM

# A live account's tighter bound must constrain a declared provider ceiling;
# neither a generic directory nor an override may raise the other limit.
"$NODE_BIN" - "$ROOT_DIR" <<'EOF'
const assert = require('node:assert/strict');
const {modelMetadataMap} = require(process.argv[2] + '/lib/route-build.js');
const limits = {context: 1000000, output: 131072, primary: 'model', overrides: new Map([['model', 1000000]])};
assert.deepEqual(modelMetadataMap(['model'], limits, new Map([['model', {context_length: 262144, max_output_tokens: 8192}]])),
  {model: {context_length: 262144, max_output_tokens: 8192}});
assert.deepEqual(modelMetadataMap(['model'], limits, new Map([['model', {context_length: 2000000, max_output_tokens: 262144}]])),
  {model: {context_length: 1000000, max_output_tokens: 131072}});
EOF
[ "$?" -eq 0 ] || exit 1

# Build two unified routes exactly as cmd_all does: per-provider candidates
# combined into one routes file. Declared limits flow through CR_* env.
CR_PREFIX=demo CR_MODELS="big-model small-model" \
  CR_API_URL=http://127.0.0.1:1 CR_API_TYPE=x-api-key CR_API_KEY=demo-key CR_AUTH_MODE=static \
  CR_CONTEXT_TOKENS=1000000 CR_MAX_OUTPUT_TOKENS=131072 \
  CR_MODEL_CONTEXT_OVERRIDES="big-model=1000000 small-model=262144" \
  "$NODE_BIN" "$ROOT_DIR/lib/route-build.js" candidates > "$TEST_DIR/demo.route"
CR_PREFIX=local CR_MODELS="unknown-model" \
  CR_API_URL=http://127.0.0.1:1 CR_AUTH_MODE=none CR_NONE_TOKEN= \
  "$NODE_BIN" "$ROOT_DIR/lib/route-build.js" candidates > "$TEST_DIR/local.route"
cat "$TEST_DIR/demo.route" "$TEST_DIR/local.route" > "$TEST_DIR/build.txt"
"$NODE_BIN" "$ROOT_DIR/lib/route-build.js" combine "$TEST_DIR/build.txt" "$TEST_DIR/routes.json"

# The route compiler must attach per-model metadata, not just ids.
TEST_DIR="$TEST_DIR" "$NODE_BIN" - <<'EOF'
const assert = require('node:assert/strict');
const fs = require('fs');
const routes = JSON.parse(fs.readFileSync(process.env.TEST_DIR + '/routes.json', 'utf8'));
const demo = routes.find((r) => r.prefix === 'demo');
const local = routes.find((r) => r.prefix === 'local');
assert.ok(demo && local);
assert.equal(demo.modelMetadata['big-model'].context_length, 1000000);
assert.equal(demo.modelMetadata['big-model'].max_output_tokens, 131072);
assert.equal(demo.modelMetadata['small-model'].context_length, 262144);
assert.equal(Object.hasOwn(demo.modelMetadata['small-model'], 'max_output_tokens'), false);
assert.equal(Object.keys(local.modelMetadata || {}).length, 0);
EOF
if [ $? -ne 0 ]; then
  printf 'FAIL  route-build did not attach per-model metadata\n'
  cat "$TEST_DIR/routes.json" >&2
  exit 1
fi

GATEWAY_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()')
CROUTER_ROUTES_FILE="$TEST_DIR/routes.json" CROUTER_GATEWAY_PORT="$GATEWAY_PORT" \
  CROUTER_GATEWAY_TOKEN="gateway-secret" \
  "$NODE_BIN" "$ROOT_DIR/bin/gateway" >"$TEST_DIR/gateway.out" 2>&1 &
GATEWAY_PID=$!
_i=0
while [ "$_i" -lt 100 ]; do
  grep -q '^CROUTER_GATEWAY_LISTENING_PORT=' "$TEST_DIR/gateway.out" 2>/dev/null && break
  kill -0 "$GATEWAY_PID" 2>/dev/null || break
  sleep 0.1
  _i=$((_i + 1))
done
grep -q '^CROUTER_GATEWAY_LISTENING_PORT=' "$TEST_DIR/gateway.out" 2>/dev/null || {
  printf 'FAIL  gateway did not start\n'; cat "$TEST_DIR/gateway.out" >&2; exit 1
}
PORT=$(grep -m1 '^CROUTER_GATEWAY_LISTENING_PORT=' "$TEST_DIR/gateway.out" | cut -d= -f2)

BODY=$(curl -sS "http://127.0.0.1:$PORT/v1/models") || {
  printf 'FAIL  GET /v1/models failed\n'; exit 1
}

"$NODE_BIN" - "$BODY" <<'EOF'
const assert = require('node:assert/strict');
const body = JSON.parse(process.argv[2]);
assert.equal(body.object, 'list');
assert.equal(body.has_more, false);
const by = Object.fromEntries(body.data.map((m) => [m.id, m]));
assert.ok(by['demo/big-model'], 'demo/big-model advertised');
assert.ok(by['demo/small-model'], 'demo/small-model advertised');
assert.ok(by['local/unknown-model'], 'local/unknown-model advertised');
assert.equal(by['demo/big-model'].type, 'model');
assert.equal(by['demo/big-model'].object, 'model');
assert.equal(by['demo/big-model'].context_length, 1000000);
assert.equal(by['demo/big-model'].max_output_tokens, 131072);
assert.equal(by['demo/big-model'].max_input_tokens, 1000000);
assert.equal(by['demo/small-model'].context_length, 262144);
assert.equal(Object.hasOwn(by['demo/small-model'], 'max_output_tokens'), false, 'small model must not inherit big model output');
assert.equal(Object.hasOwn(by['local/unknown-model'], 'context_length'), false, 'unknown model must not get a guessed context');
assert.equal(Object.hasOwn(by['local/unknown-model'], 'max_output_tokens'), false, 'unknown model must not get a guessed output');
assert.equal(Object.hasOwn(by['local/unknown-model'], 'max_input_tokens'), false);
EOF
if [ $? -ne 0 ]; then
  printf 'FAIL  GET /v1/models rows lack per-model context/output metadata\n%s\n' "$BODY" >&2
  exit 1
fi
printf 'ok    GET /v1/models carries distinct per-model context/output limits and omits unknowns\n'
