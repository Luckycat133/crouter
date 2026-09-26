#!/bin/sh
# NagaAI Claude Code Messages route; use an inference API key, not a provisioning key.
PROVIDER_NAME="nagaai"
PROVIDER_DESC="NagaAI Anthropic-compatible Messages API"

BASE_URL="https://api.naga.ac"
MODEL="claude-sonnet-4.5"
CONTEXT_TOKENS=""
MODEL_OPUS="claude-opus-4.5"
MODEL_SONNET="claude-sonnet-4.5"
MODEL_HAIKU="claude-haiku-4.5"
MODEL_SUBAGENT="claude-haiku-4.5"
EFFORT=""

AUTH_MODE="surfaces"
API_URL="https://api.naga.ac"
API_AUTH_TYPE="bearer"
API_KEY_ENV="NAGAAI_API_KEY"
API_KEYS="nagaai-api-key"
API_MODEL="claude-sonnet-4.5"
API_MODEL_OPUS="claude-opus-4.5"
API_MODEL_SONNET="claude-sonnet-4.5"
API_MODEL_HAIKU="claude-haiku-4.5"
API_MODEL_SUBAGENT="claude-haiku-4.5"

EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
ANTHROPIC_API_KEY="
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
