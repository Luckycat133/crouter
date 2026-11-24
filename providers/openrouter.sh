#!/bin/sh
# Reviewed 2026-11-07 against https://openrouter.ai/api/v1/models.
# Static seeds are not the complete catalog or account-entitlement proof.
PROVIDER_NAME="openrouter"
PROVIDER_DESC="OpenRouter Anthropic Messages gateway"
BASE_URL="https://openrouter.ai/api"
MODEL="nvidia/nemotron-3.5-super-vl:free"
CONTEXT_TOKENS="1000000"
AUTO_COMPACT_TOKENS="786432"
EFFORT=""
MODEL_OPUS="$MODEL"
MODEL_SONNET="$MODEL"
MODEL_HAIKU="$MODEL"
MODEL_SUBAGENT="$MODEL"
MODEL_ALIASES="nvidia/nemotron-3.5-super-vl:free nvidia/nemotron-3-ultra-550b-a55b:free qwen/qwen3.8-27b google/gemma-4-31b-it:free liquid/lfm-3-1.7b:free"
# Effective endpoint cap can be smaller than the model's advertised maximum.
MODEL_CONTEXT_OVERRIDES="nvidia/nemotron-3.5-super-vl:free=1000000 nvidia/nemotron-3-ultra-550b-a55b:free=1000000 qwen/qwen3.8-27b=262144 google/gemma-4-31b-it:free=262144 liquid/lfm-3-1.7b:free=262144"
MODEL_EFFORT_OVERRIDES='nvidia/nemotron-3-ultra-550b-a55b:free=high qwen/qwen3.8-27b=xhigh'
MODEL_SELF_ROUTE_MODELS='*'
AUTH_MODE="env"
AUTH_REFERENCE="OPENROUTER_API_KEY"
AUTH_KEYCHAIN_FALLBACK="openrouter-api-key"
_AUTH_SCHEME="bearer"
MODELS_DISCOVERY="remote"
MODELS_API_URL="https://openrouter.ai/api/v1/models"
MODELS_API_AUTH="none"
MODELS_API_SURFACE="public"
EXTRA_ENV="ANTHROPIC_API_KEY=
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
API_TIMEOUT_MS=1800000
CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000
CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS=1800000"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""

MODEL_ID_ALIASES='nemotron=nvidia/nemotron-3-ultra-550b-a55b:free ultra=nvidia/nemotron-3-ultra-550b-a55b:free nemotron-3-ultra=nvidia/nemotron-3-ultra-550b-a55b:free nemotron-3.5-super=nvidia/nemotron-3.5-super-vl:free nemotron-3.5-super-vl=nvidia/nemotron-3.5-super-vl:free qwen=qwen/qwen3.8-27b qwen3.8=qwen/qwen3.8-27b qwen3.8-27b=qwen/qwen3.8-27b'
# Normalize the retired label to the blocked free ID so it is refused rather
# than rewritten to the different, paid model.
MODEL_LABEL_ALIASES='nemotron 3 ultra=nvidia/nemotron-3-ultra-550b-a55b:free
qwen3.8 27b=qwen/qwen3.8-27b
qwen3.8 27b:free=qwen/qwen3.8-27b:free'
MODEL_BLOCKED_IDS='qwen3.8-27b:free qwen/qwen3.8-27b:free'
