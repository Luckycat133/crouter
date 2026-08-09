#!/bin/sh
# Provider: AWS Bedrock — Anthropic models via local proxy.
# Proxy: bedrock-proxy (https://github.com/jparkerweb/bedrock-proxy-endpoint)
# Auth: AWS credential chain (aws configure / IAM role / env vars)
# Model IDs: Bedrock uses ARN format; confirm latest in console.
PROVIDER_NAME="bedrock"
PROVIDER_DESC="AWS Bedrock (Anthropic models) via local bedrock-proxy"

BASE_URL="http://127.0.0.1:18082"
MODEL="anthropic.claude-5-sonnet-20260630-v1:0"
CONTEXT_TOKENS="200000"

MODEL_OPUS="anthropic.claude-5-opus-20260725-v1:0"
MODEL_SONNET="anthropic.claude-5-sonnet-20260630-v1:0"
MODEL_HAIKU="anthropic.claude-4-5-haiku-20260701-v1:0"
MODEL_SUBAGENT="anthropic.claude-5-sonnet-20260630-v1:0"

EFFORT="max"

AUTH_MODE="none"
EXTRA_ENV="ANTHROPIC_AUTH_TOKEN=bedrock-proxy
ANTHROPIC_API_KEY=bedrock-proxy"

BEDROCK_PROXY_DIR=${BEDROCK_PROXY_DIR:-~/.local/share/bedrock-proxy}
BEDROCK_PROXY_PORT=${BEDROCK_PROXY_PORT:-18082}

bedrock_proxy_running() {
  curl -fsS --max-time 2 "http://127.0.0.1:$BEDROCK_PROXY_PORT/health" >/dev/null 2>&1
}

bedrock_ensure_proxy() {
  if bedrock_proxy_running; then return 0; fi
  [ -d "$BEDROCK_PROXY_DIR" ] || {
    echo "bedrock-proxy not found: $BEDROCK_PROXY_DIR" >&2
    echo "Clone: git clone https://github.com/jparkerweb/bedrock-proxy-endpoint $BEDROCK_PROXY_DIR" >&2
    return 1
  }
  command -v node >/dev/null 2>&1 || { echo "node not found" >&2; return 1; }
  _log_dir=${LOG_DIR:-$ROOT_DIR/logs}
  mkdir -p "$_log_dir"
  echo "Starting bedrock-proxy on 127.0.0.1:$BEDROCK_PROXY_PORT ..."
  ( cd "$BEDROCK_PROXY_DIR" && nohup node index.js --port "$BEDROCK_PROXY_PORT" > "$_log_dir/bedrock-proxy.log" 2>&1 & )
  _i=0
  while [ "$_i" -lt 30 ]; do bedrock_proxy_running && { echo "bedrock-proxy up."; return 0; }; sleep 0.5; _i=$((_i+1)); done
  echo "bedrock-proxy failed; see $_log_dir/bedrock-proxy.log" >&2; return 1
}

bedrock_stop_proxy() {
  command -v lsof >/dev/null 2>&1 || { echo "lsof not found" >&2; return 1; }
  _pid=$(lsof -t -a -iTCP:"$BEDROCK_PROXY_PORT" -sTCP:LISTEN -c node 2>/dev/null | head -n1)
  [ -z "$_pid" ] && { echo "proxy not running."; return 0; }
  kill -TERM "$_pid" 2>/dev/null
  _i=0; while [ "$_i" -lt 20 ]; do kill -0 "$_pid" 2>/dev/null || break; sleep 0.5; _i=$((_i+1)); done
  kill -0 "$_pid" 2>/dev/null && kill -KILL "$_pid" 2>/dev/null && echo "Force-killed (PID $_pid)." || echo "Stopped (PID $_pid)."
}

PRE_START="bedrock_ensure_proxy"
POST_STOP="bedrock_stop_proxy"
HEALTH_CHECK_URL="http://127.0.0.1:$BEDROCK_PROXY_PORT/health"