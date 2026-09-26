#!/bin/sh
# Retry budgets belong to one client request. HTTP 402 quota exhaustion and
# HTTP 403 entitlement rejection must fall through to the next candidate.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node 2>/dev/null || true)}
[ -n "$NODE_BIN" ] || { printf 'skip  node not available\n'; exit 0; }

TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-keypool-retry)
UPSTREAM_PID=
POOL_PID=
cleanup() {
  [ -n "$POOL_PID" ] && kill "$POOL_PID" 2>/dev/null || true
  [ -n "$UPSTREAM_PID" ] && kill "$UPSTREAM_PID" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

cat > "$TMP_DIR/upstream.js" <<'NODE'
const fs = require('fs');
const http = require('http');
const seen = [];
const server = http.createServer((req, res) => {
  const auth = req.headers.authorization || '';
  const apiKey = req.headers['x-api-key'] || '';
  seen.push(auth ? 'plan' : apiKey ? 'api' : 'none');
  fs.writeFileSync(process.env.SEEN_FILE, seen.join(','));
  req.resume();
  req.on('end', () => {
    if (auth === 'Bearer plan-token' && !apiKey) {
      const status = seen.filter((entry) => entry === 'plan').length === 1 ? 402 : 403;
      res.writeHead(status, { 'content-type': 'application/json' });
      res.end('{"error":"plan unavailable"}');
      return;
    }
    if (apiKey === 'api-token' && !auth) {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end('{"ok":true}');
      return;
    }
    res.writeHead(400).end();
  });
});
server.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(process.env.PORT_FILE, String(server.address().port));
});
NODE

SEEN_FILE="$TMP_DIR/seen" PORT_FILE="$TMP_DIR/upstream.port" \
  "$NODE_BIN" "$TMP_DIR/upstream.js" >/dev/null 2>&1 &
UPSTREAM_PID=$!

_i=0
while [ "$_i" -lt 50 ] && [ ! -s "$TMP_DIR/upstream.port" ]; do
  sleep 0.05
  _i=$((_i + 1))
done
[ -s "$TMP_DIR/upstream.port" ] || { printf 'FAIL  mock upstream did not start\n' >&2; exit 1; }
_upstream_port=$(cat "$TMP_DIR/upstream.port")

_candidates=$(printf '[{"url":"http://127.0.0.1:%s","type":"bearer","token":"plan-token","label":"plan"},{"url":"http://127.0.0.1:%s","type":"x-api-key","token":"api-token","label":"api"}]' "$_upstream_port" "$_upstream_port")
KEYPOOL_CANDIDATES="$_candidates" KEYPOOL_PORT=0 KEYPOOL_MAX_RETRY=2 \
  CROUTER_CANDIDATE_COOLDOWN_MS=2000 \
  KEYPOOL_CLIENT_TOKEN="local-secret" \
  "$NODE_BIN" "$ROOT_DIR/bin/keypool-proxy" > "$TMP_DIR/pool.out" 2> "$TMP_DIR/pool.err" &
POOL_PID=$!

_i=0
_pool_port=
while [ "$_i" -lt 50 ]; do
  _pool_port=$(sed -n 's/^KEYPOOL_LISTENING_PORT=//p' "$TMP_DIR/pool.out" | head -n 1)
  [ -n "$_pool_port" ] && break
  sleep 0.05
  _i=$((_i + 1))
done
[ -n "$_pool_port" ] || { printf 'FAIL  keypool did not start\n' >&2; exit 1; }

_unauthorized=$(curl -sS -o "$TMP_DIR/unauthorized.body" -w '%{http_code}' \
  -X POST "http://127.0.0.1:$_pool_port/v1/messages" \
  -H 'content-type: application/json' -d '{"model":"logical-model","messages":[]}')
[ "$_unauthorized" = 401 ] || {
  printf 'FAIL  keypool accepted an unauthenticated local request (HTTP %s)\n' "$_unauthorized" >&2
  exit 1
}

_first=$(curl -sS -o "$TMP_DIR/first.body" -w '%{http_code}' \
  -X POST "http://127.0.0.1:$_pool_port/v1/messages" \
  -H 'authorization: Bearer local-secret' \
  -H 'content-type: application/json' -d '{"model":"logical-model","messages":[]}')
_second=$(curl -sS -o "$TMP_DIR/second.body" -w '%{http_code}' \
  -X POST "http://127.0.0.1:$_pool_port/v1/messages" \
  -H 'authorization: Bearer local-secret' \
  -H 'content-type: application/json' -d '{"model":"logical-model","messages":[]}')
# Leave enough margin for loaded CI workers between the first two requests;
# the exact 200 ms boundary is checked below with a controlled clock.
sleep 2.2
_third=$(curl -sS -o "$TMP_DIR/third.body" -w '%{http_code}' \
  -X POST "http://127.0.0.1:$_pool_port/v1/messages" \
  -H 'authorization: Bearer local-secret' \
  -H 'content-type: application/json' -d '{"model":"logical-model","messages":[]}')
_seen=$(cat "$TMP_DIR/seen" 2>/dev/null || true)

if [ "$_first" != 200 ] || [ "$_second" != 200 ] || [ "$_third" != 200 ]; then
  printf 'FAIL  candidate cooldown returned HTTP %s, %s, %s\n' "$_first" "$_second" "$_third" >&2
  exit 1
fi
[ "$_seen" = 'plan,api,api,plan,api' ] || {
  printf 'FAIL  expected plan,api,api,plan,api; saw %s\n' "$_seen" >&2
  exit 1
}

ROOT_DIR="$ROOT_DIR" "$NODE_BIN" - <<'NODE'
const assert = require('assert');
const {createCandidateCooldown} = require(process.env.ROOT_DIR + '/lib/proxy-common.js');
let now = 10_000;
Date.now = () => now;
const cooldown = createCandidateCooldown(2, '200');
cooldown.fail(0);
now += 199;
assert.deepStrictEqual(cooldown.order(), [1, 0]);
now += 1;
assert.deepStrictEqual(cooldown.order(), [0, 1]);
cooldown.fail(0, {'retry-after': '1'});
now += 500;
assert.deepStrictEqual(cooldown.order(), [1, 0]);
now += 501;
assert.deepStrictEqual(cooldown.order(), [0, 1]);
NODE

printf 'ok    quota failures cool down a plan, honor Retry-After, and keep API fallback live\n'
