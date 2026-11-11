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
MODEL_SELF_ROUTE_MODELS="$MODEL_ALIASES"
AUTH_MODE="env"
AUTH_REFERENCE="OPENROUTER_API_KEY"
AUTH_KEYCHAIN_FALLBACK="openrouter-api-key"
_AUTH_SCHEME="bearer"
MODELS_DISCOVERY="remote"
MODELS_API_URL="https://openrouter.ai/api/v1/models"
MODELS_API_AUTH="none"
MODELS_API_SURFACE="public"
EXTRA_ENV="ANTHROPIC_API_KEY=
CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
# Only explicit legacy nicknames are normalized; no wildcard may rewrite an
# arbitrary model. Selecting a model never silently changes free to paid.
PRE_START='
case "${_main_model:-$MODEL}" in
  nemotron|nemotron-3-ultra|ultra|"nemotron 3 ultra")
    _main_model="nvidia/nemotron-3-ultra-550b-a55b:free" ;;
  nemotron-3.5-super-vl|nemotron-3.5-super)
    _main_model="nvidia/nemotron-3.5-super-vl:free" ;;
  qwen|qwen3.8|qwen3.8-27b|"qwen3.8 27b")
    _main_model="qwen/qwen3.8-27b" ;;
  qwen3.8-27b:free|qwen/qwen3.8-27b:free|"qwen3.8 27b:free")
    die "that free route is retired; select a listed model explicitly" ;;
esac
MODEL_OPUS=$_main_model; MODEL_SONNET=$_main_model
MODEL_HAIKU=$_main_model; MODEL_SUBAGENT=$_main_model
case "$_main_model" in
  nvidia/nemotron-3-ultra-550b-a55b:free) EFFORT=high ;;
  qwen/qwen3.8-27b) EFFORT=xhigh ;;
  *) EFFORT= ;;
esac
apply_model_context_override "$_main_model"
case "${CONTEXT_TOKENS:-}" in
  ""|*[!0-9]*) AUTO_COMPACT_TOKENS= ;;
  *) [ "$CONTEXT_TOKENS" -ge 786432 ] || AUTO_COMPACT_TOKENS= ;;
esac
'
POST_STOP=""
HEALTH_CHECK_URL=""

MODEL_ID_ALIASES='nemotron=nvidia/nemotron-3-ultra-550b-a55b:free ultra=nvidia/nemotron-3-ultra-550b-a55b:free nemotron-3-ultra=nvidia/nemotron-3-ultra-550b-a55b:free nemotron-3.5-super=nvidia/nemotron-3.5-super-vl:free nemotron-3.5-super-vl=nvidia/nemotron-3.5-super-vl:free qwen=qwen/qwen3.8-27b qwen3.8=qwen/qwen3.8-27b qwen3.8-27b=qwen/qwen3.8-27b'
MODEL_BLOCKED_IDS='qwen3.8-27b:free qwen/qwen3.8-27b:free'
