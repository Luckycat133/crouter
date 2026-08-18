#!/bin/sh
# Provider: OpenRouter free model router via the Anthropic-compatible Messages API.
PROVIDER_NAME="openrouter"
PROVIDER_DESC="OpenRouter (unified gateway, Anthropic-compatible)"

BASE_URL="https://openrouter.ai/api"
MODEL="nvidia/nemotron-3-ultra-550b-a55b:free"
CONTEXT_TOKENS="1000000"

EFFORT="high"

# Single auth surface: your OpenRouter API key, sent as Authorization: Bearer.
AUTH_MODE="env"
AUTH_REFERENCE="OPENROUTER_API_KEY"
AUTH_KEYCHAIN_FALLBACK="openrouter-api-key"
_AUTH_SCHEME="bearer"

# OpenRouter requires ANTHROPIC_API_KEY to be empty to avoid an auth conflict.
EXTRA_ENV="ANTHROPIC_API_KEY=
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"

PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
