#!/bin/sh
# Provider: Ollama — local/cloud open-weight models via Ollama's native
# Anthropic-compatible Messages API (Ollama v0.14.0+).
PROVIDER_NAME="ollama"
PROVIDER_DESC="Ollama (local/cloud open-weight models) via native Anthropic-compatible Messages API"

BASE_URL="http://localhost:11434"
MODEL="glm-4.7-flash"
CONTEXT_TOKENS="65536"
# Measured on the local M2 Ultra 192 GB machine: 355,325 prompt tokens passed
# and 379,904 failed before first token with Metal OOM. Use a 365K cap for
# this exact Q8 model while leaving every other Ollama model on the safe floor.
MODEL_CONTEXT_OVERRIDES="deepseek-v4-flash:q8=373760"

# Explicit tier aliases (all map to default; override via --model or ANTHROPIC_DEFAULT_*_MODEL)
MODEL_OPUS="glm-4.7-flash"
MODEL_SONNET="glm-4.7-flash"
MODEL_HAIKU="glm-4.7-flash"
MODEL_SUBAGENT="glm-4.7-flash"

# Optional: set EFFORT for thinking-capable models (e.g. "medium"); leave empty otherwise
EFFORT=""

# Ollama ignores the auth token value but Claude Code requires a non-empty one.
# `none` auth mode leaves it unset, so inject a dummy token (and matching API key).
AUTH_MODE="none"
EXTRA_ENV="ANTHROPIC_AUTH_TOKEN=ollama
ANTHROPIC_API_KEY=ollama"

# Fail fast with a clear message if the Ollama service isn't up.
PRE_START='curl -fsS --max-time 3 http://localhost:11434 >/dev/null 2>&1 || die "Ollama not reachable at http://localhost:11434 — start it (ollama serve) and pull a model first"'

POST_STOP=""
HEALTH_CHECK_URL="http://localhost:11434"
