#!/bin/sh
# LongCat Token Pack and pay-as-you-go share one platform key and API route.
PROVIDER_NAME="longcat"
PROVIDER_DESC="LongCat API Platform Anthropic Messages"

BASE_URL="https://api.longcat.chat/anthropic"
MODEL="LongCat-2.5-Preview"
CONTEXT_TOKENS="1000000"
MODEL_OPUS="LongCat-2.5-Preview"
MODEL_SONNET="LongCat-2.5-Preview"
MODEL_HAIKU="LongCat-2.5-Preview"
MODEL_SUBAGENT="LongCat-2.5-Preview"
MODEL_ALIASES="LongCat-2.0"
EFFORT=""

AUTH_MODE="surfaces"
API_URL="https://api.longcat.chat/anthropic"
API_AUTH_TYPE="bearer"
API_KEY_ENV="LONGCAT_API_KEY"
API_KEYS="longcat-api-key"
API_MODEL="LongCat-2.5-Preview"

EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
