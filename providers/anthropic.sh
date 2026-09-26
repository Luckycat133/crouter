#!/bin/sh
# Provider: Anthropic's official API. Native Claude account login is `crouter claude`.
PROVIDER_NAME="anthropic"
PROVIDER_DESC="Anthropic Claude API (Console API key)"

BASE_URL="https://api.anthropic.com"
MODEL="claude-sonnet-5"
# The catalog mixes 1M Opus/Sonnet/Fable with 200K Haiku. Do not force one
# global Claude Code compact window across models with different limits.
CONTEXT_TOKENS=""

MODEL_OPUS="claude-opus-5-5"
MODEL_SONNET="claude-sonnet-5"
MODEL_HAIKU="claude-haiku-4-5"
MODEL_SUBAGENT="claude-sonnet-5"
MODEL_ALIASES="claude-fable-5-1"

EFFORT=""

AUTH_MODE="env"
AUTH_REFERENCE="ANTHROPIC_API_KEY"
AUTH_KEYCHAIN_FALLBACK="anthropic-api-key"
_AUTH_SCHEME="x-api-key"

EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"

PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
