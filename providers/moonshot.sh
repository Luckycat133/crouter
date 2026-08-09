#!/bin/sh
# Provider: Moonshot AI (Kimi) — Anthropic-compatible endpoint with Coding Plan.
# Official: https://platform.moonshot.cn/ (Kimi K2.5/K2.6/K2.7)
# Coding Plan: subscription for AI coding (Kimi K2.5/K2.6/K2.7), via api.moonshot.cn
# Token Plan: pay-as-you-go via api.moonshot.cn
#
# Endpoint: https://api.moonshot.cn/v1/messages (Anthropic-compatible Messages API)
# Auth: API key as Bearer token.
# Coding Plan uses dedicated keys; Token Plan uses standard keys.
# Both use keypool for automatic rotation on quota/auth errors.
PROVIDER_NAME="moonshot"
PROVIDER_DESC="Moonshot AI Kimi (Coding Plan / Token Plan) via native Anthropic-compatible API"

BASE_URL="https://api.moonshot.cn/v1/messages"
MODEL="kimi-k2.7"
CONTEXT_TOKENS="200000"

# Map Claude Code tiers to Kimi models.
MODEL_OPUS="kimi-k2.7"
MODEL_SONNET="kimi-k2.5"
MODEL_HAIKU="kimi-k2.5"
MODEL_SUBAGENT="kimi-k2.5"

EFFORT="max"

# Key pool: Coding Plan keys first, then Token Plan keys.
# Keychain service names: moonshot-coding-1, moonshot-token-1, etc.
AUTH_MODE="keypool"
AUTH_KEYS="moonshot-coding-1 moonshot-token-1"

# Optional: separate Coding Plan surface.
PLUS_URL="https://api.moonshot.cn/v1/messages"
PLUS_KEYS="moonshot-coding-2"

EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"

PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL="https://api.moonshot.cn/v1/models"