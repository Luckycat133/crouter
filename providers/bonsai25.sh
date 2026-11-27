#!/bin/sh
# Bonsai 2.5 MLX agent defaults; machine paths belong in config.sh.
PROVIDER_NAME="bonsai25"
PROVIDER_DESC="Local Bonsai 2.5 27B MLX"
BASE_URL="http://127.0.0.1:11439"
MODEL="ternary-bonsai-2.5-27b"
MODEL_ALIASES="ternary-bonsai-2.5-27b"
MODELS_DISCOVERY="static"
MODEL_SELF_ROUTE_MODELS="ternary-bonsai-2.5-27b"
CONTEXT_TOKENS="262144"
EFFORT="max"
AUTH_MODE="none"
MODEL_SERVICE="bonsai25-mlx"
EXTRA_ENV="ANTHROPIC_AUTH_TOKEN=bonsai25
ANTHROPIC_API_KEY=
API_TIMEOUT_MS=1800000
CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000
CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS=1800000"
PRE_START='. "$LIB_DIR/bonsai25-runtime.sh"; bonsai25_start'
POST_STOP='if command -v bonsai25_stop >/dev/null 2>&1; then bonsai25_stop; fi'
HEALTH_CHECK_URL="http://127.0.0.1:11439/health"
