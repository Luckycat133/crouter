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
cp "$ROOT_DIR/lib/catalog.js" "$ROOT_DIR/lib/model-state.js" "$ROOT_DIR/lib/account-live-catalog.js" "$REPO/lib/"
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
MAX_OUTPUT_TOKENS=8192
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
(CLAUDE_BIN="$TMP_DIR/no-claude" run demo small --apply-only) >/dev/null
[ ! -e "$SPY" ] || fail 'save with missing Claude executed startup'
# Pointing the launcher back to itself must fail before hooks.
if (CLAUDE_BIN="$REPO/bin/crouter" run demo small) >"$TMP_DIR/self.out" 2>&1; then fail 'recursive binary accepted'; fi
[ ! -e "$SPY" ] || fail 'recursion check ran hooks'
# Actual remembered selection is scoped to this provider; unknown stale
# context from another model must not override an explicit alternate model.
run demo large --apply-only >/dev/null
run demo --model small >/dev/null
grep -qx 'launch|small|small|small|4096' "$SPY" || fail 'old window leaked into explicit selection'
printf 'ok launch planning: save-only, side-effect order, model-bound limits, tiers, argv, help, recursion\n'

# Exercise the actual OpenRouter declaration, launcher, and child environment.
# Only auth, asset initialization, and Claude itself are stubbed.
cp "$ROOT_DIR/providers/openrouter.sh" "$REPO/providers/"
cp "$ROOT_DIR/lib/launch.sh" "$REPO/lib/"
cat > "$CLAUDE_BIN" <<'CLAUDE'
#!/bin/sh
printf 'model=%s\n' "$ANTHROPIC_MODEL"
printf 'user=%s\n' "$USER"
printf 'base=%s\n' "$ANTHROPIC_BASE_URL"
printf 'context=%s\n' "${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-}"
printf 'output=%s\n' "${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-}"
printf 'compact=%s\n' "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
printf 'tiers=%s,%s,%s,%s\n' "$ANTHROPIC_DEFAULT_OPUS_MODEL" "$ANTHROPIC_DEFAULT_SONNET_MODEL" "$ANTHROPIC_DEFAULT_HAIKU_MODEL" "$CLAUDE_CODE_SUBAGENT_MODEL"
printf 'arg=%s\n' "$@"
CLAUDE
rm "$SPY"
run openrouter 'nemotron 3.5 super vl' --plan > "$TMP_DIR/free-vl.json"
"$NODE_BIN" - "$TMP_DIR/free-vl.json" <<'NODE'
const assert = require('node:assert/strict');
const plan = require(process.argv[2]);
assert.equal(plan.model, 'nvidia/nemotron-3.5-super-vl:free');
assert.equal(plan.contextTokens, 1000000);
assert.equal(plan.maxOutputTokens, 131072);
assert.equal(plan.constraints.paidFallback, false);
NODE
[ ! -e "$SPY" ] || fail 'default free model plan initialized auth or assets'
saved=$(run openrouter --model 'qwen3.8 27b' --apply-only) || fail 'registered label cannot be saved'
[ "$saved" = 'openrouter: applied qwen/qwen3.8-27b (context=262144, effort=xhigh); no services started' ] || fail 'saved label plan differs from canonical model plan'
[ ! -e "$SPY" ] || fail 'OpenRouter apply-only initialized auth or assets'
selection_dir=$XDG_STATE_HOME/crouter
[ "$(cat "$selection_dir/last-model-openrouter")" = qwen/qwen3.8-27b ] || fail 'unresolved label saved'
[ "$("$NODE_BIN" "$REPO/lib/model-state.js" context openrouter qwen/qwen3.8-27b)" = 262144 ] || fail 'canonical model context not saved'

assert_qwen_launch() {
  run openrouter "$@" > "$TMP_DIR/openrouter.out" || fail 'OpenRouter launch failed'
  grep -Fxq 'model=qwen/qwen3.8-27b' "$TMP_DIR/openrouter.out" || fail 'child model not canonical'
  grep -Fxq 'context=262144' "$TMP_DIR/openrouter.out" || fail 'child context differs from saved plan'
  grep -Fxq 'output=' "$TMP_DIR/openrouter.out" || fail 'default model output cap leaked into Qwen'
  grep -Fxq 'compact=' "$TMP_DIR/openrouter.out" || fail 'default compact window leaked'
  grep -Fxq 'tiers=qwen/qwen3.8-27b,qwen/qwen3.8-27b,qwen/qwen3.8-27b,qwen/qwen3.8-27b' "$TMP_DIR/openrouter.out" || fail 'canonical tier configuration lost'
  grep -A 1 -Fx 'arg=--effort' "$TMP_DIR/openrouter.out" | grep -Fxq 'arg=xhigh' || fail 'child effort differs from apply-only preview'
}
assert_qwen_launch
assert_qwen_launch 'qwen3.8 27b'
assert_qwen_launch --model=qwen/qwen3.8-27b
assert_qwen_launch --model qwen3.8-27b
# Headless launch must not require a login-shell USER or LOGNAME.
(unset USER LOGNAME; assert_qwen_launch)
grep -Fxq "user=$(id -un)" "$TMP_DIR/openrouter.out" || fail 'headless username fallback lost'
run openrouter --model 'nemotron 3 ultra' > "$TMP_DIR/openrouter.out"
grep -Fxq 'model=nvidia/nemotron-3-ultra-550b-a55b:free' "$TMP_DIR/openrouter.out" || fail 'Nemotron label lost'
grep -A 1 -Fx 'arg=--effort' "$TMP_DIR/openrouter.out" | grep -Fxq 'arg=high' || fail 'Nemotron effort lost'
(CROUTER_MODEL_TIER_MODE=provider run openrouter vendor/other-model) > "$TMP_DIR/openrouter.out"
grep -Fxq 'tiers=vendor/other-model,vendor/other-model,vendor/other-model,vendor/other-model' "$TMP_DIR/openrouter.out" || fail 'OpenRouter lost single-model tier routing'
grep -Fxq 'context=' "$TMP_DIR/openrouter.out" || fail 'unknown model inherited the saved window'
! grep -Fxq 'arg=--effort' "$TMP_DIR/openrouter.out" || fail 'unknown model inherited the saved effort'

rm "$SPY"
before=$(cksum "$selection_dir/last-model-openrouter" "$selection_dir/openrouter-context" "$selection_dir/selection-openrouter.json")
for model in 'qwen3.8 27b:free' qwen3.8-27b:free qwen/qwen3.8-27b:free; do
  for action in --apply-only --; do
    if run openrouter --model "$model" "$action" > "$TMP_DIR/openrouter.out" 2>&1; then fail 'retired free model accepted'; fi
    grep -Fq 'retired model ID' "$TMP_DIR/openrouter.out" || fail 'retired model rejection lost'
  done
done
for model in 'unknown model' 'unknown?model'; do
  if run openrouter --model "$model" > "$TMP_DIR/openrouter.out" 2>&1; then fail 'invalid ID accepted'; fi
  grep -Fq 'invalid model ID' "$TMP_DIR/openrouter.out" || fail 'invalid ID rejection lost'
done
[ ! -e "$SPY" ] || fail 'rejected OpenRouter selection initialized auth or assets'
[ "$before" = "$(cksum "$selection_dir/last-model-openrouter" "$selection_dir/openrouter-context" "$selection_dir/selection-openrouter.json")" ] || fail 'rejected OpenRouter selection changed state'
printf 'ok CFG-07 OpenRouter aliases, canonical preview and launch, retired and invalid models\n'

# The preview uses the same frozen model resolution as every dispatcher path.
run openrouter --plan > "$TMP_DIR/remembered.json"
run openrouter 'qwen3.8 27b' --plan > "$TMP_DIR/positional.json"
run openrouter --model=qwen/qwen3.8-27b --plan > "$TMP_DIR/flag.json"
cmp "$TMP_DIR/remembered.json" "$TMP_DIR/positional.json"
cmp "$TMP_DIR/remembered.json" "$TMP_DIR/flag.json"
! grep -Fq 'test-only' "$TMP_DIR/remembered.json" || fail 'preview contains a credential'
[ ! -e "$SPY" ] || fail 'preview launched auth or assets'

cp "$ROOT_DIR/providers/ollama.sh" "$REPO/providers/"
mkdir "$TMP_DIR/bin"
cat > "$TMP_DIR/bin/curl" <<'CURL'
#!/bin/sh
for url do :; done
printf 'curl:%s\n' "$url" >> "$SPY"
case $url in
  http://mlx.fixture.invalid:8080/v1/models) printf '{}\n' ;;
  http://127.0.0.1:11436/health) printf '{"service":"crouter-mlx-anthropic-adapter","upstream":"mlx.fixture.invalid:8080"}\n' ;;
  http://127.0.0.1:11434) printf 'Ollama running\n' ;;
  http://127.0.0.1:11435/health) printf '{"service":"crouter-ollama-heartbeat","effort_cap":"xhigh","dflash_effort_rewrite":"qwen38-dflash-named-effort-v1"}\n' ;;
  *) exit 99 ;;
esac
CURL
chmod +x "$TMP_DIR/bin/curl"
export PATH="$TMP_DIR/bin:$PATH" MLX_UPSTREAM_HOST=mlx.fixture.invalid MLX_UPSTREAM_PORT=08080
run ollama --model qwen3.8-27b --plan > "$TMP_DIR/mlx.json"
run ollama --model qwen3.8-27b --apply-only > "$TMP_DIR/saved"
run ollama --plan > "$TMP_DIR/remembered-mlx.json"
cmp "$TMP_DIR/mlx.json" "$TMP_DIR/remembered-mlx.json"
[ ! -e "$SPY" ] || fail 'local preview or save started a resource'
"$NODE_BIN" - "$TMP_DIR/mlx.json" <<'NODE'
const assert = require('node:assert/strict');
const plan = require(process.argv[2]);
assert.equal(plan.schemaVersion, 1);
assert.equal(plan.model, 'qwen3.8-27b');
assert.equal(plan.source.origin, 'http://127.0.0.1:11436');
assert.equal(plan.contextTokens, 262144);
assert.equal(plan.maxOutputTokens, null);
assert.equal(plan.effort, 'max');
assert.deepEqual(plan.services, ['mlx-anthropic-adapter']);
assert.deepEqual(plan.assets.plugins, ['qwen-local-multimodal']);
assert.deepEqual(Object.values(plan.tiers), Array(4).fill('qwen3.8-27b'));
NODE
run ollama > "$TMP_DIR/mlx.out"
grep -Fxq 'base=http://127.0.0.1:11436' "$TMP_DIR/mlx.out" || fail 'planned endpoint did not reach Claude'
grep -Fxq 'context=262144' "$TMP_DIR/mlx.out" || fail 'planned context did not reach Claude'
grep -A 1 -Fx 'arg=--effort' "$TMP_DIR/mlx.out" | grep -Fxq 'arg=max' || fail 'planned effort did not reach Claude'
grep -Fxq 'curl:http://mlx.fixture.invalid:8080/v1/models' "$SPY" || fail 'MLX hook did not use planned upstream'
! grep -Fq ':11435' "$SPY" || fail 'MLX launch used the old relay'
rm "$SPY"
run ollama --model qwen3.8:27b-dflash > "$TMP_DIR/ollama.out"
grep -Fxq 'base=http://127.0.0.1:11435' "$TMP_DIR/ollama.out" || fail 'DFlash endpoint did not reach Claude'
grep -A 1 -Fx 'arg=--effort' "$TMP_DIR/ollama.out" | grep -Fxq 'arg=xhigh' || fail 'DFlash effort did not reach Claude'
! grep -Fq ':11436' "$SPY" || fail 'DFlash launch used the old adapter'
rm "$SPY"
if (MLX_UPSTREAM_PORT=invalid run ollama --model qwen3.8-27b --apply-only) >"$TMP_DIR/bad.out" 2>&1; then
  fail 'invalid local adapter configuration was saved'
fi
[ ! -e "$SPY" ] || fail 'invalid local plan reached an external boundary'
[ "$(cat "$selection_dir/last-model-ollama")" = qwen3.8:27b-dflash ] || fail 'failed apply-only changed the saved local plan'

# The full Hauhau window must be visible through the real CLI without
# contacting Ollama, starting the relay, or invoking Claude.
run ollama --model qwen3.6-hauhau:35b-a3b-q4_k_p --plan > "$TMP_DIR/hauhau.json"
run ollama --model qwen3.6-hauhau:35b-a3b-q4_k_p --apply-only > "$TMP_DIR/saved"
run ollama --plan > "$TMP_DIR/remembered-hauhau.json"
"$NODE_BIN" - "$TMP_DIR/hauhau.json" "$TMP_DIR/remembered-hauhau.json" <<'NODE'
const assert = require('node:assert/strict');
for (const file of process.argv.slice(2)) {
  const plan = require(file);
  assert.equal(plan.model, 'qwen3.6-hauhau:35b-a3b-q4_k_p');
  assert.equal(plan.contextTokens, 262144);
  assert.equal(plan.source.origin, 'http://127.0.0.1:11435');
  assert.deepEqual(plan.services, ['ollama-heartbeat']);
  assert.deepEqual(Object.values(plan.tiers), Array(4).fill(plan.model));
}
NODE
[ ! -e "$SPY" ] || fail 'Hauhau preview or save started a resource'

run demo large > "$TMP_DIR/large.out"
grep -Fxq 'output=8192' "$TMP_DIR/large.out" || fail 'configured output cap not sent to Claude'
run demo unknown > "$TMP_DIR/unknown.out"
for limit in context output compact; do
  grep -Fxq "$limit=" "$TMP_DIR/unknown.out" || fail "$limit leaked to an unknown model"
done
printf 'ok CFG-01/02/04 immutable preview, active local services, Claude environment and failure isolation\n'

# Use the public CLI writer to set a tighter per-model cap. The provider
# default, saved record, JSON preview and actual child must agree after reload.
"$NODE_BIN" "$REPO/lib/model-state.js" write openrouter qwen/qwen3.8-27b 131072 32768
run openrouter 'qwen3.8 27b' --plan > "$TMP_DIR/tight-context.json"
"$NODE_BIN" - "$TMP_DIR/tight-context.json" <<'NODE'
const assert = require('node:assert/strict');
const plan = require(process.argv[2]);
assert.equal(plan.contextTokens, 131072);
assert.equal(plan.maxOutputTokens, 32768);
NODE
run openrouter --model qwen/qwen3.8-27b > "$TMP_DIR/tight-context.out"
grep -Fxq 'context=131072' "$TMP_DIR/tight-context.out" || fail 'provider policy raised the saved context limit'
grep -Fxq 'output=32768' "$TMP_DIR/tight-context.out" || fail 'saved output limit was lost'
