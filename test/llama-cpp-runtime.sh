#!/bin/sh
# CLI, static catalog, identity and ownership fixtures; no real model endpoint.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d)
cleanup() {
  for file in "$TMP_DIR/native-pid" "$TMP_DIR/adapter-pid"; do
    if [ -s "$file" ]; then kill "$(cat "$file")" 2>/dev/null || true; fi
  done
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM
fail() { printf 'FAIL llama-cpp: %s\n' "$*" >&2; exit 1; }
REPO="$TMP_DIR/repo with spaces"
RUNTIME="$TMP_DIR/runtime with spaces"
mkdir -p "$REPO/bin" "$REPO/lib" "$REPO/providers" "$TMP_DIR/home" "$TMP_DIR/bin" "$RUNTIME"
: > "$RUNTIME/model.gguf"
: > "$RUNTIME/other.gguf"
cat > "$RUNTIME/start-server.sh" <<'WRAPPER'
#!/bin/sh
[ "$#" = 1 ] && [ "$1" = --check ] || exit 98
printf 'check\n' >> "$FIXTURE_DIR/launcher-checks"
alias=inkling-2-mini-unbound-v3
[ "$FIXTURE_NATIVE_STATE" != wrong-plan-alias ] || alias=other-model
model_path=$INKLING_UNBOUND_RUNTIME_DIR/model.gguf
[ "$FIXTURE_NATIVE_STATE" != relative-plan-path ] || model_path=VERSION
printf '{"model_path":"%s","alias":"%s","context_tokens":524288}\n' "$model_path" "$alias"
WRAPPER
chmod +x "$RUNTIME/start-server.sh"
cp "$ROOT_DIR/bin/crouter" "$ROOT_DIR/bin/crouter-models" "$REPO/bin/"
cp "$ROOT_DIR/VERSION" "$REPO/"
cp "$ROOT_DIR"/lib/*.sh "$ROOT_DIR"/lib/*.js "$ROOT_DIR"/lib/*.mjs "$REPO/lib/"
cp "$ROOT_DIR/providers/llama-cpp.sh" "$ROOT_DIR/providers/mlx-vlm.sh" "$REPO/providers/"
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
  http://127.0.0.1:8085/health)
    [ "$FIXTURE_NATIVE_STATE" != absent ] || [ -s "$FIXTURE_DIR/native-pid" ] || exit 1
    status=ok
    [ "$FIXTURE_NATIVE_STATE" != not-ready ] || status=loading
    printf '{"status":"%s"}' "$status" ;;
  http://127.0.0.1:8085/props)
    model=model
    [ "$FIXTURE_NATIVE_STATE" != wrong-path ] || model=other
    model_path=$INKLING_UNBOUND_RUNTIME_DIR/$model.gguf
    # Relative declaration otherwise resolves to this same real file.
    [ "$FIXTURE_NATIVE_STATE" != relative-plan-path ] || model_path=$PWD/VERSION
    context=524288
    [ "$FIXTURE_NATIVE_STATE" != short-context ] || context=32768
    printf '{"model_path":"%s","default_generation_settings":{"n_ctx":%s}}' "$model_path" "$context" ;;
  http://127.0.0.1:8085/v1/models)
    alias=inkling-2-mini-unbound-v3
    [ "$FIXTURE_NATIVE_STATE" != wrong-alias ] || alias=other-model
    printf '{"data":[{"id":"%s"}]}' "$alias" ;;
  http://127.0.0.1:11441/health)
    [ "$FIXTURE_ADAPTER_STATE" != absent ] || [ -s "$FIXTURE_DIR/adapter-pid" ] || exit 1
    model=inkling-2-mini-unbound-v3
    [ "$FIXTURE_ADAPTER_STATE" != wrong-model ] || model=other-model
    upstream=inkling-2-mini-unbound-v3
    [ "$FIXTURE_ADAPTER_STATE" != wrong-upstream ] || upstream=other-model
    defaults=true
    [ "$FIXTURE_ADAPTER_STATE" != wrong-defaults ] || defaults=false
    printf '{"service":"crouter-mlx-anthropic-adapter","model":"%s","upstream":"127.0.0.1:8085","upstream_model":"%s","inherit_defaults":%s}' "$model" "$upstream" "$defaults" ;;
  *) exit 99 ;;
esac
CURL
cat > "$TMP_DIR/bin/lsof" <<'LSOF'
#!/bin/sh
case " $* " in
  *' -iTCP:8085 '*) [ "$FIXTURE_NATIVE_STATE" != absent ] ;;
  *' -iTCP:11441 '*) [ "$FIXTURE_ADAPTER_STATE" != absent ] ;;
  *) exit 99 ;;
esac
LSOF
cat > "$TMP_DIR/bin/nohup" <<'NOHUP'
#!/bin/sh
for setting in "${MLX_TEMPERATURE-unset}" "${MLX_TOP_P-unset}" "${MLX_TOP_K-unset}" "${MLX_MIN_P-unset}" \
  "${MLX_MAX_OUTPUT_TOKENS-unset}" "${MLX_REASONING_EFFORT-unset}" "${APC_ENABLED-unset}" "${APC_MEMORY_MAX_GB-unset}" \
  "${KV_BITS-unset}" "${LLAMA_ARG_CACHE_RAM-unset}" "${LLAMA_ARG_CACHE_PROMPT-unset}" "${LLAMA_ARG_CACHE_IDLE_SLOTS-unset}" \
  "${MLX_VLM_DRAFT_MODEL-unset}" "${MLX_VLM_DRAFT_KIND-unset}" "${MLX_VLM_DRAFT_BLOCK_SIZE-unset}"; do
  [ "$setting" = unset ] || exit 90
done
if [ "$1" = node ]; then
  [ "$#" = 2 ] || exit 91
  [ "$MLX_PROXY_PORT:$MLX_UPSTREAM_HOST:$MLX_UPSTREAM_PORT" = 11441:127.0.0.1:8085 ] || exit 92
  [ "$MLX_INHERIT_DEFAULTS:$MLX_MODEL:$MLX_UPSTREAM_MODEL" = 1:inkling-2-mini-unbound-v3:inkling-2-mini-unbound-v3 ] || exit 93
  printf '%s\n' "$$" > "$FIXTURE_DIR/adapter-pid"
else
  [ "$#" = 1 ] || exit 94
  [ "$1" = "$INKLING_UNBOUND_RUNTIME_DIR/start-server.sh" ] || exit 95
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
unset KV_BITS LLAMA_ARG_CACHE_RAM LLAMA_ARG_CACHE_PROMPT LLAMA_ARG_CACHE_IDLE_SLOTS MLX_VLM_DRAFT_MODEL MLX_VLM_DRAFT_KIND MLX_VLM_DRAFT_BLOCK_SIZE
invoke() {
  HOME="$TMP_DIR/home" XDG_STATE_HOME="$TMP_DIR/state" USER=crouter-fixture \
    FIXTURE_DIR="$TMP_DIR" FIXTURE_NATIVE_STATE="${native_state:-compatible}" FIXTURE_ADAPTER_STATE="${adapter_state:-absent}" \
    INKLING_UNBOUND_RUNTIME_DIR="$RUNTIME" CLAUDE_BIN="$TMP_DIR/claude" PATH="$TMP_DIR/bin:$PATH" \
    "${TEST_SHELL:-sh}" "$REPO/bin/crouter" "$@"
}
run() { invoke llama-cpp "$@"; }
invoke list > "$TMP_DIR/providers"
grep -Eq '^llama-cpp[[:space:]]' "$TMP_DIR/providers" || fail 'provider not discovered'
invoke models llama-cpp --list > "$TMP_DIR/catalog"
grep -Fq inkling-2-mini-unbound-v3 "$TMP_DIR/catalog" || fail 'static catalog missing model'
CROUTER_PROVIDERS_DIR="$REPO/providers" bash -c '. "$1"; _crouter_providers' fixture "$ROOT_DIR/completions/crouter.bash" > "$TMP_DIR/completion"
grep -Fxq llama-cpp "$TMP_DIR/completion" || fail 'provider completion missing'
for selection in inkling-2-mini-unbound-v3 inkling-2-mini-unbound-v3:latest; do
  run --model "$selection" --plan > "$TMP_DIR/plan.json"
  run --model "$selection" --apply-only > "$TMP_DIR/saved"
  run --plan > "$TMP_DIR/remembered.json"
  node - "$TMP_DIR/plan.json" "$TMP_DIR/remembered.json" <<'NODE'
const assert = require('node:assert/strict');
for (const file of process.argv.slice(2)) {
  const p = require(file); const model = 'inkling-2-mini-unbound-v3';
  assert.equal(p.model, model); assert.equal(p.source.provider, 'llama-cpp');
  assert.equal(p.source.origin, 'http://127.0.0.1:11441');
  assert.equal(p.contextTokens, 524288); assert.equal(p.maxOutputTokens, null);
  assert.deepEqual(Object.values(p.tiers), Array(4).fill(model));
  assert.deepEqual(p.services, ['inkling-unbound-llama-cpp']);
}
NODE
done
if run --model unconfigured-model --plan > "$TMP_DIR/wrong" 2> "$TMP_DIR/wrong-error"; then fail 'unknown model accepted'; fi
[ "$(cat "$TMP_DIR/state/crouter/last-model-llama-cpp")" = inkling-2-mini-unbound-v3 ] || fail 'unknown selection changed saved ID'
invoke mlx-vlm --plan > "$TMP_DIR/stock.json"
node - "$TMP_DIR/stock.json" <<'NODE'
const assert = require('node:assert/strict'); const p = require(process.argv[2]);
assert.equal(p.model, 'inkling-2-mini:latest'); assert.equal(p.source.origin, 'http://127.0.0.1:11440');
NODE
[ ! -e "$TMP_DIR/network" ] || fail 'catalog/plan/save touched native or Ollama HTTP'
[ ! -e "$TMP_DIR/launcher-checks" ] || fail 'plan/save executed native check'
[ ! -e "$TMP_DIR/native-pid" ] && [ ! -e "$TMP_DIR/adapter-pid" ] || fail 'plan/save started service'
for native_state in compatible absent; do
  adapter_state=absent
  rm -f "$TMP_DIR/native-pid" "$TMP_DIR/adapter-pid"
  run --once > "$TMP_DIR/output" 2> "$TMP_DIR/error" || { cat "$TMP_DIR/error" >&2; fail 'CLI startup failed'; }
  grep -Fxq 'model=inkling-2-mini-unbound-v3' "$TMP_DIR/output"
  grep -Fxq 'base=http://127.0.0.1:11441' "$TMP_DIR/output"
  grep -Fxq 'context=524288' "$TMP_DIR/output"
  grep -Fxq 'tiers=inkling-2-mini-unbound-v3,inkling-2-mini-unbound-v3,inkling-2-mini-unbound-v3,inkling-2-mini-unbound-v3' "$TMP_DIR/output"
  grep -Fxq 'private=clean' "$TMP_DIR/output"
  [ -s "$TMP_DIR/adapter-pid" ] || fail 'owned adapter missing'
  ! kill -0 "$(cat "$TMP_DIR/adapter-pid")" 2>/dev/null || fail 'owned adapter leaked'
  if [ "$native_state" = absent ]; then
    [ -s "$TMP_DIR/native-pid" ] || fail 'owned native missing'
    ! kill -0 "$(cat "$TMP_DIR/native-pid")" 2>/dev/null || fail 'owned native leaked'
  else [ ! -e "$TMP_DIR/native-pid" ] || fail 'shared native was restarted'; fi
done
rm -f "$TMP_DIR/native-pid" "$TMP_DIR/adapter-pid"
native_state=compatible adapter_state=compatible
run --once > "$TMP_DIR/shared"
[ ! -e "$TMP_DIR/native-pid" ] && [ ! -e "$TMP_DIR/adapter-pid" ] || fail 'shared services became owned'
for native_state in wrong-path wrong-alias wrong-plan-alias relative-plan-path short-context not-ready; do
  adapter_state=absent
  if run --once > "$TMP_DIR/wrong" 2> "$TMP_DIR/error"; then fail 'wrong native identity accepted'; fi
  [ ! -e "$TMP_DIR/native-pid" ] && [ ! -e "$TMP_DIR/adapter-pid" ] || fail 'incompatible native was replaced'
done
native_state=compatible
for adapter_state in wrong-model wrong-upstream wrong-defaults; do
  if run --once > "$TMP_DIR/wrong" 2> "$TMP_DIR/error"; then fail 'wrong adapter identity accepted'; fi
  [ ! -e "$TMP_DIR/native-pid" ] && [ ! -e "$TMP_DIR/adapter-pid" ] || fail 'incompatible adapter was replaced'
done
if NODE_BIN=/definitely/missing/node invoke doctor llama-cpp > "$TMP_DIR/doctor" 2> "$TMP_DIR/doctor-error"; then fail 'doctor ignored missing Node'; fi
grep -Fq 'node unavailable' "$TMP_DIR/doctor" || fail 'doctor Node diagnostic missing'
printf 'ok    llama-cpp static discovery, normalized IDs, 512K native identity, absolute paths, default inheritance and owned cleanup\n'
