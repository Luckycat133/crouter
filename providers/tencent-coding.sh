#!/bin/sh
# Tencent Coding Plan has a dedicated endpoint and credential.
PROVIDER_NAME="tencent-coding"
PROVIDER_DESC="Tencent Cloud Coding Plan"

# Fallback to common Tencent Cloud env vars
if [ -z "${TENCENT_CODING_PLAN_KEY:-}" ]; then
  if [ -n "${TENCENT_API_KEY:-}" ]; then
    export TENCENT_CODING_PLAN_KEY="$TENCENT_API_KEY"
  elif [ -n "${TENCENTCLOUD_API_KEY:-}" ]; then
    export TENCENT_CODING_PLAN_KEY="$TENCENTCLOUD_API_KEY"
  fi
fi

BASE_URL="https://api.lkeap.cloud.tencent.com/coding/anthropic"
MODEL="tc-code-latest"
CONTEXT_TOKENS="262144"
MODEL_OPUS="tc-code-latest"
MODEL_SONNET="tc-code-latest"
MODEL_HAIKU="tc-code-latest"
MODEL_SUBAGENT="tc-code-latest"
EFFORT="high"

AUTH_MODE="surfaces"
PLAN_URL="https://api.lkeap.cloud.tencent.com/coding/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="TENCENT_CODING_PLAN_KEY"
PLAN_KEYS="tencent-coding-plan"
PLAN_MODEL="tc-code-latest"
PLAN_MODEL_OPUS="tc-code-latest"
PLAN_MODEL_SONNET="tc-code-latest"
PLAN_MODEL_HAIKU="tc-code-latest"
PLAN_MODEL_SUBAGENT="tc-code-latest"

ASSET_PROFILE="tencent"
EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
