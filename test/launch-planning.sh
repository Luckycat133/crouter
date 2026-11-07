#!/bin/sh
# Real dispatcher/planner, stub credential/lifecycle boundaries. No live keys.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
REPO="$TMP_DIR/repo with spaces"
mkdir -p "$REPO/bin" "$REPO/lib" "$REPO/providers" "$TMP_DIR/home"
cp "$ROOT_DIR/bin/crouter" "$ROOT_DIR/bin/crouter-models" "$REPO/bin/"
cp "$ROOT_DIR/lib/provider.sh" "$ROOT_DIR/lib/catalog.sh" "$ROOT_DIR/lib/commands.sh" "$ROOT_DIR/lib/unified.sh" "$REPO/lib/"
cp "$ROOT_DIR/lib/catalog.js" "$ROOT_DIR/lib/model-state.js" "$REPO/lib/"
printf 'test\n' > "$REPO/VERSION"
: > "$REPO/lib/key-mgmt.sh"
cat > "$REPO/lib/auth.sh" <<'AUTH'
is_dual_source() { return 1; }
resolve_auth() { printf 'auth\n' >> "$SPY"; AUTH_TOKEN=test-only; }
check_auth() { return 0; }
AUTH
cat > "$REPO/lib/assets.sh" <<'ASSETS'
prepare_provider_assets() { printf 'assets\n' >> "$SPY"; }
cleanup_provider_assets() { :; }
ASSETS
cat > "$REPO/lib/launch.sh" <<'LAUNCH'
launch_claude() {
  printf 'launch|%s|%s|%s|%s\n' "$1" "$MODEL_OPUS" "$MODEL_HAIKU" "$CONTEXT_TOKENS" >> "$SPY"
  shift 2
  printf 'arg:%s\n' "$@" >> "$SPY"
}
LAUNCH
cat > "$REPO/providers/demo.sh" <<'PROVIDER'
PROVIDER_NAME=demo
BASE_URL=https://unused.invalid
MODEL=large
MODEL_OPUS=large
MODEL_HAIKU=fast
CONTEXT_TOKENS=1000000
AUTO_COMPACT_TOKENS=700000
MODEL_CONTEXT_OVERRIDES='small=4096'
MODEL_ALIASES='small unknown'
MODELS_DISCOVERY=static
AUTH_MODE=none
PRE_START='printf "hook:%s\n" "$_main_model" >> "$SPY"'
POST_STOP=
PROVIDER
cat > "$TMP_DIR/claude" <<'CLAUDE'
#!/bin/sh
printf 'native\n'
CLAUDE
chmod +x "$TMP_DIR/claude" "$REPO/bin/crouter"
export HOME="$TMP_DIR/home" XDG_STATE_HOME="$TMP_DIR/state" SPY="$TMP_DIR/spy" CLAUDE_BIN="$TMP_DIR/claude"
export NODE_BIN
NODE_BIN=$(command -v node)
run() { "${TEST_SHELL:-sh}" "$REPO/bin/crouter" "$@"; }
fail() { printf 'FAIL planning: %s\n' "$*" >&2; exit 1; }
run demo --model small --apply-only >/dev/null
[ ! -e "$SPY" ] || fail 'apply-only executed a hook/auth/asset/launch'
[ "$(cat "$XDG_STATE_HOME/crouter/last-model-demo")" = small ] || fail 'model not saved'
[ "$(cat "$XDG_STATE_HOME/crouter/demo-context")" = 4096 ] || fail 'model override not saved'
run demo --model unknown --apply-only >/dev/null
[ ! -e "$XDG_STATE_HOME/crouter/demo-context" ] || fail 'old context survived unknown'
[ ! -e "$SPY" ] || fail 'unknown save executed side effects'
run demo small -p 'hello --browse with spaces' >/dev/null
grep -qx 'hook:small' "$SPY" || fail 'hook did not see final model'
grep -qx 'launch|small|small|small|4096' "$SPY" || fail 'tier/context resolution wrong'
grep -qx 'arg:hello --browse with spaces' "$SPY" || fail 'Claude argument bytes changed'
[ "$(head -n 1 "$SPY")" = hook:small ] || fail 'unexpected ordering'
rm "$SPY"
run demo --model large --help >/dev/null
! grep -Eq '^(hook|auth|assets)' "$SPY" || fail 'help executed startup side effects'
rm "$SPY"
run demo --model large >/dev/null
grep -qx 'launch|large|large|fast|1000000' "$SPY" || fail 'default tier specialization overwritten'
rm "$SPY"
# A valid model selection may be saved before Claude has been installed.
CLAUDE_BIN="$TMP_DIR/no-claude" run demo small --apply-only >/dev/null
[ ! -e "$SPY" ] || fail 'save with missing Claude executed startup'
# Pointing the launcher back to itself must fail before hooks.
if CLAUDE_BIN="$REPO/bin/crouter" run demo small >"$TMP_DIR/self.out" 2>&1; then fail 'recursive binary accepted'; fi
[ ! -e "$SPY" ] || fail 'recursion check ran hooks'
# Actual remembered selection is scoped to this provider; unknown stale
# context from another model must not override an explicit alternate model.
run demo large --apply-only >/dev/null
run demo --model small >/dev/null
grep -qx 'launch|small|small|small|4096' "$SPY" || fail 'old window leaked into explicit selection'
printf 'ok launch planning: save-only, side-effect order, model-bound limits, tiers, argv, help, recursion\n'
