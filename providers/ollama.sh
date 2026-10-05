#!/bin/sh
# Provider: local MLX and Ollama models exposed to Claude Code.
PROVIDER_NAME="ollama"
PROVIDER_DESC="Local models: multimodal MLX Qwen3.8 and Ollama DeepSeek"

BASE_URL="http://127.0.0.1:11435"
# Preserve the user's last selection. The exact qwen3.8-27b ID is routed to
# MLX; all other selected IDs retain the Ollama path.
MODEL="qwen3.8-27b"
_ollama_last_model=$(load_last_selected_model ollama 2>/dev/null || true)
if [ -n "$_ollama_last_model" ]; then
  MODEL="$_ollama_last_model"
fi
unset _ollama_last_model
CONTEXT_TOKENS="65536"
# DeepSeek keeps its validated practical cap. Only the canonical Qwen ID gets
# the MLX model's native 262K context; legacy Qwen aliases are intentionally
# unsupported.
MODEL_CONTEXT_OVERRIDES="deepseek-v4-flash:q8=373760 deepseek-v4-flash=373760 qwen3.8-27b=262144"
MODEL_SELF_ROUTE_MODELS="deepseek-v4-flash:q8 deepseek-v4-flash qwen3.8-27b"
EFFORT="max"

# DeepSeek V4 receives Claude Code's max effort through output_config. The
# localhost proxy preserves the thinking request; its telemetry reports the
# effective local toggle without claiming per-tier reasoning budget control.
#
# Local models can spend several minutes emitting a large tool-call payload
# without yielding another user-visible content block.  Claude Code's default
# stream watchdog otherwise mistakes that healthy generation for a stalled
# connection and aborts it. The localhost proxy emits an SSE comment every
# 60 seconds; comments are transport keepalives and do not alter model events.
# Keep the client out of the way for long local inference while retaining the
# longest stream-idle ceiling supported by Claude Code 2.1.237 (30 minutes).
# Local adapters ignore these dummy credentials, but Claude Code requires a
# non-empty token.
AUTH_MODE="none"
EXTRA_ENV="ANTHROPIC_AUTH_TOKEN=ollama
ANTHROPIC_API_KEY=
API_TIMEOUT_MS=1800000
CLAUDE_STREAM_IDLE_TIMEOUT_MS=1800000
CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS=1800000"

PRE_START='
_OLLAMA_HEARTBEAT_PROXY_PID=
_MLX_PROXY_PID=
_local_selected_model=${_main_model:-$MODEL}
if [ "$_local_selected_model" = qwen3.8-27b ]; then
  ASSET_PLUGIN_DIRS="$ROOT_DIR/assets/plugins/qwen-local-multimodal"
  BASE_URL=http://127.0.0.1:11436
  HEALTH_CHECK_URL=$BASE_URL/health
  _mlx_upstream_host=${MLX_UPSTREAM_HOST:-10.211.55.2}
  _mlx_upstream_port=${MLX_UPSTREAM_PORT:-18080}
  case $_mlx_upstream_port in
    ""|*[!0-9]*) die "MLX_UPSTREAM_PORT must be an integer from 1 to 65535" ;;
  esac
  while [ "${_mlx_upstream_port#0}" != "$_mlx_upstream_port" ]; do
    _mlx_upstream_port=${_mlx_upstream_port#0}
  done
  case $_mlx_upstream_port in
    ""|??????*) die "MLX_UPSTREAM_PORT must be an integer from 1 to 65535" ;;
  esac
  [ "$_mlx_upstream_port" -le 65535 ] || die "MLX_UPSTREAM_PORT must be an integer from 1 to 65535"
  _mlx_upstream_url="http://$_mlx_upstream_host:$_mlx_upstream_port"
  _mlx_expected_upstream="\"upstream\":\"$_mlx_upstream_host:$_mlx_upstream_port\""
  curl -fsS --max-time 3 "$_mlx_upstream_url/v1/models" >/dev/null 2>&1 || die "MLX-VLM not reachable at $_mlx_upstream_url"
  _mlx_health=$(curl -fsS --max-time 1 "$HEALTH_CHECK_URL" 2>/dev/null || true)
  if printf "%s\n" "$_mlx_health" | grep -Fq "\"service\":\"crouter-mlx-anthropic-adapter\""; then
    printf "%s\n" "$_mlx_health" | grep -Fq "$_mlx_expected_upstream" || die "MLX adapter at $BASE_URL uses another upstream; stop it before changing MLX_UPSTREAM_HOST or MLX_UPSTREAM_PORT"
  else
    MLX_HEARTBEAT_INTERVAL_MS=60000 MLX_UPSTREAM_HOST=$_mlx_upstream_host MLX_UPSTREAM_PORT=$_mlx_upstream_port MLX_MODEL=qwen3.8-27b nohup node "$ROOT_DIR/lib/anthropic-openai-proxy.mjs" >>/tmp/crouter-mlx-proxy.log 2>&1 &
    _MLX_PROXY_PID=$!
    for _mlx_proxy_try in 1 2 3 4 5 6 7 8 9 10; do
      _mlx_health=$(curl -fsS --max-time 1 "$HEALTH_CHECK_URL" 2>/dev/null || true)
      printf "%s\n" "$_mlx_health" | grep -Fq "$_mlx_expected_upstream" && break
      sleep 0.2
    done
  fi
  printf "%s\n" "$_mlx_health" | grep -Fq "\"service\":\"crouter-mlx-anthropic-adapter\"" || die "MLX adapter failed to start at $BASE_URL"
  printf "%s\n" "$_mlx_health" | grep -Fq "$_mlx_expected_upstream" || die "MLX adapter at $BASE_URL uses another upstream"
else
  BASE_URL=http://127.0.0.1:11435
  HEALTH_CHECK_URL=$BASE_URL/health
  curl -fsS --max-time 3 http://127.0.0.1:11434 >/dev/null 2>&1 || die "Ollama not reachable at http://127.0.0.1:11434 — start it (ollama serve) and pull the selected model first"
  if ! curl -fsS --max-time 1 "$HEALTH_CHECK_URL" 2>/dev/null | grep -q crouter-ollama-heartbeat; then
    OLLAMA_HEARTBEAT_INTERVAL_MS=60000 nohup node "$ROOT_DIR/lib/ollama-heartbeat-proxy.mjs" >>/tmp/crouter-ollama-heartbeat-proxy.log 2>&1 &
    _OLLAMA_HEARTBEAT_PROXY_PID=$!
    for _ollama_proxy_try in 1 2 3 4 5 6 7 8 9 10; do
      curl -fsS --max-time 1 "$HEALTH_CHECK_URL" 2>/dev/null | grep -q crouter-ollama-heartbeat && break
      sleep 0.2
    done
  fi
  curl -fsS --max-time 1 "$HEALTH_CHECK_URL" 2>/dev/null | grep -q crouter-ollama-heartbeat || die "Ollama heartbeat proxy failed to start at $BASE_URL"
fi
unset _local_selected_model _mlx_upstream_host _mlx_upstream_port _mlx_upstream_url _mlx_expected_upstream _mlx_health
'

POST_STOP='if [ -n "${_OLLAMA_HEARTBEAT_PROXY_PID:-}" ]; then kill "$_OLLAMA_HEARTBEAT_PROXY_PID" 2>/dev/null || true; wait "$_OLLAMA_HEARTBEAT_PROXY_PID" 2>/dev/null || true; _OLLAMA_HEARTBEAT_PROXY_PID=; fi; if [ -n "${_MLX_PROXY_PID:-}" ]; then kill "$_MLX_PROXY_PID" 2>/dev/null || true; wait "$_MLX_PROXY_PID" 2>/dev/null || true; _MLX_PROXY_PID=; fi'
HEALTH_CHECK_URL="http://127.0.0.1:11435/health"
