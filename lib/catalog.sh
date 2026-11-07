#!/bin/sh
# Read-only catalog operation: no PRE_START, inference proxy or session assets.
# Secrets go only to the configured catalog origin, via the child environment.
catalog_run() (
  [ -n "$NODE_BIN" ] || die 'model catalog requires Node.js'
  _cat_mode=${MODELS_DISCOVERY:-auto}
  _cat_url=${MODELS_API_URL:-}
  _cat_auth=${MODELS_API_AUTH:-none}
  _cat_surface=${MODELS_API_SURFACE:-public}
  _cat_token= _cat_env= _cat_refs=
  case ${NATIVE_BACKEND:-} in ?*) _cat_mode=native ;; esac
  if [ "$_cat_mode" != static ] && [ "$_cat_mode" != native ] && [ "$_cat_auth" != none ]; then
    case $_cat_surface in
      api) _cat_env=${API_KEY_ENV:-}; _cat_refs=${API_KEYS:-} ;;
      plan) _cat_env=${PLAN_KEY_ENV:-}; _cat_refs=${PLAN_KEYS:-} ;;
      auth)
        case $AUTH_MODE in
          env) _cat_env=${AUTH_REFERENCE:-}; _cat_refs=${AUTH_KEYCHAIN_FALLBACK:-} ;;
          keychain) _cat_refs=${AUTH_REFERENCE:-} ;;
          *) die 'catalog auth requires an explicit environment or Keychain binding' ;;
        esac ;;
      *) die 'authenticated catalog must declare a credential surface' ;;
    esac
    [ -z "$_cat_env" ] || _cat_token=$(printenv "$_cat_env" 2>/dev/null || true)
    if [ -z "$_cat_token" ]; then
      for _cat_ref in $_cat_refs; do
        _cat_token=$(kc_get "$_cat_ref" || true)
        [ -z "$_cat_token" ] || break
      done
    fi
    # No anonymous request to an account-only catalog masquerading as success.
    [ -n "$_cat_token" ] || _cat_mode=static
  fi
  CR_PROVIDER="$PROVIDER_NAME" CR_BASE_URL="$BASE_URL" \
  CR_MODELS_DISCOVERY="$_cat_mode" CR_MODELS_API_URL="$_cat_url" \
  CR_MODELS_API_AUTH="$_cat_auth" CR_MODELS_API_SURFACE="$_cat_surface" \
  CR_API_KEY="$_cat_token" \
  CR_STATIC_MODELS="${MODEL:-} ${MODEL_OPUS:-} ${MODEL_SONNET:-} ${MODEL_HAIKU:-} ${MODEL_SUBAGENT:-} ${MODEL_ALIASES:-}" \
    "$NODE_BIN" "$BIN_DIR/crouter-models" --provider "$PROVIDER_NAME" "$@"
)
model_state_context() {
  [ -n "$NODE_BIN" ] || return 0
  "$NODE_BIN" "$LIB_DIR/model-state.js" context "$1" "$2" 2>/dev/null || true
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
        "$NODE_BIN" "$LIB_DIR/catalog-inventory.js"
    )
  done
}
