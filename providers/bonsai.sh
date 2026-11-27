#!/bin/sh
# Provider: native Bonsai MLX models exposed to Claude Code.
PROVIDER_NAME="bonsai"
PROVIDER_DESC="Local Ternary Bonsai 2 / 2.5 (27B MLX 2-bit Hadamard)"

BASE_URL="http://127.0.0.1:11438"
MODEL="ternary-bonsai-2-27b"
_bonsai_last_model=$(load_last_selected_model bonsai 2>/dev/null || true)
if [ -n "$_bonsai_last_model" ]; then
  MODEL="$_bonsai_last_model"
fi
unset _bonsai_last_model

CONTEXT_TOKENS="262144"
MAX_OUTPUT_TOKENS="262144"
MODEL_CONTEXT_OVERRIDES="ternary-bonsai-2-27b=262144 ternary-bonsai-2.5-27b=262144 bonsai=262144"
MODEL_SELF_ROUTE_MODELS="ternary-bonsai-2-27b ternary-bonsai-2.5-27b bonsai"
MODEL_OPUS="ternary-bonsai-2-27b"
MODEL_SONNET="ternary-bonsai-2-27b"
MODEL_HAIKU="ternary-bonsai-2-27b"
MODEL_SUBAGENT="ternary-bonsai-2-27b"
MODEL_ALIASES="ternary-bonsai-2-27b ternary-bonsai-2.5-27b bonsai"
EFFORT="max"

# Model Sampling Hyperparameters (Standard LLM inference parameters)
# Can be overridden via environment variables
BONSAI_TEMPERATURE="${BONSAI_TEMPERATURE:-1.0}"
BONSAI_TOP_P="${BONSAI_TOP_P:-0.95}"
BONSAI_REPETITION_PENALTY="${BONSAI_REPETITION_PENALTY:-1.0}"
BONSAI_PRESENCE_PENALTY="${BONSAI_PRESENCE_PENALTY:-0.0}"
BONSAI_FREQUENCY_PENALTY="${BONSAI_FREQUENCY_PENALTY:-0.0}"

AUTH_MODE="none"
EXTRA_ENV="ANTHROPIC_AUTH_TOKEN=bonsai
ANTHROPIC_API_KEY=
API_TIMEOUT_MS=1800000
CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000
CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS=1800000"

# Planning is side-effect-free; startup owns service checks and processes.
. "$ROOT_DIR/lib/bonsai-runtime.sh"
MODEL_SETUP=bonsai_model_plan
PRE_START='bonsai_start'
POST_STOP='bonsai_stop'
HEALTH_CHECK_URL="http://127.0.0.1:11438/health"
