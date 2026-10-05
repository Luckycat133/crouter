#!/bin/sh
# Legacy Coding Plan remains available to existing Baidu Qianfan subscribers.
PROVIDER_NAME="qianfan-coding"
PROVIDER_DESC="Baidu Qianfan legacy Coding Plan (existing subscriptions)"

# Fallback to common Baidu Qianfan env vars
if [ -z "${QIANFAN_CODING_PLAN_KEY:-}" ]; then
  if [ -n "${QIANFAN_API_KEY:-}" ]; then
    export QIANFAN_CODING_PLAN_KEY="$QIANFAN_API_KEY"
  elif [ -n "${BAIDU_API_KEY:-}" ]; then
    export QIANFAN_CODING_PLAN_KEY="$BAIDU_API_KEY"
  fi
fi

BASE_URL="https://qianfan.baidubce.com/anthropic/coding"
MODEL="qianfan-code-latest"
CONTEXT_TOKENS="262144"
MODEL_OPUS="qianfan-code-latest"
MODEL_SONNET="qianfan-code-latest"
MODEL_HAIKU="deepseek-v4-flash"
MODEL_SUBAGENT="qianfan-code-latest"
MODEL_ALIASES="kimi-k2.5 deepseek-v3.2 glm-5 minimax-m2.5 ernie-4.5-turbo-20260402 deepseek-v4-flash glm-5.1"
EFFORT="high"

AUTH_MODE="surfaces"
PLAN_URL="https://qianfan.baidubce.com/anthropic/coding"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="QIANFAN_CODING_PLAN_KEY"
PLAN_KEYS="qianfan-coding-plan"
PLAN_MODEL="qianfan-code-latest"
PLAN_MODEL_OPUS="qianfan-code-latest"
PLAN_MODEL_SONNET="qianfan-code-latest"
PLAN_MODEL_HAIKU="deepseek-v4-flash"
PLAN_MODEL_SUBAGENT="qianfan-code-latest"

ASSET_PROFILE="empty"

EXTRA_ENV="API_TIMEOUT_MS=600000
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
