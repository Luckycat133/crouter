#!/bin/sh
# Audited provider contract. Values here come from each vendor's current
# Claude Code / Anthropic-compatibility documentation, not guessed model IDs.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROVIDERS_DIR="$ROOT_DIR/providers"
die() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
. "$ROOT_DIR/lib/provider.sh"

assert_eq() {
  _field=$1 _expected=$2 _actual=$3
  [ "$_actual" = "$_expected" ] || {
    printf 'FAIL  %s: expected <%s>, got <%s>\n' "$_field" "$_expected" "$_actual" >&2
    exit 1
  }
}

load() { load_provider "$1"; }

[ ! -e "$PROVIDERS_DIR/openai.sh" ] || die "OpenAI has no official Anthropic Messages endpoint; remove the invalid provider"
[ ! -e "$PROVIDERS_DIR/baichuan.sh" ] || die "Baichuan exposes OpenAI compatibility only; remove the invalid provider"

load anthropic
assert_eq anthropic.auth env "$AUTH_MODE"
assert_eq anthropic.auth-env ANTHROPIC_API_KEY "$AUTH_REFERENCE"
assert_eq anthropic.auth-header x-api-key "$_AUTH_SCHEME"
assert_eq anthropic.context '' "$CONTEXT_TOKENS"
assert_eq anthropic.extras claude-fable-5 "$MODEL_ALIASES"

load openrouter
assert_eq openrouter.model nvidia/nemotron-3-ultra-550b-a55b:free "$MODEL"
assert_eq openrouter.context 1000000 "$CONTEXT_TOKENS"

load ollama
assert_eq ollama.base http://127.0.0.1:11435 "$BASE_URL"
assert_eq ollama.model deepseek-v4-flash:q8 "$MODEL"
assert_eq ollama.context-fallback 65536 "$CONTEXT_TOKENS"
assert_eq ollama.context-override deepseek-v4-flash:q8=373760 "$MODEL_CONTEXT_OVERRIDES"
assert_eq ollama.effort high "$EFFORT"
printf '%s\n' "$EXTRA_ENV" | grep -q '^ANTHROPIC_AUTH_TOKEN=ollama$' || die "ollama auth token mismatch"
printf '%s\n' "$EXTRA_ENV" | grep -q '^ANTHROPIC_API_KEY=$' || die "ollama API key must be blank"
printf '%s\n' "$EXTRA_ENV" | grep -q '^API_TIMEOUT_MS=1800000$' || die "ollama API timeout mismatch"
printf '%s\n' "$EXTRA_ENV" | grep -q '^CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000$' || die "ollama stream timeout mismatch"
printf '%s\n' "$PRE_START" | grep -q 'OLLAMA_HEARTBEAT_INTERVAL_MS=60000' || die "ollama heartbeat interval mismatch"
printf '%s\n' "$POST_STOP" | grep -q '_OLLAMA_HEARTBEAT_PROXY_PID' || die "ollama heartbeat lifecycle cleanup missing"
assert_eq ollama.health http://127.0.0.1:11435/health "$HEALTH_CHECK_URL"

load bedrock
assert_eq bedrock.base native://amazon-bedrock "$BASE_URL"
assert_eq bedrock.auth native "$AUTH_MODE"
assert_eq bedrock.backend bedrock "$NATIVE_BACKEND"
assert_eq bedrock.model sonnet "$MODEL"

load vertex
assert_eq vertex.base native://google-vertex-ai "$BASE_URL"
assert_eq vertex.auth native "$AUTH_MODE"
assert_eq vertex.backend vertex "$NATIVE_BACKEND"
assert_eq vertex.model sonnet "$MODEL"

load minimax
assert_eq minimax.auth surfaces "$AUTH_MODE"
assert_eq minimax.model MiniMax-M3 "$MODEL"
assert_eq minimax.context 1048576 "$CONTEXT_TOKENS"
assert_eq minimax.plan.url https://api.minimaxi.com/anthropic "$PLAN_URL"
assert_eq minimax.api.url https://api.minimaxi.com/anthropic "$API_URL"
assert_eq minimax.plan.auth bearer "$PLAN_AUTH_TYPE"
assert_eq minimax.api.auth bearer "$API_AUTH_TYPE"
assert_eq minimax.assets minimax "$ASSET_PROFILE"

load moonshot
assert_eq kimi.auth surfaces "$AUTH_MODE"
assert_eq kimi.model k3-256k "$MODEL"
assert_eq kimi.context 262144 "$CONTEXT_TOKENS"
assert_eq kimi.plan.url https://api.kimi.com/coding/ "$PLAN_URL"
assert_eq kimi.plan.auth x-api-key "$PLAN_AUTH_TYPE"
assert_eq kimi.api.url '' "$API_URL"

load z-ai
assert_eq zai.auth surfaces "$AUTH_MODE"
assert_eq zai.model 'glm-5.2[1m]' "$MODEL"
assert_eq zai.haiku glm-4.7 "$MODEL_HAIKU"
assert_eq zai.context 1000000 "$CONTEXT_TOKENS"
assert_eq zai.plan.url https://api.z.ai/api/anthropic "$PLAN_URL"
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
assert_eq dashscope-coding.model qwen3.7-plus "$MODEL"
assert_eq dashscope-coding.plan.url https://coding.dashscope.aliyuncs.com/apps/anthropic "$PLAN_URL"

load deepseek
assert_eq deepseek.auth surfaces "$AUTH_MODE"
assert_eq deepseek.model 'deepseek-v4-pro[1m]' "$MODEL"
assert_eq deepseek.opus 'deepseek-v4-pro[1m]' "$MODEL_OPUS"
assert_eq deepseek.sonnet 'deepseek-v4-pro[1m]' "$MODEL_SONNET"
assert_eq deepseek.haiku deepseek-v4-flash "$MODEL_HAIKU"
assert_eq deepseek.subagent deepseek-v4-flash "$MODEL_SUBAGENT"
assert_eq deepseek.context 1000000 "$CONTEXT_TOKENS"
assert_eq deepseek.auto-compact 786432 "$AUTO_COMPACT_TOKENS"
assert_eq deepseek.api.url https://api.deepseek.com/anthropic "$API_URL"
assert_eq deepseek.api.auth x-api-key "$API_AUTH_TYPE"
assert_eq deepseek.api.model deepseek-v4-pro "$API_MODEL"

load siliconflow
assert_eq siliconflow.auth surfaces "$AUTH_MODE"
assert_eq siliconflow.model Pro/moonshotai/Kimi-K2.6 "$MODEL"
assert_eq siliconflow.context '' "$CONTEXT_TOKENS"
assert_eq siliconflow.api.url https://api.siliconflow.cn "$API_URL"
assert_eq siliconflow.api.auth bearer "$API_AUTH_TYPE"
assert_eq siliconflow.api.key-env SILICONFLOW_API_KEY "$API_KEY_ENV"

load 302ai
assert_eq 302ai.auth surfaces "$AUTH_MODE"
assert_eq 302ai.model claude-sonnet-5 "$MODEL"
assert_eq 302ai.opus claude-opus-5 "$MODEL_OPUS"
assert_eq 302ai.sonnet claude-sonnet-5 "$MODEL_SONNET"
assert_eq 302ai.haiku claude-haiku-4-5-20251001 "$MODEL_HAIKU"
assert_eq 302ai.context 1000000 "$CONTEXT_TOKENS"
assert_eq 302ai.extras claude-fable-5 "$MODEL_ALIASES"
assert_eq 302ai.plan.url '' "$PLAN_URL"
assert_eq 302ai.api.url https://api.302.ai "$API_URL"
assert_eq 302ai.api.auth x-api-key "$API_AUTH_TYPE"
assert_eq 302ai.api.key-env AI302_API_KEY "$API_KEY_ENV"
assert_eq 302ai.api.opus claude-opus-5 "$API_MODEL_OPUS"
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
assert_eq stepfun.model step-3.7-flash "$MODEL"
assert_eq stepfun.context 262144 "$CONTEXT_TOKENS"
assert_eq stepfun.plan.url https://api.stepfun.com/step_plan "$PLAN_URL"
assert_eq stepfun.api.url https://api.stepfun.com "$API_URL"
assert_eq stepfun.assets stepfun "$ASSET_PROFILE"

load volcengine
assert_eq volcengine.auth surfaces "$AUTH_MODE"
assert_eq volcengine.model doubao-seed-2.0-code "$MODEL"
assert_eq volcengine.context '' "$CONTEXT_TOKENS"
assert_eq volcengine.plan.url https://ark.cn-beijing.volces.com/api/coding "$PLAN_URL"
assert_eq volcengine.assets volcengine "$ASSET_PROFILE"

load tencent
assert_eq tencent.auth surfaces "$AUTH_MODE"
assert_eq tencent.model tc-code-latest "$MODEL"
assert_eq tencent.plan.url https://api.lkeap.cloud.tencent.com/plan/anthropic "$PLAN_URL"
assert_eq tencent.api.url https://tokenhub.tencentmaas.com "$API_URL"
assert_eq tencent.api.model hy3 "$API_MODEL"

load tencent-coding
assert_eq tencent-coding.plan.url https://api.lkeap.cloud.tencent.com/coding/anthropic "$PLAN_URL"

load qianfan
assert_eq qianfan.auth surfaces "$AUTH_MODE"
assert_eq qianfan.model deepseek-v4-pro "$MODEL"
assert_eq qianfan.plan.url https://qianfan.baidubce.com/anthropic/tokenplan/personal "$PLAN_URL"
assert_eq qianfan.plan.key-env QIANFAN_TOKEN_PLAN_KEY "$PLAN_KEY_ENV"
assert_eq qianfan.plan.key-service qianfan-token-plan "$PLAN_KEYS"
assert_eq qianfan.api.url https://qianfan.baidubce.com/anthropic "$API_URL"
assert_eq qianfan.api.model deepseek-v3.2 "$API_MODEL"

load qianfan-team
assert_eq qianfan-team.auth surfaces "$AUTH_MODE"
assert_eq qianfan-team.model deepseek-v3.2 "$MODEL"
assert_eq qianfan-team.plan.url https://qianfan.baidubce.com/anthropic/tokenplan/team "$PLAN_URL"
assert_eq qianfan-team.plan.key-env QIANFAN_TEAM_TOKEN_PLAN_KEY "$PLAN_KEY_ENV"
assert_eq qianfan-team.plan.key-service qianfan-team-token-plan "$PLAN_KEYS"
assert_eq qianfan-team.api.url '' "$API_URL"

load qianfan-coding
assert_eq qianfan-coding.auth surfaces "$AUTH_MODE"
assert_eq qianfan-coding.model qianfan-code-latest "$MODEL"
assert_eq qianfan-coding.plan.url https://qianfan.baidubce.com/anthropic/coding "$PLAN_URL"
assert_eq qianfan-coding.plan.key-env QIANFAN_CODING_PLAN_KEY "$PLAN_KEY_ENV"
assert_eq qianfan-coding.plan.key-service qianfan-coding-plan "$PLAN_KEYS"
assert_eq qianfan-coding.api.url '' "$API_URL"

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
assert_eq huawei.model glm-5.1 "$MODEL"
assert_eq huawei.plan.url https://api.modelarts-maas.com/plan/anthropic "$PLAN_URL"
assert_eq huawei.api.url https://api.modelarts-maas.com/anthropic "$API_URL"

load xiaomi
assert_eq xiaomi.auth surfaces "$AUTH_MODE"
assert_eq xiaomi.model 'mimo-v2.5-pro[1m]' "$MODEL"
assert_eq xiaomi.context 1048576 "$CONTEXT_TOKENS"
assert_eq xiaomi.plan.model mimo-v2.5-pro "$PLAN_MODEL"
assert_eq xiaomi.api.model mimo-v2.5-pro "$API_MODEL"
assert_eq xiaomi.plan.url https://token-plan-cn.xiaomimimo.com/anthropic "$PLAN_URL"
assert_eq xiaomi.api.url https://api.xiaomimimo.com/anthropic "$API_URL"

for _provider in 302ai aihubmix infini minimax moonshot ppio z-ai dashscope dashscope-coding deepseek siliconflow stepfun volcengine tencent tencent-coding qianfan qianfan-team qianfan-coding qiniu huawei xiaomi; do
  load "$_provider"
  case $BASE_URL in
    */v1/messages|*/v3/messages) die "$_provider BASE_URL must be a prefix; Claude Code appends /v1/messages" ;;
  esac
done

printf 'ok    provider matrix matches audited official Anthropic-compatible contracts\n'
