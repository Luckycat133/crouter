#!/bin/sh
# Audited provider contract. Values here come from each vendor's current
# Claude Code / Anthropic-compatibility documentation, not guessed model IDs.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROVIDERS_DIR="$ROOT_DIR/providers"
# Hermetic state: ollama.sh reads the last selected model from XDG_STATE_HOME.
# Point it at an empty temp dir so this suite always asserts the DECLARED
# provider contract instead of whichever model a previous local run selected.
XDG_STATE_HOME=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-matrix-state)
export XDG_STATE_HOME
trap 'rm -rf "$XDG_STATE_HOME"' EXIT INT TERM
die() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
. "$ROOT_DIR/lib/provider.sh"

assert_eq() {
  _field=$1 _expected=$2 _actual=$3
  [ "$_actual" = "$_expected" ] || {
    printf 'FAIL  %s: expected <%s>, got <%s>\n' "$_field" "$_expected" "$_actual" >&2
    exit 1
  }
}

assert_word() {
  case " $3 " in
    *" $2 "*) ;;
    *) die "$1: missing allowlisted $2" ;;
  esac
}

load() { load_provider "$1"; }

[ ! -e "$PROVIDERS_DIR/openai.sh" ] || die "OpenAI has no official Anthropic Messages endpoint; remove the invalid provider"
[ ! -e "$PROVIDERS_DIR/baichuan.sh" ] || die "Baichuan exposes OpenAI compatibility only; remove the invalid provider"

load anthropic
assert_eq anthropic.auth env "$AUTH_MODE"
assert_eq anthropic.auth-env ANTHROPIC_API_KEY "$AUTH_REFERENCE"
assert_eq anthropic.auth-header x-api-key "$_AUTH_SCHEME"
assert_eq anthropic.context '' "$CONTEXT_TOKENS"
assert_eq anthropic.opus claude-opus-5-5 "$MODEL_OPUS"
assert_eq anthropic.extras claude-fable-5-1 "$MODEL_ALIASES"

load openrouter
assert_eq openrouter.model nvidia/nemotron-3-ultra-550b-a55b:free "$MODEL"
assert_eq openrouter.context 1000000 "$CONTEXT_TOKENS"
assert_eq openrouter.auto-compact 786432 "$AUTO_COMPACT_TOKENS"
assert_eq openrouter.effort max "$EFFORT"

load ollama
assert_eq ollama.base http://127.0.0.1:11435 "$BASE_URL"
assert_eq ollama.model qwen3.8-27b "$MODEL"
assert_eq ollama.context-fallback 65536 "$CONTEXT_TOKENS"
assert_eq ollama.context-override "deepseek-v4-flash:q8=373760 deepseek-v4-flash=373760 qwen3.8-27b=262144 qwen3.8-27b-heretic:q4=262144 qwen3.8-27b-heretic:q4-dflash=262144 qwen3.8-27b-heretic=262144" "$MODEL_CONTEXT_OVERRIDES"
assert_eq ollama.self-route "deepseek-v4-flash:q8 deepseek-v4-flash qwen3.8-27b qwen3.8-27b-heretic:q4 qwen3.8-27b-heretic:q4-dflash qwen3.8-27b-heretic" "$MODEL_SELF_ROUTE_MODELS"
assert_eq ollama.effort max "$EFFORT"
printf '%s\n' "$EXTRA_ENV" | grep -q '^ANTHROPIC_AUTH_TOKEN=ollama$' || die "ollama auth token mismatch"
printf '%s\n' "$EXTRA_ENV" | grep -q '^ANTHROPIC_API_KEY=$' || die "ollama API key must be blank"
printf '%s\n' "$EXTRA_ENV" | grep -q '^API_TIMEOUT_MS=1800000$' || die "ollama API timeout mismatch"
printf '%s\n' "$EXTRA_ENV" | grep -q '^CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000$' || die "ollama stream timeout mismatch"
printf '%s\n' "$PRE_START" | grep -q 'OLLAMA_HEARTBEAT_INTERVAL_MS=60000' || die "ollama heartbeat interval mismatch"
printf '%s\n' "$PRE_START" | grep -q 'assets/plugins/qwen-local-multimodal' || die "Qwen multimodal session skill missing"
printf '%s\n' "$PRE_START" | grep -q 'MLX-VLM not reachable' || die "Qwen route does not require MLX-VLM"
printf '%s\n' "$POST_STOP" | grep -q '_OLLAMA_HEARTBEAT_PROXY_PID' || die "ollama heartbeat lifecycle cleanup missing"
assert_eq ollama.health http://127.0.0.1:11435/health "$HEALTH_CHECK_URL"

load bedrock
assert_eq bedrock.base native://amazon-bedrock "$BASE_URL"
assert_eq bedrock.auth native "$AUTH_MODE"
assert_eq bedrock.backend bedrock "$NATIVE_BACKEND"
assert_eq bedrock.model sonnet "$MODEL"
for _name in CLAUDE_CONFIG_DIR AWS_SHARED_CREDENTIALS_FILE AWS_CONFIG_FILE ANTHROPIC_BEDROCK_BASE_URL ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL; do
  assert_word bedrock.passthrough "$_name" "$PASSTHROUGH_ENV"
done

load vertex
assert_eq vertex.base native://google-vertex-ai "$BASE_URL"
assert_eq vertex.auth native "$AUTH_MODE"
assert_eq vertex.backend vertex "$NATIVE_BACKEND"
assert_eq vertex.model sonnet "$MODEL"
for _name in CLAUDE_CONFIG_DIR ANTHROPIC_VERTEX_BASE_URL ANTHROPIC_VERTEX_PROJECT_ID ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL; do
  assert_word vertex.passthrough "$_name" "$PASSTHROUGH_ENV"
done

load foundry
assert_eq foundry.base native://microsoft-foundry "$BASE_URL"
assert_eq foundry.auth native "$AUTH_MODE"
assert_eq foundry.backend foundry "$NATIVE_BACKEND"
assert_eq foundry.model sonnet "$MODEL"
assert_eq foundry.opus opus "$MODEL_OPUS"
assert_eq foundry.sonnet sonnet "$MODEL_SONNET"
assert_eq foundry.haiku haiku "$MODEL_HAIKU"
assert_eq foundry.extra CLAUDE_CODE_USE_FOUNDRY=1 "$EXTRA_ENV"
for _name in CLAUDE_CONFIG_DIR ANTHROPIC_FOUNDRY_RESOURCE ANTHROPIC_FOUNDRY_BASE_URL ANTHROPIC_FOUNDRY_API_KEY ANTHROPIC_FOUNDRY_AUTH_TOKEN ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL AZURE_CONFIG_DIR AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_CLIENT_SECRET; do
  assert_word foundry.passthrough "$_name" "$PASSTHROUGH_ENV"
done

load minimax
assert_eq minimax.auth surfaces "$AUTH_MODE"
assert_eq minimax.model MiniMax-M3 "$MODEL"
assert_eq minimax.base https://api.minimax.cn/anthropic "$BASE_URL"
assert_eq minimax.context 1000000 "$CONTEXT_TOKENS"
assert_eq minimax.auto-compact 1000000 "$AUTO_COMPACT_TOKENS"
assert_eq minimax.plan.url https://api.minimax.cn/anthropic "$PLAN_URL"
assert_eq minimax.plan.key-env MINIMAX_TOKEN_PLAN_KEY "$PLAN_KEY_ENV"
assert_eq minimax.plan.key-service codex-minimax-token-plan "$PLAN_KEYS"
assert_eq minimax.api.url https://api.minimax.cn/anthropic "$API_URL"
assert_eq minimax.api.key-env MINIMAX_API_KEY "$API_KEY_ENV"
assert_eq minimax.api.key-service minimax-api-key "$API_KEYS"
assert_eq minimax.plan.auth bearer "$PLAN_AUTH_TYPE"
assert_eq minimax.api.auth bearer "$API_AUTH_TYPE"
assert_eq minimax.assets minimax "$ASSET_PROFILE"

load moonshot
assert_eq kimi.auth surfaces "$AUTH_MODE"
assert_eq kimi.model k3-256k "$MODEL"
assert_eq kimi.context 262144 "$CONTEXT_TOKENS"
assert_eq kimi.plan.url https://api.kimi.com/coding/ "$PLAN_URL"
assert_eq kimi.plan.auth x-api-key "$PLAN_AUTH_TYPE"
assert_eq kimi.plan.key-env KIMI_CODE_KEY "$PLAN_KEY_ENV"
assert_eq kimi.plan.key-service moonshot-coding-1 "$PLAN_KEYS"
assert_eq kimi.api.url '' "$API_URL"
assert_eq kimi.assets empty "$ASSET_PROFILE"

load z-ai
assert_eq zai.auth surfaces "$AUTH_MODE"
assert_eq zai.model 'glm-5.3[1m]' "$MODEL"
assert_eq zai.haiku 'glm-5.3-flash[1m]' "$MODEL_HAIKU"
assert_eq zai.context 1000000 "$CONTEXT_TOKENS"
assert_eq zai.auto-compact 1000000 "$AUTO_COMPACT_TOKENS"
assert_eq zai.plan.url https://api.z.ai/api/anthropic "$PLAN_URL"
assert_eq zai.plan.key-env Z_AI_CODING_PLAN_KEY "$PLAN_KEY_ENV"
assert_eq zai.plan.key-service z-ai-coding-plan "$PLAN_KEYS"
assert_eq zai.api.url https://api.z.ai/api/anthropic "$API_URL"
assert_eq zai.api.key-env Z_AI_API_KEY "$API_KEY_ENV"
assert_eq zai.api.key-service z-ai-api-key "$API_KEYS"
assert_eq zai.assets zai "$ASSET_PROFILE"

load dashscope
assert_eq dashscope.auth surfaces "$AUTH_MODE"
assert_eq dashscope.model qwen3.8-max "$MODEL"
assert_eq dashscope.haiku qwen3.6-flash "$MODEL_HAIKU"
assert_eq dashscope.subagent qwen3.7-max "$MODEL_SUBAGENT"
assert_eq dashscope.context 983616 "$CONTEXT_TOKENS"
assert_eq dashscope.plan.url https://token-plan.cn-beijing.maas.aliyuncs.com/apps/anthropic "$PLAN_URL"
assert_eq dashscope.api.url https://dashscope.aliyuncs.com/apps/anthropic "$API_URL"
assert_eq dashscope.api.model qwen3.7-max "$API_MODEL"

DASHSCOPE_API_URL=https://workspace-id.cn-beijing.maas.aliyuncs.com/apps/anthropic
export DASHSCOPE_API_URL
load dashscope
assert_eq dashscope.api.override "$DASHSCOPE_API_URL" "$API_URL"
unset DASHSCOPE_API_URL

load dashscope-coding
assert_eq dashscope-coding.auth surfaces "$AUTH_MODE"
assert_eq dashscope-coding.model qwen3.8-plus "$MODEL"
assert_eq dashscope-coding.context 983616 "$CONTEXT_TOKENS"
assert_eq dashscope-coding.auto-compact 983616 "$AUTO_COMPACT_TOKENS"
assert_eq dashscope-coding.plan.url https://coding.dashscope.aliyuncs.com/apps/anthropic "$PLAN_URL"
assert_eq dashscope-coding.plan.key-env DASHSCOPE_CODING_PLAN_KEY "$PLAN_KEY_ENV"
assert_eq dashscope-coding.plan.key-service dashscope-coding-plan "$PLAN_KEYS"
assert_eq dashscope-coding.api.url '' "$API_URL"
assert_eq dashscope-coding.assets dashscope-coding "$ASSET_PROFILE"

load deepseek
assert_eq deepseek.auth surfaces "$AUTH_MODE"
assert_eq deepseek.model 'deepseek-flash[1m]' "$MODEL"
assert_eq deepseek.opus 'deepseek-flash[1m]' "$MODEL_OPUS"
assert_eq deepseek.sonnet 'deepseek-flash[1m]' "$MODEL_SONNET"
assert_eq deepseek.haiku deepseek-flash "$MODEL_HAIKU"
assert_eq deepseek.subagent deepseek-flash "$MODEL_SUBAGENT"
assert_eq deepseek.legacy-alias 'deepseek-v4.1-flash deepseek-v4.1 deepseek-v4-pro deepseek-v4-flash' "$MODEL_ALIASES"
assert_eq deepseek.context 1000000 "$CONTEXT_TOKENS"
assert_eq deepseek.auto-compact 786432 "$AUTO_COMPACT_TOKENS"
assert_eq deepseek.api.url https://api.deepseek.com/anthropic "$API_URL"
assert_eq deepseek.api.auth x-api-key "$API_AUTH_TYPE"
assert_eq deepseek.api.model deepseek-flash "$API_MODEL"
assert_eq deepseek.api.haiku deepseek-flash "$API_MODEL_HAIKU"
assert_eq deepseek.api.subagent deepseek-flash "$API_MODEL_SUBAGENT"

load siliconflow
assert_eq siliconflow.auth surfaces "$AUTH_MODE"
assert_eq siliconflow.model Pro/moonshotai/Kimi-K2.7-Code "$MODEL"
assert_eq siliconflow.context '' "$CONTEXT_TOKENS"
assert_eq siliconflow.api.url https://api.siliconflow.cn "$API_URL"
assert_eq siliconflow.api.auth bearer "$API_AUTH_TYPE"
assert_eq siliconflow.api.key-env SILICONFLOW_API_KEY "$API_KEY_ENV"

load fireworks
assert_eq fireworks.auth surfaces "$AUTH_MODE"
assert_eq fireworks.model accounts/fireworks/models/glm-5p3-flash "$MODEL"
assert_eq fireworks.context '' "$CONTEXT_TOKENS"
assert_eq fireworks.api.url https://api.fireworks.ai/inference "$API_URL"
assert_eq fireworks.api.auth bearer "$API_AUTH_TYPE"
assert_eq fireworks.api.key-env FIREWORKS_API_KEY "$API_KEY_ENV"
assert_eq fireworks.api.model accounts/fireworks/models/glm-5p3-flash "$API_MODEL"

load vercel
assert_eq vercel.auth surfaces "$AUTH_MODE"
assert_eq vercel.model anthropic/claude-sonnet-5 "$MODEL"
assert_eq vercel.opus anthropic/claude-opus-5.5 "$MODEL_OPUS"
assert_eq vercel.haiku anthropic/claude-haiku-4.5 "$MODEL_HAIKU"
assert_eq vercel.context '' "$CONTEXT_TOKENS"
assert_eq vercel.api.url https://ai-gateway.vercel.sh "$API_URL"
assert_eq vercel.api.auth bearer "$API_AUTH_TYPE"
assert_eq vercel.api.key-env AI_GATEWAY_API_KEY "$API_KEY_ENV"
assert_eq vercel.api.opus anthropic/claude-opus-5.5 "$API_MODEL_OPUS"
assert_eq vercel.api.haiku anthropic/claude-haiku-4.5 "$API_MODEL_HAIKU"

load longcat
assert_eq longcat.auth surfaces "$AUTH_MODE"
assert_eq longcat.model LongCat-2.5-Preview "$MODEL"
assert_eq longcat.context 1000000 "$CONTEXT_TOKENS"
assert_eq longcat.alias LongCat-2.0 "$MODEL_ALIASES"
assert_eq longcat.api.url https://api.longcat.chat/anthropic "$API_URL"
assert_eq longcat.api.auth bearer "$API_AUTH_TYPE"
assert_eq longcat.api.key-env LONGCAT_API_KEY "$API_KEY_ENV"
assert_eq longcat.api.model LongCat-2.5-Preview "$API_MODEL"

load meta
assert_eq meta.auth surfaces "$AUTH_MODE"
assert_eq meta.base https://api.meta.ai "$BASE_URL"
assert_eq meta.model muse-spark-1.3 "$MODEL"
assert_eq meta.opus muse-spark-1.3 "$MODEL_OPUS"
assert_eq meta.sonnet muse-spark-1.3 "$MODEL_SONNET"
assert_eq meta.haiku muse-spark-1.3 "$MODEL_HAIKU"
assert_eq meta.subagent muse-spark-1.3 "$MODEL_SUBAGENT"
assert_eq meta.context 1048576 "$CONTEXT_TOKENS"
assert_eq meta.api.url https://api.meta.ai "$API_URL"
assert_eq meta.api.auth bearer "$API_AUTH_TYPE"
assert_eq meta.api.key-env MODEL_API_KEY "$API_KEY_ENV"
assert_eq meta.api.key-service meta-model-api-key "$API_KEYS"
assert_eq meta.api.model muse-spark-1.3 "$API_MODEL"
printf '%s\n' "$EXTRA_ENV" | grep -qx 'ENABLE_TOOL_SEARCH=true' || die "Meta Claude Code tool search is disabled"

load requesty
assert_eq requesty.auth surfaces "$AUTH_MODE"
assert_eq requesty.base https://router.requesty.ai "$BASE_URL"
assert_eq requesty.model anthropic/claude-sonnet-5 "$MODEL"
assert_eq requesty.opus anthropic/claude-opus-5-5 "$MODEL_OPUS"
assert_eq requesty.sonnet anthropic/claude-sonnet-5 "$MODEL_SONNET"
assert_eq requesty.haiku anthropic/claude-haiku-4-5 "$MODEL_HAIKU"
assert_eq requesty.subagent anthropic/claude-haiku-4-5 "$MODEL_SUBAGENT"
assert_eq requesty.context '' "$CONTEXT_TOKENS"
assert_eq requesty.api.url https://router.requesty.ai "$API_URL"
assert_eq requesty.api.auth bearer "$API_AUTH_TYPE"
assert_eq requesty.api.key-env REQUESTY_API_KEY "$API_KEY_ENV"
assert_eq requesty.api.key-service requesty-api-key "$API_KEYS"
assert_eq requesty.api.opus anthropic/claude-opus-5-5 "$API_MODEL_OPUS"
assert_eq requesty.api.sonnet anthropic/claude-sonnet-5 "$API_MODEL_SONNET"
assert_eq requesty.api.haiku anthropic/claude-haiku-4-5 "$API_MODEL_HAIKU"
assert_eq requesty.api.subagent anthropic/claude-haiku-4-5 "$API_MODEL_SUBAGENT"

load nagaai
assert_eq nagaai.auth surfaces "$AUTH_MODE"
assert_eq nagaai.base https://api.naga.ac "$BASE_URL"
assert_eq nagaai.model claude-sonnet-4.5 "$MODEL"
assert_eq nagaai.opus claude-opus-4.5 "$MODEL_OPUS"
assert_eq nagaai.sonnet claude-sonnet-4.5 "$MODEL_SONNET"
assert_eq nagaai.haiku claude-haiku-4.5 "$MODEL_HAIKU"
assert_eq nagaai.subagent claude-haiku-4.5 "$MODEL_SUBAGENT"
assert_eq nagaai.context '' "$CONTEXT_TOKENS"
assert_eq nagaai.api.url https://api.naga.ac "$API_URL"
assert_eq nagaai.api.auth bearer "$API_AUTH_TYPE"
assert_eq nagaai.api.key-env NAGAAI_API_KEY "$API_KEY_ENV"
assert_eq nagaai.api.key-service nagaai-api-key "$API_KEYS"
assert_eq nagaai.api.opus claude-opus-4.5 "$API_MODEL_OPUS"
assert_eq nagaai.api.sonnet claude-sonnet-4.5 "$API_MODEL_SONNET"
assert_eq nagaai.api.haiku claude-haiku-4.5 "$API_MODEL_HAIKU"
assert_eq nagaai.api.subagent claude-haiku-4.5 "$API_MODEL_SUBAGENT"
printf '%s\n' "$EXTRA_ENV" | grep -qx 'ANTHROPIC_API_KEY=' || die "NagaAI requires blank Anthropic API key"

load 302ai
assert_eq 302ai.auth surfaces "$AUTH_MODE"
assert_eq 302ai.model claude-sonnet-5 "$MODEL"
assert_eq 302ai.opus claude-opus-5-5 "$MODEL_OPUS"
assert_eq 302ai.sonnet claude-sonnet-5 "$MODEL_SONNET"
assert_eq 302ai.haiku claude-haiku-4-5-20251001 "$MODEL_HAIKU"
assert_eq 302ai.context 1000000 "$CONTEXT_TOKENS"
assert_eq 302ai.extras claude-fable-5 "$MODEL_ALIASES"
assert_eq 302ai.plan.url '' "$PLAN_URL"
assert_eq 302ai.api.url https://api.302.ai "$API_URL"
assert_eq 302ai.api.auth x-api-key "$API_AUTH_TYPE"
assert_eq 302ai.api.key-env AI302_API_KEY "$API_KEY_ENV"
assert_eq 302ai.api.opus claude-opus-5-5 "$API_MODEL_OPUS"
assert_eq 302ai.api.sonnet claude-sonnet-5 "$API_MODEL_SONNET"
assert_eq 302ai.api.haiku claude-haiku-4-5-20251001 "$API_MODEL_HAIKU"

load aihubmix
assert_eq aihubmix.auth surfaces "$AUTH_MODE"
assert_eq aihubmix.model coding-glm-5.1-free "$MODEL"
assert_eq aihubmix.context '' "$CONTEXT_TOKENS"
assert_eq aihubmix.plan.url '' "$PLAN_URL"
assert_eq aihubmix.api.url https://aihubmix.com "$API_URL"
assert_eq aihubmix.api.auth bearer "$API_AUTH_TYPE"
assert_eq aihubmix.api.key-env AIHUBMIX_API_KEY "$API_KEY_ENV"
assert_eq aihubmix.assets aihubmix "$ASSET_PROFILE"

load infini
assert_eq infini.auth surfaces "$AUTH_MODE"
assert_eq infini.model glm-5.1 "$MODEL"
assert_eq infini.context '' "$CONTEXT_TOKENS"
assert_eq infini.plan.url '' "$PLAN_URL"
assert_eq infini.api.url https://cloud.infini-ai.com/maas "$API_URL"
assert_eq infini.api.auth bearer "$API_AUTH_TYPE"
assert_eq infini.api.key-env INFINI_API_KEY "$API_KEY_ENV"

load ppio
assert_eq ppio.auth surfaces "$AUTH_MODE"
assert_eq ppio.model minimax/minimax-m3 "$MODEL"
assert_eq ppio.context 1000000 "$CONTEXT_TOKENS"
assert_eq ppio.extras zai-org/glm-5.2 "$MODEL_ALIASES"
assert_eq ppio.plan.url '' "$PLAN_URL"
assert_eq ppio.api.url https://api.ppio.com/anthropic "$API_URL"
assert_eq ppio.api.auth bearer "$API_AUTH_TYPE"
assert_eq ppio.api.key-env PPIO_API_KEY "$API_KEY_ENV"
assert_eq ppio.api.model minimax/minimax-m3 "$API_MODEL"
assert_eq ppio.assets ppio "$ASSET_PROFILE"

load stepfun
assert_eq stepfun.auth surfaces "$AUTH_MODE"
assert_eq stepfun.model step-5-preview "$MODEL"
assert_eq stepfun.context 1000000 "$CONTEXT_TOKENS"
assert_eq stepfun.plan.url https://api.stepfun.com/step_plan "$PLAN_URL"
assert_eq stepfun.api.url https://api.stepfun.com "$API_URL"
assert_eq stepfun.assets stepfun "$ASSET_PROFILE"

load volcengine
assert_eq volcengine.auth surfaces "$AUTH_MODE"
assert_eq volcengine.model doubao-seed-evolving "$MODEL"
assert_eq volcengine.context 1000000 "$CONTEXT_TOKENS"
assert_eq volcengine.plan.url https://ark.cn-beijing.volces.com/api/plan "$PLAN_URL"
assert_eq volcengine.plan.key-env VOLCENGINE_PLAN_KEY "$PLAN_KEY_ENV"
assert_eq volcengine.plan.key-services 'volcengine-agent-plan volcengine-plan' "$PLAN_KEYS"
assert_eq volcengine.assets volcengine "$ASSET_PROFILE"

load volcengine-coding
assert_eq volcengine-coding.auth surfaces "$AUTH_MODE"
assert_eq volcengine-coding.model doubao-seed-evolving "$MODEL"
assert_eq volcengine-coding.context 1000000 "$CONTEXT_TOKENS"
assert_eq volcengine-coding.plan.url https://ark.cn-beijing.volces.com/api/coding "$PLAN_URL"
assert_eq volcengine-coding.plan.key-env VOLCENGINE_CODING_PLAN_KEY "$PLAN_KEY_ENV"
assert_eq volcengine-coding.plan.key-service volcengine-coding-plan "$PLAN_KEYS"
assert_eq volcengine-coding.assets volcengine-coding "$ASSET_PROFILE"

# Subscription keys must never be silently sent to the other plan endpoint.
# Stub Keychain discovery so this test is independent of a developer's account.
check_volcengine_credential_isolation() (
  . "$ROOT_DIR/lib/auth.sh"
  kc_get() { return 1; }
  unset VOLCENGINE_PLAN_KEY VOLCENGINE_AGENT_PLAN_KEY VOLCENGINE_CODING_PLAN_KEY
  unset VOLCANO_ENGINE_API_KEY ARK_API_KEY VOLCENGINE_API_KEY

  VOLCENGINE_CODING_PLAN_KEY=coding-fixture
  export VOLCENGINE_CODING_PLAN_KEY
  load volcengine
  resolve_surface_tokens 1
  assert_eq agent.reject-coding-key 0 "$_SURFACE_COUNT"
  unset VOLCENGINE_CODING_PLAN_KEY

  VOLCANO_ENGINE_API_KEY=generic-fixture
  ARK_API_KEY=generic-fixture
  VOLCENGINE_API_KEY=generic-fixture
  export VOLCANO_ENGINE_API_KEY ARK_API_KEY VOLCENGINE_API_KEY
  load volcengine
  resolve_surface_tokens 1
  assert_eq agent.reject-generic-keys 0 "$_SURFACE_COUNT"
  load volcengine-coding
  resolve_surface_tokens 1
  assert_eq coding.reject-generic-keys 0 "$_SURFACE_COUNT"
  unset VOLCANO_ENGINE_API_KEY ARK_API_KEY VOLCENGINE_API_KEY

  VOLCENGINE_AGENT_PLAN_KEY=agent-fixture
  export VOLCENGINE_AGENT_PLAN_KEY
  load volcengine
  resolve_surface_tokens 1
  assert_eq agent.accept-alias 1 "$_SURFACE_COUNT"
  assert_eq agent.alias-token agent-fixture "$_PLAN_FIRST_TOKEN"
  load volcengine-coding
  resolve_surface_tokens 1
  assert_eq coding.reject-agent-key 0 "$_SURFACE_COUNT"
  unset VOLCENGINE_AGENT_PLAN_KEY VOLCENGINE_PLAN_KEY

  kc_get() { [ "$1" = volcengine-coding-plan ] && printf 'coding-keychain-fixture'; }
  load volcengine
  resolve_surface_tokens 1
  assert_eq agent.reject-coding-keychain 0 "$_SURFACE_COUNT"
)
check_volcengine_credential_isolation

load tencent
assert_eq tencent.auth surfaces "$AUTH_MODE"
assert_eq tencent.model tc-code-latest "$MODEL"
assert_eq tencent.context 262144 "$CONTEXT_TOKENS"
assert_eq tencent.haiku deepseek-v4-flash-202605 "$MODEL_HAIKU"
assert_eq tencent.plan.url https://api.lkeap.cloud.tencent.com/plan/anthropic "$PLAN_URL"
assert_eq tencent.api.url https://tokenhub.tencentmaas.com "$API_URL"
assert_eq tencent.api.model hy3 "$API_MODEL"

load tencent-coding
assert_eq tencent-coding.auth surfaces "$AUTH_MODE"
assert_eq tencent-coding.model tc-code-latest "$MODEL"
assert_eq tencent-coding.context 262144 "$CONTEXT_TOKENS"
assert_eq tencent-coding.haiku tc-code-latest "$MODEL_HAIKU"
assert_eq tencent-coding.plan.url https://api.lkeap.cloud.tencent.com/coding/anthropic "$PLAN_URL"
assert_eq tencent-coding.plan.key-env TENCENT_CODING_PLAN_KEY "$PLAN_KEY_ENV"
assert_eq tencent-coding.plan.key-service tencent-coding-plan "$PLAN_KEYS"
assert_eq tencent-coding.api.url '' "$API_URL"
assert_eq tencent-coding.assets tencent "$ASSET_PROFILE"

load qianfan
assert_eq qianfan.auth surfaces "$AUTH_MODE"
assert_eq qianfan.model deepseek-v4-pro "$MODEL"
assert_eq qianfan.context 262144 "$CONTEXT_TOKENS"
assert_eq qianfan.plan.url https://qianfan.baidubce.com/anthropic/tokenplan/personal "$PLAN_URL"
assert_eq qianfan.plan.key-env QIANFAN_TOKEN_PLAN_KEY "$PLAN_KEY_ENV"
assert_eq qianfan.plan.key-service qianfan-token-plan "$PLAN_KEYS"
assert_eq qianfan.api.url https://qianfan.baidubce.com/anthropic "$API_URL"
assert_eq qianfan.api.model deepseek-v3.2 "$API_MODEL"

load qianfan-team
assert_eq qianfan-team.auth surfaces "$AUTH_MODE"
assert_eq qianfan-team.model deepseek-v4-flash "$MODEL"
assert_eq qianfan-team.context 262144 "$CONTEXT_TOKENS"
assert_eq qianfan-team.plan.url https://qianfan.baidubce.com/anthropic/tokenplan/team "$PLAN_URL"
assert_eq qianfan-team.plan.key-env QIANFAN_TEAM_TOKEN_PLAN_KEY "$PLAN_KEY_ENV"
assert_eq qianfan-team.plan.key-service qianfan-team-token-plan "$PLAN_KEYS"
assert_eq qianfan-team.api.url '' "$API_URL"

load qianfan-coding
assert_eq qianfan-coding.auth surfaces "$AUTH_MODE"
assert_eq qianfan-coding.model qianfan-code-latest "$MODEL"
assert_eq qianfan-coding.context 262144 "$CONTEXT_TOKENS"
assert_eq qianfan-coding.plan.url https://qianfan.baidubce.com/anthropic/coding "$PLAN_URL"
assert_eq qianfan-coding.plan.key-env QIANFAN_CODING_PLAN_KEY "$PLAN_KEY_ENV"
assert_eq qianfan-coding.plan.key-service qianfan-coding-plan "$PLAN_KEYS"
assert_eq qianfan-coding.api.url '' "$API_URL"
assert_eq qianfan-coding.assets empty "$ASSET_PROFILE"

load qiniu
assert_eq qiniu.auth surfaces "$AUTH_MODE"
assert_eq qiniu.model deepseek/deepseek-v3.2-251201 "$MODEL"
assert_eq qiniu.context '' "$CONTEXT_TOKENS"
assert_eq qiniu.plan.url https://api.qnaigc.com "$PLAN_URL"
assert_eq qiniu.plan.key-env QINIU_SUBSCRIPTION_KEY "$PLAN_KEY_ENV"
assert_eq qiniu.api.url https://api.qnaigc.com "$API_URL"
assert_eq qiniu.api.key-env QINIU_API_KEY "$API_KEY_ENV"
assert_eq qiniu.assets qiniu "$ASSET_PROFILE"

load huawei
assert_eq huawei.auth surfaces "$AUTH_MODE"
assert_eq huawei.model glm-5.3 "$MODEL"
assert_eq huawei.context 262144 "$CONTEXT_TOKENS"
assert_eq huawei.aliases 'deepseek-v4.1-flash deepseek-v4-flash glm-5.1 kimi-k2.6' "$MODEL_ALIASES"
assert_eq huawei.plan.url https://api.modelarts-maas.com/plan/anthropic "$PLAN_URL"
assert_eq huawei.api.url https://api.modelarts-maas.com/anthropic "$API_URL"

load xiaomi
assert_eq xiaomi.auth surfaces "$AUTH_MODE"
assert_eq xiaomi.model 'mimo-v2.6-pro[1m]' "$MODEL"
assert_eq xiaomi.context 1048576 "$CONTEXT_TOKENS"
assert_eq xiaomi.plan.model mimo-v2.6-pro "$PLAN_MODEL"
assert_eq xiaomi.api.model mimo-v2.6-pro "$API_MODEL"
assert_eq xiaomi.legacy-aliases 'mimo-v2.5-pro mimo-v2.5' "$MODEL_ALIASES"
assert_eq xiaomi.plan.url https://token-plan-cn.xiaomimimo.com/anthropic "$PLAN_URL"
assert_eq xiaomi.api.url https://api.xiaomimimo.com/anthropic "$API_URL"

for _provider in 302ai aihubmix fireworks vercel longcat meta requesty nagaai infini minimax moonshot ppio z-ai dashscope dashscope-coding deepseek siliconflow stepfun volcengine volcengine-coding tencent tencent-coding qianfan qianfan-team qianfan-coding qiniu huawei xiaomi; do
  load "$_provider"
  case $BASE_URL in
    */v1/messages|*/v3/messages) die "$_provider BASE_URL must be a prefix; Claude Code appends /v1/messages" ;;
  esac
done

printf 'ok    provider matrix matches audited official Anthropic-compatible contracts\n'
