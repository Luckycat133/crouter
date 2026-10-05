#!/bin/sh
# Alibaba Model Studio Token Plan and pay-as-you-go Anthropic endpoints.
PROVIDER_NAME="dashscope"
PROVIDER_DESC="Alibaba Model Studio Token Plan and pay-as-you-go API"

# Fallback to common Alibaba / DashScope env vars
if [ -z "${DASHSCOPE_TOKEN_PLAN_KEY:-}" ]; then
  if [ -n "${DASHSCOPE_API_KEY:-}" ]; then
    export DASHSCOPE_TOKEN_PLAN_KEY="$DASHSCOPE_API_KEY"
  elif [ -n "${ALIBABA_API_KEY:-}" ]; then
    export DASHSCOPE_TOKEN_PLAN_KEY="$ALIBABA_API_KEY"
  fi
fi

BASE_URL="https://token-plan.cn-beijing.maas.aliyuncs.com/apps/anthropic"
MODEL="qwen3.8-max"
CONTEXT_TOKENS="983616"
AUTO_COMPACT_TOKENS="983616"
MODEL_OPUS="qwen3.8-max"
MODEL_SONNET="qwen3.8-max"
MODEL_HAIKU="qwen3.6-flash"
MODEL_SUBAGENT="qwen3.7-max"
MODEL_ALIASES="qwen3.8-plus qwen3.7-plus glm-5.3 glm-5.2 deepseek-v4.1-flash deepseek-v4-pro deepseek-v4-flash-0731"
EFFORT="xhigh"

AUTH_MODE="surfaces"
PLAN_URL="https://token-plan.cn-beijing.maas.aliyuncs.com/apps/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="DASHSCOPE_TOKEN_PLAN_KEY"
PLAN_KEYS="dashscope-token-plan"
PLAN_MODEL="qwen3.8-max"
PLAN_MODEL_OPUS="qwen3.8-max"
PLAN_MODEL_SONNET="qwen3.8-max"
PLAN_MODEL_HAIKU="qwen3.6-flash"
PLAN_MODEL_SUBAGENT="qwen3.7-max"

# The legacy domain remains supported. A workspace-specific domain is the
# current recommendation and can be supplied without editing this file.
API_URL="${DASHSCOPE_API_URL:-https://dashscope.aliyuncs.com/apps/anthropic}"
API_AUTH_TYPE="bearer"
API_KEY_ENV="DASHSCOPE_API_KEY"
API_KEYS="dashscope-api-key"
API_MODEL="qwen3.7-max"
API_MODEL_OPUS="qwen3.7-max"
API_MODEL_SONNET="qwen3.7-max"
API_MODEL_HAIKU="qwen3.6-flash"
API_MODEL_SUBAGENT="qwen3.7-max"

ASSET_PROFILE="dashscope"
ASSET_PLAN_PLUGIN_DIRS="$ROOT_DIR/assets/plugins/dashscope-token-plan"
EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
