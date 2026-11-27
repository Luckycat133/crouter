#!/bin/sh
# Session-owned MLX server and the existing Anthropic adapter. No model I/O at load.

bonsai25_stop() {
  for _b25_pid in "${_BONSAI25_PROXY_PID:-}" "${_BONSAI25_SERVER_PID:-}"; do
    [ -n "$_b25_pid" ] || continue
    kill "$_b25_pid" 2>/dev/null || true
    wait "$_b25_pid" 2>/dev/null || true
  done
  _BONSAI25_PROXY_PID= _BONSAI25_SERVER_PID=
}

bonsai25_start() {
  _BONSAI25_PROXY_PID= _BONSAI25_SERVER_PID=
  [ -n "${BONSAI25_DEMO_DIR:-}" ] || die 'Set BONSAI25_DEMO_DIR in config.sh to the existing Bonsai demo checkout'
  [ -n "${BONSAI25_MODEL_DIR:-}" ] || die 'Set BONSAI25_MODEL_DIR in config.sh to the existing Bonsai 2.5 MLX weights'
  case $BONSAI25_DEMO_DIR in /*) ;; *) die 'BONSAI25_DEMO_DIR must be an absolute path' ;; esac
  case $BONSAI25_MODEL_DIR in /*) ;; *) die 'BONSAI25_MODEL_DIR must be an absolute path' ;; esac
  [ -f "$BONSAI25_MODEL_DIR/config.json" ] || die 'BONSAI25_MODEL_DIR has no config.json; no weights were downloaded'
  [ -f "$BONSAI25_DEMO_DIR/scripts/start_mlx_server.sh" ] &&
    [ -x "$BONSAI25_DEMO_DIR/.venv-vlm/bin/python" ] || die 'BONSAI25_DEMO_DIR needs its existing start_mlx_server.sh and .venv-vlm runtime'
  for _b25_port in 8081 11439; do
    if lsof -nP -iTCP:"$_b25_port" -sTCP:LISTEN >/dev/null 2>&1; then
      die "Bonsai 2.5 port $_b25_port is already in use; let its owning task finish before launching this profile"
    fi
  done
  _b25_ps=$(curl -fsS --max-time 2 http://127.0.0.1:11434/api/ps 2>/dev/null || true)
  if [ -n "$_b25_ps" ]; then
    printf '%s' "$_b25_ps" | "$NODE_BIN" -e '
      let s=""; process.stdin.on("data", c=>s+=c); process.stdin.on("end",()=>{
        try { const d=JSON.parse(s); process.exit(Array.isArray(d.models)&&d.models.length===0?0:1); }
        catch { process.exit(1); }
      });' || die 'Ollama has a loaded model or returned an invalid residency status; no model was stopped'
  fi
  if pgrep -f '(^|/)(llama-server)( |$)|(^|/)(python[0-9.]*)( +-m +mlx_(vlm|lm)\.server)( |$)' >/dev/null 2>&1; then
    die 'Another local inference server is running; no process was stopped'
  fi
  mkdir -p "${LOG_DIR:-$ROOT_DIR/logs}" || die 'Cannot create the crouter log directory'
  _b25_server_log=${LOG_DIR:-$ROOT_DIR/logs}/bonsai25-server.log
  _b25_proxy_log=${LOG_DIR:-$ROOT_DIR/logs}/bonsai25-proxy.log
  (
    # Do not inherit another model's quantization or speculative settings.
    unset MLX_VLM_DRAFT_MODEL MLX_VLM_DRAFT_KIND MLX_VLM_DRAFT_BLOCK_SIZE
    unset KV_BITS KV_KEY_BITS KV_VALUE_BITS KV_QUANT_SCHEME KV_KEY_SCHEME KV_VALUE_SCHEME KV_GROUP_SIZE QUANTIZED_KV_START MAX_KV_SIZE
    unset APC_TEXT_EMBED_HASH_FIX APC_IMAGE_EMBED_HASH_FIX MLX_VLM_THINKING_BUDGET
    export BONSAI_MODEL=27B BONSAI_FAMILY=bonsai25 PORT=8081
    export APC_ENABLED=1 APC_DISK_ENABLED=0 APC_MEMORY_MAX_GB=4 APC_CHECKPOINT_ENTRIES=2
    export MLX_VLM_TOKEN_QUEUE_TIMEOUT=0 MLX_VLM_MAX_NUM_SEQS=1
    exec /bin/sh "$BONSAI25_DEMO_DIR/scripts/start_mlx_server.sh" \
      --model "$BONSAI25_MODEL_DIR" --prefill-step-size 256 --max-tokens 262144
  ) >>"$_b25_server_log" 2>&1 &
  _BONSAI25_SERVER_PID=$!
  _b25_ready=0
  _b25_try=0
  while [ "$_b25_try" -lt 150 ]; do
    _b25_try=$((_b25_try + 1))
    kill -0 "$_BONSAI25_SERVER_PID" 2>/dev/null || break
    _b25_health=$(curl -fsS --max-time 2 http://127.0.0.1:8081/health 2>/dev/null || true)
    if printf '%s' "$_b25_health" | "$NODE_BIN" -e '
      let s=""; process.stdin.on("data",c=>s+=c); process.stdin.on("end",()=>{
        try { const d=JSON.parse(s),fs=require("fs"); process.exit(d.status==="healthy"&&d.apc_enabled===true&&fs.realpathSync(d.loaded_model)===fs.realpathSync(process.argv[1])?0:1); }
        catch { process.exit(1); }
      });' "$BONSAI25_MODEL_DIR"; then _b25_ready=1; break; fi
    sleep 2
  done
  if [ "$_b25_ready" != 1 ]; then
    bonsai25_stop
    die "Bonsai 2.5 did not become healthy with the configured model and APC; see $_b25_server_log"
  fi
  (
    unset MLX_MAX_OUTPUT_TOKENS MLX_ALLOW_ANY_MODEL
    MLX_PROXY_HOST=127.0.0.1 MLX_PROXY_PORT=11439 MLX_UPSTREAM_HOST=127.0.0.1 MLX_UPSTREAM_PORT=8081 \
    MLX_MODEL=ternary-bonsai-2.5-27b MLX_UPSTREAM_MODEL="$BONSAI25_MODEL_DIR" \
    MLX_TEMPERATURE=1 MLX_TOP_P=0.95 MLX_TOP_K=20 MLX_MIN_P=0 \
    MLX_REPETITION_PENALTY=1 MLX_PRESENCE_PENALTY=0 MLX_FREQUENCY_PENALTY=0 \
    MLX_REASONING_EFFORT=xhigh MLX_HEARTBEAT_INTERVAL_MS=60000 \
    exec node "$ROOT_DIR/lib/anthropic-openai-proxy.mjs" \
      --upstream-model "$BONSAI25_MODEL_DIR"
  ) >>"$_b25_proxy_log" 2>&1 &
  _BONSAI25_PROXY_PID=$!
  _b25_ready=0
  for _b25_try in 1 2 3 4 5 6 7 8 9 10; do
    kill -0 "$_BONSAI25_PROXY_PID" 2>/dev/null || break
    _b25_health=$(curl -fsS --max-time 1 http://127.0.0.1:11439/health 2>/dev/null || true)
    if printf '%s' "$_b25_health" | "$NODE_BIN" -e '
      let s=""; process.stdin.on("data",c=>s+=c); process.stdin.on("end",()=>{
        try { const d=JSON.parse(s); process.exit(d.service==="crouter-mlx-anthropic-adapter"&&d.upstream==="127.0.0.1:8081"&&d.model==="ternary-bonsai-2.5-27b"?0:1); }
        catch { process.exit(1); }
      });'; then _b25_ready=1; break; fi
    sleep 0.2
  done
  if [ "$_b25_ready" != 1 ]; then
    bonsai25_stop
    die "Bonsai 2.5 adapter did not become healthy; see $_b25_proxy_log"
  fi
}
