#!/bin/sh
# Provider: local MLX and Ollama models exposed to Claude Code.
PROVIDER_NAME="ollama"
PROVIDER_DESC="Local models: multimodal MLX Qwen3.8 and Ollama DeepSeek"

BASE_URL="http://127.0.0.1:11435"
# Default to the DFlash profile while preserving explicit selections.
# The exact qwen3.8-27b ID retains the existing MLX route.
MODEL="qwen3.8:27b-dflash"
CONTEXT_TOKENS="65536"
# Keep context windows scoped to the selected model; both native Qwen routes
# and the DFlash profile retain their 262K window.
MODEL_CONTEXT_OVERRIDES="deepseek-v4-flash:q8=373760 deepseek-v4-flash=373760 qwen3.8-27b=262144 qwen3.8-27b-heretic:q4=262144 qwen3.8-27b-heretic:q4-dflash=262144 qwen3.8-27b-heretic=262144 qwen3.8:27b-dflash=262144 dflash/qwen3.8-27b=262144 inkling-2-mini=1048576 inkling-2-mini:latest=1048576 qwen3.6-hauhau:35b-a3b-q4_k_p=262144 qwen3.8-abliterated:27b-dflash=262144 abliterated-dflash/qwen3.8-27b=262144"
MODEL_SELF_ROUTE_MODELS="deepseek-v4-flash:q8 deepseek-v4-flash qwen3.8-27b qwen3.8-27b-heretic:q4 qwen3.8-27b-heretic:q4-dflash qwen3.8-27b-heretic qwen3.8:27b-dflash dflash/qwen3.8-27b qwen3.8-abliterated:27b-dflash abliterated-dflash/qwen3.8-27b qwen3.6-hauhau:35b-a3b-q4_k_p inkling-2-mini inkling-2-mini:latest"
MODEL_ALIASES="qwen3.8:27b-dflash dflash/qwen3.8-27b qwen3.8-abliterated:27b-dflash abliterated-dflash/qwen3.8-27b qwen3.6-hauhau:35b-a3b-q4_k_p inkling-2-mini:latest"
# Ollama's catalog appends :latest to these exact copies; keep their standard
# basenames in the selected ID without stripping tags from other models.
MODEL_ID_ALIASES="abliterated-dflash/qwen3.8-27b:latest=abliterated-dflash/qwen3.8-27b dflash/qwen3.8-27b:latest=dflash/qwen3.8-27b"
# Opt in only after installing the corresponding Ollama copies. Each keeps its
# variant while exposing a standard basename for usage pricing.
if [ "${OLLAMA_QWEN38_PRICING_ALIASES:-0}" = 1 ]; then
  MODEL_ID_ALIASES="$MODEL_ID_ALIASES qwen3.8:27b-dflash=dflash/qwen3.8-27b qwen3.8-abliterated:27b-dflash=abliterated-dflash/qwen3.8-27b"
fi
EFFORT="xhigh"

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

. "$ROOT_DIR/lib/inkling-runtime.sh"
MODEL_SETUP=ollama_model_plan
ollama_model_plan() {
  _ollama_effort_cap=
  ASSET_PLUGIN_DIRS=
  MODEL_SERVICE=ollama-heartbeat
  BASE_URL=http://127.0.0.1:11435
  EFFORT=max
  case $1 in
    inkling-2-mini|inkling-2-mini:latest)
      if [ "${OLLAMA_INKLING_MLX_VLM:-0}" = 1 ]; then inkling_model_plan "$1"; fi
      ;;
    qwen3.8-27b)
      MODEL_SERVICE=mlx-anthropic-adapter
      BASE_URL=http://127.0.0.1:11436
      ASSET_PLUGIN_DIRS="$ROOT_DIR/assets/plugins/qwen-local-multimodal"
      _mlx_upstream_host=${MLX_UPSTREAM_HOST:-10.211.55.2}
      _mlx_upstream_port=${MLX_UPSTREAM_PORT:-18080}
      case $_mlx_upstream_port in *[!0-9]*) die 'MLX_UPSTREAM_PORT must be an integer from 1 to 65535' ;; esac
      while [ "${_mlx_upstream_port#0}" != "$_mlx_upstream_port" ]; do
        _mlx_upstream_port=${_mlx_upstream_port#0}
      done
      case $_mlx_upstream_port in ''|??????*) die 'MLX_UPSTREAM_PORT must be an integer from 1 to 65535' ;; esac
      [ "$_mlx_upstream_port" -le 65535 ] || die 'MLX_UPSTREAM_PORT must be an integer from 1 to 65535'
      ;;
    # The stock Qwen template rejects the high level Ollama maps from xhigh.
    # The patched DFlash profile can use xhigh. The relay also caps overrides.
    qwen3.8:27b-dflash|dflash/qwen3.8-27b) EFFORT=xhigh; _ollama_effort_cap=xhigh ;;
    abliterated-dflash/qwen3.8-27b) EFFORT=medium; _ollama_effort_cap=medium ;;
    qwen3.8*) EFFORT=medium; _ollama_effort_cap=medium ;;
  esac
  HEALTH_CHECK_URL=$BASE_URL/health
}

PRE_START='
_OLLAMA_HEARTBEAT_PROXY_PID=
_MLX_PROXY_PID=
_local_selected_model=${_main_model:-$MODEL}
if [ "$MODEL_SERVICE" = inkling-mlx-vlm ]; then
  inkling_start
elif [ "$MODEL_SERVICE" = mlx-anthropic-adapter ]; then
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
  curl -fsS --max-time 3 http://127.0.0.1:11434 >/dev/null 2>&1 || die "Ollama not reachable at http://127.0.0.1:11434 — start it (ollama serve) and pull the selected model first"
  # A model-specific Jinja compatibility patch can preserve late system turns
  # and the preceding cached conversation. Never enable this for an unpatched
  # template, which would reject the same request before generation.
  _ollama_system_order_models=""
  case $_local_selected_model in
    qwen3.8-27b-heretic:q4)
      _ollama_template_info=$(curl -fsS --max-time 3 http://127.0.0.1:11434/api/show \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$_local_selected_model\"}") || die "Cannot inspect selected Ollama model template"
      _ollama_template_mode=$(printf "%s" "$_ollama_template_info" | node -e '\''
        let input = "";
        process.stdin.setEncoding("utf8");
        process.stdin.on("data", chunk => input += chunk);
        process.stdin.on("end", () => {
          try {
            const template = JSON.parse(input).template;
            if (typeof template !== "string") process.exit(1);
            process.stdout.write(template.startsWith("{#CROUTER_QWEN_SYSTEM_ORDER_V1 ") ? "preserve" : "fold");
          } catch { process.exit(1); }
        });
      '\'') || die "Invalid Ollama model template response"
      if [ "$_ollama_template_mode" = preserve ]; then
        _ollama_system_order_models=$_local_selected_model
      fi
      ;;
  esac
  _ollama_health=$(curl -fsS --max-time 1 "$HEALTH_CHECK_URL" 2>/dev/null || true)
  if printf "%s\n" "$_ollama_health" | grep -q crouter-ollama-heartbeat; then
    case $_local_selected_model in qwen3.8:27b-dflash|dflash/qwen3.8-27b)
      _ollama_dflash_versions=qwen38-dflash-named-effort-v2
      [ "$_local_selected_model" != qwen3.8:27b-dflash ] || _ollama_dflash_versions="qwen38-dflash-named-effort-v[12]"
      printf "%s\n" "$_ollama_health" | grep -Fq "\"effort_cap\":\"xhigh\"" &&
        printf "%s\n" "$_ollama_health" | grep -Eq "\"dflash_effort_rewrite\":\"$_ollama_dflash_versions\"" ||
        die "Ollama relay uses another DFlash effort profile; wait for its current task to finish, then restart the relay"
      ;;
    esac
    if [ -n "$_ollama_system_order_models" ]; then
      printf "%s\n" "$_ollama_health" | grep -Fq "\"system_order_models\":\"$_ollama_system_order_models\"" || \
        die "Ollama relay predates the selected model template; restart the relay after its current task finishes"
    elif printf "%s\n" "$_ollama_health" | grep -Eq "\"system_order_models\":\"[^\"]+\""; then
      die "Ollama relay uses another model template profile; restart it after its current task finishes"
    fi
    # Reuse the running relay only when it clamps to the level this model needs.
    printf "%s\n" "$_ollama_health" | grep -Fq "\"effort_cap\":\"$_ollama_effort_cap\"" || \
      die "Ollama relay uses another model effort profile; wait for its current task to finish, then restart the relay"
  fi
  if ! printf "%s\n" "$_ollama_health" | grep -q crouter-ollama-heartbeat; then
    OLLAMA_SYSTEM_ORDER_MODELS=$_ollama_system_order_models OLLAMA_EFFORT_MAX=$_ollama_effort_cap OLLAMA_HEARTBEAT_INTERVAL_MS=60000 nohup node "$ROOT_DIR/lib/ollama-heartbeat-proxy.mjs" >>/tmp/crouter-ollama-heartbeat-proxy.log 2>&1 &
    _OLLAMA_HEARTBEAT_PROXY_PID=$!
    for _ollama_proxy_try in 1 2 3 4 5 6 7 8 9 10; do
      curl -fsS --max-time 1 "$HEALTH_CHECK_URL" 2>/dev/null | grep -q crouter-ollama-heartbeat && break
      sleep 0.2
    done
  fi
  curl -fsS --max-time 1 "$HEALTH_CHECK_URL" 2>/dev/null | grep -q crouter-ollama-heartbeat || die "Ollama heartbeat proxy failed to start at $BASE_URL"
fi
unset _local_selected_model _ollama_effort_cap _ollama_dflash_versions _ollama_system_order_models _ollama_template_info _ollama_template_mode _ollama_health _mlx_upstream_host _mlx_upstream_port _mlx_upstream_url _mlx_expected_upstream _mlx_health
'

POST_STOP='inkling_stop; if [ -n "${_OLLAMA_HEARTBEAT_PROXY_PID:-}" ]; then kill "$_OLLAMA_HEARTBEAT_PROXY_PID" 2>/dev/null || true; wait "$_OLLAMA_HEARTBEAT_PROXY_PID" 2>/dev/null || true; _OLLAMA_HEARTBEAT_PROXY_PID=; fi; if [ -n "${_MLX_PROXY_PID:-}" ]; then kill "$_MLX_PROXY_PID" 2>/dev/null || true; wait "$_MLX_PROXY_PID" 2>/dev/null || true; _MLX_PROXY_PID=; fi'
HEALTH_CHECK_URL="http://127.0.0.1:11435/health"
