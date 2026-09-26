#!/bin/sh
# Xiaomi MiMo Token Plan and pay-as-you-go keys are not interchangeable.
PROVIDER_NAME="xiaomi"
PROVIDER_DESC="Xiaomi MiMo Token Plan and pay-as-you-go API"

BASE_URL="https://token-plan-cn.xiaomimimo.com/anthropic"
MODEL="mimo-v2.6-pro[1m]"
CONTEXT_TOKENS="1048576"
MODEL_OPUS="mimo-v2.6-pro[1m]"
MODEL_SONNET="mimo-v2.6-pro[1m]"
MODEL_HAIKU="mimo-v2.6-pro[1m]"
MODEL_SUBAGENT="mimo-v2.6-pro[1m]"
MODEL_ALIASES="mimo-v2.5-pro mimo-v2.5"
EFFORT="high"

AUTH_MODE="surfaces"
PLAN_URL="https://token-plan-cn.xiaomimimo.com/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="XIAOMI_TOKEN_PLAN_KEY"
PLAN_KEYS="xiaomi-token-plan"
PLAN_MODEL="mimo-v2.6-pro"

API_URL="https://api.xiaomimimo.com/anthropic"
API_AUTH_TYPE="bearer"
API_KEY_ENV="XIAOMI_API_KEY"
API_KEYS="xiaomi-api-key"
API_MODEL="mimo-v2.6-pro"

EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
