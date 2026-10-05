#!/bin/sh
# Alibaba Model Studio Coding Plan is isolated from its Token Plan endpoint.
PROVIDER_NAME="dashscope-coding"
PROVIDER_DESC="Alibaba Model Studio Coding Plan"

# Fallback to common Alibaba / DashScope env vars
if [ -z "${DASHSCOPE_CODING_PLAN_KEY:-}" ]; then
  if [ -n "${DASHSCOPE_API_KEY:-}" ]; then
    export DASHSCOPE_CODING_PLAN_KEY="$DASHSCOPE_API_KEY"
  elif [ -n "${ALIBABA_API_KEY:-}" ]; then
    export DASHSCOPE_CODING_PLAN_KEY="$ALIBABA_API_KEY"
  fi
fi

BASE_URL="https://coding.dashscope.aliyuncs.com/apps/anthropic"
MODEL="qwen3.8-plus"
CONTEXT_TOKENS="983616"
AUTO_COMPACT_TOKENS="983616"
MODEL_OPUS="qwen3.8-plus"
MODEL_SONNET="qwen3.8-plus"
MODEL_HAIKU="qwen3.8-plus"
MODEL_SUBAGENT="qwen3.8-plus"
EFFORT="high"

AUTH_MODE="surfaces"
PLAN_URL="https://coding.dashscope.aliyuncs.com/apps/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="DASHSCOPE_CODING_PLAN_KEY"
PLAN_KEYS="dashscope-coding-plan"
PLAN_MODEL="qwen3.8-plus"
PLAN_MODEL_OPUS="qwen3.8-plus"
PLAN_MODEL_SONNET="qwen3.8-plus"
PLAN_MODEL_HAIKU="qwen3.8-plus"
PLAN_MODEL_SUBAGENT="qwen3.8-plus"

ASSET_PROFILE="dashscope-coding"
EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
