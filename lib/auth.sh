#!/bin/sh
# Auth resolution, health checks, and the keypool proxy launcher.
# Sourced by bin/crouter. Functions only read these globals at call time:
# AUTH_MODE, AUTH_REFERENCE, PLUS_URL, PLUS_KEYS, AUTH_KEYS, BASE_URL, USER,
# PROVIDER_NAME, BIN_DIR, LIB_DIR, NODE_BIN, LOG_DIR, ROOT_DIR.

# ---------------------------------------------------------------------------
# Auth. The secret only ever lives in AUTH_TOKEN inside this process.
# ---------------------------------------------------------------------------
# Read a secret out of the macOS login Keychain. Prints nothing (rc 1) when the
# item does not exist, so callers can treat "missing" as "empty".
kc_get() { security find-generic-password -a "$USER" -s "$1" -w 2>/dev/null; }

_new_local_proxy_token() {
  "$NODE_BIN" -e "process.stdout.write(require('crypto').randomBytes(32).toString('hex'))"
}

# Keychain availability cache (disk-backed): avoids repeating `security` lookups.
_kc_cache_dir() { printf '%s/.kc-cache' "${LOG_DIR:-$ROOT_DIR/logs}"; }
_kc_state() {
  _d=$(_kc_cache_dir)
  _f="$_d/$1"
  [ -f "$_f" ] && cat "$_f" 2>/dev/null
  return 0
}
_kc_set_state() {
  mkdir -p "$(_kc_cache_dir)" 2>/dev/null
  printf '%s' "$2" > "$(_kc_cache_dir)/$1" 2>/dev/null
}

resolve_auth() {
  AUTH_TOKEN=
  case $AUTH_MODE in
    keychain)
      AUTH_TOKEN=$(kc_get "$AUTH_REFERENCE")
      [ -n "$AUTH_TOKEN" ] || die "keychain item '$AUTH_REFERENCE' not found (provider '$PROVIDER_NAME')"
      ;;
    env)
      AUTH_TOKEN=$(printenv "$AUTH_REFERENCE" 2>/dev/null)
      # Optional Keychain fallback: lets a provider accept both "export the key"
      # and "store it in the Keychain" without inventing a second AUTH_MODE.
      if [ -z "$AUTH_TOKEN" ] && [ -n "${AUTH_KEYCHAIN_FALLBACK:-}" ]; then
        AUTH_TOKEN=$(kc_get "$AUTH_KEYCHAIN_FALLBACK")
      fi
      [ -n "$AUTH_TOKEN" ] || die "provider '$PROVIDER_NAME': no key in \$$AUTH_REFERENCE${AUTH_KEYCHAIN_FALLBACK:+ or keychain item '$AUTH_KEYCHAIN_FALLBACK'}"
      ;;
    command)
      AUTH_TOKEN=$(eval "$AUTH_REFERENCE") ||
        die "auth command failed (provider '$PROVIDER_NAME')"
      [ -n "$AUTH_TOKEN" ] || die "auth command returned empty output (provider '$PROVIDER_NAME')"
      ;;
    static)
      AUTH_TOKEN=$AUTH_REFERENCE
      ;;
    none)
      ;;
    native)
      ;;
    *)
      die "provider '$PROVIDER_NAME': unsupported AUTH_MODE '$AUTH_MODE'"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Token Plan + pay-as-you-go surfaces. Unlike the legacy keypool contract,
# credentials are resolved into two distinct pools and converted directly to
# explicit candidates. There is deliberately no keys x URLs cross product.
# ---------------------------------------------------------------------------
resolve_surface_tokens() {
  _allow_missing=${1:-0}
  _PLAN_TOKENS=""
  _API_TOKENS=""
  _PLAN_FIRST_TOKEN=""
  _API_FIRST_TOKEN=""
  _SURFACE_COUNT=0

  if [ -n "${PLAN_KEY_ENV:-}" ]; then
    _t=$(printenv "$PLAN_KEY_ENV" 2>/dev/null || true)
    if [ -n "$_t" ]; then
      _PLAN_TOKENS=$_t
      _PLAN_FIRST_TOKEN=$_t
      _SURFACE_COUNT=$((_SURFACE_COUNT + 1))
    fi
  fi
  for _ref in ${PLAN_KEYS:-}; do
    _t=$(kc_get "$_ref" || true)
    [ -n "$_t" ] || continue
    [ -n "$_PLAN_FIRST_TOKEN" ] || _PLAN_FIRST_TOKEN=$_t
    _PLAN_TOKENS="${_PLAN_TOKENS:+$_PLAN_TOKENS }$_t"
    _SURFACE_COUNT=$((_SURFACE_COUNT + 1))
  done

  if [ -n "${API_KEY_ENV:-}" ]; then
    _t=$(printenv "$API_KEY_ENV" 2>/dev/null || true)
    if [ -n "$_t" ]; then
      _API_TOKENS=$_t
      _API_FIRST_TOKEN=$_t
      _SURFACE_COUNT=$((_SURFACE_COUNT + 1))
    fi
  fi
  for _ref in ${API_KEYS:-}; do
    _t=$(kc_get "$_ref" || true)
    [ -n "$_t" ] || continue
    [ -n "$_API_FIRST_TOKEN" ] || _API_FIRST_TOKEN=$_t
    _API_TOKENS="${_API_TOKENS:+$_API_TOKENS }$_t"
    _SURFACE_COUNT=$((_SURFACE_COUNT + 1))
  done

  if [ "$_allow_missing" -eq 0 ] && [ "$_SURFACE_COUNT" -eq 0 ]; then
    die "provider '$PROVIDER_NAME': no Token Plan or API key configured (use crouter add '$PROVIDER_NAME' --surface plan|api)"
  fi
}

build_surface_candidates() {
  CR_MODEL="$MODEL" CR_MODEL_OPUS="$MODEL_OPUS" CR_MODEL_SONNET="$MODEL_SONNET" \
  CR_MODEL_HAIKU="$MODEL_HAIKU" CR_MODEL_SUBAGENT="$MODEL_SUBAGENT" \
  CR_PLAN_URL="${PLAN_URL:-}" CR_PLAN_TYPE="${PLAN_AUTH_TYPE:-bearer}" \
  CR_PLAN_TOKENS="${_PLAN_TOKENS:-}" CR_PLAN_MODEL="${PLAN_MODEL:-}" \
  CR_PLAN_MODEL_OPUS="${PLAN_MODEL_OPUS:-}" CR_PLAN_MODEL_SONNET="${PLAN_MODEL_SONNET:-}" \
  CR_PLAN_MODEL_HAIKU="${PLAN_MODEL_HAIKU:-}" CR_PLAN_MODEL_SUBAGENT="${PLAN_MODEL_SUBAGENT:-}" \
  CR_API_URL="${API_URL:-}" CR_API_TYPE="${API_AUTH_TYPE:-bearer}" \
  CR_API_TOKENS="${_API_TOKENS:-}" CR_API_MODEL="${API_MODEL:-}" \
  CR_API_MODEL_OPUS="${API_MODEL_OPUS:-}" CR_API_MODEL_SONNET="${API_MODEL_SONNET:-}" \
  CR_API_MODEL_HAIKU="${API_MODEL_HAIKU:-}" CR_API_MODEL_SUBAGENT="${API_MODEL_SUBAGENT:-}" \
    "$NODE_BIN" "$LIB_DIR/route-build.js" surface-candidates
}

start_surface_pool() {
  [ -n "$NODE_BIN" ] || die "node not found; surface keypool cannot start"
  resolve_surface_tokens
  _cands=$(build_surface_candidates)
  [ "$_cands" != "[]" ] || die "provider '$PROVIDER_NAME': no usable surface candidates"

  KEYPOOL_AUTH_TOKEN=$(_new_local_proxy_token) || die "failed to generate a local keypool token"
  _out=$(mktemp -t surfacepool.XXXXXX)
  KEYPOOL_CANDIDATES="$_cands" KEYPOOL_PORT=0 KEYPOOL_CLIENT_TOKEN="$KEYPOOL_AUTH_TOKEN" \
    CROUTER_CANDIDATE_COOLDOWN_MS="${CROUTER_CANDIDATE_COOLDOWN_MS:-300000}" \
    "$NODE_BIN" "$BIN_DIR/keypool-proxy" > "$_out" 2>/dev/null &
  KEYPOOL_PID=$!

  _lp=""
  _i=0
  while [ "$_i" -lt 30 ]; do
    _lp=$(sed -n 's/^KEYPOOL_LISTENING_PORT=//p' "$_out" 2>/dev/null | head -n 1)
    [ -n "$_lp" ] && break
    kill -0 "$KEYPOOL_PID" 2>/dev/null || break
    sleep 0.1
    _i=$((_i + 1))
  done
  rm -f "$_out"
  if [ -z "$_lp" ]; then
    kill "$KEYPOOL_PID" 2>/dev/null || true
    KEYPOOL_PID=""
    die "surface keypool failed to start (provider '$PROVIDER_NAME')"
  fi
  KEYPOOL_URL="http://127.0.0.1:$_lp"
  export KEYPOOL_URL KEYPOOL_PID
  info "auth: Token Plan/API candidates isolated ($_SURFACE_COUNT credential(s), local failover on $KEYPOOL_URL)"
}

_surface_available() {
  _env_name=$1
  _refs=$2
  if [ -n "$_env_name" ] && [ -n "$(printenv "$_env_name" 2>/dev/null)" ]; then
    return 0
  fi
  for _ref in $_refs; do
    if security find-generic-password -a "$USER" -s "$_ref" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

surface_state() {
  _state=""
  if _surface_available "${PLAN_KEY_ENV:-}" "${PLAN_KEYS:-}"; then
    _state=plan
  fi
  if _surface_available "${API_KEY_ENV:-}" "${API_KEYS:-}"; then
    _state="${_state:+$_state+}api"
  fi
  printf '%s' "$_state"
}

# ---------------------------------------------------------------------------
# Legacy/custom dual-source providers: one preferred credential/endpoint is
# tried first, with an API credential as fallback. Both are declared through
# DEFAULT_*/API_* fields. Official Token Plan providers use AUTH_MODE=surfaces.
#
# resolve_dual_source() discovers BOTH surfaces and exports:
#   _DUAL_DEF_TOKEN / _DUAL_API_TOKEN   raw credentials (may be empty)
#   _DUAL_COUNT                         how many surfaces are usable (1 or 2)
#   AUTH_TOKEN / BASE_URL / _AUTH_SCHEME  the single best surface (direct launch)
# When both are present, start_dual_failover() fronts them with the local proxy
# so rotation on 401/402/403/429 happens mid-session, like the unified gateway.
# ---------------------------------------------------------------------------
is_dual_source() {
  [ "${AUTH_MODE:-}" = surfaces ] && return 1
  [ -n "${DEFAULT_TOKEN_ENV:-}" ] || [ -n "${DEFAULT_TOKEN_ENV_FALLBACK:-}" ] ||
    [ -n "${API_KEY_ENV:-}" ] || [ -n "${API_KEY_REF:-}" ]
}

resolve_dual_source() {
  AUTH_TOKEN=""
  _AUTH_SCHEME="x-api-key"
  _DUAL_DEF_TOKEN=""
  _DUAL_API_TOKEN=""
  _DUAL_COUNT=0

  # Preferred custom/default credential.
  if [ -n "${DEFAULT_TOKEN_ENV:-}" ] && [ -n "$(printenv "$DEFAULT_TOKEN_ENV" 2>/dev/null)" ]; then
    _DUAL_DEF_TOKEN=$(printenv "$DEFAULT_TOKEN_ENV")
  elif [ -n "${DEFAULT_TOKEN_ENV_FALLBACK:-}" ] && [ -n "$(printenv "$DEFAULT_TOKEN_ENV_FALLBACK" 2>/dev/null)" ]; then
    _DUAL_DEF_TOKEN=$(printenv "$DEFAULT_TOKEN_ENV_FALLBACK")
  fi
  # Fallback API key (env first, then keychain).
  if [ -n "${API_KEY_ENV:-}" ] && [ -n "$(printenv "$API_KEY_ENV" 2>/dev/null)" ]; then
    _DUAL_API_TOKEN=$(printenv "$API_KEY_ENV")
  elif [ -n "${API_KEY_REF:-}" ]; then
    _DUAL_API_TOKEN=$(kc_get "$API_KEY_REF")
  fi

  [ -n "$_DUAL_DEF_TOKEN" ] && _DUAL_COUNT=$((_DUAL_COUNT + 1))
  [ -n "$_DUAL_API_TOKEN" ] && _DUAL_COUNT=$((_DUAL_COUNT + 1))

  if [ -n "$_DUAL_DEF_TOKEN" ]; then
    AUTH_TOKEN="$_DUAL_DEF_TOKEN"
    [ -n "${DEFAULT_URL:-}" ] && BASE_URL="$DEFAULT_URL"
    _AUTH_SCHEME="${DEFAULT_AUTH_TYPE:-bearer}"
    return 0
  fi
  if [ -n "$_DUAL_API_TOKEN" ]; then
    AUTH_TOKEN="$_DUAL_API_TOKEN"
    [ -n "${API_URL:-}" ] && BASE_URL="$API_URL"
    _AUTH_SCHEME="${API_AUTH_TYPE:-x-api-key}"
    return 0
  fi
  die "no auth configured for dual-source provider '$PROVIDER_NAME' (set ${DEFAULT_TOKEN_ENV:-<default token env>} / ${API_KEY_ENV:-<api key env>}, or keychain ${API_KEY_REF:-<none>})"
}

# Front both surfaces with the local failover proxy so that a 401/402/403/429 on the
# preferred credential rotates to the API key mid-session (no restart needed).
# Requires resolve_dual_source() to have run. No-op unless both are available.
start_dual_failover() {
  [ "${_DUAL_COUNT:-0}" -ge 2 ] || return 0
  if [ -z "$NODE_BIN" ]; then
    info "warn: node not found; dual-source failover disabled (using default account only)"
    return 0
  fi

  _cands=$(
    CR_DEFAULT_URL="${DEFAULT_URL:-$BASE_URL}" CR_DEFAULT_TYPE="${DEFAULT_AUTH_TYPE:-bearer}" CR_DEFAULT_TOKEN="$_DUAL_DEF_TOKEN" \
    CR_API_URL="${API_URL:-$BASE_URL}" CR_API_TYPE="${API_AUTH_TYPE:-x-api-key}" CR_API_KEY="$_DUAL_API_TOKEN" \
      "$NODE_BIN" "$LIB_DIR/route-build.js" dual-candidates
  )

  KEYPOOL_AUTH_TOKEN=$(_new_local_proxy_token) || die "failed to generate a local keypool token"
  _out=$(mktemp -t dualpool.XXXXXX)
  KEYPOOL_CANDIDATES="$_cands" KEYPOOL_PORT=0 KEYPOOL_CLIENT_TOKEN="$KEYPOOL_AUTH_TOKEN" \
    CROUTER_CANDIDATE_COOLDOWN_MS="${CROUTER_CANDIDATE_COOLDOWN_MS:-300000}" \
    "$NODE_BIN" "$BIN_DIR/keypool-proxy" > "$_out" 2>/dev/null &
  KEYPOOL_PID=$!

  _lp=""
  _i=0
  while [ $_i -lt 30 ]; do
    _lp=$(grep -m1 '^KEYPOOL_LISTENING_PORT=' "$_out" 2>/dev/null | cut -d= -f2)
    [ -n "$_lp" ] && break
    sleep 0.1
    _i=$((_i + 1))
  done
  rm -f "$_out"
  if [ -z "$_lp" ]; then
    kill "$KEYPOOL_PID" 2>/dev/null
    KEYPOOL_PID=""
    info "warn: dual-source failover proxy failed to start; using default account only"
    return 0
  fi
  KEYPOOL_URL="http://127.0.0.1:$_lp"
  export KEYPOOL_URL KEYPOOL_PID
  info "auth: default account first, API key on 401/402/403/429 (local failover on $KEYPOOL_URL)"
}

# keypool: resolve a pool of keys from keychain, start a local key-failover proxy,
# and expose its URL. Claude Code then talks to the proxy, which rotates keys on
# 401/402/403/429 so quota exhaustion and entitlement rejection are handled
# transparently (mid-session).
#
# Plus-endpoint ordering: PLUS keys stay bound to PLUS_URL and are tried before
# the main keys bound to BASE_URL. They are never cross-combined.
build_legacy_keypool_candidates() {
  CR_PLAN_URL="${PLUS_URL:-}" CR_PLAN_TYPE="${_AUTH_SCHEME:-both}" \
  CR_PLAN_TOKENS="${_plus_pool:-}" \
  CR_API_URL="$BASE_URL" CR_API_TYPE="${_AUTH_SCHEME:-both}" \
  CR_API_TOKENS="${_main_pool:-}" \
    "$NODE_BIN" "$LIB_DIR/route-build.js" surface-candidates
}

start_keypool() {
  [ -n "$NODE_BIN" ] || die "node not found; keypool proxy cannot start"
  [ -n "${AUTH_KEYS:-}" ] || die "provider '$PROVIDER_NAME': AUTH_MODE=keypool requires AUTH_KEYS"

  _plus_pool=""
  if [ -n "${PLUS_URL:-}" ] && [ -n "${PLUS_KEYS:-}" ]; then
    for _ref in $PLUS_KEYS; do
      _t=$(kc_get "$_ref")
      [ -n "$_t" ] || die "keychain item '$_ref' not found (provider '$PROVIDER_NAME')"
      _plus_pool="$_plus_pool $_t"
    done
    _plus_pool=$(echo "$_plus_pool" | sed 's/^ *//; s/ *$//')
  fi

  _main_pool=""
  for _ref in $AUTH_KEYS; do
    _t=$(kc_get "$_ref")
    [ -n "$_t" ] || die "keychain item '$_ref' not found (provider '$PROVIDER_NAME')"
    _main_pool="$_main_pool $_t"
  done
  _main_pool=$(echo "$_main_pool" | sed 's/^ *//; s/ *$//')

  _cands=$(build_legacy_keypool_candidates)

  KEYPOOL_AUTH_TOKEN=$(_new_local_proxy_token) || die "failed to generate a local keypool token"
  _out=$(mktemp -t keypool.XXXXXX)
  KEYPOOL_CANDIDATES="$_cands" KEYPOOL_PORT=0 KEYPOOL_CLIENT_TOKEN="$KEYPOOL_AUTH_TOKEN" \
    CROUTER_CANDIDATE_COOLDOWN_MS="${CROUTER_CANDIDATE_COOLDOWN_MS:-300000}" \
    "$NODE_BIN" "$BIN_DIR/keypool-proxy" > "$_out" 2>/dev/null &
  KEYPOOL_PID=$!

  _lp=""
  _i=0
  while [ $_i -lt 30 ]; do
    _lp=$(grep -m1 '^KEYPOOL_LISTENING_PORT=' "$_out" 2>/dev/null | cut -d= -f2)
    [ -n "$_lp" ] && break
    sleep 0.1
    _i=$((_i + 1))
  done
  rm -f "$_out"
  if [ -z "$_lp" ]; then
    kill "$KEYPOOL_PID" 2>/dev/null
    die "keypool proxy failed to start (provider '$PROVIDER_NAME')"
  fi
  KEYPOOL_URL="http://127.0.0.1:$_lp"
  export KEYPOOL_URL KEYPOOL_PID
  _nkeys=$(printf '%s %s\n' "$_plus_pool" "$_main_pool" | wc -w | tr -d ' ')
  _ntargets=1
  [ -n "$_plus_pool" ] && _ntargets=2
  _note=""
  if [ "$_ntargets" -gt 1 ]; then
    _note=" (plus-first: $_ntargets bound endpoints, $_nkeys keys)"
  else
    _note=" ($_nkeys keys, 1 endpoint)"
  fi
  info "keypool: proxy on $KEYPOOL_URL$_note"
}

# Which dual-source surfaces are currently usable. Prints e.g. "default+api",
# "default", "api", or nothing. Never prints the secrets themselves.
dual_source_state() {
  _s=""
  if { [ -n "${DEFAULT_TOKEN_ENV:-}" ] && [ -n "$(printenv "$DEFAULT_TOKEN_ENV" 2>/dev/null)" ]; } ||
     { [ -n "${DEFAULT_TOKEN_ENV_FALLBACK:-}" ] && [ -n "$(printenv "$DEFAULT_TOKEN_ENV_FALLBACK" 2>/dev/null)" ]; }; then
    _s="default"
  fi
  if [ -n "${API_KEY_ENV:-}" ] && [ -n "$(printenv "$API_KEY_ENV" 2>/dev/null)" ]; then
    _s="${_s:+$_s+}api"
  elif [ -n "${API_KEY_REF:-}" ] && security find-generic-password -a "$USER" -s "$API_KEY_REF" >/dev/null 2>&1; then
    _s="${_s:+$_s+}api"
  fi
  printf '%s' "$_s"
}

# Non-destructive availability check used by status/doctor (never prints secrets).
check_auth() {
  # Dual-source providers don't use AUTH_MODE; at least one surface must exist.
  if is_dual_source; then
    [ -n "$(dual_source_state)" ]
    return $?
  fi
  if [ "${AUTH_MODE:-}" = surfaces ]; then
    [ -n "$(surface_state)" ]
    return $?
  fi
  case $AUTH_MODE in
    keychain)
      _st=$(_kc_state "$AUTH_REFERENCE")
      if [ -z "$_st" ]; then
        if security find-generic-password -a "$USER" -s "$AUTH_REFERENCE" >/dev/null 2>&1; then
          _st=ok
        else
          _st=missing
        fi
        _kc_set_state "$AUTH_REFERENCE" "$_st"
      fi
      [ "$_st" = ok ]
      ;;
    env)
      _v=$(printenv "$AUTH_REFERENCE" 2>/dev/null)
      if [ -n "$_v" ]; then
        true
      elif [ -n "${AUTH_KEYCHAIN_FALLBACK:-}" ]; then
        security find-generic-password -a "$USER" -s "$AUTH_KEYCHAIN_FALLBACK" >/dev/null 2>&1
      else
        false
      fi ;;
    command)
      _v=$(eval "$AUTH_REFERENCE" 2>/dev/null) && [ -n "$_v" ] ;;
    static|none|native)
      true ;;
    keypool)
      _ok=0
      for _ref in ${AUTH_KEYS:-}; do
        if security find-generic-password -a "$USER" -s "$_ref" >/dev/null 2>&1; then _ok=1; break; fi
      done
      [ "$_ok" -eq 1 ] ;;
    *)
      false ;;
  esac
}

check_health() {
  [ -n "$HEALTH_CHECK_URL" ] || return 2
  curl -fsS --max-time 3 "$HEALTH_CHECK_URL" >/dev/null 2>&1
}
