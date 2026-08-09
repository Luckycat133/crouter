#!/bin/sh
# Provider: Google Cloud Vertex AI — Anthropic models via local proxy.
# Proxy: vertex2anthropic (https://github.com/stackia/vertex2anthropic)
# Auth: Google Cloud ADC (gcloud auth application-default login)
# Model IDs: Vertex AI requires date suffix; confirm latest in console.
PROVIDER_NAME="vertex"
PROVIDER_DESC="Google Cloud Vertex AI (Anthropic models) via local vertex2anthropic proxy"

BASE_URL="http://127.0.0.1:18081"
MODEL="claude-sonnet-5@20260630"
CONTEXT_TOKENS="200000"

MODEL_OPUS="claude-opus-5@20260725"
MODEL_SONNET="claude-sonnet-5@20260630"
MODEL_HAIKU="claude-haiku-4-5@20260701"
MODEL_SUBAGENT="claude-sonnet-5@20260630"

EFFORT="max"

AUTH_MODE="none"
EXTRA_ENV="ANTHROPIC_AUTH_TOKEN=vertex-proxy
ANTHROPIC_API_KEY=vertex-proxy"

VERTEX_PROXY_DIR=${VERTEX_PROXY_DIR:-~/.local/share/vertex2anthropic}
VERTEX_PROXY_PORT=${VERTEX_PROXY_PORT:-18081}

vertex_proxy_running() {
  curl -fsS --max-time 2 "http://127.0.0.1:$VERTEX_PROXY_PORT/health" >/dev/null 2>&1
}

vertex_ensure_proxy() {
  if vertex_proxy_running; then return 0; fi
  [ -d "$VERTEX_PROXY_DIR" ] || {
    echo "vertex2anthropic proxy not found: $VERTEX_PROXY_DIR" >&2
    echo "Clone: git clone https://github.com/stackia/vertex2anthropic $VERTEX_PROXY_DIR" >&2
    return 1
  }
  command -v node >/dev/null 2>&1 || { echo "node not found" >&2; return 1; }
  _log_dir=${LOG_DIR:-$ROOT_DIR/logs}
  mkdir -p "$_log_dir"
  echo "Starting vertex2anthropic proxy on 127.0.0.1:$VERTEX_PROXY_PORT ..."
  ( cd "$VERTEX_PROXY_DIR" && nohup node index.js --port "$VERTEX_PROXY_PORT" > "$_log_dir/vertex-proxy.log" 2>&1 & )
  _i=0
  while [ "$_i" -lt 30 ]; do vertex_proxy_running && { echo "vertex2anthropic proxy up."; return 0; }; sleep 0.5; _i=$((_i+1)); done
  echo "vertex2anthropic proxy failed; see $_log_dir/vertex-proxy.log" >&2; return 1
}

vertex_stop_proxy() {
  command -v lsof >/dev/null 2>&1 || { echo "lsof not found" >&2; return 1; }
  _pid=$(lsof -t -a -iTCP:"$VERTEX_PROXY_PORT" -sTCP:LISTEN -c node 2>/dev/null | head -n1)
  [ -z "$_pid" ] && { echo "proxy not running."; return 0; }
  kill -TERM "$_pid" 2>/dev/null
  _i=0; while [ "$_i" -lt 20 ]; do kill -0 "$_pid" 2>/dev/null || break; sleep 0.5; _i=$((_i+1)); done
  kill -0 "$_pid" 2>/dev/null && kill -KILL "$_pid" 2>/dev/null && echo "Force-killed (PID $_pid)." || echo "Stopped (PID $_pid)."
}

PRE_START="vertex_ensure_proxy"
POST_STOP="vertex_stop_proxy"
HEALTH_CHECK_URL="http://127.0.0.1:$VERTEX_PROXY_PORT/health"