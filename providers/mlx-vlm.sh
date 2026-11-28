#!/bin/sh
# Provider: native MLX-VLM inference, independent of Ollama.
PROVIDER_NAME="mlx-vlm"
PROVIDER_DESC="Local MLX-VLM: Inkling 2 Mini"

BASE_URL="http://127.0.0.1:11440"
MODEL="inkling-2-mini:latest"
CONTEXT_TOKENS="1048576"
MODEL_CONTEXT_OVERRIDES="inkling-2-mini=1048576 inkling-2-mini:latest=1048576"
MODEL_SELF_ROUTE_MODELS="inkling-2-mini inkling-2-mini:latest"
MODEL_ALIASES="inkling-2-mini:latest inkling-2-mini"
MODELS_DISCOVERY="static"
EFFORT="max"

AUTH_MODE="none"
EXTRA_ENV="ANTHROPIC_AUTH_TOKEN=mlx-vlm
ANTHROPIC_API_KEY=
API_TIMEOUT_MS=1800000
CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000
CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS=1800000"

# Sampling, cache and drafting defaults remain in the native runtime.
. "$ROOT_DIR/lib/inkling-runtime.sh"
MODEL_SETUP=inkling_model_plan
PRE_START='inkling_start'
POST_STOP='inkling_stop'
HEALTH_CHECK_URL="http://127.0.0.1:11440/health"
