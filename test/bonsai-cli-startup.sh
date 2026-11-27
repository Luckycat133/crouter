#!/bin/sh
# Real dispatcher and env-i launcher, fake native endpoint and adapter process.
# This covers PRE_START after build_launch_plan has sealed MODEL_SERVICE.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
cleanup() {
  if [ -s "$TMP_DIR/adapter-pid" ]; then
    kill "$(cat "$TMP_DIR/adapter-pid")" 2>/dev/null || true
  fi
  if [ -s "$TMP_DIR/native-pid" ]; then
    kill "$(cat "$TMP_DIR/native-pid")" 2>/dev/null || true
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM
REPO="$TMP_DIR/repo with spaces"
mkdir -p "$REPO/bin" "$REPO/lib" "$REPO/providers" "$TMP_DIR/home" "$TMP_DIR/bin" "$TMP_DIR/demo/models/Ternary-Bonsai-2.5-27B-mlx-2bit"
mkdir -p "$TMP_DIR/demo/scripts"
printf '#!/bin/sh\nexit 99\n' > "$TMP_DIR/demo/scripts/start_mlx_server.sh"
chmod +x "$TMP_DIR/demo/scripts/start_mlx_server.sh"
cp "$ROOT_DIR/bin/crouter" "$REPO/bin/"
cp "$ROOT_DIR/VERSION" "$REPO/"
cp "$ROOT_DIR"/lib/*.sh "$ROOT_DIR"/lib/*.js "$ROOT_DIR"/lib/*.mjs "$REPO/lib/"
cp "$ROOT_DIR/providers/bonsai.sh" "$REPO/providers/"
cat > "$REPO/lib/auth.sh" <<'AUTH'
is_dual_source() { return 1; }
resolve_auth() { AUTH_TOKEN=; }
AUTH
: > "$REPO/lib/key-mgmt.sh"
cat > "$REPO/lib/assets.sh" <<'ASSETS'
prepare_provider_assets() { :; }
cleanup_provider_assets() { :; }
ASSETS
cat > "$TMP_DIR/bin/curl" <<'CURL'
#!/bin/sh
for arg do case $arg in http://*) url=$arg ;; esac; done
case $url in
  http://127.0.0.1:8081/health)
    [ "$FIXTURE_NATIVE_STATE" != absent ] || [ -s "$FIXTURE_DIR/native-pid" ] || exit 1
    printf '{"status":"healthy","loaded_model":"%s"}' "$BONSAI_DEMO_DIR/models/Ternary-Bonsai-2.5-27B-mlx-2bit" ;;
  http://127.0.0.1:8081/v1/models)
    printf '{"data":[{"id":"%s"}]}' "$BONSAI_DEMO_DIR/models/Ternary-Bonsai-2.5-27B-mlx-2bit" ;;
  http://127.0.0.1:11439/health)
    [ -s "$FIXTURE_DIR/adapter-pid" ] || exit 1
    printf '{"service":"crouter-mlx-anthropic-adapter","model":"ternary-bonsai-2.5-27b","upstream":"127.0.0.1:8081"}' ;;
  *) exit 99 ;;
esac
CURL
cat > "$TMP_DIR/bin/lsof" <<'LSOF'
#!/bin/sh
# Only the native fixture service already exists.
case " $* " in
  *' -iTCP:11438 '*) exit 0 ;;
  *' -iTCP:8081 '*) [ "$FIXTURE_NATIVE_STATE" != absent ] ;;
  *) exit 1 ;;
esac
LSOF
cat > "$TMP_DIR/bin/nohup" <<'NOHUP'
#!/bin/sh
if [ "$1" != node ]; then
  [ "$1" = "$BONSAI_DEMO_DIR/scripts/start_mlx_server.sh" ] || exit 91
  [ "$#" = 1 ] || exit 95
  [ "$BONSAI_FAMILY:$BONSAI_MODEL:$PORT" = bonsai25:27B:8081 ] || exit 96
  printf '%s\n' "$$" > "$FIXTURE_DIR/native-pid"
  exec sleep 30
fi
[ "$MLX_PROXY_PORT" = 11439 ] || exit 94
[ "$MLX_INHERIT_DEFAULTS" = 1 ] || exit 92
[ "$MLX_MODEL" = ternary-bonsai-2.5-27b ] || exit 93
printf '%s\n' "$$" > "$FIXTURE_DIR/adapter-pid"
exec sleep 30
NOHUP
cat > "$TMP_DIR/claude" <<'CLAUDE'
#!/bin/sh
printf 'model=%s\n' "$ANTHROPIC_MODEL"
printf 'base=%s\n' "$ANTHROPIC_BASE_URL"
printf 'context=%s\n' "$CLAUDE_CODE_MAX_CONTEXT_TOKENS"
printf 'tiers=%s,%s,%s,%s\n' "$ANTHROPIC_DEFAULT_OPUS_MODEL" "$ANTHROPIC_DEFAULT_SONNET_MODEL" "$ANTHROPIC_DEFAULT_HAIKU_MODEL" "$CLAUDE_CODE_SUBAGENT_MODEL"
printf 'private=%s\n' "${FIXTURE_DIR-clean}"
CLAUDE
chmod +x "$TMP_DIR/bin/"* "$TMP_DIR/claude"
# Persisting 2.5 makes it the provider's primary MODEL on the next process.
# Its client context must survive while the legacy primary's output cap must not.
plan_run() {
  HOME="$TMP_DIR/home" XDG_STATE_HOME="$TMP_DIR/state" CLAUDE_BIN="$TMP_DIR/claude" \
    BONSAI_DEMO_DIR="$TMP_DIR/demo" PATH="$TMP_DIR/bin:$PATH" \
    "${TEST_SHELL:-sh}" "$REPO/bin/crouter" bonsai "$@"
}
plan_run --plan > "$TMP_DIR/legacy-plan.json"
plan_run --model ternary-bonsai-2.5-27b --plan > "$TMP_DIR/new-plan.json"
plan_run --model ternary-bonsai-2.5-27b --apply-only > "$TMP_DIR/saved"
plan_run --plan > "$TMP_DIR/saved-plan.json"
node - "$TMP_DIR/legacy-plan.json" "$TMP_DIR/new-plan.json" "$TMP_DIR/saved-plan.json" <<'NODE'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const [legacy, fresh, saved] = process.argv.slice(2).map(file => JSON.parse(fs.readFileSync(file, 'utf8')));
assert.equal(legacy.model, 'ternary-bonsai-2-27b');
assert.equal(legacy.maxOutputTokens, 262144);
for (const plan of [fresh, saved]) {
  assert.equal(plan.model, 'ternary-bonsai-2.5-27b');
  assert.equal(plan.contextTokens, 262144);
  assert.equal(plan.maxOutputTokens, null, 'Bonsai 2.5 inherited a legacy output cap after saving');
  assert.equal(plan.source.origin, 'http://127.0.0.1:11439');
}
NODE
[ "$(cat "$TMP_DIR/state/crouter/last-model-bonsai")" = ternary-bonsai-2.5-27b ]
[ "$(cat "$TMP_DIR/state/crouter/bonsai-context")" = 262144 ]
[ ! -e "$TMP_DIR/adapter-pid" ]
[ ! -e "$TMP_DIR/native-pid" ]
HOME="$TMP_DIR/home" XDG_STATE_HOME="$TMP_DIR/state" USER=crouter-fixture \
  FIXTURE_DIR="$TMP_DIR" FIXTURE_NATIVE_STATE="${FIXTURE_NATIVE_STATE:-compatible}" BONSAI_DEMO_DIR="$TMP_DIR/demo" CLAUDE_BIN="$TMP_DIR/claude" \
  PATH="$TMP_DIR/bin:$PATH" "${TEST_SHELL:-sh}" "$REPO/bin/crouter" \
  bonsai --model ternary-bonsai-2.5-27b --once > "$TMP_DIR/output" 2> "$TMP_DIR/error" || {
    cat "$TMP_DIR/error" >&2
    exit 1
  }
grep -Fxq 'model=ternary-bonsai-2.5-27b' "$TMP_DIR/output"
grep -Fxq 'base=http://127.0.0.1:11439' "$TMP_DIR/output"
grep -Fxq 'context=262144' "$TMP_DIR/output"
grep -Fxq 'tiers=ternary-bonsai-2.5-27b,ternary-bonsai-2.5-27b,ternary-bonsai-2.5-27b,ternary-bonsai-2.5-27b' "$TMP_DIR/output"
grep -Fxq 'private=clean' "$TMP_DIR/output"
[ -s "$TMP_DIR/adapter-pid" ]
! kill -0 "$(cat "$TMP_DIR/adapter-pid")" 2>/dev/null
if [ "${FIXTURE_NATIVE_STATE:-compatible}" = absent ]; then
  [ -s "$TMP_DIR/native-pid" ]
  ! kill -0 "$(cat "$TMP_DIR/native-pid")" 2>/dev/null
fi
printf 'ok    real Bonsai CLI starts after readonly planning, isolates env and cleans owned adapter\n'
