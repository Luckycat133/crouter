#!/bin/sh
# Shared helpers for Antigravity-based providers.
# Sourced by providers/antigravity-*.sh; not a provider itself.

antigravity_port() { printf '%s' "${ANTIGRAVITY_PORT:-18080}"; }
antigravity_base_url() { printf 'http://127.0.0.1:%s' "$(antigravity_port)"; }

antigravity_gateway_running() {
  curl -fsS --max-time 2 "$(antigravity_base_url)/health" >/dev/null 2>&1
}

# PRE_START hook: start the local gateway if it is not already healthy.
antigravity_ensure_gateway() {
  if antigravity_gateway_running; then
    # Preserve ownership when this same crouter session already started it;
    # otherwise a healthy process predates us and must be left alone.
    if [ "${ANTIGRAVITY_GATEWAY_OWNED:-0}" != 1 ]; then
      ANTIGRAVITY_GATEWAY_OWNED=0
      ANTIGRAVITY_GATEWAY_PID=""
    fi
    return 0
  fi

  ANTIGRAVITY_GATEWAY_OWNED=0
  ANTIGRAVITY_GATEWAY_PID=""

  _proxy_dir=${ANTIGRAVITY_PROXY_DIR:-$ROOT_DIR/antigravity-claude-proxy}
  [ -d "$_proxy_dir" ] || {
    echo "Antigravity proxy directory not found: $_proxy_dir (set ANTIGRAVITY_PROXY_DIR in config.sh)" >&2
    return 1
  }
  command -v npm >/dev/null 2>&1 || { echo "npm not found; cannot start Antigravity gateway." >&2; return 1; }

  # Ensure proxy patch is applied when GPT-OSS or patchable models are configured.
  case "${_main_model:-} ${MODEL:-} ${MODEL_ALIASES:-}" in
    *gpt-oss*)
      if [ -x "$ROOT_DIR/bin/antigravity-proxy-patch" ]; then
        if ! grep -qF "gpt-oss" "$_proxy_dir/src/constants.js" 2>/dev/null; then
          "$ROOT_DIR/bin/antigravity-proxy-patch" --proxy-dir "$_proxy_dir" >/dev/null 2>&1 || true
        fi
      fi
      ;;
  esac

  _log_dir=${LOG_DIR:-$ROOT_DIR/logs}
  mkdir -p "$_log_dir"
  echo "Starting Antigravity gateway on 127.0.0.1:$(antigravity_port) ..."
  (
    cd "$_proxy_dir" || exit 1
    exec nohup env HOST=127.0.0.1 PORT="$(antigravity_port)" npm start
  ) > "$_log_dir/antigravity-proxy.log" 2>&1 &
  ANTIGRAVITY_GATEWAY_PID=$!

  _i=0
  while [ "$_i" -lt 30 ]; do
    if antigravity_gateway_running; then
      if command -v lsof >/dev/null 2>&1; then
        _listener_pid=$(lsof -t -a -iTCP:"$(antigravity_port)" -sTCP:LISTEN 2>/dev/null | head -n 1)
        [ -n "$_listener_pid" ] && ANTIGRAVITY_GATEWAY_PID=$_listener_pid
      fi
      ANTIGRAVITY_GATEWAY_OWNED=1
      echo "Antigravity gateway is up."
      return 0
    fi
    sleep 0.5
    _i=$((_i + 1))
  done
  kill "${ANTIGRAVITY_GATEWAY_PID:-}" 2>/dev/null || true
  ANTIGRAVITY_GATEWAY_PID=""
  echo "Antigravity gateway did not become healthy; see $_log_dir/antigravity-proxy.log" >&2
  return 1
}

# POST_STOP hook: stop the node process listening on the gateway port.
antigravity_stop_gateway() {
  if [ "${ANTIGRAVITY_GATEWAY_OWNED:-0}" != 1 ]; then
    return 0
  fi
  _pid=${ANTIGRAVITY_GATEWAY_PID:-}
  if [ -z "$_pid" ]; then
    ANTIGRAVITY_GATEWAY_OWNED=0
    return 0
  fi
  if command -v lsof >/dev/null 2>&1; then
    _listener_pid=$(lsof -t -a -iTCP:"$(antigravity_port)" -sTCP:LISTEN 2>/dev/null | head -n 1)
    if [ -n "$_listener_pid" ] && [ "$_listener_pid" != "$_pid" ]; then
      echo "Antigravity gateway ownership changed; leaving PID $_listener_pid running." >&2
      ANTIGRAVITY_GATEWAY_OWNED=0
      ANTIGRAVITY_GATEWAY_PID=""
      return 0
    fi
  fi
  kill -TERM "$_pid" 2>/dev/null
  _i=0
  while [ "$_i" -lt 20 ]; do
    kill -0 "$_pid" 2>/dev/null || break
    sleep 0.5
    _i=$((_i + 1))
  done
  if kill -0 "$_pid" 2>/dev/null; then
    kill -KILL "$_pid" 2>/dev/null && echo "Force-killed Antigravity gateway (PID $_pid)."
  else
    echo "Stopped Antigravity gateway (PID $_pid)."
  fi
  ANTIGRAVITY_GATEWAY_OWNED=0
  ANTIGRAVITY_GATEWAY_PID=""
}
