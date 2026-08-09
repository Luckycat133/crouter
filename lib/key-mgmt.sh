#!/bin/sh
# Key management for all provider auth modes. Interactive Chinese menu-driven.
# Never prints the secret value.
# Depends: provider.sh (provider_file, load_provider, provider_names).

# _surface_var <name>   ->  variable name holding the keys for that surface.
_surface_var() {
  case $1 in
    main)    printf 'AUTH_KEYS' ;;
    plus)  printf 'PLUS_KEYS' ;;
    *) die "unknown surface '$1' (expected: main or plus)" ;;
  esac
}

# _read_kv <file> <var>   ->  print current value of VAR="..." in file
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

# _write_kv <file> <var> <value>   ->   set VAR="value" in place
_write_kv() {
  _file=$1; _var=$2; _val=$3
  awk -v var="$_var" -v val="$_val" '
    BEGIN { found=0 }
    $0 ~ "^" var "=" { print var "=\"" val "\""; found=1; next }
    { print }
    END { if (!found) print var "=\"" val "\"" }
  ' "$_file" > "$_file.tmp" && mv "$_file.tmp" "$_file"
}

# _single_key_service <provider> -> Keychain service name for single-key providers
# For env mode: returns AUTH_KEYCHAIN_FALLBACK if set, else AUTH_REFERENCE as fallback
_single_key_service() {
  if is_dual_source; then
    printf '%s' "${API_KEY_REF:-}"; return
  fi
  case "${AUTH_MODE:-}" in
    keychain) printf '%s' "${AUTH_REFERENCE:-}" ;;
    env)      printf '%s' "${AUTH_KEYCHAIN_FALLBACK:-${AUTH_REFERENCE:-}}" ;;
    *)        printf '' ;;
  esac
}

# _prompt_secret <prompt> -> read secret from /dev/tty with no echo
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

# _keychain_put <service> <value>
_keychain_put() { security add-generic-password -U -a "$USER" -s "$1" -w "$2"; }

# _keychain_delete <service>
_keychain_delete() { security delete-generic-password -a "$USER" -s "$1" >/dev/null 2>&1 || true; }

# _keychain_exists <service> -> 0 if exists
_keychain_exists() { security find-generic-password -a "$USER" -s "$1" >/dev/null 2>&1; }

# _next_key_name <provider> <surface> -> suggest "<provider>-2", "<provider>-3", ...
_next_key_name() {
  _base=$1; _n=2
  while _keychain_exists "${_base}-${_n}"; do _n=$((_n + 1)); done
  printf '%s-%d' "$_base" "$_n"
}

# ---------- 简洁交互式菜单 ----------

# _menu <title> <options...> -> print menu, read choice, return index (1-based) or 0 for quit
_menu() {
  _title=$1; shift
  printf '\n%s\n' "$_title" >/dev/tty
  _i=1
  for _opt; do
    printf '  %d. %s\n' "$_i" "$_opt" >/dev/tty
    _i=$((_i + 1))
  done
  printf '  0. 退出\n' >/dev/tty
  printf '> ' >/dev/tty
  IFS= read -r _choice </dev/tty || _choice=0
  case "$_choice" in
    ''|*[!0-9]*) return 1 ;;
    0) return 0 ;;
    *) [ "$_choice" -ge 1 ] && [ "$_choice" -le $((_i - 1)) ] && { printf '%s' "$_choice"; return 0; } ;;
  esac
}

# _confirm <msg> -> 0 for yes, 1 for no
_confirm() { printf '%s [y/N]: ' "$1" >/dev/tty; IFS= read -r _ans </dev/tty || _ans=n; case "$_ans" in y|Y) return 0 ;; *) return 1 ;; esac; }

# _input <prompt> [default] -> read line
_input() { _prompt=$1; _default=${2:-}; [ -n "$_default" ] && _prompt="$_prompt [$_default]: " || _prompt="$_prompt: "; printf '%s' "$_prompt" >/dev/tty; IFS= read -r _val </dev/tty || _val=; [ -z "$_val" ] && _val=$_default; printf '%s' "$_val"; }

# _list_providers_with_keys -> print provider list with key status for menu
_list_providers_with_keys() {
  for _p in $(provider_names); do
    ( load_provider "$_p"
      _status=""
      case "${AUTH_MODE:-}" in
        keypool)
          _main=$(_read_kv "$(provider_file "$_p")" "AUTH_KEYS")
          _plus=$(_read_kv "$(provider_file "$_p")" "PLUS_KEYS")
          _cnt=0; for _k in $_main $_plus; do _cnt=$((_cnt + 1)); done
          _status="keypool (${_cnt})"
          ;;
        keychain|env)
          _svc=$(_single_key_service)
          [ -n "$_svc" ] && _keychain_exists "$_svc" && _status="已配置" || _status="未配置"
          _status="$AUTH_MODE ($_status)"
          ;;
        dual-source|"") _status="dual" ;;
        *) _status="$AUTH_MODE" ;;
      esac
      printf '%s|%s\n' "$_p" "$_status"
    )
  done | sort
}

# _provider_key_menu <provider> -> interactive key management for one provider
_provider_key_menu() {
  _provider=$1
  load_provider "$_provider"
  _file=$(provider_file "$_provider")

  while true; do
    case "${AUTH_MODE:-}" in
      keypool)
        _main=$(_read_kv "$_file" "AUTH_KEYS")
        _plus=$(_read_kv "$_file" "PLUS_KEYS")
        printf '\n%s (keypool)\n' "$_provider" >/dev/tty
        [ -n "$_main" ] && for _k in $_main; do _keychain_exists "$_k" && printf '  ✓ %s\n' "$_k" >/dev/tty || printf '  ✗ %s\n' "$_k" >/dev/tty; done
        [ -n "$_plus" ] && for _k in $_plus; do _keychain_exists "$_k" && printf '  + %s\n' "$_k" >/dev/tty || printf '  - %s\n' "$_k" >/dev/tty; done
        _choice=$(_menu "操作" "添加主密钥" "添加 Plus 密钥" "删除密钥")
        ;;
      keychain|env)
        _svc=$(_single_key_service)
        printf '\n%s (%s)\n' "$_provider" "$AUTH_MODE" >/dev/tty
        [ -n "$_svc" ] && _keychain_exists "$_svc" && printf '  ✓ %s\n' "$_svc" >/dev/tty || printf '  ✗ %s\n' "$_svc" >/dev/tty
        [ -n "$_svc" ] && _choice=$(_menu "操作" "设置密钥" "删除密钥") || _choice=0
        ;;
      dual-source|"")
        printf '\n%s (dual)\n' "$_provider" >/dev/tty
        [ -n "${DEFAULT_TOKEN_ENV:-}" ] && printf '  默认: $%s\n' "$DEFAULT_TOKEN_ENV" >/dev/tty
        [ -n "${API_KEY_REF:-}" ] && printf '  备用: keychain:%s\n' "$API_KEY_REF" >/dev/tty
        _choice=$(_menu "操作" "设置备用 Key" "删除备用 Key")
        ;;
      *) return ;;
    esac
    [ -z "$_choice" ] || [ "$_choice" -eq 0 ] && break

    case "${AUTH_MODE:-}" in
      keypool)
        case "$_choice" in
          1) _keypool_add "$_provider" "AUTH_KEYS" "主密钥" "$_file" ;;
          2) _keypool_add "$_provider" "PLUS_KEYS" "Plus密钥" "$_file" ;;
          3) _keypool_remove "$_provider" "$_file" ;;
        esac ;;
      keychain|env)
        case "$_choice" in
          1) _single_key_set "$_provider" "$_file" ;;
          2) _single_key_remove "$_provider" ;;
        esac ;;
      dual-source|"")
        case "$_choice" in
          1) _dual_api_key_set "$_provider" ;;
          2) _dual_api_key_remove "$_provider" ;;
        esac ;;
    esac
  done
}

# _keypool_add <provider> <var> <label> <file>
_keypool_add() {
  _provider=$1; _var=$2; _label=$3; _file=$4
  _existing=$(_read_kv "$_file" "$_var")
  _suggest=$(_next_key_name "$_provider" "$([ "$_var" = "AUTH_KEYS" ] && echo main || echo plus)")
  _name=$(_input "Keychain 名称" "$_suggest")
  [ -z "$_name" ] && return
  for _k in $_existing; do [ "$_k" = "$_name" ] && { printf '已存在\n' >/dev/tty; return; }; done
  _secret=$(_prompt_secret "粘贴密钥: ")
  [ -z "$_secret" ] && return
  _keychain_put "$_name" "$_secret"
  [ -z "$_existing" ] && _new="$_name" || _new="$_existing $_name"
  _write_kv "$_file" "$_var" "$_new"
  printf '✓ %s → %s\n' "$_name" "$_label" >/dev/tty
}

# _keypool_remove <provider> <file> - removes from correct surface (AUTH_KEYS or PLUS_KEYS)
_keypool_remove() {
  _provider=$1; _file=$2
  _main=$(_read_kv "$_file" "AUTH_KEYS")
  _plus=$(_read_kv "$_file" "PLUS_KEYS")
  _keys=""; _i=1
  for _k in $_main; do _keys="$_keys $_k (主)"; _i=$((_i+1)); done
  for _k in $_plus; do _keys="$_keys $_k (Plus)"; _i=$((_i+1)); done
  [ -z "$_keys" ] && { printf '无密钥\n' >/dev/tty; return; }
  _choice=$(_menu "删除哪个" $_keys)
  [ -z "$_choice" ] && return
  _idx=1; _target=""; _target_var=""
  for _k in $_main; do
    [ "$_idx" -eq "$_choice" ] && { _target="$_k"; _target_var="AUTH_KEYS"; }
    _idx=$((_idx+1))
  done
  for _k in $_plus; do
    [ "$_idx" -eq "$_choice" ] && { _target="$_k"; _target_var="PLUS_KEYS"; }
    _idx=$((_idx+1))
  done
  [ -z "$_target" ] && return
  _confirm "删除 $_target?" || return
  _keychain_delete "$_target"
  _new=""
  if [ "$_target_var" = "AUTH_KEYS" ]; then
    for _k in $_main; do [ "$_k" != "$_target" ] && _new="$_new $_k"; done
    for _k in $_plus; do _new="$_new $_k"; done
  else
    for _k in $_main; do _new="$_new $_k"; done
    for _k in $_plus; do [ "$_k" != "$_target" ] && _new="$_new $_k"; done
  fi
  _write_kv "$_file" "$_target_var" "$_new"
  printf '✓ 删除 %s\n' "$_target" >/dev/tty
}

# _single_key_set <provider> <file>
_single_key_set() {
  _provider=$1; _file=$2
  _svc=$(_single_key_service)
  [ -z "$_svc" ] && return
  _secret=$(_prompt_secret "粘贴密钥: ")
  [ -z "$_secret" ] && return
  _keychain_put "$_svc" "$_secret"
  printf '✓ 存储到 keychain:%s\n' "$_svc" >/dev/tty
}

# _single_key_remove <provider>
_single_key_remove() {
  _provider=$1
  _svc=$(_single_key_service)
  [ -z "$_svc" ] && return
  _keychain_exists "$_svc" || { printf '不存在\n' >/dev/tty; return; }
  _confirm "删除 keychain:%s?" "$_svc" || return
  _keychain_delete "$_svc"
  printf '✓ 删除\n' >/dev/tty
}

# _dual_api_key_set <provider>
_dual_api_key_set() {
  _provider=$1
  [ -z "${API_KEY_REF:-}" ] && return
  _secret=$(_prompt_secret "粘贴备用 Key: ")
  [ -z "$_secret" ] && return
  _keychain_put "$API_KEY_REF" "$_secret"
  printf '✓ keychain:%s\n' "$API_KEY_REF" >/dev/tty
}

# _dual_api_key_remove <provider>
_dual_api_key_remove() {
  _provider=$1
  [ -z "${API_KEY_REF:-}" ] && return
  _keychain_exists "$API_KEY_REF" || return
  _confirm "删除 keychain:%s?" "$API_KEY_REF" || return
  _keychain_delete "$API_KEY_REF"
  printf '✓ 删除\n' >/dev/tty
}

# _keychain_put <service> <value>
_keychain_put() { security add-generic-password -U -a "$USER" -s "$1" -w "$2"; }

# _keychain_delete <service>
_keychain_delete() { security delete-generic-password -a "$USER" -s "$1" >/dev/null 2>&1 || true; }

# _keychain_exists <service> -> 0 if exists
_keychain_exists() { security find-generic-password -a "$USER" -s "$1" >/dev/null 2>&1; }

# _next_key_name <provider> <surface> -> suggest "<provider>-2", "<provider>-3", ...
_next_key_name() {
  _base=$1; _n=2
  while _keychain_exists "${_base}-${_n}"; do _n=$((_n + 1)); done
  printf '%s-%d' "$_base" "$_n"
}

# ---------- 外部命令入口 ----------

# cmd_key -> 交互式密钥管理主入口
cmd_key() {
  _list=$(_list_providers_with_keys)
  [ -z "$_list" ] && return
  while true; do
    printf '\n密钥管理\n' >/dev/tty
    _i=1
    for _line in $_list; do
      _p=${_line%%|*}; _st=${_line##*|}
      printf '  %d. %s [%s]\n' "$_i" "$_p" "$_st" >/dev/tty
      _i=$((_i + 1))
    done
    printf '  0. 退出\n> ' >/dev/tty
    IFS= read -r _choice </dev/tty || _choice=0
    case "$_choice" in
      ''|*[!0-9]*) ;;
      0) break ;;
      *) [ "$_choice" -ge 1 ] && [ "$_choice" -le $((_i - 1)) ] || continue
         _idx=1; _provider=""
         for _line in $_list; do [ "$_idx" -eq "$_choice" ] && _provider=${_line%%|*}; _idx=$((_idx+1)); done
         _provider_key_menu "$_provider"
         ;;
    esac
  done
}

# cmd_list_keys <provider> -> 兼容旧命令，显示单个 provider 密钥状态
cmd_list_keys() {
  if [ -z "${1:-}" ]; then
    for _p in $(provider_names); do
      cmd_list_keys_one "$_p"
      echo
    done
    return
  fi
  cmd_list_keys_one "$1"
}

# cmd_list_keys_one <provider> -> 显示单个 provider 密钥详情（保留给脚本用）
cmd_list_keys_one() {
  _p=$1
  load_provider "$_p"
  _file=$(provider_file "$_p")
  _ds=''; is_dual_source && _ds=' (dual-source)'
  printf 'provider: %s   auth_mode: %s%s\n' "$_p" "${AUTH_MODE:-}" "$_ds"

  if is_dual_source; then
    [ -n "${DEFAULT_TOKEN_ENV:-}" ] && {
      _dt=$(printenv "$DEFAULT_TOKEN_ENV" 2>/dev/null || true)
      [ -z "$_dt" ] && [ -n "${DEFAULT_TOKEN_ENV_FALLBACK:-}" ] && _dt=$(printenv "$DEFAULT_TOKEN_ENV_FALLBACK" 2>/dev/null || true)
      [ -n "$_dt" ] && printf '  - default account: env:%s set\n' "$DEFAULT_TOKEN_ENV" || printf '  - default account: env:%s unset\n' "$DEFAULT_TOKEN_ENV"
    }
    [ -n "${API_KEY_ENV:-}" ] && {
      _ak=$(printenv "$API_KEY_ENV" 2>/dev/null || true)
      [ -n "$_ak" ] && printf '  - api key: env:%s set\n' "$API_KEY_ENV" || printf '  - api key: env:%s unset\n' "$API_KEY_ENV"
    }
    [ -n "${API_KEY_REF:-}" ] && {
      _keychain_exists "$API_KEY_REF" && printf '  - api key: keychain:%s in Keychain\n' "$API_KEY_REF" || printf '  - api key: keychain:%s MISSING\n' "$API_KEY_REF"
    }
    return
  fi

  case "${AUTH_MODE:-}" in
    keypool)
      for _s in main plus; do
        _var=$(_surface_var "$_s")
        _existing=$(_read_kv "$_file" "$_var")
        [ -z "$_existing" ] && continue
        printf '%-8s surface (%s):\n' "$_s" "$_var"
        for _k in $_existing; do
          _keychain_exists "$_k" && _st='in Keychain' || _st='MISSING from Keychain'
          printf '  - %-40s %s\n' "$_k" "$_st"
        done
      done ;;
    keychain)
      _ref=${AUTH_REFERENCE:-}
      _keychain_exists "$_ref" && printf '  - %-40s in Keychain\n' "$_ref" || printf '  - %-40s MISSING\n' "${_ref:-<AUTH_REFERENCE unset>}" ;;
    env)
      _v=$(printenv "${AUTH_REFERENCE:-}" 2>/dev/null || true)
      [ -n "$_v" ] && printf '  - env:%s set\n' "${AUTH_REFERENCE:-}" || printf '  - env:%s unset\n' "${AUTH_REFERENCE:-}"
      _svc=${AUTH_KEYCHAIN_FALLBACK:-}
      [ -n "$_svc" ] && { _keychain_exists "$_svc" && printf '  - keychain:%s in Keychain\n' "$_svc" || printf '  - keychain:%s MISSING\n' "$_svc"; } ;;
    static) printf '  - static placeholder: %s\n' "${AUTH_REFERENCE:-<none>}" ;;
    none) printf '  - (no key — local proxy supplies auth)\n' ;;
    *) printf '  - (unsupported AUTH_MODE: %s)\n' "${AUTH_MODE:-}" ;;
  esac
}

# cmd_add_key <provider> [--surface main|plus] [--name <service>] -> 兼容旧命令
cmd_add_key() {
  _p=$1; shift
  load_provider "$_p"

  if [ "${AUTH_MODE:-}" = "keypool" ]; then
    _surface=main; _name=
    while [ $# -gt 0 ]; do
      case $1 in
        --surface) _surface=$2; shift 2 ;;
        --surface=*) _surface=${1#--surface=}; shift ;;
        --name) _name=$2; shift 2 ;;
        --name=*) _name=${1#--name=}; shift ;;
        *) die "add: unknown arg '$1'" ;;
      esac
    done
    _var=$(_surface_var "$_surface")
    _file=$(provider_file "$_p")
    [ -z "$_name" ] && _name=$(_next_key_name "$_p" "$_surface")
    _existing=$(_read_kv "$_file" "$_var")
    for _k in $_existing; do [ "$_k" = "$_name" ] && die "service '$_name' already in $_var"; done
    _secret=$(_prompt_secret "Paste key for $_name: ")
    [ -n "$_secret" ] || die "empty key"
    _keychain_put "$_name" "$_secret"
    [ -z "$_existing" ] && _new="$_name" || _new="$_existing $_name"
    _write_kv "$_file" "$_var" "$_new"
    info "added '$_name' to $_surface surface of '$_p'"
    return
  fi

  # Single-key / dual-source
  _svc=$(_single_key_service)
  if [ -z "$_svc" ]; then
    case "${AUTH_MODE:-}" in
      static) die "provider '$_p' uses static auth — credentials are supplied by the local proxy, so there is no API key to add" ;;
      none)   die "provider '$_p' uses none auth — no API key needed (local proxy supplies auth)" ;;
      *)      die "no Keychain target for this provider" ;;
    esac
  fi
  _secret=$(_prompt_secret "Paste key for $_svc ($_p): ")
  [ -n "$_secret" ] || die "empty key"
  _keychain_put "$_svc" "$_secret"
  info "stored key for '$_p' in Keychain service '$_svc'"
}

# cmd_remove_key <provider> --name <service> [--surface main|plus] [-y] -> 兼容旧命令
cmd_remove_key() {
  _p=$1; shift
  load_provider "$_p"

  if [ "${AUTH_MODE:-}" = "keypool" ]; then
    _surface=main; _name=; _yes=0
    while [ $# -gt 0 ]; do
      case $1 in
        --surface) _surface=$2; shift 2 ;;
        --surface=*) _surface=${1#--surface=}; shift ;;
        --name) _name=$2; shift 2 ;;
        --name=*) _name=${1#--name=}; shift ;;
        -y|--yes) _yes=1; shift ;;
        *) die "remove: unknown arg '$1'" ;;
      esac
    done
    [ -n "$_name" ] || die "--name is required"
    _var=$(_surface_var "$_surface")
    _file=$(provider_file "$_p")
    _existing=$(_read_kv "$_file" "$_var")
    _found=0; _new=
    for _k in $_existing; do [ "$_k" = "$_name" ] && _found=1 || _new="$_new $_k"; done
    [ "$_found" -eq 1 ] || die "service '$_name' is not in $_var"
    [ "$_yes" -eq 1 ] || _confirm "remove $_name from $_surface surface of $_p?" || return 0
    _write_kv "$_file" "$_var" "$_new"
    _keychain_delete "$_name"
    info "removed '$_name' from $_surface surface of '$_p'"
    return
  fi

  _svc=$(_single_key_service)
  if [ -z "$_svc" ]; then
    case "${AUTH_MODE:-}" in
      static) die "provider '$_p' has no single-key to remove (mode=static, credentials in local proxy)" ;;
      none)   die "provider '$_p' has no single-key to remove (mode=none, no API key needed)" ;;
      *)      die "no single-key to remove" ;;
    esac
  fi
  [ "$_yes" -eq 1 ] || _confirm "delete Keychain item $_svc for $_p?" || return 0
  _keychain_delete "$_svc"
  info "removed Keychain item '$_svc' for '$_p'"
}