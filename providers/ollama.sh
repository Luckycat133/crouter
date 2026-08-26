#!/bin/sh
# Provider: Ollama via the native Anthropic-compatible Messages API.
PROVIDER_NAME="ollama"
PROVIDER_DESC="Ollama (local/cloud open-weight models) via native Anthropic-compatible Messages API"

BASE_URL="http://127.0.0.1:11435"
# This machine's validated local default. Users can still select any installed
# Ollama model with `crouter ollama <model>` or `--model <model>`.
MODEL="deepseek-v4-flash:q8"
_ollama_last_model=$(load_last_selected_model ollama 2>/dev/null || true)
if [ -n "$_ollama_last_model" ]; then
  MODEL="$_ollama_last_model"
fi
unset _ollama_last_model
CONTEXT_TOKENS="65536"
# DeepSeek keeps its validated 365K practical cap. Only the selected Qwen MTP
# tag gets its native 256K context; other Ollama models retain 65536.
MODEL_CONTEXT_OVERRIDES="deepseek-v4-flash:q8=373760 qwen3.8:27b-mtp-q8_0=262144"
# For this exact Qwen MTP tag, route Claude Code's tier and subagent aliases to
# the same model instead of inheriting DeepSeek's aliases.
MODEL_SELF_ROUTE_MODELS="qwen3.8:27b-mtp-q8_0"
EFFORT="max"

# DeepSeek V4 receives Claude Code's max effort through output_config. The
# localhost proxy removes a conflicting top-level thinking=enabled toggle so
# Ollama preserves the string-valued native think level instead of reducing it
# to the boolean think=true.
#
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

PRE_START='_OLLAMA_HEARTBEAT_PROXY_PID=; curl -fsS --max-time 3 http://127.0.0.1:11434 >/dev/null 2>&1 || die "Ollama not reachable at http://127.0.0.1:11434 — start it (ollama serve) and pull a model first"; if ! curl -fsS --max-time 1 http://127.0.0.1:11435/health 2>/dev/null | grep -q crouter-ollama-heartbeat; then OLLAMA_HEARTBEAT_INTERVAL_MS=60000 nohup node "$ROOT_DIR/lib/ollama-heartbeat-proxy.mjs" >>/tmp/crouter-ollama-heartbeat-proxy.log 2>&1 & _OLLAMA_HEARTBEAT_PROXY_PID=$!; for _ollama_proxy_try in 1 2 3 4 5 6 7 8 9 10; do curl -fsS --max-time 1 http://127.0.0.1:11435/health 2>/dev/null | grep -q crouter-ollama-heartbeat && break; sleep 0.2; done; fi; curl -fsS --max-time 1 http://127.0.0.1:11435/health 2>/dev/null | grep -q crouter-ollama-heartbeat || die "Ollama heartbeat proxy failed to start at http://127.0.0.1:11435"'

POST_STOP='if [ -n "${_OLLAMA_HEARTBEAT_PROXY_PID:-}" ]; then kill "$_OLLAMA_HEARTBEAT_PROXY_PID" 2>/dev/null || true; wait "$_OLLAMA_HEARTBEAT_PROXY_PID" 2>/dev/null || true; _OLLAMA_HEARTBEAT_PROXY_PID=; fi'
HEALTH_CHECK_URL="http://127.0.0.1:11435/health"
