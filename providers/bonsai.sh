#!/bin/sh
# Provider: Local Bonsai-2 27B MLX Hadamard inference exposed to Claude Code.
PROVIDER_NAME="bonsai"
PROVIDER_DESC="Local Ternary Bonsai 2 (27B MLX 2-bit Hadamard)"

BASE_URL="http://127.0.0.1:11438"
MODEL="ternary-bonsai-2-27b"
_bonsai_last_model=$(load_last_selected_model bonsai 2>/dev/null || true)
if [ -n "$_bonsai_last_model" ]; then
  MODEL="$_bonsai_last_model"
fi
unset _bonsai_last_model

CONTEXT_TOKENS="262144"
MODEL_CONTEXT_OVERRIDES="ternary-bonsai-2-27b=262144 bonsai=262144"
MODEL_SELF_ROUTE_MODELS="ternary-bonsai-2-27b bonsai"
MODEL_OPUS="ternary-bonsai-2-27b"
MODEL_SONNET="ternary-bonsai-2-27b"
MODEL_HAIKU="ternary-bonsai-2-27b"
MODEL_SUBAGENT="ternary-bonsai-2-27b"
MODEL_ALIASES="ternary-bonsai-2-27b bonsai"
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
CLAUDE_CODE_MAX_OUTPUT_TOKENS=262144
CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000
CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS=1800000"

PRE_START='
_BONSAI_PROXY_PID=
BASE_URL=http://127.0.0.1:11438
HEALTH_CHECK_URL=$BASE_URL/health
_upstream_host="127.0.0.1"
_upstream_port="8000"
export MLX_MAX_OUTPUT_TOKENS=262144
export MLX_TOP_K=20 MLX_MIN_P=0.0 MLX_REASONING_EFFORT=xhigh

curl -fsS --max-time 3 "http://$_upstream_host:$_upstream_port/v1/models" >/dev/null 2>&1 || die "PrismML MLX runtime endpoint not reachable at http://$_upstream_host:$_upstream_port"

if lsof -nP -iTCP:11438 -sTCP:LISTEN >/dev/null 2>&1; then
  die "Bonsai adapter port 11438 is already owned by another session"
fi
MLX_HEARTBEAT_INTERVAL_MS=60000 MLX_PROXY_PORT=11438 MLX_UPSTREAM_HOST=$_upstream_host MLX_UPSTREAM_PORT=$_upstream_port MLX_MODEL="ternary-bonsai-2-27b" MLX_UPSTREAM_MODEL="/Users/jack/.cache/huggingface/hub/models--ternary-bonsai-2-27b/snapshots/local" MLX_TEMPERATURE="$BONSAI_TEMPERATURE" MLX_TOP_P="$BONSAI_TOP_P" MLX_PRESENCE_PENALTY="$BONSAI_PRESENCE_PENALTY" MLX_FREQUENCY_PENALTY="$BONSAI_FREQUENCY_PENALTY" MLX_REPETITION_PENALTY="$BONSAI_REPETITION_PENALTY" nohup node "$ROOT_DIR/lib/anthropic-openai-proxy.mjs" --port 11438 --upstream-host "$_upstream_host" --upstream-port "$_upstream_port" --model "ternary-bonsai-2-27b" --upstream-model "/Users/jack/.cache/huggingface/hub/models--ternary-bonsai-2-27b/snapshots/local" --temperature "$BONSAI_TEMPERATURE" --top-p "$BONSAI_TOP_P" --repetition-penalty "$BONSAI_REPETITION_PENALTY" --presence-penalty "$BONSAI_PRESENCE_PENALTY" --frequency-penalty "$BONSAI_FREQUENCY_PENALTY" >>/tmp/crouter-bonsai-proxy.log 2>&1 &
_BONSAI_PROXY_PID=$!
for _try in 1 2 3 4 5 6 7 8 9 10; do
  _proxy_health=$(curl -fsS --max-time 1 "$HEALTH_CHECK_URL" 2>/dev/null || true)
  printf "%s\n" "$_proxy_health" | grep -Fq "\"service\":\"crouter-mlx-anthropic-adapter\"" && break
  sleep 0.2
done
printf "%s\n" "$_proxy_health" | grep -Fq "\"service\":\"crouter-mlx-anthropic-adapter\"" || die "Bonsai adapter failed to start at $BASE_URL"
unset _upstream_host _upstream_port _proxy_health _try
'

POST_STOP='if [ -n "${_BONSAI_PROXY_PID:-}" ]; then kill "$_BONSAI_PROXY_PID" 2>/dev/null || true; wait "$_BONSAI_PROXY_PID" 2>/dev/null || true; _BONSAI_PROXY_PID=; fi'
HEALTH_CHECK_URL="http://127.0.0.1:11438/health"
