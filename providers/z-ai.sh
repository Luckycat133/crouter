#!/bin/sh
# Provider: Z.ai GLM — Anthropic-compatible endpoint with Coding Plan support.
# Official: https://z.ai/ (GLM-5.2, GLM-5.1, GLM-4.7 for coding)
# Coding Plan: subscription for AI coding (GLM-5.2/5-Turbo), via api.z.ai
# Token Plan: pay-as-you-go via api.z.ai
#
# Endpoint: https://api.z.ai/api/anthropic (Anthropic-compatible Messages API)
# Auth: API key as Bearer token.
# Coding Plan uses dedicated keys; Token Plan uses standard keys.
# Both use keypool for automatic rotation on quota/auth errors.
PROVIDER_NAME="z-ai"
PROVIDER_DESC="Z.ai GLM (Coding Plan / Token Plan) via native Anthropic-compatible API"

BASE_URL="https://api.z.ai/api/anthropic"
MODEL="glm-5.2"
CONTEXT_TOKENS="200000"

# Map Claude Code tiers to GLM models.
MODEL_OPUS="glm-5.2"
MODEL_SONNET="glm-5.2"
MODEL_HAIKU="glm-5-turbo"
MODEL_SUBAGENT="glm-5-turbo"

EFFORT="max"

# Key pool: Coding Plan keys first (priority), then Token Plan keys.
# Add service names to Keychain: z-ai-coding-1, z-ai-token-1, etc.
# Enable keypool mode when multiple keys are configured:
# AUTH_MODE="keypool"
# AUTH_KEYS="z-ai-coding-1 z-ai-token-1"
# PLUS_URL="https://api.z.ai/api/anthropic"
# PLUS_KEYS="z-ai-coding-2"
AUTH_MODE="env"
AUTH_REFERENCE="Z_AI_API_KEY"
AUTH_KEYCHAIN_FALLBACK="z-ai-api-key"
_AUTH_SCHEME="bearer"

# OpenRouter-compatible: empty ANTHROPIC_API_KEY to avoid auth conflict with Bearer token
EXTRA_ENV="ANTHROPIC_API_KEY=
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"

PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL="https://api.z.ai/api/anthropic/v1/models"