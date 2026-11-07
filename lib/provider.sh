#!/bin/sh
# Provider loading; metadata and secrets remain separate.
provider_file() { printf '%s/%s.sh' "$PROVIDERS_DIR" "$1"; }
provider_registry_file() {
  [ -n "${STATE_DIR:-}" ] || return 1
  printf '%s/keypools/%s.tsv' "$STATE_DIR" "$1"
}
_append_provider_key() {
  _apk_var=$1 _apk_service=$2
  case $_apk_service in ''|.|..|*[!A-Za-z0-9._:@+-]*) die "invalid provider key service name" ;; esac
  case $_apk_var in
    PLAN_KEYS) _apk_current=${PLAN_KEYS:-} ;;
    API_KEYS) _apk_current=${API_KEYS:-} ;;
    AUTH_KEYS) _apk_current=${AUTH_KEYS:-} ;;
    PLUS_KEYS) _apk_current=${PLUS_KEYS:-} ;;
    *) die "invalid provider key surface" ;;
  esac
  case " $_apk_current " in *" $_apk_service "*) return 0 ;; esac
  _apk_current="${_apk_current:+$_apk_current }$_apk_service"
  case $_apk_var in
    PLAN_KEYS) PLAN_KEYS=$_apk_current ;; API_KEYS) API_KEYS=$_apk_current ;;
    AUTH_KEYS) AUTH_KEYS=$_apk_current ;; PLUS_KEYS) PLUS_KEYS=$_apk_current ;;
  esac
}
_load_provider_registry() {
  _lpr_file=$(provider_registry_file "$1") || return 0
  [ -f "$_lpr_file" ] || return 0
  while IFS='	' read -r _lpr_surface _lpr_service; do
    [ -n "$_lpr_surface$_lpr_service" ] || continue
    case $_lpr_surface in
      plan) [ "${AUTH_MODE:-}" = surfaces ] && [ -n "${PLAN_URL:-}" ] || die "plan key without plan surface"; _append_provider_key PLAN_KEYS "$_lpr_service" ;;
      api) [ "${AUTH_MODE:-}" = surfaces ] && [ -n "${API_URL:-}" ] || die "API key without API surface"; _append_provider_key API_KEYS "$_lpr_service" ;;
      main) [ "${AUTH_MODE:-}" = keypool ] || die "legacy main key for non-keypool provider"; _append_provider_key AUTH_KEYS "$_lpr_service" ;;
      plus) [ "${AUTH_MODE:-}" = keypool ] || die "legacy plus key for non-keypool provider"; _append_provider_key PLUS_KEYS "$_lpr_service" ;;
      *) die "provider registry contains unknown surface" ;;
    esac
  done < "$_lpr_file"
}
provider_names() {
  for f in "$PROVIDERS_DIR"/*.sh; do
    [ -f "$f" ] || continue
    f=${f##*/}; printf '%s\n' "${f%.sh}"
  done
}
load_provider() {
  _name=$1
  case $_name in ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*) die "invalid provider name" ;; esac
  _file=$(provider_file "$_name")
  [ -f "$_file" ] || die "unknown provider '$_name' (try: crouter list)"
  PROVIDER_NAME= PROVIDER_DESC= BASE_URL= MODEL=
  MODEL_OPUS= MODEL_SONNET= MODEL_HAIKU= MODEL_SUBAGENT= MODEL_ALIASES=
  CONTEXT_TOKENS= AUTO_COMPACT_TOKENS= MODEL_CONTEXT_OVERRIDES= MODEL_SELF_ROUTE_MODELS=
  MODELS_DISCOVERY= MODELS_API_URL= MODELS_API_AUTH= MODELS_API_SURFACE=
  PLAN_MODELS= API_MODELS= MODEL_ID_ALIASES= MODEL_BLOCKED_IDS=
  AUTH_MODE=none AUTH_REFERENCE= AUTH_KEYCHAIN_FALLBACK= _AUTH_SCHEME=
  EXTRA_ENV= PRE_START= POST_STOP= HEALTH_CHECK_URL= EFFORT=
  AUTH_KEYS= PLUS_URL= PLUS_KEYS=
  PLAN_URL= PLAN_AUTH_TYPE= PLAN_KEY_ENV= PLAN_KEYS= PLAN_MODEL=
  PLAN_MODEL_OPUS= PLAN_MODEL_SONNET= PLAN_MODEL_HAIKU= PLAN_MODEL_SUBAGENT=
  API_KEYS= API_MODEL= API_MODEL_OPUS= API_MODEL_SONNET= API_MODEL_HAIKU= API_MODEL_SUBAGENT=
  ASSET_PROFILE= ASSET_PLUGIN_DIRS= ASSET_PLAN_PLUGIN_DIRS= ASSET_API_PLUGIN_DIRS=
  PROVIDER_MCP_CONFIG= PROVIDER_PLUGIN_DIRS= PROVIDER_ASSET_ENV= NATIVE_BACKEND= PASSTHROUGH_ENV=
  DEFAULT_URL= DEFAULT_AUTH_TYPE= DEFAULT_TOKEN_ENV= DEFAULT_TOKEN_ENV_FALLBACK=
  API_URL= API_AUTH_TYPE= API_KEY_ENV= API_KEY_REF=
  . "$_file"
  _load_provider_registry "$_name"
  # Runtime-owned catalog defaults for local/native backends. Do not replace
  # their installed model IDs with public-cloud marketing names.
  if [ -z "$MODELS_DISCOVERY" ]; then
    case $_name in
      bedrock|vertex|foundry) MODELS_DISCOVERY=native ;;
      antigravity|antigravity-claude|codex)
        MODELS_DISCOVERY=remote
        MODELS_API_URL="${BASE_URL%/}/v1/models"
        MODELS_API_AUTH=none MODELS_API_SURFACE=public ;;
      ollama)
        MODELS_DISCOVERY=remote
        MODELS_API_URL=${OLLAMA_MODELS_URL:-http://127.0.0.1:11434/v1/models}
        MODELS_API_AUTH=none MODELS_API_SURFACE=public ;;
      bonsai) MODELS_DISCOVERY=static ;;
    esac
  fi
  PROVIDER_NAME=${PROVIDER_NAME:-$_name}
  [ -n "$BASE_URL" ] || die "provider '$_name': BASE_URL is required"
  [ -n "$MODEL" ] || die "provider '$_name': MODEL is required"
  MODEL_OPUS=${MODEL_OPUS:-$MODEL}
  MODEL_SONNET=${MODEL_SONNET:-$MODEL}
  MODEL_HAIKU=${MODEL_HAIKU:-$MODEL}
  MODEL_SUBAGENT=${MODEL_SUBAGENT:-$MODEL_HAIKU}
}
is_surface_provider() { [ "${AUTH_MODE:-}" = surfaces ]; }
resolve_model_id() {
  _rmi_model=$1
  case $_rmi_model in ''|*[!A-Za-z0-9._:/@_\[\]-]*) die 'invalid model ID' ;; esac
  for _rmi_blocked in ${MODEL_BLOCKED_IDS:-}; do
    [ "$_rmi_model" != "$_rmi_blocked" ] || die 'retired model ID; select a current model explicitly'
  done
  for _rmi_pair in ${MODEL_ID_ALIASES:-}; do
    if [ "${_rmi_pair%%=*}" = "$_rmi_model" ]; then printf '%s' "${_rmi_pair#*=}"; return 0; fi
  done
  printf '%s' "$_rmi_model"
}
apply_model_context_override() {
  _amco_model=$1
  for _amco_pair in ${MODEL_CONTEXT_OVERRIDES:-}; do
    _amco_name=${_amco_pair%%=*}
    [ "$_amco_name" = "$_amco_pair" ] && continue
    if [ "$_amco_model" = "$_amco_name" ]; then CONTEXT_TOKENS=${_amco_pair#*=}; return 0; fi
    case $_amco_name in *:) case $_amco_model in "$_amco_name"*) CONTEXT_TOKENS=${_amco_pair#*=}; return 0 ;; esac ;; esac
  done
}
apply_model_self_route() {
  for _amsr_name in ${MODEL_SELF_ROUTE_MODELS:-}; do
    if [ "$1" = "$_amsr_name" ]; then
      MODEL_OPUS=$1 MODEL_SONNET=$1 MODEL_HAIKU=$1 MODEL_SUBAGENT=$1
      return 0
    fi
  done
}
# Preserve provider-defined tier specialization for its default. An explicitly
# selected alternate model uses a single-model mapping unless the user chooses
# to preserve provider tiers. Surface mapping follows the ORIGINAL logical IDs.
apply_model_tier_settings() {
  [ "$1" != "$MODEL" ] || return 0
  [ "${CROUTER_MODEL_TIER_MODE:-single}" != provider ] || return 0
  _amts_selected=$1
  _amts_plan=$_amts_selected _amts_api=$_amts_selected
  if [ "$_amts_selected" = "$MODEL_OPUS" ]; then
    _amts_plan=${PLAN_MODEL_OPUS:-${PLAN_MODEL:-$_amts_selected}}
    _amts_api=${API_MODEL_OPUS:-${API_MODEL:-$_amts_selected}}
  elif [ "$_amts_selected" = "$MODEL_SONNET" ]; then
    _amts_plan=${PLAN_MODEL_SONNET:-${PLAN_MODEL:-$_amts_selected}}
    _amts_api=${API_MODEL_SONNET:-${API_MODEL:-$_amts_selected}}
  elif [ "$_amts_selected" = "$MODEL_HAIKU" ]; then
    _amts_plan=${PLAN_MODEL_HAIKU:-${PLAN_MODEL:-$_amts_selected}}
    _amts_api=${API_MODEL_HAIKU:-${API_MODEL:-$_amts_selected}}
  elif [ "$_amts_selected" = "$MODEL_SUBAGENT" ]; then
    _amts_plan=${PLAN_MODEL_SUBAGENT:-${PLAN_MODEL:-$_amts_selected}}
    _amts_api=${API_MODEL_SUBAGENT:-${API_MODEL:-$_amts_selected}}
  fi
  MODEL=$_amts_selected MODEL_OPUS=$_amts_selected MODEL_SONNET=$_amts_selected
  MODEL_HAIKU=$_amts_selected MODEL_SUBAGENT=$_amts_selected
  if [ -n "$PLAN_URL" ]; then
    PLAN_MODEL=$_amts_plan PLAN_MODEL_OPUS=$_amts_plan PLAN_MODEL_SONNET=$_amts_plan
    PLAN_MODEL_HAIKU=$_amts_plan PLAN_MODEL_SUBAGENT=$_amts_plan
  fi
  if [ -n "$API_URL" ]; then
    API_MODEL=$_amts_api API_MODEL_OPUS=$_amts_api API_MODEL_SONNET=$_amts_api
    API_MODEL_HAIKU=$_amts_api API_MODEL_SUBAGENT=$_amts_api
  fi
}
crouter_model_state_file() { printf '%s/crouter/last-model-%s' "${XDG_STATE_HOME:-$HOME/.local/state}" "$1"; }
load_last_selected_model() {
  _clsm_file=$(crouter_model_state_file "$1")
  [ -f "$_clsm_file" ] && [ ! -L "$_clsm_file" ] || return 0
  _clsm_model=$(cat "$_clsm_file") || return 0
  case $_clsm_model in ''|*[!A-Za-z0-9._:/@_\[\]-]*) return 0 ;; esac
  printf '%s' "$_clsm_model"
}
remember_last_selected_model() {
  _rlsm_provider=$1 _rlsm_model=$2
  [ -n "$_rlsm_model" ] || return 0
  _rlsm_dir="${XDG_STATE_HOME:-$HOME/.local/state}/crouter"
  (umask 077; mkdir -p "$_rlsm_dir") || return 1
  _rlsm_tmp=$(mktemp "$_rlsm_dir/.model.XXXXXXXX") || return 1
  if ! chmod 600 "$_rlsm_tmp" || ! printf '%s\n' "$_rlsm_model" > "$_rlsm_tmp" || ! mv -f "$_rlsm_tmp" "$(crouter_model_state_file "$_rlsm_provider")"; then
    rm -f "$_rlsm_tmp"; return 1
  fi
}
