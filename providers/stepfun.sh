#!/bin/sh
# Step Plan and ordinary API use different Anthropic-compatible prefixes.
PROVIDER_NAME="stepfun"
PROVIDER_DESC="StepFun Step Plan and pay-as-you-go API"

# Fallback to common StepFun env vars
if [ -z "${STEPFUN_PLAN_KEY:-}" ]; then
  if [ -n "${STEPFUN_API_KEY:-}" ]; then
    export STEPFUN_PLAN_KEY="$STEPFUN_API_KEY"
  fi
fi

BASE_URL="https://api.stepfun.com/step_plan"
MODEL="step-5-preview"
CONTEXT_TOKENS="1000000"
AUTO_COMPACT_TOKENS="1000000"
MODEL_OPUS="step-5-preview"
MODEL_SONNET="step-5-preview"
MODEL_HAIKU="step-3.7-flash"
MODEL_SUBAGENT="step-3.7-flash"
MODEL_ALIASES="step-3.7-flash step-3.5-flash-2603 step-3.5-flash step-router-v1"
EFFORT="medium"

AUTH_MODE="surfaces"
PLAN_URL="https://api.stepfun.com/step_plan"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="STEPFUN_PLAN_KEY"
PLAN_KEYS="stepfun-plan"
PLAN_MODEL="step-5-preview"
PLAN_MODEL_OPUS="step-5-preview"
PLAN_MODEL_SONNET="step-5-preview"
PLAN_MODEL_HAIKU="step-3.7-flash"
PLAN_MODEL_SUBAGENT="step-3.7-flash"

API_URL="https://api.stepfun.com"
API_AUTH_TYPE="bearer"
API_KEY_ENV="STEPFUN_API_KEY"
API_KEYS="stepfun-api-key"
API_MODEL="step-5-preview"
API_MODEL_HAIKU="step-3.7-flash"
API_MODEL_SUBAGENT="step-3.7-flash"

ASSET_PROFILE="stepfun"
ASSET_PLAN_PLUGIN_DIRS="$ROOT_DIR/assets/plugins/stepfun-plan"
EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
