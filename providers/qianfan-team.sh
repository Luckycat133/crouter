#!/bin/sh
# Baidu Qianfan team Token Plan has its own endpoint and credential.
PROVIDER_NAME="qianfan-team"
PROVIDER_DESC="Baidu Qianfan team Token Plan"

# Fallback to common Baidu Qianfan env vars
if [ -z "${QIANFAN_TEAM_TOKEN_PLAN_KEY:-}" ]; then
  if [ -n "${QIANFAN_API_KEY:-}" ]; then
    export QIANFAN_TEAM_TOKEN_PLAN_KEY="$QIANFAN_API_KEY"
  elif [ -n "${BAIDU_API_KEY:-}" ]; then
    export QIANFAN_TEAM_TOKEN_PLAN_KEY="$BAIDU_API_KEY"
  fi
fi

BASE_URL="https://qianfan.baidubce.com/anthropic/tokenplan/team"
MODEL="deepseek-v4-flash"
CONTEXT_TOKENS="262144"
MODEL_OPUS="deepseek-v4-flash"
MODEL_SONNET="deepseek-v4-flash"
MODEL_HAIKU="deepseek-v4-flash"
MODEL_SUBAGENT="deepseek-v4-flash"
MODEL_ALIASES="deepseek-v3.2"
EFFORT="high"

AUTH_MODE="surfaces"
PLAN_URL="https://qianfan.baidubce.com/anthropic/tokenplan/team"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="QIANFAN_TEAM_TOKEN_PLAN_KEY"
PLAN_KEYS="qianfan-team-token-plan"
PLAN_MODEL="deepseek-v4-flash"
PLAN_MODEL_OPUS="deepseek-v4-flash"
PLAN_MODEL_SONNET="deepseek-v4-flash"
PLAN_MODEL_HAIKU="deepseek-v4-flash"
PLAN_MODEL_SUBAGENT="deepseek-v4-flash"

ASSET_PROFILE="empty"
EXTRA_ENV="API_TIMEOUT_MS=600000
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
