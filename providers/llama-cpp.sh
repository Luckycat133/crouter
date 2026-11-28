#!/bin/sh
# Provider: the configured native Inkling Unbound GGUF runtime, not Ollama.
PROVIDER_NAME="llama-cpp"
PROVIDER_DESC="Local llama.cpp: Inkling 2 Mini Unbound v3"

BASE_URL="http://127.0.0.1:11441"
MODEL="inkling-2-mini-unbound-v3"
CONTEXT_TOKENS="524288"
MODEL_CONTEXT_OVERRIDES="inkling-2-mini-unbound-v3=524288"
MODEL_SELF_ROUTE_MODELS="inkling-2-mini-unbound-v3"
MODEL_ALIASES="inkling-2-mini-unbound-v3"
MODEL_ID_ALIASES="inkling-2-mini-unbound-v3:latest=inkling-2-mini-unbound-v3"
MODELS_DISCOVERY="static"
EFFORT="max"

AUTH_MODE="none"
EXTRA_ENV="ANTHROPIC_AUTH_TOKEN=llama-cpp
ANTHROPIC_API_KEY=
API_TIMEOUT_MS=1800000
CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000
CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS=1800000"

# The separately configured native launcher owns all inference defaults.
. "$ROOT_DIR/lib/llama-cpp-runtime.sh"
MODEL_SETUP=llama_cpp_model_plan
PRE_START='llama_cpp_start'
POST_STOP='llama_cpp_stop'
HEALTH_CHECK_URL="http://127.0.0.1:11441/health"
