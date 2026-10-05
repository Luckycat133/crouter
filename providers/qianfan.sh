#!/bin/sh
# Baidu Qianfan personal Token Plan and ordinary MaaS use separate prefixes.
PROVIDER_NAME="qianfan"
PROVIDER_DESC="Baidu Qianfan personal Token Plan and pay-as-you-go API"

# Fallback to common Baidu Qianfan env vars
if [ -z "${QIANFAN_TOKEN_PLAN_KEY:-}" ]; then
  if [ -n "${QIANFAN_API_KEY:-}" ]; then
    export QIANFAN_TOKEN_PLAN_KEY="$QIANFAN_API_KEY"
  elif [ -n "${BAIDU_API_KEY:-}" ]; then
    export QIANFAN_TOKEN_PLAN_KEY="$BAIDU_API_KEY"
  fi
fi

BASE_URL="https://qianfan.baidubce.com/anthropic/tokenplan/personal"
MODEL="deepseek-v4-pro"
CONTEXT_TOKENS="262144"
MODEL_OPUS="deepseek-v4-pro"
MODEL_SONNET="deepseek-v4-pro"
MODEL_HAIKU="deepseek-v3.2"
MODEL_SUBAGENT="deepseek-v4-pro"
MODEL_ALIASES="deepseek-v3.2"
EFFORT="high"

AUTH_MODE="surfaces"
PLAN_URL="https://qianfan.baidubce.com/anthropic/tokenplan/personal"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="QIANFAN_TOKEN_PLAN_KEY"
PLAN_KEYS="qianfan-token-plan"
PLAN_MODEL="deepseek-v4-pro"
PLAN_MODEL_OPUS="deepseek-v4-pro"
PLAN_MODEL_SONNET="deepseek-v4-pro"
PLAN_MODEL_HAIKU="deepseek-v3.2"
PLAN_MODEL_SUBAGENT="deepseek-v4-pro"

API_URL="https://qianfan.baidubce.com/anthropic"
API_AUTH_TYPE="bearer"
API_KEY_ENV="QIANFAN_API_KEY"
API_KEYS="qianfan-api-key"
API_MODEL="deepseek-v3.2"

ASSET_PROFILE="empty"
EXTRA_ENV="API_TIMEOUT_MS=600000
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
