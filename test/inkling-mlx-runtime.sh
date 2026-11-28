#!/bin/sh
# Real CLI/planner and owned-process lifecycle; all model endpoints are mocks.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
cleanup() {
  for pid_file in "$TMP_DIR/native-pid" "$TMP_DIR/adapter-pid"; do
    if [ -s "$pid_file" ]; then kill "$(cat "$pid_file")" 2>/dev/null || true; fi
  done
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM
fail() { printf 'FAIL Inkling: %s\n' "$*" >&2; exit 1; }
REPO="$TMP_DIR/repo with spaces"
RUNTIME="$TMP_DIR/runtime with spaces"
mkdir -p "$REPO/bin" "$REPO/lib" "$REPO/providers" "$TMP_DIR/home" "$TMP_DIR/bin" "$RUNTIME" "$TMP_DIR/actual model"
ln -s "$TMP_DIR/actual model" "$RUNTIME/model"
printf '#!/bin/sh\nexit 99\n' > "$RUNTIME/start-server.sh"
chmod +x "$RUNTIME/start-server.sh"
cp "$ROOT_DIR/bin/crouter" "$ROOT_DIR/bin/crouter-models" "$REPO/bin/"
cp "$ROOT_DIR/VERSION" "$REPO/"
cp "$ROOT_DIR"/lib/*.sh "$ROOT_DIR"/lib/*.js "$ROOT_DIR"/lib/*.mjs "$REPO/lib/"
cp "$ROOT_DIR/providers/ollama.sh" "$ROOT_DIR/providers/mlx-vlm.sh" "$REPO/providers/"
cat > "$REPO/lib/auth.sh" <<'AUTH'
is_dual_source() { return 1; }
resolve_auth() { AUTH_TOKEN=; }
check_auth() { return 0; }
AUTH
: > "$REPO/lib/key-mgmt.sh"
cat > "$REPO/lib/assets.sh" <<'ASSETS'
prepare_provider_assets() { :; }
cleanup_provider_assets() { :; }
ASSETS
cat > "$TMP_DIR/bin/curl" <<'CURL'
#!/bin/sh
for arg do case $arg in http://*) url=$arg ;; esac; done
printf '%s\n' "$url" >> "$FIXTURE_DIR/network"
case $url in
  http://127.0.0.1:8082/health)
    [ "$FIXTURE_NATIVE_STATE" != absent ] || [ -s "$FIXTURE_DIR/native-pid" ] || exit 1
    model=$INKLING_MLX_RUNTIME_DIR/model
    [ "$FIXTURE_NATIVE_STATE" != wrong-health ] || model=$INKLING_MLX_RUNTIME_DIR
    ready=true
    [ "$FIXTURE_NATIVE_STATE" != not-ready ] || ready=false
    printf '{"status":"healthy","loaded_model":"%s","model_ready":%s}' "$model" "$ready" ;;
  http://127.0.0.1:8082/v1/models)
    model=$INKLING_MLX_RUNTIME_DIR/model
    [ "$FIXTURE_NATIVE_STATE" != wrong-list ] || model=$INKLING_MLX_RUNTIME_DIR
    printf '{"data":[{"id":"%s"}]}' "$model" ;;
  http://127.0.0.1:11440/health)
    [ "$FIXTURE_ADAPTER_STATE" != absent ] || [ -s "$FIXTURE_DIR/adapter-pid" ] || exit 1
    model=$FIXTURE_MODEL
    [ "$FIXTURE_ADAPTER_STATE" != wrong-model ] || model=another-model
    path=$INKLING_MLX_RUNTIME_DIR/model
    [ "$FIXTURE_ADAPTER_STATE" != wrong-path ] || path=$INKLING_MLX_RUNTIME_DIR
    defaults=true
    [ "$FIXTURE_ADAPTER_STATE" != wrong-defaults ] || defaults=false
    printf '{"service":"crouter-mlx-anthropic-adapter","model":"%s","upstream":"127.0.0.1:8082","upstream_model":"%s","inherit_defaults":%s}' "$model" "$path" "$defaults" ;;
  *) exit 99 ;;
esac
CURL
cat > "$TMP_DIR/bin/lsof" <<'LSOF'
#!/bin/sh
case " $* " in
  *' -iTCP:8082 '*) [ "$FIXTURE_NATIVE_STATE" != absent ] ;;
  *' -iTCP:11440 '*) [ "$FIXTURE_ADAPTER_STATE" != absent ] ;;
  *) exit 99 ;;
esac
LSOF
cat > "$TMP_DIR/bin/nohup" <<'NOHUP'
#!/bin/sh
# Neither native generation defaults nor adapter generation overrides belong here.
for setting in "${MLX_TEMPERATURE-unset}" "${MLX_TOP_P-unset}" "${MLX_TOP_K-unset}" "${MLX_MIN_P-unset}" \
  "${MLX_MAX_OUTPUT_TOKENS-unset}" "${MLX_REASONING_EFFORT-unset}" "${APC_ENABLED-unset}" "${APC_MEMORY_MAX_GB-unset}"; do
  [ "$setting" = unset ] || exit 90
done
if [ "$1" = node ]; then
  [ "$#" = 2 ] || exit 91
  [ "$MLX_PROXY_PORT:$MLX_UPSTREAM_HOST:$MLX_UPSTREAM_PORT" = 11440:127.0.0.1:8082 ] || exit 92
  [ "$MLX_INHERIT_DEFAULTS" = 1 ] || exit 93
  [ "$MLX_MODEL" = "$FIXTURE_MODEL" ] || exit 94
  [ "$MLX_UPSTREAM_MODEL" = "$INKLING_MLX_RUNTIME_DIR/model" ] || exit 95
  printf '%s\n' "$$" > "$FIXTURE_DIR/adapter-pid"
else
  [ "$#" = 1 ] || exit 96
  [ "$1" = "$INKLING_MLX_RUNTIME_DIR/start-server.sh" ] || exit 97
  printf '%s\n' "$$" > "$FIXTURE_DIR/native-pid"
fi
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
unset MLX_TEMPERATURE MLX_TOP_P MLX_TOP_K MLX_MIN_P MLX_MAX_OUTPUT_TOKENS MLX_REASONING_EFFORT APC_ENABLED APC_MEMORY_MAX_GB
invoke() {
  HOME="$TMP_DIR/home" XDG_STATE_HOME="$TMP_DIR/state" USER=crouter-fixture \
    FIXTURE_DIR="$TMP_DIR" FIXTURE_MODEL="${fixture_model:-inkling-2-mini:latest}" \
    FIXTURE_NATIVE_STATE="${native_state:-compatible}" FIXTURE_ADAPTER_STATE="${adapter_state:-absent}" \
    INKLING_MLX_RUNTIME_DIR="$RUNTIME" CLAUDE_BIN="$TMP_DIR/claude" PATH="$TMP_DIR/bin:$PATH" \
    "${TEST_SHELL:-sh}" "$REPO/bin/crouter" "$@"
}
run() { invoke mlx-vlm "$@"; }
invoke list > "$TMP_DIR/providers"
grep -Eq '^mlx-vlm[[:space:]]' "$TMP_DIR/providers" || fail 'independent provider was not discovered'
invoke models mlx-vlm --list > "$TMP_DIR/catalog"
grep -Fq inkling-2-mini:latest "$TMP_DIR/catalog" || fail 'default Inkling missing from static catalog'
run --plan > "$TMP_DIR/default.json"
node - "$TMP_DIR/default.json" <<'NODE'
const assert = require('node:assert/strict');
const plan = require(process.argv[2]);
assert.equal(plan.model, 'inkling-2-mini:latest');
assert.equal(plan.source.provider, 'mlx-vlm');
NODE
for fixture_model in inkling-2-mini inkling-2-mini:latest; do
  run --model "$fixture_model" --plan > "$TMP_DIR/fresh.json"
  run --model "$fixture_model" --apply-only > "$TMP_DIR/saved"
  run --plan > "$TMP_DIR/remembered.json"
  node - "$TMP_DIR/fresh.json" "$TMP_DIR/remembered.json" "$fixture_model" <<'NODE'
const assert = require('node:assert/strict');
const [fresh, saved, model] = process.argv.slice(2);
for (const file of [fresh, saved]) {
  const plan = require(file);
  assert.equal(plan.source.provider, 'mlx-vlm');
  assert.equal(plan.model, model);
  assert.equal(plan.contextTokens, 1048576);
  assert.equal(plan.maxOutputTokens, null);
  assert.deepEqual(Object.values(plan.tiers), Array(4).fill(model));
  assert.equal(plan.source.origin, 'http://127.0.0.1:11440');
  assert.deepEqual(plan.services, ['inkling-mlx-vlm']);
}
NODE
  [ "$(cat "$TMP_DIR/state/crouter/last-model-mlx-vlm")" = "$fixture_model" ] || fail 'selection was saved under another provider'
done
for old_flag in 0 1; do
  printf 'OLLAMA_INKLING_MLX_VLM=%s\n' "$old_flag" > "$REPO/config.sh"
  for fixture_model in inkling-2-mini inkling-2-mini:latest; do
    for action in --plan --apply-only --once; do
      if invoke ollama --model "$fixture_model" "$action" > "$TMP_DIR/legacy-output" 2> "$TMP_DIR/legacy-error"; then
        fail 'Ollama still accepted an Inkling model'
      fi
      grep -Fq 'crouter mlx-vlm' "$TMP_DIR/legacy-error" || fail 'legacy rejection omitted the new command'
    done
  done
done
[ ! -e "$TMP_DIR/state/crouter/last-model-ollama" ] || fail 'rejected legacy selection changed Ollama state'
if run --model another-model --plan > "$TMP_DIR/unknown-output" 2> "$TMP_DIR/unknown-error"; then fail 'native provider accepted another model'; fi
(
  ROOT_DIR=$REPO PROVIDERS_DIR=$REPO/providers STATE_DIR=$TMP_DIR/empty-state
  die() { printf '%s\n' "$*" >&2; exit 1; }
  . "$REPO/lib/provider.sh"
  load_provider ollama
  [ -n "$MODEL_BLOCKED_MESSAGE" ] || exit 1
  load_provider mlx-vlm
  [ -z "$MODEL_BLOCKED_MESSAGE$MODEL_BLOCKED_IDS" ] || exit 1
) || fail 'blocked-model policy leaked between providers'
[ ! -e "$TMP_DIR/network" ] || fail 'preview/save contacted a service'
[ ! -e "$TMP_DIR/adapter-pid" ] || fail 'preview/save started an adapter'
[ ! -e "$TMP_DIR/native-pid" ] || fail 'preview/save started native service'
printf 'ok    independent MLX-VLM discovery, catalog, 1M plans, saved IDs and legacy rejection stay offline\n'

for fixture_model in inkling-2-mini inkling-2-mini:latest; do
  for native_state in compatible absent; do
    adapter_state=absent
    rm -f "$TMP_DIR/adapter-pid" "$TMP_DIR/native-pid"
    run --model "$fixture_model" --once > "$TMP_DIR/output" 2> "$TMP_DIR/error" || { cat "$TMP_DIR/error" >&2; fail 'mocked native launch failed'; }
    grep -Fxq "model=$fixture_model" "$TMP_DIR/output"
    grep -Fxq 'base=http://127.0.0.1:11440' "$TMP_DIR/output"
    grep -Fxq 'context=1048576' "$TMP_DIR/output"
    grep -Fxq "tiers=$fixture_model,$fixture_model,$fixture_model,$fixture_model" "$TMP_DIR/output"
    grep -Fxq 'private=clean' "$TMP_DIR/output"
    [ -s "$TMP_DIR/adapter-pid" ] || fail 'owned adapter was not started'
    ! kill -0 "$(cat "$TMP_DIR/adapter-pid")" 2>/dev/null || fail 'owned adapter was not cleaned'
    if [ "$native_state" = absent ]; then
      [ -s "$TMP_DIR/native-pid" ] || fail 'absent native was not started'
      ! kill -0 "$(cat "$TMP_DIR/native-pid")" 2>/dev/null || fail 'owned native was not cleaned'
    else
      [ ! -e "$TMP_DIR/native-pid" ] || fail 'compatible native was restarted'
    fi
  done
done
rm -f "$TMP_DIR/adapter-pid" "$TMP_DIR/native-pid"
native_state=compatible adapter_state=compatible
run --model "$fixture_model" --once > "$TMP_DIR/output"
[ ! -e "$TMP_DIR/adapter-pid" ] || fail 'compatible adapter was restarted'
[ ! -e "$TMP_DIR/native-pid" ] || fail 'compatible native became owned'

for native_state in wrong-health wrong-list not-ready; do
  adapter_state=absent
  if run --model "$fixture_model" --once > "$TMP_DIR/output" 2> "$TMP_DIR/error"; then fail 'incompatible native was accepted'; fi
  [ ! -e "$TMP_DIR/adapter-pid" ] || fail 'adapter started for an incompatible native'
  [ ! -e "$TMP_DIR/native-pid" ] || fail 'incompatible native was replaced'
done
native_state=compatible
for adapter_state in wrong-model wrong-path wrong-defaults; do
  if run --model "$fixture_model" --once > "$TMP_DIR/output" 2> "$TMP_DIR/error"; then fail 'incompatible adapter was accepted'; fi
  [ ! -e "$TMP_DIR/adapter-pid" ] || fail 'incompatible adapter was replaced'
  [ ! -e "$TMP_DIR/native-pid" ] || fail 'native started for an incompatible adapter'
done
printf 'ok    Inkling native identity, compatible reuse, rejection, defaults and owned cleanup\n'

# The same blocked-model declaration filters stale/static catalog entries and
# the unified route snapshot, including names obtained from `ollama list`.
HOME="$TMP_DIR/home" XDG_STATE_HOME="$TMP_DIR/routes-state" \
  CR_PROVIDER=ollama CR_PREFIX=ollama CR_MODELS_DISCOVERY=static \
  CR_AUTH_MODE=none CR_API_URL=http://127.0.0.1:11435 CR_DEFAULT_URL=http://127.0.0.1:11435 \
  CR_MODELS='inkling-2-mini inkling-2-mini:latest qwen3.8:27b-dflash' \
  CR_MODEL_BLOCKED='inkling-2-mini inkling-2-mini:latest' \
  node "$REPO/lib/route-build.js" candidates > "$TMP_DIR/ollama-route.json"
HOME="$TMP_DIR/home" XDG_STATE_HOME="$TMP_DIR/routes-state" \
  CR_PROVIDER=mlx-vlm CR_PREFIX=mlx-vlm CR_MODELS_DISCOVERY=static \
  CR_AUTH_MODE=none CR_API_URL=http://127.0.0.1:11440 CR_DEFAULT_URL=http://127.0.0.1:11440 \
  CR_MODELS='inkling-2-mini inkling-2-mini:latest' CR_MODEL_BLOCKED= \
  node "$REPO/lib/route-build.js" candidates > "$TMP_DIR/mlx-route.json"
node - "$TMP_DIR/ollama-route.json" "$TMP_DIR/mlx-route.json" <<'NODE'
const assert = require('node:assert/strict');
const ollama = require(process.argv[2]);
const mlx = require(process.argv[3]);
assert.deepEqual(ollama.models, ['qwen3.8:27b-dflash']);
assert.deepEqual(ollama.blockedModels, ['inkling-2-mini', 'inkling-2-mini:latest']);
assert.deepEqual(mlx.models, ['inkling-2-mini', 'inkling-2-mini:latest']);
assert.equal(mlx.prefix, 'mlx-vlm');
assert.equal(mlx.blockedModels, undefined);
NODE
HOME="$TMP_DIR/home" XDG_STATE_HOME="$TMP_DIR/routes-state" \
  CR_MODELS_DISCOVERY=static CR_STATIC_MODELS='inkling-2-mini inkling-2-mini:latest qwen3.8:27b-dflash' \
  CR_MODEL_BLOCKED='inkling-2-mini inkling-2-mini:latest' \
  node "$REPO/bin/crouter-models" --provider ollama --list > "$TMP_DIR/filtered-catalog"
! grep -Fq inkling "$TMP_DIR/filtered-catalog" || fail 'Ollama catalog still advertised Inkling'
grep -Fq qwen3.8:27b-dflash "$TMP_DIR/filtered-catalog" || fail 'catalog filtering removed another model'
native_state=compatible adapter_state=compatible
if NODE_BIN=/definitely/missing/node invoke doctor mlx-vlm > "$TMP_DIR/doctor" 2> "$TMP_DIR/doctor-error"; then fail 'MLX-VLM doctor accepted a missing Node runtime'; fi
grep -Fq 'node unavailable' "$TMP_DIR/doctor" || fail 'MLX-VLM doctor omitted its Node requirement'
printf 'ok    Inkling leaves Ollama catalogs and routes; independent provider checks Node\n'
