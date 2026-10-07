#!/bin/sh
# Kimi Code membership API; Moonshot pay-as-you-go is not mixed into this route.
PROVIDER_NAME="moonshot"
PROVIDER_DESC="Kimi Code membership (K3 256K recommended)"

# Fallback to common Moonshot env vars
if [ -z "${KIMI_CODE_KEY:-}" ]; then
  if [ -n "${MOONSHOT_API_KEY:-}" ]; then
    export KIMI_CODE_KEY="$MOONSHOT_API_KEY"
  fi
fi

BASE_URL="https://api.kimi.com/coding/"
MODEL="k3-256k"
CONTEXT_TOKENS="262144"
MODEL_OPUS="k3-256k"
MODEL_SONNET="k3-256k"
MODEL_HAIKU="k3-256k"
MODEL_SUBAGENT="k3-256k"
MODEL_ALIASES="k3[1m] kimi-for-coding kimi-for-coding-highspeed"
MODEL_CONTEXT_OVERRIDES="k3[1m]=1000000"
EFFORT="high"

AUTH_MODE="surfaces"
PLAN_URL="https://api.kimi.com/coding/"
PLAN_AUTH_TYPE="x-api-key"
PLAN_KEY_ENV="KIMI_CODE_KEY"
PLAN_KEYS="moonshot-coding-1"
PLAN_MODEL="k3-256k"
PLAN_MODEL_OPUS="k3-256k"
PLAN_MODEL_SONNET="k3-256k"
PLAN_MODEL_HAIKU="k3-256k"
PLAN_MODEL_SUBAGENT="k3-256k"

ASSET_PROFILE="empty"
EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
