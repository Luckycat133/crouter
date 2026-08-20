#!/bin/sh
# Provider: Ollama via the native Anthropic-compatible Messages API.
PROVIDER_NAME="ollama"
PROVIDER_DESC="Ollama (local/cloud open-weight models) via native Anthropic-compatible Messages API"

BASE_URL="http://127.0.0.1:11435"
# This machine's validated local default. Users can still select any installed
# Ollama model with `crouter ollama <model>` or `--model <model>`.
MODEL="deepseek-v4-flash:q8"
CONTEXT_TOKENS="65536"
# This exact local profile was validated with a 365K-token practical cap;
# other user-selected Ollama models retain the conservative provider default.
MODEL_CONTEXT_OVERRIDES="deepseek-v4-flash:q8=373760"
EFFORT="high"

# Local models can spend several minutes emitting a large tool-call payload
# without yielding another user-visible content block.  Claude Code's default
# stream watchdog otherwise mistakes that healthy generation for a stalled
# connection and aborts it. The localhost proxy emits an SSE comment every
# 60 seconds; comments are transport keepalives and do not alter model events.
# Keep the client out of the way for long local inference while retaining the
# longest stream-idle ceiling supported by Claude Code 2.1.237 (30 minutes).
# Ollama ignores these dummy credentials, but Claude Code requires non-empty values.
AUTH_MODE="none"
EXTRA_ENV="ANTHROPIC_AUTH_TOKEN=ollama
ANTHROPIC_API_KEY=
API_TIMEOUT_MS=1800000
CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000
CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS=1800000"

PRE_START='_OLLAMA_HEARTBEAT_PROXY_PID=; curl -fsS --max-time 3 http://127.0.0.1:11434 >/dev/null 2>&1 || die "Ollama not reachable at http://127.0.0.1:11434 — start it (ollama serve) and pull a model first"; if ! curl -fsS --max-time 1 http://127.0.0.1:11435/health 2>/dev/null | grep -q '"service":"crouter-ollama-heartbeat"'; then OLLAMA_HEARTBEAT_INTERVAL_MS=60000 nohup node "$ROOT_DIR/lib/ollama-heartbeat-proxy.mjs" >>/tmp/crouter-ollama-heartbeat-proxy.log 2>&1 & _OLLAMA_HEARTBEAT_PROXY_PID=$!; for _ollama_proxy_try in 1 2 3 4 5 6 7 8 9 10; do curl -fsS --max-time 1 http://127.0.0.1:11435/health 2>/dev/null | grep -q '"service":"crouter-ollama-heartbeat"' && break; sleep 0.2; done; fi; curl -fsS --max-time 1 http://127.0.0.1:11435/health 2>/dev/null | grep -q '"service":"crouter-ollama-heartbeat"' || die "Ollama heartbeat proxy failed to start at http://127.0.0.1:11435"'

POST_STOP='if [ -n "${_OLLAMA_HEARTBEAT_PROXY_PID:-}" ]; then kill "$_OLLAMA_HEARTBEAT_PROXY_PID" 2>/dev/null || true; wait "$_OLLAMA_HEARTBEAT_PROXY_PID" 2>/dev/null || true; _OLLAMA_HEARTBEAT_PROXY_PID=; fi'
HEALTH_CHECK_URL="http://127.0.0.1:11435/health"
