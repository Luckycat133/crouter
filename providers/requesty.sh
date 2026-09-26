#!/bin/sh
# Requesty's Claude Code Messages route. The OpenAI-compatible /v1 URL differs.
PROVIDER_NAME="requesty"
PROVIDER_DESC="Requesty Claude Code Anthropic Messages gateway"

BASE_URL="https://router.requesty.ai"
MODEL="anthropic/claude-sonnet-5"
CONTEXT_TOKENS=""
MODEL_OPUS="anthropic/claude-opus-5-5"
MODEL_SONNET="anthropic/claude-sonnet-5"
MODEL_HAIKU="anthropic/claude-haiku-4-5"
MODEL_SUBAGENT="anthropic/claude-haiku-4-5"
EFFORT=""

AUTH_MODE="surfaces"
API_URL="https://router.requesty.ai"
API_AUTH_TYPE="bearer"
API_KEY_ENV="REQUESTY_API_KEY"
API_KEYS="requesty-api-key"
API_MODEL="anthropic/claude-sonnet-5"
API_MODEL_OPUS="anthropic/claude-opus-5-5"
API_MODEL_SONNET="anthropic/claude-sonnet-5"
API_MODEL_HAIKU="anthropic/claude-haiku-4-5"
API_MODEL_SUBAGENT="anthropic/claude-haiku-4-5"

EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
