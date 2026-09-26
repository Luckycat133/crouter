#!/bin/sh
# Unified gateway owns its credential-bearing route file and startup temps until
# launch_claude takes over, including interrupted checks and failed startup.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REAL_NODE=$(command -v node 2>/dev/null || true)
[ -n "$REAL_NODE" ] || { printf 'skip  node not available\n'; exit 0; }

TEST_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-unified-cleanup)
GATEWAY_PID_FILE="$TEST_DIR/gateway.pid"
cleanup() {
  if [ -s "$GATEWAY_PID_FILE" ]; then
    kill "$(cat "$GATEWAY_PID_FILE")" 2>/dev/null || true
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT INT TERM

FAKE_ROOT="$TEST_DIR/repo"
FAKE_BIN="$TEST_DIR/bin"
TASK_TMP="$TEST_DIR/tmp"
READY_FILE="$TEST_DIR/ready"
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/lib" "$FAKE_ROOT/providers" "$FAKE_BIN" "$TASK_TMP"
cp "$ROOT_DIR/bin/crouter" "$FAKE_ROOT/bin/"
cp "$ROOT_DIR/lib/"*.sh "$ROOT_DIR/lib/"*.js "$FAKE_ROOT/lib/"
printf 'test\n' > "$FAKE_ROOT/VERSION"
cat > "$FAKE_ROOT/providers/demo.sh" <<'EOF'
PROVIDER_NAME="demo"
BASE_URL="https://example.invalid/anthropic"
MODEL="demo-model"
AUTH_MODE="static"
AUTH_REFERENCE="test-secret"
EOF

cat > "$FAKE_BIN/node-wrapper" <<'EOF'
#!/bin/sh
case "${TEST_STAGE:-}:$1:${2:-}" in
  inspect-signal:*/route-build.js:inspect)
    : > "$READY_FILE"
    sleep 1
    ;;
  gateway-signal:*/gateway:*)
    printf '%s\n' "$$" > "$GATEWAY_PID_FILE"
    : > "$READY_FILE"
    exec "$REAL_NODE" -e 'setInterval(() => {}, 1000)'
    ;;
  asset-render-signal:*/gateway:*)
    printf '%s\n' "$$" > "$GATEWAY_PID_FILE"
    exec "$REAL_NODE" -e 'process.stdout.write("CROUTER_GATEWAY_LISTENING_PORT=12345\\n"); setInterval(() => {}, 1000)'
    ;;
  asset-render-signal:*/provider-assets.js:render)
    : > "$READY_FILE"
    sleep 1
    exec "$REAL_NODE" "$@"
    ;;
  combine-failure:*/route-build.js:combine)
    exit 17
    ;;
  asset-failure:*/gateway:*)
    printf '%s\n' "$$" > "$GATEWAY_PID_FILE"
    exec "$REAL_NODE" -e 'process.stdout.write("CROUTER_GATEWAY_LISTENING_PORT=12345\\n"); setInterval(() => {}, 1000)'
    ;;
  asset-failure:*/provider-assets.js:render)
    exit 17
    ;;
esac
exec "$REAL_NODE" "$@"
EOF
chmod +x "$FAKE_BIN/node-wrapper"

assert_no_temp() {
  if find "$TASK_TMP" -type f \( -name 'call-routes*' -o -name 'call-gw*' -o -name 'crouter-mcp*' \) | grep -q .; then
    printf 'FAIL  unified route, gateway, or MCP temp survived %s\n' "$1" >&2
    find "$TASK_TMP" -type f >&2
    exit 1
  fi
}

wait_ready() {
  _i=0
  while [ ! -e "$READY_FILE" ] && [ "$_i" -lt 50 ]; do
    sleep 0.1
    _i=$((_i + 1))
  done
  [ -e "$READY_FILE" ] || {
    printf 'FAIL  %s did not reach the intended interruption point\n' "$1" >&2
    exit 1
  }
}

run_interrupted() {
  _stage=$1
  shift
  rm -f "$READY_FILE" "$GATEWAY_PID_FILE"
  _assets=0
  [ "$_stage" != asset-render-signal ] || _assets=1
  TEST_STAGE="$_stage" READY_FILE="$READY_FILE" GATEWAY_PID_FILE="$GATEWAY_PID_FILE" \
    REAL_NODE="$REAL_NODE" TMPDIR="$TASK_TMP" NODE_BIN="$FAKE_BIN/node-wrapper" \
    CROUTER_PROVIDER_ASSETS="$_assets" "$FAKE_ROOT/bin/crouter" all "$@" \
    > "$TEST_DIR/$_stage.out" 2> "$TEST_DIR/$_stage.err" &
  _crouter_pid=$!
  wait_ready "$_stage"
  kill -TERM "$_crouter_pid"
  if wait "$_crouter_pid"; then
    printf 'FAIL  interrupted %s returned success\n' "$_stage" >&2
    exit 1
  else
    _rc=$?
  fi
  [ "$_rc" -eq 143 ] || {
    printf 'FAIL  interrupted %s exited %s instead of 143\n' "$_stage" "$_rc" >&2
    exit 1
  }
  assert_no_temp "$_stage"
  if [ -s "$GATEWAY_PID_FILE" ] && kill -0 "$(cat "$GATEWAY_PID_FILE")" 2>/dev/null; then
    printf 'FAIL  interrupted %s left its gateway running\n' "$_stage" >&2
    exit 1
  fi
}

run_interrupted inspect-signal --check
printf 'ok    interrupted all --check removes credential-bearing route temps\n'

run_interrupted gateway-signal
printf 'ok    interrupted gateway startup removes route and output temps\n'

run_interrupted asset-render-signal
printf 'ok    interrupted MCP render removes its partial config and route temps\n'

if TEST_STAGE=combine-failure REAL_NODE="$REAL_NODE" TMPDIR="$TASK_TMP" \
  NODE_BIN="$FAKE_BIN/node-wrapper" "$FAKE_ROOT/bin/crouter" all --check \
  > "$TEST_DIR/combine-failure.out" 2> "$TEST_DIR/combine-failure.err"; then
  printf 'FAIL  failed route combination returned success\n' >&2
  exit 1
fi
grep -q 'failed to combine unified provider routes' "$TEST_DIR/combine-failure.err" || {
  printf 'FAIL  failed route combination lost its diagnostic\n' >&2
  cat "$TEST_DIR/combine-failure.err" >&2
  exit 1
}
assert_no_temp 'route combination failure'
printf 'ok    failed route combination removes both route temps\n'

rm -f "$GATEWAY_PID_FILE"
if TEST_STAGE=asset-failure READY_FILE="$READY_FILE" GATEWAY_PID_FILE="$GATEWAY_PID_FILE" \
  REAL_NODE="$REAL_NODE" TMPDIR="$TASK_TMP" NODE_BIN="$FAKE_BIN/node-wrapper" \
  "$FAKE_ROOT/bin/crouter" all > "$TEST_DIR/asset-failure.out" 2> "$TEST_DIR/asset-failure.err"; then
  printf 'FAIL  failed provider asset render returned success\n' >&2
  exit 1
fi
grep -q "failed to render provider MCP profile 'empty'" "$TEST_DIR/asset-failure.err" || {
  printf 'FAIL  asset-render failure did not reach expected startup path\n' >&2
  cat "$TEST_DIR/asset-failure.err" >&2
  exit 1
}
assert_no_temp 'asset render failure'
if [ -s "$GATEWAY_PID_FILE" ] && kill -0 "$(cat "$GATEWAY_PID_FILE")" 2>/dev/null; then
  printf 'FAIL  asset-render failure left its gateway running\n' >&2
  exit 1
fi
printf 'ok    failed startup reaps its gateway and removes route temps\n'
