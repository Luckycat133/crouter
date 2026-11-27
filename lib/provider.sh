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
  CONTEXT_TOKENS= MAX_OUTPUT_TOKENS= AUTO_COMPACT_TOKENS= MODEL_CONTEXT_OVERRIDES= MODEL_SELF_ROUTE_MODELS=
  MODELS_DISCOVERY= MODELS_API_URL= MODELS_API_AUTH= MODELS_API_SURFACE=
  MODELS_ACCOUNT_LIVE=
  PLAN_MODELS= API_MODELS= MODEL_ID_ALIASES= MODEL_LABEL_ALIASES= MODEL_BLOCKED_IDS= MODEL_EFFORT_OVERRIDES=
  AUTH_MODE=none AUTH_REFERENCE= AUTH_KEYCHAIN_FALLBACK= _AUTH_SCHEME=
  EXTRA_ENV= PRE_START= POST_STOP= HEALTH_CHECK_URL= EFFORT= MODEL_SETUP= MODEL_SERVICE=
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
  # Labels are exact newline-delimited records. Keep the original space-separated
  # format for aliases that are themselves valid model IDs.
  case $1 in
    *' '*)
      while IFS='=' read -r _rmi_label _rmi_target; do
        [ "$_rmi_label" = "$1" ] || continue
        _rmi_model=$_rmi_target; break
      done <<EOF
${MODEL_LABEL_ALIASES:-}
EOF
      ;;
    *)
      for _rmi_pair in ${MODEL_ID_ALIASES:-}; do
        [ "${_rmi_pair%%=*}" = "$1" ] || continue
        _rmi_model=${_rmi_pair#*=}; break
      done
      ;;
  esac
  case $_rmi_model in ''|*[!A-Za-z0-9._:/@_\[\]-]*) die 'invalid model ID' ;; esac
  [ "${#_rmi_model}" -le 512 ] || die 'invalid model ID'
  for _rmi_blocked in ${MODEL_BLOCKED_IDS:-}; do
    [ "$_rmi_model" != "$_rmi_blocked" ] || die 'retired model ID; select a current model explicitly'
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
apply_model_effort_override() {
  for _ameo_pair in ${MODEL_EFFORT_OVERRIDES:-}; do
    [ "${_ameo_pair%%=*}" = "$1" ] || continue
    EFFORT=${_ameo_pair#*=}; return 0
  done
}
apply_model_self_route() {
  if [ "${MODEL_SELF_ROUTE_MODELS:-}" != '*' ]; then
    _amsr_name=
    for _amsr_name in ${MODEL_SELF_ROUTE_MODELS:-}; do
      [ "$1" != "$_amsr_name" ] || break
    done
    [ "$1" = "$_amsr_name" ] || return 0
  fi
  MODEL_OPUS=$1 MODEL_SONNET=$1 MODEL_HAIKU=$1 MODEL_SUBAGENT=$1
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

# Resolve model policy once, before any startup hook can contact an upstream.
# The launcher and provider hooks consume these same frozen shell values.
build_launch_plan() {
  LAUNCH_MODEL=$(resolve_model_id "$1") || return 1
  if [ "$LAUNCH_MODEL" != "$MODEL" ]; then
    CONTEXT_TOKENS= MAX_OUTPUT_TOKENS= AUTO_COMPACT_TOKENS=
  fi
  if [ -n "$MODEL_SETUP" ]; then "$MODEL_SETUP" "$LAUNCH_MODEL" || return $?; fi
  _lp_limits=$(model_state_limits "$PROVIDER_NAME" "$LAUNCH_MODEL")
  IFS=' ' read -r _lp_context _lp_output _lp_catalog_context _lp_catalog_output LAUNCH_SELECTION_REVISION <<EOF
$_lp_limits
EOF
  if [ "${_lp_context:-0}" -gt 0 ] && { [ -z "$CONTEXT_TOKENS" ] || [ "$_lp_context" -lt "$CONTEXT_TOKENS" ]; }; then
    CONTEXT_TOKENS=$_lp_context
  fi
  if [ "${_lp_output:-0}" -gt 0 ] && { [ -z "$MAX_OUTPUT_TOKENS" ] || [ "$_lp_output" -lt "$MAX_OUTPUT_TOKENS" ]; }; then
    MAX_OUTPUT_TOKENS=$_lp_output
  fi
  apply_model_context_override "$LAUNCH_MODEL"
  apply_model_effort_override "$LAUNCH_MODEL"
  apply_model_tier_settings "$LAUNCH_MODEL"
  apply_model_self_route "$LAUNCH_MODEL"
  # Unscoped values and inherited limits must not outlive the chosen model.
  for _lp_limit in "$CONTEXT_TOKENS" "$MAX_OUTPUT_TOKENS" "$AUTO_COMPACT_TOKENS"; do
    case $_lp_limit in ''|[1-9]|[1-9][0-9]*) ;; *) die 'invalid model token limit' ;; esac
    case $_lp_limit in *[!0-9]*|??????????*) die 'invalid model token limit' ;; esac
    [ "${_lp_limit:-1}" -le 100000000 ] || die 'invalid model token limit'
  done
  # Directory bounds are revalidated each time. Saving a default keeps the
  # model and local limits without turning a cache hint into unscoped state.
  if [ -n "$MAX_OUTPUT_TOKENS" ] && [ -n "$CONTEXT_TOKENS" ] && [ "$MAX_OUTPUT_TOKENS" -gt "$CONTEXT_TOKENS" ]; then
    MAX_OUTPUT_TOKENS=$CONTEXT_TOKENS
  fi
  LAUNCH_SAVED_CONTEXT=$CONTEXT_TOKENS LAUNCH_SAVED_OUTPUT=$MAX_OUTPUT_TOKENS
  if [ "${_lp_catalog_context:-0}" -gt 0 ] && { [ -z "$CONTEXT_TOKENS" ] || [ "$_lp_catalog_context" -lt "$CONTEXT_TOKENS" ]; }; then
    CONTEXT_TOKENS=$_lp_catalog_context
  fi
  if [ "${_lp_catalog_output:-0}" -gt 0 ] && { [ -z "$MAX_OUTPUT_TOKENS" ] || [ "$_lp_catalog_output" -lt "$MAX_OUTPUT_TOKENS" ]; }; then
    MAX_OUTPUT_TOKENS=$_lp_catalog_output
  fi
  if [ -n "$CONTEXT_TOKENS" ]; then
    if [ -n "$AUTO_COMPACT_TOKENS" ] && [ "$AUTO_COMPACT_TOKENS" -gt "$CONTEXT_TOKENS" ]; then AUTO_COMPACT_TOKENS=; fi
    if [ -n "$MAX_OUTPUT_TOKENS" ] && [ "$MAX_OUTPUT_TOKENS" -gt "$CONTEXT_TOKENS" ]; then MAX_OUTPUT_TOKENS=$CONTEXT_TOKENS; fi
  fi

  LAUNCH_SOURCE_URL=$BASE_URL
  [ -n "$MODEL_SERVICE" ] || [ -z "$PRE_START" ] || MODEL_SERVICE=$PROVIDER_NAME
  readonly LAUNCH_MODEL LAUNCH_SOURCE_URL CONTEXT_TOKENS MAX_OUTPUT_TOKENS AUTO_COMPACT_TOKENS EFFORT
  readonly LAUNCH_SAVED_CONTEXT LAUNCH_SAVED_OUTPUT LAUNCH_SELECTION_REVISION
  readonly MODEL MODEL_OPUS MODEL_SONNET MODEL_HAIKU MODEL_SUBAGENT MODEL_SERVICE
  readonly PLAN_MODEL PLAN_MODEL_OPUS PLAN_MODEL_SONNET PLAN_MODEL_HAIKU PLAN_MODEL_SUBAGENT
  readonly API_MODEL API_MODEL_OPUS API_MODEL_SONNET API_MODEL_HAIKU API_MODEL_SUBAGENT
  readonly ASSET_PROFILE ASSET_PLUGIN_DIRS ASSET_PLAN_PLUGIN_DIRS ASSET_API_PLUGIN_DIRS
}

show_launch_plan() {
  [ -n "$NODE_BIN" ] || die 'previewing a launch plan requires Node.js'
  _lp_ref=
  case $AUTH_MODE in
    env) _lp_ref="$AUTH_REFERENCE $AUTH_KEYCHAIN_FALLBACK" ;;
    keychain) _lp_ref=$AUTH_REFERENCE ;;
    keypool) _lp_ref="$AUTH_KEYS $PLUS_KEYS" ;;
  esac
  _lp_effort=$EFFORT _lp_effort_source=provider _lp_next=0
  for _lp_arg in "$@"; do
    if [ "$_lp_next" -eq 1 ]; then _lp_effort=$_lp_arg; _lp_next=0; continue; fi
    case $_lp_arg in
      --) break ;;
      --effort) _lp_effort= _lp_effort_source=caller _lp_next=1 ;;
      --effort=*) _lp_effort=${_lp_arg#*=} _lp_effort_source=caller ;;
    esac
  done
  LP_SOURCE="$LAUNCH_SOURCE_URL" LP_AUTH_MODE="$AUTH_MODE" LP_AUTH_REFS="$_lp_ref" \
  LP_TIER_OPUS="$MODEL_OPUS" LP_TIER_SONNET="$MODEL_SONNET" LP_TIER_HAIKU="$MODEL_HAIKU" LP_TIER_SUBAGENT="$MODEL_SUBAGENT" \
  LP_PLAN_URL="$PLAN_URL" LP_PLAN_REFS="$PLAN_KEY_ENV $PLAN_KEYS" \
  LP_API_URL="$API_URL" LP_API_REFS="$API_KEY_ENV $API_KEY_REF $API_KEYS" \
  LP_DEFAULT_URL="$DEFAULT_URL" LP_DEFAULT_REFS="$DEFAULT_TOKEN_ENV $DEFAULT_TOKEN_ENV_FALLBACK" \
  LP_EFFORT="$_lp_effort" LP_EFFORT_SOURCE="$_lp_effort_source" LP_NATIVE="$NATIVE_BACKEND" LP_SERVICE="$MODEL_SERVICE" \
  LP_ASSET_PROFILE="$ASSET_PROFILE" LP_PLUGINS="$ASSET_PLUGIN_DIRS" \
  LP_PLAN_PLUGINS="$ASSET_PLAN_PLUGIN_DIRS" LP_API_PLUGINS="$ASSET_API_PLUGIN_DIRS" \
  LP_ASSETS_ENABLED="${CROUTER_PROVIDER_ASSETS:-1}" LP_STRICT_MCP="${CROUTER_STRICT_PROVIDER_MCP:-1}" \
  LP_PAID_FALLBACK="${CROUTER_ALLOW_PAID_FALLBACK:-0}" LP_CROSS_MODEL_FALLBACK="${CROUTER_ALLOW_CROSS_MODEL_FALLBACK:-0}" \
    "$NODE_BIN" "$LIB_DIR/model-state.js" plan "$PROVIDER_NAME" "$LAUNCH_MODEL" "$CONTEXT_TOKENS" "$MAX_OUTPUT_TOKENS" "$AUTO_COMPACT_TOKENS"
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
