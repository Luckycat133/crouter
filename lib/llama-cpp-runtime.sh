#!/bin/sh
# Lifecycle for the configured Inkling Unbound runtime; no inference tuning here.
llama_cpp_model_plan() {
  case $1 in
    inkling-2-mini-unbound-v3) ;;
    *) die 'llama-cpp currently supports inkling-2-mini-unbound-v3; run: crouter llama-cpp' ;;
  esac
  _llama_cpp_selected_model=$1
  _llama_cpp_runtime_dir=${INKLING_UNBOUND_RUNTIME_DIR:-$HOME/.local/share/local-llm/inkling-unbound-llama}
  MODEL_SERVICE=inkling-unbound-llama-cpp
  BASE_URL=http://127.0.0.1:11441
  HEALTH_CHECK_URL=$BASE_URL/health
}

# Check the declared file and actual per-slot allocation, not just a friendly ID.
llama_cpp_native_identity() {
  _llama_cpp_health=$(curl -fsS --max-time 3 http://127.0.0.1:8085/health 2>/dev/null) || return 1
  _llama_cpp_props=$(curl -fsS --max-time 3 http://127.0.0.1:8085/props 2>/dev/null) || return 1
  _llama_cpp_models=$(curl -fsS --max-time 3 http://127.0.0.1:8085/v1/models 2>/dev/null) || return 1
  [ -x "$_llama_cpp_runtime_dir/start-server.sh" ] || return 1
  _llama_cpp_plan=$("$_llama_cpp_runtime_dir/start-server.sh" --check) || return 1
  node -e '
    const fs = require("fs");
    const path = require("path");
    try {
      const [plan, health, props, models] = process.argv.slice(1, 5).map(JSON.parse);
      const alias = process.argv[5];
      if (plan.alias !== alias || plan.context_tokens !== 524288 || health.status !== "ok") process.exit(1);
      if (typeof plan.model_path !== "string" || !path.isAbsolute(plan.model_path)) process.exit(1);
      const expected = fs.realpathSync(plan.model_path);
      if (!fs.statSync(expected).isFile() || fs.realpathSync(props.model_path) !== expected) process.exit(1);
      const context = props.default_generation_settings?.n_ctx;
      if (!Number.isSafeInteger(context) || context < plan.context_tokens) process.exit(1);
      if (!models.data?.some(row => row.id === alias)) process.exit(1);
      process.stdout.write(alias);
    } catch { process.exit(1); }
  ' "$_llama_cpp_plan" "$_llama_cpp_health" "$_llama_cpp_props" "$_llama_cpp_models" "$_llama_cpp_selected_model"
}

llama_cpp_adapter_identity() {
  _llama_cpp_adapter_health=$(curl -fsS --max-time 1 "$HEALTH_CHECK_URL" 2>/dev/null) || return 1
  node -e '
    try {
      const h = JSON.parse(process.argv[1]);
      const model = process.argv[2];
      if (h.service !== "crouter-mlx-anthropic-adapter" || h.model !== model ||
          h.upstream !== "127.0.0.1:8085" || h.upstream_model !== model ||
          h.inherit_defaults !== true) process.exit(1);
    } catch { process.exit(1); }
  ' "$_llama_cpp_adapter_health" "$_llama_cpp_selected_model"
}

llama_cpp_start() {
  _LLAMA_CPP_PROXY_PID=
  _LLAMA_CPP_NATIVE_PID=
  if lsof -nP -iTCP:11441 -sTCP:LISTEN >/dev/null 2>&1; then
    if _llama_cpp_upstream_model=$(llama_cpp_native_identity) && llama_cpp_adapter_identity; then return 0; fi
    die 'llama.cpp adapter port 11441 is already owned by an incompatible or unverifiable service'
  fi
  if ! _llama_cpp_upstream_model=$(llama_cpp_native_identity); then
    if lsof -nP -iTCP:8085 -sTCP:LISTEN >/dev/null 2>&1; then
      die 'llama.cpp native service on port 8085 cannot be verified as the configured Inkling Unbound model and context'
    fi
    [ -x "$_llama_cpp_runtime_dir/start-server.sh" ] || die "Inkling Unbound native launcher not found in $_llama_cpp_runtime_dir"
    nohup "$_llama_cpp_runtime_dir/start-server.sh" >>/tmp/crouter-llama-cpp-native.log 2>&1 &
    _LLAMA_CPP_NATIVE_PID=$!
    _llama_cpp_wait=0
    while [ "$_llama_cpp_wait" -lt 300 ]; do
      if _llama_cpp_upstream_model=$(llama_cpp_native_identity); then break; fi
      kill -0 "$_LLAMA_CPP_NATIVE_PID" 2>/dev/null || break
      _llama_cpp_wait=$((_llama_cpp_wait + 1))
      sleep 1
    done
    [ -n "$_llama_cpp_upstream_model" ] || die 'Inkling Unbound native service failed to become ready on port 8085; see /tmp/crouter-llama-cpp-native.log'
  fi
  MLX_INHERIT_DEFAULTS=1 MLX_HEARTBEAT_INTERVAL_MS=60000 MLX_PROXY_PORT=11441 MLX_UPSTREAM_HOST=127.0.0.1 MLX_UPSTREAM_PORT=8085 MLX_MODEL="$_llama_cpp_selected_model" MLX_UPSTREAM_MODEL="$_llama_cpp_upstream_model" nohup node "$ROOT_DIR/lib/anthropic-openai-proxy.mjs" >>/tmp/crouter-llama-cpp-proxy.log 2>&1 &
  _LLAMA_CPP_PROXY_PID=$!
  for _llama_cpp_try in 1 2 3 4 5 6 7 8 9 10; do
    if llama_cpp_adapter_identity; then return 0; fi
    kill -0 "$_LLAMA_CPP_PROXY_PID" 2>/dev/null || break
    sleep 0.2
  done
  die 'Inkling Unbound adapter failed to become ready at http://127.0.0.1:11441'
}

llama_cpp_stop() {
  if [ -n "${_LLAMA_CPP_PROXY_PID:-}" ]; then
    kill "$_LLAMA_CPP_PROXY_PID" 2>/dev/null || true
    wait "$_LLAMA_CPP_PROXY_PID" 2>/dev/null || true
    _LLAMA_CPP_PROXY_PID=
  fi
  if [ -n "${_LLAMA_CPP_NATIVE_PID:-}" ]; then
    kill "$_LLAMA_CPP_NATIVE_PID" 2>/dev/null || true
    wait "$_LLAMA_CPP_NATIVE_PID" 2>/dev/null || true
    _LLAMA_CPP_NATIVE_PID=
  fi
}
