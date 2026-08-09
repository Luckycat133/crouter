#!/bin/sh
# Provider: Anthropic Claude — default account (subscription OAuth)
# first, API key fallback. Dual-source: gateway fronts both surfaces
# and fails over on 401/429.
PROVIDER_NAME="anthropic"
PROVIDER_DESC="Anthropic Claude (subscription OAuth preferred, API key fallback)"

BASE_URL="https://api.anthropic.com"
MODEL="claude-sonnet-4"
CONTEXT_TOKENS="200000"

MODEL_OPUS="claude-opus-4-5"
MODEL_SONNET="claude-sonnet-4"
MODEL_HAIKU="claude-haiku-4"
MODEL_SUBAGENT="claude-sonnet-4"

EFFORT="max"

# --- Preferred "default account" (subscription OAuth) — tried FIRST ---------
DEFAULT_URL="https://api.anthropic.com"
DEFAULT_AUTH_TYPE="bearer"
DEFAULT_TOKEN_ENV="CLAUDE_CODE_OAUTH_TOKEN"
DEFAULT_TOKEN_ENV_FALLBACK="ANTHROPIC_AUTH_TOKEN"

# --- Fallback API surface (Anthropic Console API key) -----------------------
API_URL="https://api.anthropic.com"
API_AUTH_TYPE="x-api-key"
API_KEY_ENV="ANTHROPIC_API_KEY"
API_KEY_REF="anthropic-api-key"

EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"

PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""