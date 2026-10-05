#!/bin/sh
# Tencent personal Token Plan and TokenHub pay-as-you-go are isolated surfaces.
PROVIDER_NAME="tencent"
PROVIDER_DESC="Tencent Cloud Token Plan and TokenHub API"

# Fallback to common Tencent Cloud env vars
if [ -z "${TENCENT_TOKEN_PLAN_KEY:-}" ]; then
  if [ -n "${TENCENT_API_KEY:-}" ]; then
    export TENCENT_TOKEN_PLAN_KEY="$TENCENT_API_KEY"
  elif [ -n "${TENCENTCLOUD_API_KEY:-}" ]; then
    export TENCENT_TOKEN_PLAN_KEY="$TENCENTCLOUD_API_KEY"
  fi
fi

BASE_URL="https://api.lkeap.cloud.tencent.com/plan/anthropic"
MODEL="tc-code-latest"
CONTEXT_TOKENS="262144"
MODEL_OPUS="tc-code-latest"
MODEL_SONNET="tc-code-latest"
MODEL_HAIKU="deepseek-v4-flash-202605"
MODEL_SUBAGENT="tc-code-latest"
MODEL_ALIASES="hy4-preview hy3 glm-5.3 glm-5.2 glm-5.1 glm-5 minimax-m2.7 deepseek-v4-flash-202605 deepseek-v4-pro-202606"
EFFORT="high"

AUTH_MODE="surfaces"
PLAN_URL="https://api.lkeap.cloud.tencent.com/plan/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="TENCENT_TOKEN_PLAN_KEY"
PLAN_KEYS="tencent-token-plan"
PLAN_MODEL="tc-code-latest"
PLAN_MODEL_OPUS="tc-code-latest"
PLAN_MODEL_SONNET="tc-code-latest"
PLAN_MODEL_HAIKU="deepseek-v4-flash-202605"
PLAN_MODEL_SUBAGENT="tc-code-latest"

API_URL="https://tokenhub.tencentmaas.com"
API_AUTH_TYPE="bearer"
API_KEY_ENV="TENCENT_API_KEY"
API_KEYS="tencent-api-key"
API_MODEL="hy3"

ASSET_PROFILE="tencent"
EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
ENABLE_TOOL_SEARCH=false"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
