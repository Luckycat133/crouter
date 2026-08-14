#!/bin/sh
# Provider: Ollama via the native Anthropic-compatible Messages API.
PROVIDER_NAME="ollama"
PROVIDER_DESC="Ollama (local/cloud open-weight models) via native Anthropic-compatible Messages API"

BASE_URL="http://localhost:11434"
# Users can override this default with any model available through their Ollama installation.
MODEL="glm-4.7-flash"
CONTEXT_TOKENS="65536"
# This exact local profile was validated with a 365 Ki-token practical cap;
# other user-selected Ollama models retain the conservative provider default.
MODEL_CONTEXT_OVERRIDES="deepseek-v4-flash:q8=373760"

# Ollama ignores these dummy credentials, but Claude Code requires non-empty values.
AUTH_MODE="none"
EXTRA_ENV="ANTHROPIC_AUTH_TOKEN=ollama
ANTHROPIC_API_KEY="

PRE_START='curl -fsS --max-time 3 http://localhost:11434 >/dev/null 2>&1 || die "Ollama not reachable at http://localhost:11434 — start it (ollama serve) and pull a model first"'

POST_STOP=""
HEALTH_CHECK_URL="http://localhost:11434"
