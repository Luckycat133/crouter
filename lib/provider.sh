#!/bin/sh
# Provider loading. Sourced by bin/crouter after core globals are set.
# Each provider file (providers/<name>.sh) declares only "how to connect".
# Uses globals: PROVIDERS_DIR.

provider_file() { printf '%s/%s.sh' "$PROVIDERS_DIR" "$1"; }

# User-added Keychain service names are metadata, not provider source. Keeping
# them below STATE_DIR means an installed/read-only provider catalog remains
# reproducible and package upgrades never overwrite a user's key pool.
provider_registry_file() {
  [ -n "${STATE_DIR:-}" ] || return 1
  printf '%s/keypools/%s.tsv' "$STATE_DIR" "$1"
}

_append_provider_key() {
  _apk_var=$1
  _apk_service=$2
  case $_apk_service in
    ''|.|..|*[!A-Za-z0-9._:@+-]*)
      die "provider key registry contains invalid service name '$_apk_service'" ;;
  esac
  case $_apk_var in
    PLAN_KEYS) _apk_current=${PLAN_KEYS:-} ;;
    API_KEYS)  _apk_current=${API_KEYS:-} ;;
    AUTH_KEYS) _apk_current=${AUTH_KEYS:-} ;;
    PLUS_KEYS) _apk_current=${PLUS_KEYS:-} ;;
    *) die "provider key registry contains invalid surface variable '$_apk_var'" ;;
  esac
  case " $_apk_current " in
    *" $_apk_service "*) return 0 ;;
  esac
  _apk_current="${_apk_current:+$_apk_current }$_apk_service"
  case $_apk_var in
    PLAN_KEYS) PLAN_KEYS=$_apk_current ;;
    API_KEYS)  API_KEYS=$_apk_current ;;
    AUTH_KEYS) AUTH_KEYS=$_apk_current ;;
    PLUS_KEYS) PLUS_KEYS=$_apk_current ;;
  esac
}

_load_provider_registry() {
  _lpr_file=$(provider_registry_file "$1") || return 0
  [ -f "$_lpr_file" ] || return 0
  while IFS='	' read -r _lpr_surface _lpr_service; do
    [ -n "$_lpr_surface$_lpr_service" ] || continue
    case $_lpr_surface in
      plan) [ "${AUTH_MODE:-}" = surfaces ] && [ -n "${PLAN_URL:-}" ] ||
              die "provider '$1' registry has a plan key but no plan surface"
            _append_provider_key PLAN_KEYS "$_lpr_service" ;;
      api)  [ "${AUTH_MODE:-}" = surfaces ] && [ -n "${API_URL:-}" ] ||
              die "provider '$1' registry has an API key but no API surface"
            _append_provider_key API_KEYS "$_lpr_service" ;;
      main) [ "${AUTH_MODE:-}" = keypool ] ||
              die "provider '$1' registry has a legacy main key for a non-keypool provider"
            _append_provider_key AUTH_KEYS "$_lpr_service" ;;
      plus) [ "${AUTH_MODE:-}" = keypool ] ||
              die "provider '$1' registry has a legacy plus key for a non-keypool provider"
            _append_provider_key PLUS_KEYS "$_lpr_service" ;;
      *) die "provider '$1' registry contains unknown surface '$_lpr_surface'" ;;
    esac
  done < "$_lpr_file"
}

provider_names() {
  for f in "$PROVIDERS_DIR"/*.sh; do
    [ -f "$f" ] || continue
    basename "$f" .sh
  done
}

load_provider() {
  _name=$1
  _file=$(provider_file "$_name")
  [ -f "$_file" ] || die "unknown provider '$_name' (try: crouter list)"

  # Reset the provider contract before sourcing. Every optional field must be
  # cleared here, otherwise values leak between providers when several are
  # loaded in the same shell (crouter doctor / all).
  PROVIDER_NAME= PROVIDER_DESC= BASE_URL= MODEL=
  MODEL_OPUS= MODEL_SONNET= MODEL_HAIKU= MODEL_SUBAGENT=
  MODEL_ALIASES=
  CONTEXT_TOKENS= AUTO_COMPACT_TOKENS= MODEL_CONTEXT_OVERRIDES=
  AUTH_MODE=none AUTH_REFERENCE= AUTH_KEYCHAIN_FALLBACK= _AUTH_SCHEME=
  EXTRA_ENV= PRE_START= POST_STOP= HEALTH_CHECK_URL= EFFORT=
  AUTH_KEYS= PLUS_URL= PLUS_KEYS=
  # Explicit subscription/pay-as-you-go surfaces. Keys on these surfaces are
  # never cross-combined: each remains bound to its own URL and header shape.
  PLAN_URL= PLAN_AUTH_TYPE= PLAN_KEY_ENV= PLAN_KEYS= PLAN_MODEL=
  PLAN_MODEL_OPUS= PLAN_MODEL_SONNET= PLAN_MODEL_HAIKU= PLAN_MODEL_SUBAGENT=
  API_KEYS= API_MODEL=
  API_MODEL_OPUS= API_MODEL_SONNET= API_MODEL_HAIKU= API_MODEL_SUBAGENT=
  # Optional session assets and native Claude Code cloud backends.
  ASSET_PROFILE= ASSET_PLUGIN_DIRS= ASSET_PLAN_PLUGIN_DIRS= ASSET_API_PLUGIN_DIRS=
  PROVIDER_MCP_CONFIG= PROVIDER_PLUGIN_DIRS=
  PROVIDER_ASSET_ENV= NATIVE_BACKEND= PASSTHROUGH_ENV=
  # Legacy/custom dual-source contract. Official providers use explicit
  # surfaces or one auth mode, but custom definitions remain compatible.
  DEFAULT_URL= DEFAULT_AUTH_TYPE= DEFAULT_TOKEN_ENV= DEFAULT_TOKEN_ENV_FALLBACK=
  API_URL= API_AUTH_TYPE= API_KEY_ENV= API_KEY_REF=

  . "$_file"

  _load_provider_registry "$_name"

  PROVIDER_NAME=${PROVIDER_NAME:-$_name}
  [ -n "$BASE_URL" ] || die "provider '$_name': BASE_URL is required"
  [ -n "$MODEL" ]    || die "provider '$_name': MODEL is required"
  # The tier aliases are optional: a provider that serves one model for every
  # tier just sets MODEL and inherits it here. Only declare an alias when it
  # actually differs.
  MODEL_OPUS=${MODEL_OPUS:-$MODEL}
  MODEL_SONNET=${MODEL_SONNET:-$MODEL}
  MODEL_HAIKU=${MODEL_HAIKU:-$MODEL}
  MODEL_SUBAGENT=${MODEL_SUBAGENT:-$MODEL_HAIKU}
}

is_surface_provider() {
  [ "${AUTH_MODE:-}" = surfaces ]
}

# Apply a provider-owned context limit for an exact model ID. The declaration
# is a whitespace-separated list of model=context entries.
apply_model_context_override() {
  _amco_model=$1
  for _amco_pair in ${MODEL_CONTEXT_OVERRIDES:-}; do
    _amco_name=${_amco_pair%%=*}
    [ "$_amco_name" = "$_amco_pair" ] && continue
    if [ "$_amco_name" = "$_amco_model" ]; then
      CONTEXT_TOKENS=${_amco_pair#*=}
      return 0
    fi
  done
}
