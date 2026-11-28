#!/bin/sh
# The native Inkling launcher owns sampling, cache and speculative defaults.
inkling_model_plan() {
  _inkling_selected_model=$1
  _inkling_runtime_dir=${INKLING_MLX_RUNTIME_DIR:-$HOME/.local/share/local-llm/inkling-mlx-vlm}
  MODEL_SERVICE=inkling-mlx-vlm
  BASE_URL=http://127.0.0.1:11440
  HEALTH_CHECK_URL=$BASE_URL/health
}

# A listing alone does not establish which model is loaded. Both endpoints
# must identify runtime/model, accepting symlink spellings only by realpath.
inkling_native_identity() {
  _inkling_native_health=$(curl -fsS --max-time 3 http://127.0.0.1:8082/health 2>/dev/null) || return 1
  _inkling_native_models=$(curl -fsS --max-time 3 http://127.0.0.1:8082/v1/models 2>/dev/null) || return 1
  node -e '
    const fs = require("fs");
    try {
      const expected = fs.realpathSync(process.argv[1]);
      const health = JSON.parse(process.argv[2]);
      const models = JSON.parse(process.argv[3]);
      if (health.status !== "healthy" || health.model_ready === false ||
          fs.realpathSync(health.loaded_model) !== expected) process.exit(1);
      const match = models.data?.find(row => {
        try { return fs.realpathSync(row.id) === expected; } catch { return false; }
      });
      if (!match) process.exit(1);
      process.stdout.write(match.id);
    } catch { process.exit(1); }
  ' "$_inkling_runtime_dir/model" "$_inkling_native_health" "$_inkling_native_models"
}

inkling_adapter_identity() {
  _inkling_adapter_health=$(curl -fsS --max-time 1 "$HEALTH_CHECK_URL" 2>/dev/null) || return 1
  node -e '
    const fs = require("fs");
    try {
      const h = JSON.parse(process.argv[1]);
      const expected = fs.realpathSync(process.argv[3]);
      if (h.service !== "crouter-mlx-anthropic-adapter" || h.model !== process.argv[2] ||
          h.upstream !== "127.0.0.1:8082" || h.inherit_defaults !== true ||
          fs.realpathSync(h.upstream_model) !== expected) process.exit(1);
    } catch { process.exit(1); }
  ' "$_inkling_adapter_health" "$_inkling_selected_model" "$_inkling_runtime_dir/model"
}

inkling_start() {
  _INKLING_PROXY_PID=
  _INKLING_NATIVE_PID=
  # Consume the sealed plan; do not run MODEL_SETUP a second time here.
  if lsof -nP -iTCP:11440 -sTCP:LISTEN >/dev/null 2>&1; then
    if _inkling_upstream_model=$(inkling_native_identity) && inkling_adapter_identity; then return 0; fi
    die 'Inkling adapter port 11440 is already owned by an incompatible or unverifiable service'
  fi
  if ! _inkling_upstream_model=$(inkling_native_identity); then
    if lsof -nP -iTCP:8082 -sTCP:LISTEN >/dev/null 2>&1; then
      die 'Inkling native service on port 8082 cannot be verified as runtime/model'
    fi
    [ -x "$_inkling_runtime_dir/start-server.sh" ] || die "Inkling native launcher not found in $_inkling_runtime_dir"
    nohup "$_inkling_runtime_dir/start-server.sh" >>/tmp/crouter-inkling-native.log 2>&1 &
    _INKLING_NATIVE_PID=$!
    _inkling_wait=0
    while [ "$_inkling_wait" -lt 180 ]; do
      if _inkling_upstream_model=$(inkling_native_identity); then break; fi
      kill -0 "$_INKLING_NATIVE_PID" 2>/dev/null || break
      _inkling_wait=$((_inkling_wait + 1))
      sleep 1
    done
    [ -n "$_inkling_upstream_model" ] || die 'Inkling native service failed to become ready on port 8082; see /tmp/crouter-inkling-native.log'
  fi
  MLX_INHERIT_DEFAULTS=1 MLX_HEARTBEAT_INTERVAL_MS=60000 MLX_PROXY_PORT=11440 MLX_UPSTREAM_HOST=127.0.0.1 MLX_UPSTREAM_PORT=8082 MLX_MODEL="$_inkling_selected_model" MLX_UPSTREAM_MODEL="$_inkling_upstream_model" nohup node "$ROOT_DIR/lib/anthropic-openai-proxy.mjs" >>/tmp/crouter-inkling-proxy.log 2>&1 &
  _INKLING_PROXY_PID=$!
  for _inkling_try in 1 2 3 4 5 6 7 8 9 10; do
    if inkling_adapter_identity; then return 0; fi
    kill -0 "$_INKLING_PROXY_PID" 2>/dev/null || break
    sleep 0.2
  done
  die 'Inkling adapter failed to become ready at http://127.0.0.1:11440'
}

inkling_stop() {
  if [ -n "${_INKLING_PROXY_PID:-}" ]; then
    kill "$_INKLING_PROXY_PID" 2>/dev/null || true
    wait "$_INKLING_PROXY_PID" 2>/dev/null || true
    _INKLING_PROXY_PID=
  fi
  if [ -n "${_INKLING_NATIVE_PID:-}" ]; then
    kill "$_INKLING_NATIVE_PID" 2>/dev/null || true
    wait "$_INKLING_NATIVE_PID" 2>/dev/null || true
    _INKLING_NATIVE_PID=
  fi
}
