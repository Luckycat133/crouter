#!/bin/sh
# Z.AI Coding Plan and API keys share the documented Anthropic endpoint.
PROVIDER_NAME="z-ai"
PROVIDER_DESC="Z.AI GLM Coding Plan and API"

# Fallback to common Zhipu / Z.AI env vars
if [ -z "${Z_AI_CODING_PLAN_KEY:-}" ]; then
  if [ -n "${Z_AI_API_KEY:-}" ]; then
    export Z_AI_CODING_PLAN_KEY="$Z_AI_API_KEY"
  elif [ -n "${ZHIPU_API_KEY:-}" ]; then
    export Z_AI_CODING_PLAN_KEY="$ZHIPU_API_KEY"
  fi
fi

BASE_URL="https://api.z.ai/api/anthropic"
MODEL="glm-5.3[1m]"
CONTEXT_TOKENS="1000000"
AUTO_COMPACT_TOKENS="1000000"
MODEL_OPUS="glm-5.3[1m]"
MODEL_SONNET="glm-5.3[1m]"
MODEL_HAIKU="glm-5.3-flash[1m]"
MODEL_SUBAGENT="glm-5.3-flash[1m]"
MODEL_ALIASES="glm-5.3-flash glm-5.3-flash[1m] glm-5.2[1m] glm-5.2 glm-5.1 glm-5 glm-4.7"
EFFORT="high"

AUTH_MODE="surfaces"
PLAN_URL="https://api.z.ai/api/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="Z_AI_CODING_PLAN_KEY"
PLAN_KEYS="z-ai-coding-plan"
PLAN_MODEL="glm-5.3[1m]"
PLAN_MODEL_OPUS="glm-5.3[1m]"
PLAN_MODEL_SONNET="glm-5.3[1m]"
PLAN_MODEL_HAIKU="glm-5.3-flash[1m]"
PLAN_MODEL_SUBAGENT="glm-5.3-flash[1m]"

API_URL="https://api.z.ai/api/anthropic"
API_AUTH_TYPE="bearer"
API_KEY_ENV="Z_AI_API_KEY"
API_KEYS="z-ai-api-key"
API_MODEL="glm-5.3[1m]"
API_MODEL_OPUS="glm-5.3[1m]"
API_MODEL_SONNET="glm-5.3[1m]"
API_MODEL_HAIKU="glm-5.3-flash[1m]"
API_MODEL_SUBAGENT="glm-5.3-flash[1m]"

ASSET_PROFILE="zai"
EXTRA_ENV="API_TIMEOUT_MS=3000000
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
