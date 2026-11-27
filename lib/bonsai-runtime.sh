#!/bin/sh
# Bonsai's native launcher owns sampling, cache, batching and speculative defaults.
bonsai_model_plan() {
  _bonsai_selected_model=$1
  _bonsai_upstream_port=8000
  _bonsai_adapter_port=11438
  _bonsai_inherit_defaults=0
  _bonsai_demo_dir=${BONSAI_DEMO_DIR:-$ROOT_DIR/../Bonsai-demo}
  case $1 in
    ternary-bonsai-2.5-27b)
      _bonsai_upstream_port=8081
      _bonsai_adapter_port=11439
      _bonsai_inherit_defaults=1
      ;;
  esac
  BASE_URL=http://127.0.0.1:$_bonsai_adapter_port
  MODEL_SERVICE=mlx-anthropic-adapter
  HEALTH_CHECK_URL=$BASE_URL/health
}

# A model listing alone does not prove which model is loaded. Both endpoints
# must identify the installed pack (symlink paths are compared by realpath).
bonsai_native_identity() {
  _bonsai_native_health=$(curl -fsS --max-time 3 "http://127.0.0.1:8081/health" 2>/dev/null) || return 1
  _bonsai_native_models=$(curl -fsS --max-time 3 "http://127.0.0.1:8081/v1/models" 2>/dev/null) || return 1
  node -e '
    const fs = require("fs");
    try {
      const expected = fs.realpathSync(process.argv[1]);
      const health = JSON.parse(process.argv[2]);
      const models = JSON.parse(process.argv[3]);
      if (health.status !== "healthy" || fs.realpathSync(health.loaded_model) !== expected) process.exit(1);
      const match = models.data?.find(row => {
        try { return fs.realpathSync(row.id) === expected; } catch { return false; }
      });
      if (!match) process.exit(1);
      process.stdout.write(match.id);
    } catch { process.exit(1); }
  ' "$_bonsai_demo_dir/models/Ternary-Bonsai-2.5-27B-mlx-2bit" "$_bonsai_native_health" "$_bonsai_native_models"
}

bonsai_start() {
  _BONSAI_PROXY_PID=
  _BONSAI_NATIVE_PID=
  # MODEL_SETUP already resolved the route before the launcher sealed its plan.
  # Startup consumes that plan; it must not write readonly provider fields.
  if lsof -nP -iTCP:"$_bonsai_adapter_port" -sTCP:LISTEN >/dev/null 2>&1; then
    die "Bonsai adapter port $_bonsai_adapter_port is already owned by another session"
  fi
  if [ "$_bonsai_inherit_defaults" = 1 ]; then
    if ! _bonsai_upstream_model=$(bonsai_native_identity); then
      # Never replace, kill or silently reuse an incompatible existing listener.
      if lsof -nP -iTCP:8081 -sTCP:LISTEN >/dev/null 2>&1; then
        die 'Bonsai native service on port 8081 cannot be verified as the selected Bonsai 2.5 model'
      fi
      [ -x "$_bonsai_demo_dir/scripts/start_mlx_server.sh" ] || die "Bonsai native launcher not found in $_bonsai_demo_dir"
      BONSAI_FAMILY=bonsai25 BONSAI_MODEL=27B PORT=8081 nohup "$_bonsai_demo_dir/scripts/start_mlx_server.sh" >>/tmp/crouter-bonsai-native.log 2>&1 &
      _BONSAI_NATIVE_PID=$!
      _bonsai_wait=0
      while [ "$_bonsai_wait" -lt 180 ]; do
        if _bonsai_upstream_model=$(bonsai_native_identity); then break; fi
        kill -0 "$_BONSAI_NATIVE_PID" 2>/dev/null || break
        _bonsai_wait=$((_bonsai_wait + 1))
        sleep 1
      done
      [ -n "$_bonsai_upstream_model" ] || die 'Bonsai 2.5 native service failed to become ready on port 8081; see /tmp/crouter-bonsai-native.log'
    fi
    MLX_INHERIT_DEFAULTS=1 MLX_HEARTBEAT_INTERVAL_MS=60000 MLX_PROXY_PORT="$_bonsai_adapter_port" MLX_UPSTREAM_HOST=127.0.0.1 MLX_UPSTREAM_PORT=8081 MLX_MODEL="$_bonsai_selected_model" MLX_UPSTREAM_MODEL="$_bonsai_upstream_model" nohup node "$ROOT_DIR/lib/anthropic-openai-proxy.mjs" >>/tmp/crouter-bonsai-proxy.log 2>&1 &
  else
    curl -fsS --max-time 3 http://127.0.0.1:8000/v1/models >/dev/null 2>&1 || die 'PrismML MLX runtime endpoint not reachable at http://127.0.0.1:8000'
    MLX_INHERIT_DEFAULTS=0 MLX_MAX_OUTPUT_TOKENS=262144 MLX_TOP_K=20 MLX_MIN_P=0.0 MLX_REASONING_EFFORT=xhigh MLX_HEARTBEAT_INTERVAL_MS=60000 MLX_PROXY_PORT="$_bonsai_adapter_port" MLX_UPSTREAM_HOST=127.0.0.1 MLX_UPSTREAM_PORT=8000 MLX_MODEL="$_bonsai_selected_model" MLX_UPSTREAM_MODEL="/Users/jack/.cache/huggingface/hub/models--ternary-bonsai-2-27b/snapshots/local" MLX_TEMPERATURE="$BONSAI_TEMPERATURE" MLX_TOP_P="$BONSAI_TOP_P" MLX_PRESENCE_PENALTY="$BONSAI_PRESENCE_PENALTY" MLX_FREQUENCY_PENALTY="$BONSAI_FREQUENCY_PENALTY" MLX_REPETITION_PENALTY="$BONSAI_REPETITION_PENALTY" nohup node "$ROOT_DIR/lib/anthropic-openai-proxy.mjs" >>/tmp/crouter-bonsai-proxy.log 2>&1 &
  fi
  _BONSAI_PROXY_PID=$!
  for _bonsai_try in 1 2 3 4 5 6 7 8 9 10; do
    _bonsai_proxy_health=$(curl -fsS --max-time 1 "$HEALTH_CHECK_URL" 2>/dev/null || true)
    if printf '%s\n' "$_bonsai_proxy_health" | node -e '
      let input=""; process.stdin.on("data", chunk => input += chunk);
      process.stdin.on("end", () => {
        try {
          const h=JSON.parse(input);
          process.exit(h.service === "crouter-mlx-anthropic-adapter" && h.model === process.argv[1] && h.upstream === "127.0.0.1:" + process.argv[2] ? 0 : 1);
        } catch { process.exit(1); }
      });
    ' "$_bonsai_selected_model" "$_bonsai_upstream_port"; then return 0; fi
    sleep 0.2
  done
  die "Bonsai adapter failed to start at $BASE_URL"
}

bonsai_stop() {
  if [ -n "${_BONSAI_PROXY_PID:-}" ]; then
    kill "$_BONSAI_PROXY_PID" 2>/dev/null || true
    wait "$_BONSAI_PROXY_PID" 2>/dev/null || true
    _BONSAI_PROXY_PID=
  fi
  if [ -n "${_BONSAI_NATIVE_PID:-}" ]; then
    kill "$_BONSAI_NATIVE_PID" 2>/dev/null || true
    wait "$_BONSAI_NATIVE_PID" 2>/dev/null || true
    _BONSAI_NATIVE_PID=
  fi
}
