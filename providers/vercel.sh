#!/bin/sh
# Vercel AI Gateway API-key route; Claude Max gateway passthrough is separate.
PROVIDER_NAME="vercel"
PROVIDER_DESC="Vercel AI Gateway Anthropic Messages API"

BASE_URL="https://ai-gateway.vercel.sh"
MODEL="anthropic/claude-sonnet-5"
CONTEXT_TOKENS=""
MODEL_OPUS="anthropic/claude-opus-5.5"
MODEL_SONNET="anthropic/claude-sonnet-5"
MODEL_HAIKU="anthropic/claude-haiku-4.5"
MODEL_SUBAGENT="anthropic/claude-haiku-4.5"
EFFORT=""

AUTH_MODE="surfaces"
API_URL="https://ai-gateway.vercel.sh"
API_AUTH_TYPE="bearer"
API_KEY_ENV="AI_GATEWAY_API_KEY"
API_KEYS="vercel-ai-gateway-api-key"
API_MODEL="anthropic/claude-sonnet-5"
API_MODEL_OPUS="anthropic/claude-opus-5.5"
API_MODEL_SONNET="anthropic/claude-sonnet-5"
API_MODEL_HAIKU="anthropic/claude-haiku-4.5"
API_MODEL_SUBAGENT="anthropic/claude-haiku-4.5"

EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
