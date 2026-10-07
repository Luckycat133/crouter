#!/bin/sh
# Provider: OpenRouter free model router via the Anthropic-compatible Messages API.
PROVIDER_NAME="openrouter"
PROVIDER_DESC="OpenRouter (unified gateway, Anthropic-compatible)"

BASE_URL="https://openrouter.ai/api"
MODEL="nvidia/nemotron-3-ultra-550b-a55b:free"
CONTEXT_TOKENS="1000000"
AUTO_COMPACT_TOKENS="786432"
EFFORT="max"

MODEL_OPUS="nvidia/nemotron-3-ultra-550b-a55b:free"
MODEL_SONNET="nvidia/nemotron-3-ultra-550b-a55b:free"
MODEL_HAIKU="nvidia/nemotron-3-ultra-550b-a55b:free"
MODEL_SUBAGENT="nvidia/nemotron-3-ultra-550b-a55b:free"

MODEL_ALIASES="qwen/qwen3.8-27b deepseek/deepseek-v4.1-flash nvidia/nemotron-3-ultra-550b-a55b:free google/gemma-4-31b-it:free"
MODEL_CONTEXT_OVERRIDES="qwen/qwen3.8-27b:free=262144 qwen/qwen3.8-27b=262144 google/gemma-4-31b-it:free=131072 nvidia/nemotron-3-ultra-550b-a55b:free=1000000"
MODEL_SELF_ROUTE_MODELS="qwen/qwen3.8-27b:free qwen/qwen3.8-27b nvidia/nemotron-3-ultra-550b-a55b:free google/gemma-4-31b-it:free"

# Single auth surface: your OpenRouter API key, sent as Authorization: Bearer.
AUTH_MODE="env"
AUTH_REFERENCE="OPENROUTER_API_KEY"
AUTH_KEYCHAIN_FALLBACK="openrouter-api-key"
_AUTH_SCHEME="bearer"

# OpenRouter requires ANTHROPIC_API_KEY to be empty to avoid an auth conflict.
EXTRA_ENV="ANTHROPIC_API_KEY=
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"

PRE_START='
case "${_main_model:-$MODEL}" in
  nemotron|nemotron-3-ultra|ultra|"nemotron 3 ultra"|nvidia/nemotron-3-ultra-550b-a55b|nvidia/nemotron-3-ultra-550b-a55b:free|*nemotron-3-ultra*)
    _main_model="nvidia/nemotron-3-ultra-550b-a55b:free"
    CONTEXT_TOKENS="1000000"
    AUTO_COMPACT_TOKENS="786432"
    EFFORT="max"
    MODEL_OPUS="$_main_model"; MODEL_SONNET="$_main_model"; MODEL_HAIKU="$_main_model"; MODEL_SUBAGENT="$_main_model"
    ;;
  qwen3.8-27b|qwen/qwen3.8-27b|qwen3.8-27b:free|qwen/qwen3.8-27b:free|"qwen3.8 27b"|"qwen3.8 27b:free"|qwen|qwen3.8|*qwen3.8*27b*)
    _main_model="qwen/qwen3.8-27b"
    CONTEXT_TOKENS="262144"
    EFFORT="xhigh"
    MODEL_OPUS="$_main_model"; MODEL_SONNET="$_main_model"; MODEL_HAIKU="$_main_model"; MODEL_SUBAGENT="$_main_model"
    ;;
esac
'
POST_STOP=""
HEALTH_CHECK_URL=""
