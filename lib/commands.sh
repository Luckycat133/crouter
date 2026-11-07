#!/bin/sh
# Human-facing metadata/diagnostics, kept separate from model launch planning.
# These functions retain the existing CLI contracts; none starts providers.
provider_auth_mode() {
  if is_dual_source; then
    if [ -n "${DEFAULT_TOKEN_ENV:-}" ]; then printf dual; else printf apikey; fi
  elif is_surface_provider; then
    if [ -n "$PLAN_URL" ] && [ -n "$API_URL" ]; then printf plan+api
    elif [ -n "$PLAN_URL" ]; then printf plan; else printf api; fi
  else printf '%s' "$AUTH_MODE"; fi
}
provider_status() {
  case ${NATIVE_BACKEND:-} in ?*) printf native; return 0 ;; esac
  case $AUTH_MODE in static|none) printf local; return 0 ;; esac
  if check_auth; then printf ready; else printf no-key; fi
}
provider_scan() {
  _ps_dir=$1 _ps_kind=$2
  for _ps_n in $(provider_names); do
    (
      load_provider "$_ps_n" || exit 0
      case $_ps_kind in
        list) printf '%s\t%s\t%s\t%s\t%s\n' "$_ps_n" "$(provider_status)" "$(provider_auth_mode)" "$MODEL" "$BASE_URL" > "$_ps_dir/$_ps_n" ;;
        doctor) status_one "$_ps_n" > "$_ps_dir/$_ps_n" ;;
      esac
    ) &
  done
  wait
}
cmd_list() {
  _all=0
  for _arg in "$@"; do
    case $_arg in
      --all|-a) _all=1 ;; -h|--help) usage_list; return 0 ;;
      *) die "list: unknown argument '$_arg' (try: crouter list [--all])" ;;
    esac
  done
  _rows=$(mktemp -d "${TMPDIR:-/tmp}/crouter-list.XXXXXX") || die 'list: cannot create a temporary directory'
  provider_scan "$_rows" list
  printf '%-22s %-7s %-11s %-30s %s\n' PROVIDER STATUS AUTH 'DEFAULT MODEL' ENDPOINT
  _shown=0 _total=0
  for _n in $(provider_names); do
    [ -f "$_rows/$_n" ] || continue
    _total=$((_total + 1))
    IFS='	' read -r _n _st _mode _model _url < "$_rows/$_n" || continue
    [ -n "${_st:-}" ] || continue
    if [ "$_all" -eq 0 ] && [ "$_st" = no-key ]; then continue; fi
    printf '%-22s %-7s %-11s %-30s %s\n' "$_n" "$_st" "$_mode" "$_model" "$_url"
    _shown=$((_shown + 1))
  done
  rm -rf "$_rows"; _rows=
  if [ "$_shown" -eq 0 ]; then
    info ''; info "no provider is configured yet — run 'crouter add' to set one up, or 'crouter list --all' to see the full catalog"
  elif [ "$_all" -eq 0 ]; then
    info ''; info "$((_total - _shown)) of $_total providers have no credential yet — 'crouter list --all' to show them all, 'crouter add <provider>' to configure one"
  fi
}
status_one() (
  load_provider "$1"
  if check_auth; then
    _auth=ok
    if is_dual_source; then _auth="ok($(dual_source_state))"; fi
    if is_surface_provider; then _auth="ok($(surface_state))"; fi
  else _auth=MISSING; fi
  case ${NATIVE_BACKEND:-} in
    bedrock|vertex) _auth=UNVERIFIED ;;
    foundry)
      if [ -n "${ANTHROPIC_FOUNDRY_AUTH_TOKEN:-}${ANTHROPIC_FOUNDRY_API_KEY:-}" ]; then _auth=ok; else _auth=UNVERIFIED; fi ;;
  esac
  if [ -n "$HEALTH_CHECK_URL" ]; then
    if check_health; then _health=up; else _health=DOWN; fi
  else _health=-; fi
  printf '%-22s auth:%-9s health:%-6s %s\n' "$1" "$_auth" "$_health" "$BASE_URL"
  _status=0
  if [ "$_auth" = UNVERIFIED ] && [ "${2:-0}" -eq 1 ]; then
    case ${NATIVE_BACKEND:-} in
      bedrock) info 'note  AWS credential chain is unverified; doctor cannot check Bedrock account or model access' ;;
      vertex) info 'note  Google ADC is unverified; doctor cannot check Vertex project or model access' ;;
      foundry) info 'note  Azure credential chain is unverified; doctor cannot check Foundry account or model access' ;;
    esac
  fi
  if [ "${NATIVE_BACKEND:-}" = foundry ] && [ -z "${ANTHROPIC_FOUNDRY_RESOURCE:-}" ] && [ -z "${ANTHROPIC_FOUNDRY_BASE_URL:-}" ] && [ "${2:-0}" -eq 1 ]; then
    info 'note  Foundry endpoint not visible to crouter; check ANTHROPIC_FOUNDRY_RESOURCE or ANTHROPIC_FOUNDRY_BASE_URL in the shell, config.sh, or Claude settings'
  fi
  if [ "${NATIVE_BACKEND:-}" = vertex ] && [ -z "${ANTHROPIC_VERTEX_PROJECT_ID:-}" ] && [ "${2:-0}" -eq 1 ]; then
    info 'note  Vertex project not visible to crouter; check ANTHROPIC_VERTEX_PROJECT_ID in the shell, config.sh, or Claude settings'
  fi
  _needs_node=0
  case $AUTH_MODE in
    surfaces) _needs_node=1 ;;
    keypool) _doctor_key_count=$(set -- ${AUTH_KEYS:-}; printf '%s' "$#"); if [ "$_doctor_key_count" -ne 1 ] || [ -n "${PLUS_KEYS:-}" ]; then _needs_node=1; fi ;;
  esac
  if [ "${CROUTER_PROVIDER_ASSETS:-1}" != 0 ] && [ -n "${ASSET_PROFILE:-}" ]; then _needs_node=1; fi
  case $PROVIDER_NAME in ollama|bonsai|antigravity|antigravity-claude) _needs_node=1 ;; esac
  if [ "${2:-0}" -eq 1 ] && [ "$_needs_node" -eq 1 ]; then
    _doctor_node=$(command -v "$NODE_BIN" 2>/dev/null || true)
    if [ -z "$_doctor_node" ] || [ ! -f "$_doctor_node" ] || [ ! -x "$_doctor_node" ]; then
      _status=1; info "FAIL  node unavailable; install Node.js or set NODE_BIN in config.sh to an executable Node binary, then retry crouter doctor '$1'"
    fi
  fi
  if [ "$_auth" = MISSING ]; then
    _status=1
    if [ "${2:-0}" -eq 1 ]; then
      if [ "${NATIVE_BACKEND:-}" = foundry ]; then
        info "next: set ANTHROPIC_FOUNDRY_AUTH_TOKEN or ANTHROPIC_FOUNDRY_API_KEY, or configure Azure SDK credentials, then retry crouter doctor '$1'"
      elif is_surface_provider; then
        if [ -n "$PLAN_URL" ]; then _doctor_surface=plan; else _doctor_surface=api; fi
        info "next: run crouter add '$1' --surface $_doctor_surface to configure a credential"
      elif is_dual_source; then
        if [ -n "${API_KEY_REF:-}" ]; then info "next: run crouter add '$1' to configure an API credential"
        else info "next: set ${DEFAULT_TOKEN_ENV:-${DEFAULT_TOKEN_ENV_FALLBACK:-${API_KEY_ENV:-the provider credential environment variable}}} and retry crouter doctor '$1'"; fi
      else
        case $AUTH_MODE in
          keychain|keypool) info "next: run crouter add '$1' to configure a credential" ;;
          env) info "next: export $AUTH_REFERENCE with your provider credential and retry crouter doctor '$1'"; [ -z "$AUTH_KEYCHAIN_FALLBACK" ] || info "      or store it in Keychain with crouter add '$1'" ;;
          command) info "next: check the configured authentication command for '$1'; it must return a nonempty credential" ;;
          *) info "next: check AUTH_MODE in providers/$1.sh" ;;
        esac
      fi
    fi
  fi
  if [ "$_health" = DOWN ]; then
    _status=1
    if [ "${2:-0}" -eq 1 ]; then
      info "next: check the configured health URL and service connectivity, then retry crouter doctor '$1'"
      [ -z "$PRE_START" ] || info "      doctor does not start the service; crouter '$1' runs its startup hook"
    fi
  fi
  exit "$_status"
)
cmd_doctor() {
  case ${1:-} in -h|--help) usage_doctor; return 0 ;; -*) die "doctor: unknown argument '$1' (try: crouter doctor [<provider>])" ;; esac
  _fail=0
  info Environment
  if [ -n "$CLAUDE_BIN" ] && [ -x "$CLAUDE_BIN" ]; then info "ok    claude binary: $CLAUDE_BIN"
  else info 'FAIL  claude binary not found (set CLAUDE_BIN in config.sh)'; _fail=1; fi
  if [ -f "$ROOT_DIR/config.sh" ]; then info "ok    config: $ROOT_DIR/config.sh"
  else info 'note  no config.sh (using defaults; copy config.example.sh if needed)'; fi
  if command -v curl >/dev/null 2>&1; then info 'ok    curl available'; else info 'FAIL  curl missing'; _fail=1; fi
  if command -v security >/dev/null 2>&1; then info 'ok    macOS keychain (security) available'
  else info "note  'security' missing (keychain providers unavailable)"; fi
  info ''
  if [ -n "${1:-}" ]; then status_one "$1" 1 || _fail=1; else cmd_doctor_overview; fi
  return "$_fail"
}
cmd_doctor_overview() {
  _dr=$(mktemp -d "${TMPDIR:-/tmp}/crouter-doctor.XXXXXX") || {
    info 'note  cannot create a temporary directory; printing providers unsorted'
    for _n in $(provider_names); do status_one "$_n" || :; done
    return 0
  }
  provider_scan "$_dr" doctor
  _pending=$(mktemp "${TMPDIR:-/tmp}/crouter-doctor-rows.XXXXXX") || {
    for _n in $(provider_names); do
      [ -f "$_dr/$_n" ] || continue
      IFS= read -r _line < "$_dr/$_n" || continue
      [ -z "$_line" ] || info "$_line"
    done
    rm -rf "$_dr"; return 0
  }
  _total=0 _missing=0 _down=0
  for _n in $(provider_names); do
    [ -f "$_dr/$_n" ] || continue
    IFS= read -r _line < "$_dr/$_n" || continue
    [ -n "$_line" ] || continue
    _total=$((_total + 1))
    case $_line in
      *auth:MISSING*) _key=0; _missing=$((_missing + 1)) ;;
      *health:DOWN*) _key=1; _down=$((_down + 1)) ;;
      *) _key=2 ;;
    esac
    printf '%s\t%s\n' "$_key" "$_line" >> "$_pending"
  done
  rm -rf "$_dr"; _dr=
  _summary="$_total total"
  [ "$_missing" -eq 0 ] || _summary="$_summary — $_missing without a credential"
  [ "$_down" -eq 0 ] || _summary="$_summary, $_down with a failing health check"
  info "Providers ($_summary)"
  sort -k1,1n -k2,2 "$_pending" | cut -f2-
  rm -f "$_pending"; _pending=
  if [ "$_missing" -gt 0 ] || [ "$_down" -gt 0 ]; then
    info ''; info "next: 'crouter doctor <provider>' explains one in detail"
    [ "$_down" -eq 0 ] || info "      'crouter <provider>' runs the startup hook that health checks do not start"
  fi
}
cmd_provider_show() {
  case ${1:-} in -h|--help) usage_provider; return 0 ;; '') die 'provider: name a provider (try: crouter list)' ;; esac
  _p=$1; load_provider "$_p"; apply_model_context_override "$MODEL"
  printf 'provider:    %s\ndescription: %s\nconfig file: %s\n\n' "$_p" "${PROVIDER_DESC:-<none>}" "$(provider_file "$_p")"
  printf 'endpoint:    %s\ndefault:     %s\ncontext:     %s tokens\n' "$BASE_URL" "$MODEL" "${CONTEXT_TOKENS:-<unset>}"
  printf 'auto compact: %s\neffort:      %s\n\n' "${AUTO_COMPACT_TOKENS:-<unset>}" "${EFFORT:-<unset>}"
  printf 'aliases:\n  opus:      %s\n  sonnet:    %s\n  haiku:     %s\n  subagent:  %s\n' "$MODEL_OPUS" "$MODEL_SONNET" "$MODEL_HAIKU" "$MODEL_SUBAGENT"
  [ -z "$MODEL_ALIASES" ] || printf '  extras:    %s\n' "$MODEL_ALIASES"
  printf '\n'
  if is_surface_provider; then
    printf 'auth:        Token Plan / API key surfaces\n'
    if [ -n "$PLAN_URL" ]; then
      printf '  plan URL:  %s\n    type:    %s\n    key env: %s\n    keychain: %s\n    model:   %s\n' "$PLAN_URL" "${PLAN_AUTH_TYPE:-bearer}" "${PLAN_KEY_ENV:-<unset>}" "${PLAN_KEYS:-<none>}" "${PLAN_MODEL:-$MODEL}"
      printf '    tiers:   opus=%s sonnet=%s haiku=%s subagent=%s\n' "${PLAN_MODEL_OPUS:-${PLAN_MODEL:-$MODEL_OPUS}}" "${PLAN_MODEL_SONNET:-${PLAN_MODEL:-$MODEL_SONNET}}" "${PLAN_MODEL_HAIKU:-${PLAN_MODEL:-$MODEL_HAIKU}}" "${PLAN_MODEL_SUBAGENT:-${PLAN_MODEL:-$MODEL_SUBAGENT}}"
    fi
    if [ -n "$API_URL" ]; then
      printf '  API URL:   %s\n    type:    %s\n    key env: %s\n    keychain: %s\n    model:   %s\n' "$API_URL" "${API_AUTH_TYPE:-bearer}" "${API_KEY_ENV:-<unset>}" "${API_KEYS:-<none>}" "${API_MODEL:-$MODEL}"
      printf '    tiers:   opus=%s sonnet=%s haiku=%s subagent=%s\n' "${API_MODEL_OPUS:-${API_MODEL:-$MODEL_OPUS}}" "${API_MODEL_SONNET:-${API_MODEL:-$MODEL_SONNET}}" "${API_MODEL_HAIKU:-${API_MODEL:-$MODEL_HAIKU}}" "${API_MODEL_SUBAGENT:-${API_MODEL:-$MODEL_SUBAGENT}}"
    fi
    printf '  live now:  %s\n' "$(_s=$(surface_state); printf '%s' "${_s:-<none configured>}")"
  elif is_dual_source; then
    if [ -n "${DEFAULT_TOKEN_ENV:-}" ]; then
      printf 'auth:        dual-source (default account first, API key on 401/402/403/429)\n'
      printf '  default:   %s\n    type:    %s\n    token:   $%s\n' "${DEFAULT_URL:-$BASE_URL}" "${DEFAULT_AUTH_TYPE:-bearer}" "$DEFAULT_TOKEN_ENV"
    else printf 'auth:        api key\n'; fi
    printf '  api:       %s\n    type:    %s\n    key:     $%s\n' "${API_URL:-$BASE_URL}" "${API_AUTH_TYPE:-x-api-key}" "${API_KEY_ENV:-<unset>}"
    printf '  live now:  %s\n' "$(_s=$(dual_source_state); printf '%s' "${_s:-<none configured>}")"
  else
    printf 'auth:        %s\n' "$AUTH_MODE"
    case $AUTH_MODE in
      keychain|env) printf '  reference: %s\n' "$AUTH_REFERENCE"; [ -z "$AUTH_KEYCHAIN_FALLBACK" ] || printf '  keychain fallback: %s\n' "$AUTH_KEYCHAIN_FALLBACK" ;;
      command) printf '  reference: <configured command>\n' ;;
      static) printf '  reference: <redacted>\n' ;;
      native) printf '  backend:   %s\n  passthrough: %s\n' "${NATIVE_BACKEND:-<unset>}" "${PASSTHROUGH_ENV:-<none>}" ;;
      keypool) printf '  AUTH_KEYS: %s\n  PLUS_URL: %s\n  PLUS_KEYS: %s\n' "${AUTH_KEYS:-<empty>}" "${PLUS_URL:-<unset>}" "${PLUS_KEYS:-<empty>}" ;;
    esac
  fi
  if [ -n "${ASSET_PROFILE:-}${ASSET_PLUGIN_DIRS:-}${ASSET_PLAN_PLUGIN_DIRS:-}${ASSET_API_PLUGIN_DIRS:-}" ]; then
    printf '\nassets:      MCP profile %s' "${ASSET_PROFILE:-empty}"
    [ -z "${ASSET_PLUGIN_DIRS:-}${ASSET_PLAN_PLUGIN_DIRS:-}${ASSET_API_PLUGIN_DIRS:-}" ] || printf ' + session skills'
    printf '\n  isolation: session-only%s\n' "$([ "${CROUTER_STRICT_PROVIDER_MCP:-1}" = 1 ] && printf ', strict MCP' || true)"
  fi
  if [ -n "$EXTRA_ENV" ]; then
    printf '\nextra env:\n'; _old_ifs=$IFS; IFS='
'
    for _pair in $EXTRA_ENV; do
      case $_pair in *=*) printf '  %s=<redacted>\n' "${_pair%%=*}" ;; *) printf '  <invalid entry>\n' ;; esac
    done
    IFS=$_old_ifs
  fi
  if [ -n "$PRE_START$POST_STOP$HEALTH_CHECK_URL" ]; then
    printf '\nhooks:\n'
    [ -z "$PRE_START" ] || printf '  PRE_START:        <configured>\n'
    [ -z "$POST_STOP" ] || printf '  POST_STOP:        <configured>\n'
    [ -z "$HEALTH_CHECK_URL" ] || printf '  HEALTH_CHECK_URL: <configured>\n'
  fi
  return 0
}
cmd_config_path() {
  if [ -f "$ROOT_DIR/config.sh" ]; then printf '%s\n' "$ROOT_DIR/config.sh"
  else printf 'no config.sh (using built-in defaults; copy %s/config.example.sh to %s/config.sh to override)\n' "$ROOT_DIR" "$ROOT_DIR"; return 1; fi
}
cmd_config_show() {
  printf 'ROOT_DIR:      <repository>\nVERSION:       <use crouter --version>\n'
  if [ -f "$ROOT_DIR/config.sh" ]; then printf 'CONFIG_FILE:   <present; use crouter config path>\n'; else printf 'CONFIG_FILE:   <none; using built-in defaults>\n'; fi
  if [ -n "${INSTALL_DIR:-}" ]; then printf 'INSTALL_DIR:   <configured>\n'; else printf 'INSTALL_DIR:   <default: ~/.local/bin>\n'; fi
  [ "$LOG_DIR" = "$ROOT_DIR/logs" ] && _cps='<default: repository logs>' || _cps='<configured>'; printf 'LOG_DIR:       %s\n' "$_cps"
  [ "$STATE_DIR" = "$ROOT_DIR/.state" ] && _cps='<default: repository .state>' || _cps='<configured>'; printf 'STATE_DIR:     %s\n' "$_cps"
  [ -z "$CLAUDE_BIN" ] && _cps='<not found>' || _cps='<configured>'; printf 'CLAUDE_BIN:    %s\n' "$_cps"
  [ -z "$NODE_BIN" ] && _cps='<not found>' || _cps='<configured>'; printf 'NODE_BIN:      %s\n' "$_cps"
  _config_bypass=0; [ "${BYPASS_PERMISSIONS:-0}" != 1 ] || _config_bypass=1
  _config_assets=1; [ "${CROUTER_PROVIDER_ASSETS:-1}" != 0 ] || _config_assets=0
  _config_strict=0; [ "${CROUTER_STRICT_PROVIDER_MCP:-1}" != 1 ] || _config_strict=1
  printf 'BYPASS_PERMISSIONS: %s\nCROUTER_PROVIDER_ASSETS: %s\nCROUTER_STRICT_PROVIDER_MCP: %s\n' "$_config_bypass" "$_config_assets" "$_config_strict"
}
cmd_logs_list() {
  _ld=${LOG_DIR:-$ROOT_DIR/logs}
  if [ ! -d "$_ld" ]; then info "no logs directory: $_ld"; return 0; fi
  _any=0
  for _f in "$_ld"/*; do [ -e "$_f" ] || continue; _any=1; break; done
  if [ "$_any" -eq 0 ]; then info '(no logs yet)'; return 0; fi
  printf '%10s  %-16s  %s\n' SIZE MODIFIED FILE
  for _f in "$_ld"/*; do
    [ -e "$_f" ] || continue
    _meta=$(ls -l "$_f" 2>/dev/null | awk 'NR==1{print $5, $6, $7}')
    if [ -n "$_meta" ]; then _size=${_meta%% *}; _when=${_meta#* }; else _size='?' _when=unknown; fi
    printf '%10s  %-16s  %s\n' "$_size" "$_when" "$_f"
  done
}
cmd_logs_tail() {
  case ${1:-} in -h|--help) usage_logs; return 0 ;; '') die 'logs: name a provider (try: crouter logs list)' ;; -*) die "logs: unknown argument '$1'" ;; esac
  _p=$1 _ld=${LOG_DIR:-$ROOT_DIR/logs} _found=
  case $_p in *[!A-Za-z0-9._-]*) die 'invalid log provider' ;; esac
  for _candidate in "$_ld/$_p.log" "$_ld/keypool-$_p.log" "$_ld/$_p-proxy.log"; do
    if [ -f "$_candidate" ]; then _found=$_candidate; break; fi
  done
  [ -n "$_found" ] || die "no log file for provider '$_p' under $_ld"
  info "tailing $_found (Ctrl-C to exit)"; tail -n 50 -F "$_found"
}
cmd_uninstall() {
  _yes=0
  while [ $# -gt 0 ]; do
    case $1 in -y|--yes) _yes=1; shift ;; -h|--help) info 'usage: crouter uninstall [-y]'; return 0 ;; *) die "uninstall: unknown argument '$1'" ;; esac
  done
  _dir=${INSTALL_DIR:-$HOME/.local/bin}
  if [ "$_yes" -eq 0 ]; then
    printf 'remove crouter from %s? [y/N] ' "$_dir" >/dev/tty
    _ans=; IFS= read -r _ans </dev/tty || _ans=
    case $_ans in y|Y|yes|YES) ;; *) info aborted; return 0 ;; esac
  fi
  _shortcut=$_dir/crouter
  if [ -L "$_shortcut" ]; then
    case $(readlink "$_shortcut" 2>/dev/null) in
      "$ROOT_DIR/bin/crouter") rm -f "$_shortcut" && info "removed $_shortcut" ;;
      *) info "skipped non-crouter symlink: $_shortcut" ;;
    esac
  elif [ -e "$_shortcut" ]; then info "skipped non-crouter file: $_shortcut"; fi
}
