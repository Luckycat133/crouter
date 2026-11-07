#!/bin/sh
# Exact vendor values live in a committed, reviewed fixture; structural and
# local/native invariants remain independent assertions, not regenerated goldens.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-node}
"$NODE_BIN" "$ROOT_DIR/test/provider-config.js"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
export HOME="$TMP_DIR" XDG_STATE_HOME="$TMP_DIR" ROOT_DIR
PROVIDERS_DIR=$ROOT_DIR/providers
STATE_DIR=$TMP_DIR/state
export PROVIDERS_DIR STATE_DIR
die() { printf 'FAIL provider matrix: %s\n' "$*" >&2; exit 1; }
. "$ROOT_DIR/lib/provider.sh"
word() { case " $3 " in *" $2 "*) ;; *) die "$1 missing $2" ;; esac; }
[ ! -e "$PROVIDERS_DIR/openai.sh" ] || die 'direct OpenAI is not a Messages provider'
[ ! -e "$PROVIDERS_DIR/baichuan.sh" ] || die 'unverified direct Messages provider'
for name in $(provider_names); do
  load_provider "$name"
  for url in "$BASE_URL" "$PLAN_URL" "$API_URL"; do
    case $url in */v1/messages|*/v3/messages) die "$name uses a full Messages URL, not a base prefix" ;; esac
  done
  [ -n "$MODEL_OPUS$MODEL_SONNET$MODEL_HAIKU$MODEL_SUBAGENT" ] || die "$name lacks model tiers"
done
load_provider bedrock
for field in CLAUDE_CONFIG_DIR AWS_SHARED_CREDENTIALS_FILE AWS_CONFIG_FILE ANTHROPIC_BEDROCK_BASE_URL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL; do word bedrock "$field" "$PASSTHROUGH_ENV"; done
load_provider vertex
for field in CLAUDE_CONFIG_DIR ANTHROPIC_VERTEX_BASE_URL ANTHROPIC_VERTEX_PROJECT_ID ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL; do word vertex "$field" "$PASSTHROUGH_ENV"; done
load_provider foundry
for field in CLAUDE_CONFIG_DIR ANTHROPIC_FOUNDRY_RESOURCE ANTHROPIC_FOUNDRY_BASE_URL ANTHROPIC_FOUNDRY_API_KEY ANTHROPIC_FOUNDRY_AUTH_TOKEN AZURE_CONFIG_DIR AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_CLIENT_SECRET; do word foundry "$field" "$PASSTHROUGH_ENV"; done
load_provider ollama
[ "$BASE_URL" = http://127.0.0.1:11435 ] || die 'Ollama relay base changed'
[ "$CONTEXT_TOKENS" = 65536 ] || die 'Ollama fallback cap changed'
word ollama 'qwen3.8:27b-dflash=262144' "$MODEL_CONTEXT_OVERRIDES"
word ollama 'qwen3.8:27b-dflash' "$MODEL_SELF_ROUTE_MODELS"
for pattern in 'OLLAMA_HEARTBEAT_INTERVAL_MS=60000' 'assets/plugins/qwen-local-multimodal' 'MLX-VLM not reachable'; do printf '%s' "$PRE_START" | grep -Fq "$pattern" || die "missing local behavior: $pattern"; done
printf '%s' "$POST_STOP" | grep -q '_OLLAMA_HEARTBEAT_PROXY_PID' || die 'local cleanup absent'
for pattern in 'ANTHROPIC_AUTH_TOKEN=ollama' 'ANTHROPIC_API_KEY=' 'API_TIMEOUT_MS=1800000' 'CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000'; do printf '%s\n' "$EXTRA_ENV" | grep -Fxq "$pattern" || die "local environment: $pattern"; done
DASHSCOPE_API_URL=https://workspace-id.cn-beijing.maas.aliyuncs.com/apps/anthropic
export DASHSCOPE_API_URL
load_provider dashscope
[ "$API_URL" = "$DASHSCOPE_API_URL" ] || die 'workspace endpoint override lost'
unset DASHSCOPE_API_URL
load_provider openrouter
[ "$(resolve_model_id qwen3.8-27b)" = qwen/qwen3.8-27b ] || die 'explicit paid alias lost'
if (resolve_model_id qwen/qwen3.8-27b:free) >/dev/null 2>&1; then die 'retired free model silently upgraded'; fi
load_provider anthropic
[ "$MODELS_API_AUTH" = x-api-key ] || die 'Anthropic catalog header'
load_provider minimax
[ "${MODELS_API_AUTH:-none}" = none ] || die 'catalog state leaked between providers'
printf 'ok provider matrix: reviewed values, auth isolation, local/native invariants\n'
