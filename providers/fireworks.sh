#!/bin/sh
# Fireworks' direct Anthropic Messages surface; Nexus/FireConnect is separate.
PROVIDER_NAME="fireworks"
PROVIDER_DESC="Fireworks AI serverless Messages API"

BASE_URL="https://api.fireworks.ai/inference"
MODEL="accounts/fireworks/models/glm-5p3-flash"
CONTEXT_TOKENS=""
MODEL_OPUS="accounts/fireworks/models/glm-5p3-flash"
MODEL_SONNET="accounts/fireworks/models/glm-5p3-flash"
MODEL_HAIKU="accounts/fireworks/models/glm-5p3-flash"
MODEL_SUBAGENT="accounts/fireworks/models/glm-5p3-flash"
MODEL_ALIASES="accounts/fireworks/models/kimi-k3"
EFFORT=""

AUTH_MODE="surfaces"
API_URL="https://api.fireworks.ai/inference"
API_AUTH_TYPE="bearer"
API_KEY_ENV="FIREWORKS_API_KEY"
API_KEYS="fireworks-api-key"
API_MODEL="accounts/fireworks/models/glm-5p3-flash"

EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
