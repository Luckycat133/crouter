#!/bin/sh
# Meta Model API Messages route. Muse Code's native subscription/login is separate.
PROVIDER_NAME="meta"
PROVIDER_DESC="Meta Model API Muse Spark (Anthropic Messages)"

BASE_URL="https://api.meta.ai"
MODEL="muse-spark-1.3"
CONTEXT_TOKENS="1048576"
MODEL_OPUS="muse-spark-1.3"
MODEL_SONNET="muse-spark-1.3"
MODEL_HAIKU="muse-spark-1.3"
MODEL_SUBAGENT="muse-spark-1.3"
EFFORT=""

AUTH_MODE="surfaces"
API_URL="https://api.meta.ai"
API_AUTH_TYPE="bearer"
API_KEY_ENV="MODEL_API_KEY"
API_KEYS="meta-model-api-key"
API_MODEL="muse-spark-1.3"

EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
ENABLE_TOOL_SEARCH=true"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
