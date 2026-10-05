#!/bin/sh
# MiniMax Token Plan and pay-as-you-go keys use distinct credential surfaces.
PROVIDER_NAME="minimax"
PROVIDER_DESC="MiniMax M3 (Token Plan and API key failover)"

# Fallback to common MiniMax env vars
if [ -z "${MINIMAX_TOKEN_PLAN_KEY:-}" ]; then
  if [ -n "${MINIMAX_API_KEY:-}" ]; then
    export MINIMAX_TOKEN_PLAN_KEY="$MINIMAX_API_KEY"
  fi
fi

BASE_URL="https://api.minimax.cn/anthropic"
MODEL="MiniMax-M3"
CONTEXT_TOKENS="1000000"
AUTO_COMPACT_TOKENS="1000000"
MODEL_OPUS="MiniMax-M3"
MODEL_SONNET="MiniMax-M3"
MODEL_HAIKU="MiniMax-M3"
MODEL_SUBAGENT="MiniMax-M3"
EFFORT="max"

AUTH_MODE="surfaces"
PLAN_URL="https://api.minimax.cn/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="MINIMAX_TOKEN_PLAN_KEY"
PLAN_KEYS="codex-minimax-token-plan"
PLAN_MODEL="MiniMax-M3"
PLAN_MODEL_OPUS="MiniMax-M3"
PLAN_MODEL_SONNET="MiniMax-M3"
PLAN_MODEL_HAIKU="MiniMax-M3"
PLAN_MODEL_SUBAGENT="MiniMax-M3"

API_URL="https://api.minimax.cn/anthropic"
API_AUTH_TYPE="bearer"
API_KEY_ENV="MINIMAX_API_KEY"
API_KEYS="minimax-api-key"
API_MODEL="MiniMax-M3"
API_MODEL_OPUS="MiniMax-M3"
API_MODEL_SONNET="MiniMax-M3"
API_MODEL_HAIKU="MiniMax-M3"
API_MODEL_SUBAGENT="MiniMax-M3"

ASSET_PROFILE="minimax"
ASSET_PLAN_PLUGIN_DIRS="$ROOT_DIR/assets/plugins/minimax-token-plan"
EXTRA_ENV="API_TIMEOUT_MS=3000000
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"

PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
