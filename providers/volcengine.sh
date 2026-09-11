#!/bin/sh
# Volcengine Ark Agent Plan; multi-model gateway supporting Doubao, DeepSeek, GLM, Kimi, and MiniMax.
PROVIDER_NAME="volcengine"
PROVIDER_DESC="Volcengine Ark Agent Plan (Multi-Model Gateway)"

# Fallback to common Volcano Engine env vars
if [ -z "${VOLCENGINE_PLAN_KEY:-}" ]; then
  if [ -n "${VOLCENGINE_AGENT_PLAN_KEY:-}" ]; then
    export VOLCENGINE_PLAN_KEY="$VOLCENGINE_AGENT_PLAN_KEY"
  elif [ -n "${VOLCENGINE_CODING_PLAN_KEY:-}" ]; then
    export VOLCENGINE_PLAN_KEY="$VOLCENGINE_CODING_PLAN_KEY"
  elif [ -n "${VOLCANO_ENGINE_API_KEY:-}" ]; then
    export VOLCENGINE_PLAN_KEY="$VOLCANO_ENGINE_API_KEY"
  elif [ -n "${ARK_API_KEY:-}" ]; then
    export VOLCENGINE_PLAN_KEY="$ARK_API_KEY"
  elif [ -n "${VOLCENGINE_API_KEY:-}" ]; then
    export VOLCENGINE_PLAN_KEY="$VOLCENGINE_API_KEY"
  fi
fi

BASE_URL="https://ark.cn-beijing.volces.com/api/plan"
MODEL="doubao-seed-evolving"
CONTEXT_TOKENS="1000000"
AUTO_COMPACT_TOKENS="1000000"
MODEL_OPUS="doubao-seed-evolving"
MODEL_SONNET="doubao-seed-evolving"
MODEL_HAIKU="doubao-seed-2.1-turbo"
MODEL_SUBAGENT="doubao-seed-evolving"
MODEL_ALIASES="doubao-seed-2.1-turbo doubao-seed-2.0-code doubao-seed-2.0-lite doubao-seed-2.0-mini ark-code-latest deepseek-v4-pro deepseek-v4-flash glm-5.3 glm-latest glm-5.3-flash kimi-k3 kimi-k2.7-code kimi-k2.6 minimax-m3 minimax-m2.7 glm-5.3[1m] glm-5.3-flash[1m] deepseek-v4-pro[1m] deepseek-v4-flash[1m] kimi-k3[1m] doubao-seed-evolving[1m]"
MODEL_CONTEXT_OVERRIDES="kimi-k3=262144 kimi-k2.7-code=262144 kimi-k2.6=262144 doubao-seed-2.1-turbo=262144 doubao-seed-2.0-code=262144 doubao-seed-2.0-lite=262144 doubao-seed-2.0-mini=262144 minimax-m2.7=262144 deepseek-v4-flash=262144 glm-5.3-flash=262144"
MODEL_SELF_ROUTE_MODELS="$MODEL_ALIASES"
EFFORT="high"

AUTH_MODE="surfaces"
PLAN_URL="https://ark.cn-beijing.volces.com/api/plan"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="VOLCENGINE_PLAN_KEY"
PLAN_KEYS="volcengine-coding-plan volcengine-agent-plan volcengine-plan"
PLAN_MODEL="doubao-seed-evolving"
PLAN_MODEL_OPUS="doubao-seed-evolving"
PLAN_MODEL_SONNET="doubao-seed-evolving"
PLAN_MODEL_HAIKU="doubao-seed-2.1-turbo"
PLAN_MODEL_SUBAGENT="doubao-seed-evolving"

ASSET_PROFILE="volcengine"
EXTRA_ENV="API_TIMEOUT_MS=1800000
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
