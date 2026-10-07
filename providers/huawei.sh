#!/bin/sh
# Huawei ModelArts MaaS Token Plan and pay-as-you-go Anthropic endpoints.
PROVIDER_NAME="huawei"
PROVIDER_DESC="Huawei Cloud ModelArts MaaS Token Plan and API"

# Fallback to common Huawei Cloud env vars
if [ -z "${HUAWEI_TOKEN_PLAN_KEY:-}" ]; then
  if [ -n "${HUAWEI_API_KEY:-}" ]; then
    export HUAWEI_TOKEN_PLAN_KEY="$HUAWEI_API_KEY"
  fi
fi

BASE_URL="https://api.modelarts-maas.com/plan/anthropic"
MODEL="glm-5.3"
CONTEXT_TOKENS="262144"
MODEL_OPUS="glm-5.3"
MODEL_SONNET="glm-5.3"
MODEL_HAIKU="deepseek-v4.1-flash"
MODEL_SUBAGENT="glm-5.3"
MODEL_ALIASES="deepseek-v4.1-flash deepseek-v4-flash glm-5.1 kimi-k2.6"
EFFORT="high"

AUTH_MODE="surfaces"
PLAN_URL="https://api.modelarts-maas.com/plan/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="HUAWEI_TOKEN_PLAN_KEY"
PLAN_KEYS="huawei-token-plan"
PLAN_MODEL="glm-5.3"
PLAN_MODEL_OPUS="glm-5.3"
PLAN_MODEL_SONNET="glm-5.3"
PLAN_MODEL_HAIKU="deepseek-v4.1-flash"
PLAN_MODEL_SUBAGENT="glm-5.3"

API_URL="https://api.modelarts-maas.com/anthropic"
API_AUTH_TYPE="bearer"
API_KEY_ENV="HUAWEI_API_KEY"
API_KEYS="huawei-api-key"
API_MODEL="glm-5.3"
API_MODEL_HAIKU="deepseek-v4.1-flash"

EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
