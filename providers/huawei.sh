#!/bin/sh
# Huawei ModelArts MaaS Token Plan and pay-as-you-go Anthropic endpoints.
PROVIDER_NAME="huawei"
PROVIDER_DESC="Huawei Cloud ModelArts MaaS Token Plan and API"

BASE_URL="https://api.modelarts-maas.com/plan/anthropic"
MODEL="glm-5.1"
CONTEXT_TOKENS=""
MODEL_OPUS="glm-5.1"
MODEL_SONNET="glm-5.1"
MODEL_HAIKU="glm-5.1"
MODEL_SUBAGENT="glm-5.1"
MODEL_ALIASES="kimi-k2.6 deepseek-v4-flash"
EFFORT="high"

AUTH_MODE="surfaces"
PLAN_URL="https://api.modelarts-maas.com/plan/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="HUAWEI_TOKEN_PLAN_KEY"
PLAN_KEYS="huawei-token-plan"
PLAN_MODEL="glm-5.1"

API_URL="https://api.modelarts-maas.com/anthropic"
API_AUTH_TYPE="bearer"
API_KEY_ENV="HUAWEI_API_KEY"
API_KEYS="huawei-api-key"
API_MODEL="glm-5.1"

EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
