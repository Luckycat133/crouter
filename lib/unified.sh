#!/bin/sh
# Unified gateway lifecycle and route snapshots (formerly in bin/crouter).
build_all_routes() {
  _routes_dest=$1 _rt=$2
  for _n in $(provider_names); do
    case " ${CROUTER_ALL_EXCLUDE_PROVIDERS:-} " in *" $_n "*) continue ;; esac
    if ! (
      load_provider "$_n"
      [ -z "${NATIVE_BACKEND:-}" ] || exit 0
      _surface_candidates=
      if is_surface_provider; then
        resolve_surface_tokens 1
        _surface_candidates=$(build_surface_candidates) || exit 1
      fi
      if [ "$AUTH_MODE" = keypool ]; then
        _plus_pool=
        for _ref in ${PLUS_KEYS:-}; do
          _t=$(kc_get "$_ref")
          [ -z "$_t" ] || _plus_pool="${_plus_pool:+$_plus_pool }$_t"
        done
        _main_pool=
        for _ref in ${AUTH_KEYS:-}; do
          _t=$(kc_get "$_ref")
          [ -z "$_t" ] || _main_pool="${_main_pool:+$_main_pool }$_t"
        done
        _surface_candidates=$(build_legacy_keypool_candidates) || exit 1
      fi
      _api_key=
      if [ -n "${API_KEY_ENV:-}" ] && [ -n "$(printenv "$API_KEY_ENV" 2>/dev/null)" ]; then _api_key=$(printenv "$API_KEY_ENV")
      elif [ -n "${API_KEY_REF:-}" ]; then _api_key=$(kc_get "$API_KEY_REF")
      else
        case $AUTH_MODE in
          keychain) [ -z "$AUTH_REFERENCE" ] || _api_key=$(kc_get "$AUTH_REFERENCE") ;;
          env)
            [ -z "$AUTH_REFERENCE" ] || _api_key=$(printenv "$AUTH_REFERENCE" 2>/dev/null)
            if [ -z "$_api_key" ] && [ -n "$AUTH_KEYCHAIN_FALLBACK" ]; then _api_key=$(kc_get "$AUTH_KEYCHAIN_FALLBACK"); fi ;;
          command) [ -z "$AUTH_REFERENCE" ] || _api_key=$(eval "$AUTH_REFERENCE" 2>/dev/null) ;;
          static) _api_key=$AUTH_REFERENCE ;;
        esac
      fi
      _def_token=
      if [ -n "${DEFAULT_TOKEN_ENV:-}" ] && [ -n "$(printenv "$DEFAULT_TOKEN_ENV" 2>/dev/null)" ]; then _def_token=$(printenv "$DEFAULT_TOKEN_ENV")
      elif [ -n "${DEFAULT_TOKEN_ENV_FALLBACK:-}" ] && [ -n "$(printenv "$DEFAULT_TOKEN_ENV_FALLBACK" 2>/dev/null)" ]; then _def_token=$(printenv "$DEFAULT_TOKEN_ENV_FALLBACK"); fi
      _te=
      if [ "$AUTH_MODE" = none ]; then
        _ifs=$IFS; IFS='
;'
        for _kv in $EXTRA_ENV; do
          case $_kv in ANTHROPIC_AUTH_TOKEN=*) _te=${_kv#ANTHROPIC_AUTH_TOKEN=} ;; esac
        done
        IFS=$_ifs
      fi
      _models="$MODEL $MODEL_OPUS $MODEL_SONNET $MODEL_HAIKU $MODEL_SUBAGENT $MODEL_ALIASES"
      # Any provider may have a catalog; do not special-case OpenRouter. Read
      # JSON as data with argv, never interpolate paths into JavaScript source.
      _cache="${XDG_STATE_HOME:-$HOME/.local/state}/crouter/models-${PROVIDER_NAME}.json"
      if [ -r "$_cache" ]; then
        _cached_models=$("$NODE_BIN" "$LIB_DIR/catalog-inventory.js" --models "$_cache" 2>/dev/null || true)
        [ -z "$_cached_models" ] || _models="$_models $_cached_models"
      fi
      if [ "$PROVIDER_NAME" = ollama ] && command -v ollama >/dev/null 2>&1; then _models="$_models $(ollama list 2>/dev/null | awk 'NR>1{print $1}')"; fi
      CR_PREFIX="$PROVIDER_NAME" CR_MODELS="$_models" CR_KEYPOOL_KEYS= \
      CR_SURFACE_CANDIDATES="$_surface_candidates" \
      CR_DEFAULT_URL="${DEFAULT_URL:-$BASE_URL}" CR_DEFAULT_TYPE="${DEFAULT_AUTH_TYPE:-}" CR_DEFAULT_TOKEN="$_def_token" \
      CR_API_URL="${API_URL:-$BASE_URL}" CR_API_TYPE="${API_AUTH_TYPE:-}" CR_API_KEY="$_api_key" \
      CR_AUTH_MODE="$AUTH_MODE" CR_AUTH_SCHEME="$_AUTH_SCHEME" CR_NONE_TOKEN="$_te" \
        "$NODE_BIN" "$LIB_DIR/route-build.js" candidates
    ) >> "$_rt"; then die "failed to build unified routes for provider '$_n'"; fi
  done
  "$NODE_BIN" "$LIB_DIR/route-build.js" combine "$_rt" "$_routes_dest" || die 'failed to combine unified provider routes'
}
_default_namespaced_model() { "$NODE_BIN" "$LIB_DIR/route-build.js" default-model "$1"; }
cmd_all() {
  [ -n "$NODE_BIN" ] || die 'node not found; unified gateway cannot start'
  _check=0
  case ${1:-} in --check) _check=1; shift ;; -h|--help) info 'usage: crouter all [--check] [claude args...]'; return 0 ;; esac
  [ "$_check" -eq 0 ] || [ $# -eq 0 ] || die 'all --check does not accept Claude arguments'
  _gwpid= _routes_file= _build_routes_file= _out= _all_cleanup_done=0
  _all_cleanup() {
    [ "${_all_cleanup_done:-0}" -eq 0 ] || return 0
    _all_cleanup_done=1
    if [ -n "${_gwpid:-}" ]; then kill "$_gwpid" 2>/dev/null || true; wait "$_gwpid" 2>/dev/null || true; fi
    [ -z "${_out:-}" ] || rm -f "$_out"
    [ -z "${_build_routes_file:-}" ] || rm -f "$_build_routes_file"
    [ -z "${_routes_file:-}" ] || rm -f "$_routes_file"
    cleanup_provider_assets || true
    return 0
  }
  trap '_all_cleanup' EXIT
  trap '_all_cleanup; exit 130' INT
  trap '_all_cleanup; exit 143' TERM
  _routes_file=$(mktemp "${TMPDIR:-/tmp}/call-routes-arr.XXXXXX") || die 'failed to create unified route file'
  _build_routes_file=$(mktemp "${TMPDIR:-/tmp}/call-routes.XXXXXX") || die 'failed to create unified route build file'
  build_all_routes "$_routes_file" "$_build_routes_file" || die 'failed to build unified provider routes'
  rm -f "$_build_routes_file"; _build_routes_file=
  [ -s "$_routes_file" ] || die 'no providers found to build the gateway'
  if [ "$_check" -eq 1 ]; then
    if "$NODE_BIN" "$LIB_DIR/route-build.js" inspect "$_routes_file"; then _check_rc=0; else _check_rc=$?; fi
    _all_cleanup; trap - EXIT INT TERM; return "$_check_rc"
  fi
  check_claude_binary
  _out=$(mktemp "${TMPDIR:-/tmp}/call-gw.XXXXXX") || die 'failed to create unified gateway output file'
  _gateway_token=$("$NODE_BIN" -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))") || die 'failed to generate a local gateway token'
  CROUTER_ROUTES_FILE="$_routes_file" CROUTER_GATEWAY_PORT="${CROUTER_GATEWAY_PORT:-18799}" \
  CROUTER_GATEWAY_TOKEN="$_gateway_token" CROUTER_CANDIDATE_COOLDOWN_MS="${CROUTER_CANDIDATE_COOLDOWN_MS:-300000}" \
    "$NODE_BIN" "$BIN_DIR/gateway" > "$_out" 2>/dev/null &
  _gwpid=$! _port= _i=0
  while [ "$_i" -lt 50 ]; do
    _port=$(grep -m1 '^CROUTER_GATEWAY_LISTENING_PORT=' "$_out" 2>/dev/null | cut -d= -f2)
    [ -n "$_port" ] && break
    kill -0 "$_gwpid" 2>/dev/null || break
    sleep 0.1; _i=$((_i + 1))
  done
  [ -n "$_port" ] || die 'unified gateway failed to start'
  rm -f "$_out"; _out=
  info "crouter all: unified gateway on http://127.0.0.1:$_port — switch providers with /model <provider>/<model>"
  GATEWAY_PID=$_gwpid
  POST_STOP='kill "$GATEWAY_PID" 2>/dev/null; rm -f "$_routes_file" 2>/dev/null'
  _def=$(_default_namespaced_model "$_routes_file")
  BASE_URL="http://127.0.0.1:$_port"
  MODEL=$_def MODEL_OPUS=$_def MODEL_SONNET=$_def MODEL_HAIKU=$_def MODEL_SUBAGENT=$_def
  AUTH_MODE=none AUTH_TOKEN= CONTEXT_TOKENS=
  EXTRA_ENV="ANTHROPIC_AUTH_TOKEN=$_gateway_token"
  _bypass_auth=0
  PROVIDER_MCP_CONFIG= PROVIDER_PLUGIN_DIRS=
  if [ "${CROUTER_PROVIDER_ASSETS:-1}" != 0 ] && [ "${CROUTER_STRICT_PROVIDER_MCP:-1}" = 1 ]; then ASSET_PROFILE=empty; prepare_provider_assets; fi
  launch_claude "$_def" "$_bypass_auth" "$@"
}
