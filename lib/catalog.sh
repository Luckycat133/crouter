#!/bin/sh
# Resolve the binding from non-secret configuration. The catalog command and
# every passive cache reader use the same directory and Messages endpoints.
catalog_binding() {
  _cat_mode=${MODELS_DISCOVERY:-auto} _cat_auth=${MODELS_API_AUTH:-none}
  _cat_surface=${MODELS_API_SURFACE:-public} _cat_source=$BASE_URL
  _cat_env= _cat_refs=
  [ -z "${NATIVE_BACKEND:-}" ] || _cat_mode=native
  case $_cat_surface in
    api) _cat_source=${API_URL:-$BASE_URL}; _cat_env=${API_KEY_ENV:-}; _cat_refs="${API_KEYS:-} ${API_KEY_REF:-}" ;;
    plan) _cat_source=${PLAN_URL:-$BASE_URL}; _cat_env=${PLAN_KEY_ENV:-}; _cat_refs=${PLAN_KEYS:-} ;;
    auth)
      case $AUTH_MODE in
        env) _cat_env=${AUTH_REFERENCE:-}; _cat_refs=${AUTH_KEYCHAIN_FALLBACK:-} ;;
        keychain) _cat_refs=${AUTH_REFERENCE:-} ;;
      esac ;;
  esac
}
catalog_exec() (
  catalog_binding
  CR_PROVIDER="$PROVIDER_NAME" CR_CATALOG_SOURCE_URL="$_cat_source" CR_CATALOG_KEY_ENV="$_cat_env" CR_MODEL_BLOCKED="$MODEL_BLOCKED_IDS" \
  CR_MODELS_ACCOUNT_LIVE="${MODELS_ACCOUNT_LIVE:-}" \
  CR_MODELS_DISCOVERY="$_cat_mode" CR_MODELS_API_URL="${MODELS_API_URL:-}" \
  CR_MODELS_API_AUTH="$_cat_auth" CR_MODELS_API_SURFACE="$_cat_surface" \
    "$@"
)
# Only an explicit directory operation resolves a dedicated Keychain token.
catalog_run() (
  [ -n "$NODE_BIN" ] || die 'model catalog requires Node.js'
  catalog_binding
  _cat_token=
  if [ "$_cat_mode" != static ] && [ "$_cat_mode" != native ] && [ "$_cat_auth" != none ]; then
    case $_cat_surface in api|plan|auth) ;; *) die 'authenticated catalog must declare a credential surface' ;; esac
    [ -z "$_cat_env" ] || _cat_token=$(printenv "$_cat_env" 2>/dev/null || true)
    if [ -z "$_cat_token" ]; then
      for _cat_ref in $_cat_refs; do
        _cat_token=$(kc_get "$_cat_ref" || true)
        [ -z "$_cat_token" ] || break
      done
    fi
  fi
  CR_CATALOG_TOKEN="$_cat_token" \
  CR_APPLY_SELECTION="$BIN_DIR/crouter" \
  CR_STATIC_MODELS="${MODEL:-} ${MODEL_OPUS:-} ${MODEL_SONNET:-} ${MODEL_HAIKU:-} ${MODEL_SUBAGENT:-} ${MODEL_ALIASES:-}" \
    catalog_exec "$NODE_BIN" "$BIN_DIR/crouter-models" --provider "$PROVIDER_NAME" "$@"
)
model_state_limits() {
  [ -n "$NODE_BIN" ] || return 0
  catalog_exec "$NODE_BIN" "$LIB_DIR/model-state.js" limits "$1" "$2" 2>/dev/null || true
}
# JSON metadata for the interactive home. Presence tests never read key values.
cmd_inventory() {
  [ -n "$NODE_BIN" ] || die 'interactive home requires Node.js'
  for _inv_name in $(provider_names); do
    (
      load_provider "$_inv_name"
      _inv_auth_refs=
      case "$AUTH_MODE" in
        env) _inv_auth_refs=${AUTH_KEYCHAIN_FALLBACK:-} ;;
        keychain) _inv_auth_refs=${AUTH_REFERENCE:-} ;;
        keypool) _inv_auth_refs=${AUTH_KEYS:-} ;;
      esac
      CR_NAME="$PROVIDER_NAME" CR_DESC="$PROVIDER_DESC" CR_STATUS="$(provider_status)" \
      CR_MODEL="$MODEL" CR_MODELS="$MODEL $MODEL_OPUS $MODEL_SONNET $MODEL_HAIKU $MODEL_SUBAGENT $MODEL_ALIASES" \
      CR_HAS_PLAN="${PLAN_URL:+1}" CR_HAS_API="${API_URL:+1}" CR_AUTH_MODE="$AUTH_MODE" \
      CR_KEYS_PLAN="$PLAN_KEYS" CR_KEYS_API="$API_KEYS" \
      CR_KEYS_AUTH="$_inv_auth_refs" \
        catalog_exec "$NODE_BIN" "$LIB_DIR/catalog-inventory.js"
    )
  done
}
