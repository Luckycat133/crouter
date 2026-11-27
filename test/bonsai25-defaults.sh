#!/bin/sh
# Offline launch contract: fake servers capture arguments, never load weights.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_SHELL=${TEST_SHELL:-sh}
NODE_BIN=$(command -v node)
export NODE_BIN
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT INT TERM
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
die() { fail "$*"; }
[ -f "$ROOT_DIR/providers/bonsai25.sh" ] || fail 'Bonsai 2.5 provider is missing'
. "$ROOT_DIR/lib/provider.sh"
. "$ROOT_DIR/providers/bonsai25.sh"
[ "$MODEL" = ternary-bonsai-2.5-27b ] || fail 'wrong model identity'
[ "$CONTEXT_TOKENS" = 262144 ] || fail 'wrong client context'
[ "$EFFORT" = max ] || fail 'wrong client effort'
apply_model_self_route "$MODEL"
for tier in "$MODEL_OPUS" "$MODEL_SONNET" "$MODEL_HAIKU" "$MODEL_SUBAGENT"; do
  [ "$tier" = "$MODEL" ] || fail 'tier escaped the selected model'
done
mkdir -p "$TEST_DIR/bin" "$TEST_DIR/demo/scripts" "$TEST_DIR/demo/.venv-vlm/bin" "$TEST_DIR/model"
BONSAI25_DEMO_DIR=$TEST_DIR/demo BONSAI25_MODEL_DIR=$TEST_DIR/model
BONSAI_TEST_DIR=$TEST_DIR
LOG_DIR=$TEST_DIR/logs
export BONSAI25_DEMO_DIR BONSAI25_MODEL_DIR BONSAI_TEST_DIR
: > "$TEST_DIR/model/config.json"
: > "$TEST_DIR/demo/.venv-vlm/bin/python"
chmod +x "$TEST_DIR/demo/.venv-vlm/bin/python"
cat > "$TEST_DIR/demo/scripts/start_mlx_server.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$@" > "$BONSAI_TEST_DIR/server-args"
printf '%s|%s|%s|%s|%s|%s|%s|%s\n' "$APC_ENABLED" "$APC_DISK_ENABLED" "$APC_MEMORY_MAX_GB" "$APC_CHECKPOINT_ENTRIES" "$MLX_VLM_TOKEN_QUEUE_TIMEOUT" "$MLX_VLM_MAX_NUM_SEQS" "${MLX_VLM_DRAFT_MODEL-unset}" "${KV_BITS-unset}" > "$BONSAI_TEST_DIR/server-env"
: > "$BONSAI_TEST_DIR/server-ready"
exec sleep 30
SH
cat > "$TEST_DIR/bin/node" <<'SH'
#!/bin/sh
printf '%s\n' "$@" > "$BONSAI_TEST_DIR/proxy-args"
printf '%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' "$MLX_TEMPERATURE" "$MLX_TOP_P" "$MLX_TOP_K" "$MLX_MIN_P" "$MLX_REPETITION_PENALTY" "$MLX_PRESENCE_PENALTY" "$MLX_FREQUENCY_PENALTY" "$MLX_REASONING_EFFORT" "${MLX_MAX_OUTPUT_TOKENS-unset}" "$MLX_PROXY_HOST" > "$BONSAI_TEST_DIR/proxy-env"
: > "$BONSAI_TEST_DIR/proxy-ready"
exec sleep 30
SH
cat > "$TEST_DIR/bin/curl" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$BONSAI_TEST_DIR/probes"
for arg do url=$arg; done
case $url in
  */api/ps) printf '{"models":%s}' "${BONSAI_TEST_OLLAMA_MODELS-[]}" ;;
  http://127.0.0.1:8081/health)
    [ -f "$BONSAI_TEST_DIR/server-ready" ] || exit 7
    printf '{"status":"healthy","loaded_model":"%s","apc_enabled":true}' "$BONSAI25_MODEL_DIR" ;;
  http://127.0.0.1:11439/health)
    [ -f "$BONSAI_TEST_DIR/proxy-ready" ] || exit 7
    printf '{"service":"crouter-mlx-anthropic-adapter","upstream":"127.0.0.1:8081","model":"ternary-bonsai-2.5-27b"}' ;;
  *) exit 8 ;;
esac
SH
cat > "$TEST_DIR/bin/lsof" <<'SH'
#!/bin/sh
case "$*" in *":${BONSAI_TEST_BUSY_PORT-none}"*) exit 0 ;; *) exit 1 ;; esac
SH
cat > "$TEST_DIR/bin/pgrep" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$TEST_DIR/bin/"*
PATH=$TEST_DIR/bin:$PATH
export PATH
LIB_DIR=$ROOT_DIR/lib
. "$LIB_DIR/bonsai25-runtime.sh"

# Planning must work without configured machine paths and without any probes.
env HOME="$TEST_DIR/home" XDG_STATE_HOME="$TEST_DIR/state" BONSAI25_DEMO_DIR= BONSAI25_MODEL_DIR= \
  "$TEST_SHELL" "$ROOT_DIR/bin/crouter" bonsai25 --plan > "$TEST_DIR/plan"
[ ! -e "$TEST_DIR/probes" ] || fail 'plan performed network I/O'
"$NODE_BIN" -e 'const p=JSON.parse(require("fs").readFileSync(process.argv[1])); if(p.model!=="ternary-bonsai-2.5-27b") process.exit(1)' "$TEST_DIR/plan" || fail 'wrong plan identity'

# An occupied upstream or adapter is never replaced or stopped.
for busy_port in 8081 11439; do
  if (BONSAI_TEST_BUSY_PORT=$busy_port; export BONSAI_TEST_BUSY_PORT; bonsai25_start) > "$TEST_DIR/error" 2>&1; then
    fail 'occupied port accepted'
  fi
  grep -q 'already in use' "$TEST_DIR/error" || fail 'occupied port diagnostic missing'
done
[ ! -e "$TEST_DIR/server-env" ] || fail 'occupied port started a server'
# JSON data is passed through the environment, never evaluated as shell text.
# shellcheck disable=SC2089,SC2090
if (BONSAI_TEST_OLLAMA_MODELS='[{"name":"busy"}]'; export BONSAI_TEST_OLLAMA_MODELS; bonsai25_start) > "$TEST_DIR/error" 2>&1; then
  fail 'loaded Ollama model was ignored'
fi
grep -q 'Ollama has a loaded model' "$TEST_DIR/error" || fail 'loaded model diagnostic missing'
[ ! -e "$TEST_DIR/server-env" ] || fail 'busy Ollama started a server'
if (BONSAI25_MODEL_DIR=; bonsai25_start) > "$TEST_DIR/error" 2>&1; then fail 'missing model path accepted'; fi
grep -q BONSAI25_MODEL_DIR "$TEST_DIR/error" || fail 'missing path diagnostic missing'

(
  trap 'bonsai25_stop' EXIT INT TERM
  # A caller's unrelated MTP/KV flags must not silently alter this profile.
  MLX_VLM_DRAFT_MODEL=unrelated KV_BITS=4 MLX_MAX_OUTPUT_TOKENS=1 MLX_PROXY_HOST=0.0.0.0
  export MLX_VLM_DRAFT_MODEL KV_BITS MLX_MAX_OUTPUT_TOKENS MLX_PROXY_HOST
  bonsai25_start
  printf '%s\n%s\n' "$_BONSAI25_SERVER_PID" "$_BONSAI25_PROXY_PID" > "$TEST_DIR/pids"
  [ "$(cat "$TEST_DIR/server-env")" = '1|0|4|2|0|1|unset|unset' ] || fail 'server defaults were not applied'
  [ "$(cat "$TEST_DIR/proxy-env")" = '1|0.95|20|0|1|0|0|xhigh|unset|127.0.0.1' ] || fail 'proxy defaults were not isolated'
  grep -A 1 -x -- '--prefill-step-size' "$TEST_DIR/server-args" | grep -qx 256 || fail 'prefill256 missing'
  grep -qx "$BONSAI25_MODEL_DIR" "$TEST_DIR/server-args" || fail 'configured weights not used'
  grep -qx "$BONSAI25_MODEL_DIR" "$TEST_DIR/proxy-args" || fail 'proxy upstream identity missing'
)
while IFS= read -r pid; do
  if kill -0 "$pid" 2>/dev/null; then fail 'owned process survived cleanup'; fi
done < "$TEST_DIR/pids"
printf 'ok    Bonsai 2.5 plans offline, applies agent defaults and cleans up only owned fake servers\n'
