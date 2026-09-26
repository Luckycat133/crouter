#!/bin/sh
# Official coding-agent CLIs. This path never loads a crouter provider, resolves
# its credential, or inserts a model/endpoint; each CLI owns its authentication.

native_app_names() {
  printf '%s\n' claude codex gemini opencode copilot cursor kiro qoder kimi qwen amp vibe muse kilo
}

native_app_binary() {
  case $1 in
    claude|codex|gemini|opencode|copilot|qoder|kimi|qwen|amp|vibe|muse|kilo) printf '%s\n' "$1" ;;
    cursor) printf '%s\n' agent ;;
    kiro) printf '%s\n' kiro-cli ;;
    *) return 2 ;;
  esac
}

native_app_resolve() {
  _crouter_native_command=$(native_app_binary "$1") || return 2
  if [ "$1" = claude ] && [ -n "${CLAUDE_BIN:-}" ]; then
    _crouter_native_path=$CLAUDE_BIN
  else
    _crouter_native_path=$(command -v "$_crouter_native_command" 2>/dev/null) || _crouter_native_path=
    if { [ -z "$_crouter_native_path" ] || [ ! -f "$_crouter_native_path" ] || [ ! -x "$_crouter_native_path" ]; } &&
       [ "$1" = cursor ]; then
      _crouter_native_path=$(command -v cursor-agent 2>/dev/null) || _crouter_native_path=
    fi
  fi
  [ -f "$_crouter_native_path" ] && [ -x "$_crouter_native_path" ] || return 127
  printf '%s\n' "$_crouter_native_path"
}

native_app_list() {
  printf '%-10s %-13s %s\n' 'APP' 'COMMAND' 'STATUS'
  for _crouter_native_name in $(native_app_names); do
    _crouter_native_command=$(native_app_binary "$_crouter_native_name")
    if _crouter_native_path=$(native_app_resolve "$_crouter_native_name"); then
      _crouter_native_status=available
      if [ "$_crouter_native_name" = cursor ] &&
         [ "${_crouter_native_path##*/}" = cursor-agent ]; then
        _crouter_native_command=cursor-agent
      fi
    else
      _crouter_native_status=missing
    fi
    printf '%-10s %-13s %s\n' "$_crouter_native_name" "$_crouter_native_command" "$_crouter_native_status"
  done
}

native_app_run() {
  [ "$#" -ge 1 ] || {
    printf 'crouter: usage: crouter app <name> [args...]\n' >&2
    return 2
  }
  _crouter_native_name=$1
  shift
  _crouter_native_command=$(native_app_binary "$_crouter_native_name") || {
    printf 'crouter: unknown native app: %s\n' "$_crouter_native_name" >&2
    return 2
  }
  _crouter_native_path=$(native_app_resolve "$_crouter_native_name") || {
    printf 'crouter: %s is not installed or executable\n' "$_crouter_native_command" >&2
    return 127
  }
  exec "$_crouter_native_path" "$@"
}

native_app_dispatch() {
  case ${1:-} in
    list)
      [ "$#" -eq 1 ] || {
        printf 'crouter: usage: crouter app list\n' >&2
        return 2
      }
      native_app_list ;;
    '')
      printf 'crouter: usage: crouter app <name> [args...] (or crouter app list)\n' >&2
      return 2 ;;
    *) native_app_run "$@" ;;
  esac
}
