#!/bin/sh
# Key management for pooled providers. Built-in service names remain in the
# provider catalog; user-added names live in STATE_DIR/keypools/*.tsv. Secrets
# live only in the macOS Keychain and are never printed.
# Depends on: provider.sh (provider_file, load_provider).

# _surface_var <name>   ->  variable name holding the keys for that surface.
# Public surfaces are plan/api. main/plus remain compatibility aliases.
_surface_var() {
  case $1 in
    plan|token-plan) printf 'PLAN_KEYS' ;;
    api|api-key)     printf 'API_KEYS' ;;
    main)
      if [ "${AUTH_MODE:-}" = surfaces ]; then printf 'API_KEYS'; else printf 'AUTH_KEYS'; fi
      ;;
    plus)
      if [ "${AUTH_MODE:-}" = surfaces ]; then printf 'PLAN_KEYS'; else printf 'PLUS_KEYS'; fi
      ;;
    *) die "unknown surface '$1' (expected: plan or api)" ;;
  esac
}

_canonical_surface() {
  case $1 in
    plan|token-plan|plus)
      if [ "${AUTH_MODE:-}" = surfaces ]; then printf plan; else printf plus; fi ;;
    api|api-key|main)
      if [ "${AUTH_MODE:-}" = surfaces ]; then printf api; else printf main; fi ;;
    *) die "unknown surface '$1' (expected: plan or api)" ;;
  esac
}

_key_var_value() {
  case $1 in
    PLAN_KEYS) printf '%s' "${PLAN_KEYS:-}" ;;
    API_KEYS)  printf '%s' "${API_KEYS:-}" ;;
    AUTH_KEYS) printf '%s' "${AUTH_KEYS:-}" ;;
    PLUS_KEYS) printf '%s' "${PLUS_KEYS:-}" ;;
    *) die "unsupported key variable '$1'" ;;
  esac
}

_validate_service_name() {
  case $1 in
    ''|.|..|*[!A-Za-z0-9._:@+-]*)
      die "invalid Keychain service name '$1' (use letters, digits, dot, underscore, colon, at, plus, or hyphen)" ;;
  esac
}

# _read_kv <file> <var>   ->  print current value of VAR="..." in file (no quotes, no comments)
_read_kv() {
  awk -v v="$2" '
    $0 ~ "^"v"=" {
      sub("^"v"=\"?", "")
      sub("\"?[[:space:]]*$", "")
      print
      exit
    }
  ' "$1"
}

_registry_add() {
  _ra_provider=$1 _ra_surface=$2 _ra_service=$3
  _ra_file=$(provider_registry_file "$_ra_provider") || die "STATE_DIR is not configured"
  _ra_dir=$(dirname -- "$_ra_file")
  (umask 077; mkdir -p "$_ra_dir") || die "cannot create key registry directory: $_ra_dir"
  chmod 700 "$_ra_dir" 2>/dev/null || true
  if [ -f "$_ra_file" ] && awk -F '\t' -v s="$_ra_surface" -v n="$_ra_service" \
      '$1 == s && $2 == n {found=1} END {exit !found}' "$_ra_file"; then
    return 0
  fi
  (umask 077; printf '%s\t%s\n' "$_ra_surface" "$_ra_service" >> "$_ra_file") ||
    die "cannot update key registry: $_ra_file"
  chmod 600 "$_ra_file" 2>/dev/null || true
}

_registry_remove() {
  _rr_provider=$1 _rr_surface=$2 _rr_service=$3
  _rr_file=$(provider_registry_file "$_rr_provider") || return 0
  [ -f "$_rr_file" ] || return 0
  _rr_tmp="$_rr_file.tmp.$$"
  (umask 077; awk -F '\t' -v s="$_rr_surface" -v n="$_rr_service" \
    '!( $1 == s && $2 == n )' "$_rr_file" > "$_rr_tmp") || {
      rm -f "$_rr_tmp"
      die "cannot update key registry: $_rr_file"
    }
  chmod 600 "$_rr_tmp" 2>/dev/null || true
  mv "$_rr_tmp" "$_rr_file"
}

_contains_word() {
  case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac
}

_first_missing_service() {
  for _fms_service in $1; do
    if ! security find-generic-password -a "$USER" -s "$_fms_service" >/dev/null 2>&1; then
      printf '%s' "$_fms_service"
      return 0
    fi
  done
  return 1
}

# _single_key_service <provider>   ->  the Keychain service name a single-key
# provider should use for `crouter add`, or empty if the mode has no
# user-managed key. Covers keychain / env(fallback) / legacy dual-source.
# keypool, none and static are intentionally NOT served here (pool / proxy).
_single_key_service() {
  if is_dual_source; then
    printf '%s' "${API_KEY_REF:-}"
    return
  fi
  case "${AUTH_MODE:-}" in
    keychain) printf '%s' "${AUTH_REFERENCE:-}" ;;
    env)      printf '%s' "${AUTH_KEYCHAIN_FALLBACK:-${AUTH_REFERENCE:-}}" ;;
    *)        printf '' ;;
  esac
}

# _prompt_secret <prompt>   ->  read a secret from /dev/tty with no echo
_prompt_secret() {
  [ -r /dev/tty ] || die "no TTY available; cannot prompt for secret"
  _old_stty=$(stty -g 2>/dev/null || true)
  trap 'stty "$_old_stty" 2>/dev/null; trap - INT TERM' INT TERM
  printf '%s' "$1" >/dev/tty
  stty -echo 2>/dev/null
  IFS= read -r _secret </dev/tty || _secret=
  stty echo 2>/dev/null
  printf '\n' >/dev/tty
  trap - INT TERM
  [ -n "$_old_stty" ] && stty "$_old_stty" 2>/dev/null
  printf '%s' "$_secret"
  unset _secret
}

# _keychain_put <service> <value>   ->  add or update (-U) a generic password for current $USER
_keychain_put() {
  # A trailing `security -w` opens /dev/tty and asks for the value twice even
  # after crouter has already collected it. Supplying the captured value here
  # makes crouter's explicit hidden prompt the only user interaction.
  security add-generic-password -U -a "$USER" -s "$1" -w "$2" >/dev/null 2>&1
}

# _keychain_delete <service>   ->  delete a generic password; missing is okay.
_keychain_delete() {
  security delete-generic-password -a "$USER" -s "$1" >/dev/null 2>&1
  _kd_rc=$?
  case $_kd_rc in
    0|44) return 0 ;;
    *) return "$_kd_rc" ;;
  esac
}

# _next_key_name <base> <existing refs> -> suggest "<base>-2", "<base>-3", ...
_next_key_name() {
  _base=$1
  _existing_names=${2:-}
  _n=2
  while _contains_word "$_existing_names" "${_base}-${_n}" ||
        security find-generic-password -a "$USER" -s "${_base}-${_n}" >/dev/null 2>&1; do
    _n=$((_n + 1))
  done
  printf '%s-%d' "$_base" "$_n"
}

_read_managed_secret() {
  if [ "$1" -eq 1 ]; then
    IFS= read -r _rms_secret || _rms_secret=
    printf '%s' "$_rms_secret"
  else
    _prompt_secret "$2"
  fi
}

cmd_add_key() {
  _p=$1; shift
  load_provider "$_p"

  # Pooled providers: multiple keys per surface, rich --surface/--name flags.
  if [ "${AUTH_MODE:-}" = "keypool" ] || [ "${AUTH_MODE:-}" = surfaces ]; then
    if [ "${AUTH_MODE:-}" = surfaces ]; then
      if [ -n "${PLAN_URL:-}" ]; then _surface=plan; else _surface=api; fi
    else
      _surface=main
    fi
    _name=
    _secret_stdin=0
    while [ $# -gt 0 ]; do
      case $1 in
        --surface) [ $# -ge 2 ] || die "add: --surface needs an argument (plan|api)"
                   _surface=$2; shift 2 ;;
        --surface=*) _surface=${1#--surface=}; shift ;;
        --name)   [ $# -ge 2 ] || die "add: --name needs an argument (keychain service name)"
                  _name=$2; shift 2 ;;
        --name=*) _name=${1#--name=}; shift ;;
        --stdin|--from-stdin) _secret_stdin=1; shift ;;
        -h|--help) info "usage: crouter add <provider> [--surface plan|api] [--name <service>] [--stdin]"; return 0 ;;
        *) die "add: unknown argument '$1'" ;;
      esac
    done

    _var=$(_surface_var "$_surface")
    _surface=$(_canonical_surface "$_surface")
    _file=$(provider_file "$_p")

    if [ "${AUTH_MODE:-}" = surfaces ]; then
      case $_var in
        PLAN_KEYS) [ -n "${PLAN_URL:-}" ] || die "provider '$_p' has no Token Plan surface" ;;
        API_KEYS)  [ -n "${API_URL:-}" ] || die "provider '$_p' has no pay-as-you-go API surface" ;;
      esac
    fi

    _existing=$(_key_var_value "$_var")
    _declared=$(_read_kv "$_file" "$_var")
    _new_registry=0
    # Fill the provider's declared Keychain slot before allocating a local
    # registry name. This makes the common one-key setup a single command.
    if [ -z "$_name" ]; then
      _name=$(_first_missing_service "$_declared" || true)
      if [ -z "$_name" ]; then
        _name=$(_next_key_name "$_p-$_surface" "$_existing")
        _new_registry=1
      fi
    elif ! _contains_word "$_existing" "$_name"; then
      _new_registry=1
    fi
    _validate_service_name "$_name"

    # Read from a hidden TTY prompt by default. --stdin supports password
    # managers and CI without ever putting the value in argv or source files.
    _secret=$(_read_managed_secret "$_secret_stdin" "Paste API key for $_name: ")
    [ -n "$_secret" ] || die "add: empty key; aborting"

    # Store in Keychain (add or update).
    _keychain_put "$_name" "$_secret" || die "add: failed to store '$_name' in macOS Keychain"
    unset _secret

    [ "$_new_registry" -eq 0 ] || _registry_add "$_p" "$_surface" "$_name"

    info "added '$_name' to $_surface surface of provider '$_p'"
    if [ "$_new_registry" -eq 1 ]; then
      info "  registered in $(provider_registry_file "$_p")"
    else
      info "  filled built-in Keychain service ($_var)"
    fi
    info "verify: crouter list $_p"
    return
  fi

  # Single-key providers (keychain / env / legacy dual-source): one item.
  _service=$(_single_key_service)
  if [ -z "$_service" ]; then
    case "${AUTH_MODE:-}" in
      none|static)
        die "provider '$_p' uses ${AUTH_MODE} auth — credentials are supplied by the local proxy, so there is no API key to add" ;;
      command)
        die "provider '$_p' uses command-based auth (AUTH_REFERENCE); crouter add can't manage it" ;;
      *)
        die "provider '$_p' has no Keychain target for add (set AUTH_KEYCHAIN_FALLBACK / AUTH_REFERENCE / API_KEY_REF)" ;;
    esac
  fi
  _secret_stdin=0
  while [ $# -gt 0 ]; do
    case $1 in
      --stdin|--from-stdin) _secret_stdin=1; shift ;;
      -h|--help) info "usage: crouter add <provider> [--stdin]"; return 0 ;;
      *) die "add: '$1' is not valid for a single-key provider" ;;
    esac
  done

  _secret=$(_read_managed_secret "$_secret_stdin" "Paste API key for $_service ($_p): ")
  [ -n "$_secret" ] || die "add: empty key; aborting"
  _keychain_put "$_service" "$_secret" || die "add: failed to store '$_service' in macOS Keychain"
  unset _secret

  info "stored key for '$_p' in Keychain service '$_service'"
  info "verify: crouter list $_p"
}

cmd_remove_key() {
  _p=$1; shift
  load_provider "$_p"

  if [ "${AUTH_MODE:-}" = "keypool" ] || [ "${AUTH_MODE:-}" = surfaces ]; then
    if [ "${AUTH_MODE:-}" = surfaces ]; then
      if [ -n "${PLAN_URL:-}" ]; then _surface=plan; else _surface=api; fi
    else
      _surface=main
    fi
    _name=
    _yes=0
    while [ $# -gt 0 ]; do
      case $1 in
        --surface) [ $# -ge 2 ] || die "remove: --surface needs an argument (plan|api)"
                   _surface=$2; shift 2 ;;
        --surface=*) _surface=${1#--surface=}; shift ;;
        --name)   [ $# -ge 2 ] || die "remove: --name needs an argument"
                  _name=$2; shift 2 ;;
        --name=*) _name=${1#--name=}; shift ;;
        -y|--yes) _yes=1; shift ;;
        -h|--help) info "usage: crouter remove <provider> --name <service> [--surface plan|api] [-y]"; return 0 ;;
        *) die "remove: unknown argument '$1'" ;;
      esac
    done
    [ -n "$_name" ] || die "remove: --name is required (the keychain service name to remove)"
    _validate_service_name "$_name"

    _var=$(_surface_var "$_surface")
    _surface=$(_canonical_surface "$_surface")
    _file=$(provider_file "$_p")

    _existing=$(_key_var_value "$_var")
    _declared=$(_read_kv "$_file" "$_var")
    _found=0
    _new=
    for _w in $_existing; do
      if [ "$_w" = "$_name" ]; then
        _found=1
      else
        _new="$_new $_w"
      fi
    done
    _new=$(echo "$_new" | sed 's/^ *//; s/ *$//')
    [ "$_found" -eq 1 ] || die "remove: service '$_name' is not in $_var"

    if [ "$_yes" -eq 0 ]; then
      printf 'remove %s from %s surface of %s and delete the Keychain item? [y/N] ' \
        "$_name" "$_surface" "$_p" >/dev/tty
      _ans=
      IFS= read -r _ans </dev/tty || _ans=
      case "$_ans" in y|Y|yes|YES) ;; *) info "aborted"; return 0 ;; esac
    fi

    _keychain_delete "$_name" || die "remove: failed to delete '$_name' from macOS Keychain"
    if ! _contains_word "$_declared" "$_name"; then
      _registry_remove "$_p" "$_surface" "$_name"
    fi

    info "removed '$_name' from $_surface surface of provider '$_p'"
    return
  fi

  # Single-key provider: delete the one Keychain item.
  _service=$(_single_key_service)
  [ -n "$_service" ] || die "provider '$_p' has no single-key to remove (mode=${AUTH_MODE:-})"

  _yes=0
  while [ $# -gt 0 ]; do
    case $1 in
      -y|--yes) _yes=1; shift ;;
      -h|--help) info "usage: crouter remove <provider> [-y]"; return 0 ;;
      *) die "remove: unknown argument '$1'" ;;
    esac
  done

  if [ "$_yes" -eq 0 ]; then
    printf 'delete Keychain item %s for provider %s? [y/N] ' "$_service" "$_p" >/dev/tty
    _ans=
    IFS= read -r _ans </dev/tty || _ans=
    case "$_ans" in y|Y|yes|YES) ;; *) info "aborted"; return 0 ;; esac
  fi

  _keychain_delete "$_service" || die "remove: failed to delete '$_service' from macOS Keychain"
  info "removed Keychain item '$_service' for provider '$_p'"
}

# cmd_list_keys [provider]   ->  list registered keys. No provider = all.
cmd_list_keys() {
  if [ -z "${1:-}" ]; then
    for _n in $(provider_names); do
      cmd_list_keys_one "$_n"
      echo
    done
    return
  fi
  cmd_list_keys_one "$1"
}

cmd_list_keys_one() {
  _p=$1
  load_provider "$_p"
  _file=$(provider_file "$_p")

  _ds=''; is_dual_source && _ds=' (dual-source)'
  printf 'provider: %s   auth_mode: %s%s\n' "$_p" "${AUTH_MODE:-}" "$_ds"

  # Legacy dual-source: preferred env credential + fallback API key.
  if is_dual_source; then
    if [ -n "${DEFAULT_TOKEN_ENV:-}" ]; then
      _dt=$(printenv "$DEFAULT_TOKEN_ENV" 2>/dev/null || true)
      [ -z "$_dt" ] && [ -n "${DEFAULT_TOKEN_ENV_FALLBACK:-}" ] && \
        _dt=$(printenv "$DEFAULT_TOKEN_ENV_FALLBACK" 2>/dev/null || true)
      if [ -n "$_dt" ]; then printf '  - default account: env:%s set\n' "$DEFAULT_TOKEN_ENV"
      else printf '  - default account: env:%s unset\n' "$DEFAULT_TOKEN_ENV"; fi
    fi
    if [ -n "${API_KEY_ENV:-}" ]; then
      _ak=$(printenv "$API_KEY_ENV" 2>/dev/null || true)
      if [ -n "$_ak" ]; then printf '  - api key: env:%s set\n' "$API_KEY_ENV"
      else printf '  - api key: env:%s unset\n' "$API_KEY_ENV"; fi
    fi
    if [ -n "${API_KEY_REF:-}" ]; then
      if security find-generic-password -a "$USER" -s "$API_KEY_REF" >/dev/null 2>&1; then
        printf '  - api key: keychain:%s in Keychain\n' "$API_KEY_REF"
      else
        printf '  - api key: keychain:%s MISSING\n' "$API_KEY_REF"
      fi
    fi
    return
  fi

  case "${AUTH_MODE:-}" in
    keypool|surfaces)
      if [ "${AUTH_MODE:-}" = surfaces ]; then _surfaces="plan api"; else _surfaces="main plus"; fi
      for _surface in $_surfaces; do
        _var=$(_surface_var "$_surface")
        _existing=$(_key_var_value "$_var")
        [ -z "$_existing" ] && continue
        printf '%-8s surface (%s):\n' "$_surface" "$_var"
        for _w in $_existing; do
          if security find-generic-password -a "$USER" -s "$_w" >/dev/null 2>&1; then
            _st='in Keychain'
          else
            _st='MISSING from Keychain'
          fi
          printf '  - %-40s %s\n' "$_w" "$_st"
        done
      done
      if [ "${AUTH_MODE:-}" = surfaces ]; then
        [ -n "${PLAN_KEY_ENV:-}" ] && printf '  - plan env:%s %s\n' "$PLAN_KEY_ENV" \
          "$([ -n "$(printenv "$PLAN_KEY_ENV" 2>/dev/null)" ] && printf set || printf unset)"
        [ -n "${API_KEY_ENV:-}" ] && printf '  - api env:%s %s\n' "$API_KEY_ENV" \
          "$([ -n "$(printenv "$API_KEY_ENV" 2>/dev/null)" ] && printf set || printf unset)"
      fi
      ;;
    keychain)
      _ref=${AUTH_REFERENCE:-}
      if [ -n "$_ref" ] && security find-generic-password -a "$USER" -s "$_ref" >/dev/null 2>&1; then
        printf '  - %-40s in Keychain\n' "$_ref"
      else
        printf '  - %-40s MISSING\n' "${_ref:-<AUTH_REFERENCE unset>}"
      fi
      ;;
    env)
      _v=$(printenv "${AUTH_REFERENCE:-}" 2>/dev/null || true)
      if [ -n "$_v" ]; then
        printf '  - env:%s set\n' "${AUTH_REFERENCE:-}"
      else
        printf '  - env:%s unset\n' "${AUTH_REFERENCE:-}"
      fi
      _svc=${AUTH_KEYCHAIN_FALLBACK:-}
      if [ -n "$_svc" ]; then
        if security find-generic-password -a "$USER" -s "$_svc" >/dev/null 2>&1; then
          printf '  - keychain:%s in Keychain\n' "$_svc"
        else
          printf '  - keychain:%s MISSING\n' "$_svc"
        fi
      fi
      ;;
    static)
      printf '  - static placeholder: %s\n' "${AUTH_REFERENCE:-<none>}"
      ;;
    none)
      printf '  - (no key — local proxy supplies auth)\n'
      ;;
    native)
      printf '  - (native cloud credential chain; no crouter key)\n'
      ;;
    *)
      printf '  - (unsupported AUTH_MODE: %s)\n' "${AUTH_MODE:-}"
      ;;
  esac
  return 0
}
