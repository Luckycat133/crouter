#!/bin/sh
# POST_STOP is an exactly-once hook, including normal Claude exits.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-lifecycle)
SIGNAL_PID_FILE="$TMP_DIR/signal-child.pid"
cleanup() {
  if [ -s "$SIGNAL_PID_FILE" ]; then
    _signal_child_pid=$(cat "$SIGNAL_PID_FILE")
    kill "$_signal_child_pid" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

MOCK_CLAUDE="$TMP_DIR/claude"
STOP_FILE="$TMP_DIR/stops"
cat > "$MOCK_CLAUDE" <<'MOCK'
#!/bin/sh
exit 0
MOCK
chmod +x "$MOCK_CLAUDE"

set +e
(
  info() { :; }
  die() { printf '%s\n' "$*" >&2; exit 1; }
  CLAUDE_BIN=$MOCK_CLAUDE
  MODEL_OPUS=demo
  MODEL_SONNET=demo
  MODEL_HAIKU=demo
  MODEL_SUBAGENT=demo
  CONTEXT_TOKENS=
  EFFORT=
  EXTRA_ENV=
  AUTH_MODE=none
  AUTH_TOKEN=
  KEYPOOL_URL=
  KEYPOOL_PID=
  BASE_URL=https://example.invalid
  POST_STOP="printf x >> '$STOP_FILE'"
  PROVIDER_MCP_CONFIG=
  PROVIDER_PLUGIN_DIRS=
  PASSTHROUGH_ENV=
  NATIVE_BACKEND=
  . "$ROOT_DIR/lib/launch.sh"
  launch_claude demo 0
)
_launch_rc=$?
set -e

[ "$_launch_rc" -eq 0 ] || {
  printf 'FAIL  launcher changed Claude exit 0 to %s\n' "$_launch_rc" >&2
  exit 1
}

_count=$(wc -c < "$STOP_FILE" | tr -d ' ')
[ "$_count" -eq 1 ] || {
  printf 'FAIL  POST_STOP ran %s times (expected exactly once)\n' "$_count" >&2
  exit 1
}
printf 'ok    POST_STOP runs exactly once\n'

# A signal delivered by the Claude child immediately after it starts must not
# land before the launcher's final cleanup trap is active.
SIGNAL_CLAUDE="$TMP_DIR/signal-claude"
cat > "$SIGNAL_CLAUDE" <<'MOCK'
#!/bin/sh
printf '%s\n' "$$" > "$CROUTER_SIGNAL_PID_FILE"
kill -TERM "$PPID"
while :; do sleep 1; done
MOCK
chmod +x "$SIGNAL_CLAUDE"

set +e
(
  info() { :; }
  die() { printf '%s\n' "$*" >&2; exit 1; }
  CLAUDE_BIN=$SIGNAL_CLAUDE
  MODEL_OPUS=demo
  MODEL_SONNET=demo
  MODEL_HAIKU=demo
  MODEL_SUBAGENT=demo
  CONTEXT_TOKENS=
  EFFORT=
  EXTRA_ENV="CROUTER_SIGNAL_PID_FILE=$SIGNAL_PID_FILE"
  AUTH_MODE=none
  AUTH_TOKEN=
  KEYPOOL_URL=
  KEYPOOL_PID=
  BASE_URL=https://example.invalid
  POST_STOP=
  PROVIDER_MCP_CONFIG=
  PROVIDER_PLUGIN_DIRS=
  PASSTHROUGH_ENV=
  NATIVE_BACKEND=
  . "$ROOT_DIR/lib/launch.sh"
  launch_claude demo 0
)
_signal_launch_rc=$?
set -e

[ "$_signal_launch_rc" -eq 143 ] || {
  printf 'FAIL  TERM launcher exit status was %s, expected 143\n' "$_signal_launch_rc" >&2
  exit 1
}
[ -s "$SIGNAL_PID_FILE" ] || {
  printf 'FAIL  signal-race Claude child did not start\n' >&2
  exit 1
}
_signal_child_pid=$(cat "$SIGNAL_PID_FILE")
_i=0
while [ "$_i" -lt 30 ] && kill -0 "$_signal_child_pid" 2>/dev/null; do
  sleep 0.05
  _i=$((_i + 1))
done
if kill -0 "$_signal_child_pid" 2>/dev/null; then
  printf 'FAIL  Claude child survived a TERM during launcher handoff (launcher rc=%s)\n' "$_signal_launch_rc" >&2
  exit 1
fi
printf 'ok    launch cleanup trap covers immediate TERM handoff\n'
