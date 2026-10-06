#!/bin/bash
# Bash completion for crouter.
# Source it from your shell rc, e.g.:
#   source /path/to/crouters/completions/crouter.bash
# or symlink it into your bash-completion directory.

_crouter_providers() {
  # List provider names from the providers/ dir (exclude lib/).
  local dir="${CROUTER_PROVIDERS_DIR:-}"
  if [ -z "$dir" ] && [ -n "${BASH_SOURCE:-}" ]; then
    dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/../providers" && pwd)
  fi
  [ -d "$dir" ] || return 0
  local f
  for f in "$dir"/*.sh; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in
      lib*) continue ;;
    esac
    basename "$f" .sh
  done
}

_crouter_complete() {
  local cur cmds providers native_apps candidates app
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]:-}"
  cmds="run use claude app all list doctor add remove provider config logs uninstall help --version"
  providers="$(_crouter_providers)"
  native_apps="claude codex gemini opencode copilot cursor kiro qoder kimi qwen amp vibe muse kilo"
  candidates=""

  if [ "$COMP_CWORD" -eq 1 ]; then
    # Position 1 is either a subcommand or a provider name (`crouter deepseek`).
    candidates="$cmds $providers"
  else
    case "${COMP_WORDS[1]}" in
      app)
        [ "$COMP_CWORD" -ne 2 ] || candidates="list $native_apps" ;;
      use)
        if [ "$COMP_CWORD" -eq 2 ]; then
          candidates="--clear $providers"
          for app in $native_apps; do candidates="$candidates app/$app"; done
        fi ;;
      doctor)
        [ "$COMP_CWORD" -ne 2 ] || candidates="$providers" ;;
      remove)
        if [ "$COMP_CWORD" -eq 2 ]; then
          candidates="$providers"
        elif [ "${COMP_WORDS[COMP_CWORD-1]:-}" = --surface ]; then
          candidates="plan api"
        else
          candidates="--surface --name -y --yes"
        fi ;;
      add)
        if [ "$COMP_CWORD" -eq 2 ]; then
          candidates="--all -a $providers"
        elif [ "${COMP_WORDS[COMP_CWORD-1]:-}" = --surface ]; then
          candidates="plan api"
        else
          candidates="--all --surface --name --stdin"
        fi ;;
      provider)
        if [ "$COMP_CWORD" -eq 2 ]; then
          candidates="show $providers"
        elif [ "$COMP_CWORD" -eq 3 ] && [ "${COMP_WORDS[2]:-}" = show ]; then
          candidates="$providers"
        fi ;;
      config)
        [ "$COMP_CWORD" -ne 2 ] || candidates="show path" ;;
      logs)
        if [ "$COMP_CWORD" -eq 2 ]; then
          candidates="list tail"
        elif [ "$COMP_CWORD" -eq 3 ] && [ "${COMP_WORDS[2]:-}" = tail ]; then
          candidates="$providers"
        fi ;;
      list)
        if [ "$COMP_CWORD" -eq 2 ]; then
          candidates="--all -a keys $providers"
        elif [ "$COMP_CWORD" -eq 3 ] && [ "${COMP_WORDS[2]:-}" = keys ]; then
          candidates="$providers"
        fi ;;
      all)
        [ "$COMP_CWORD" -ne 2 ] || candidates="--check" ;;
      uninstall)
        [ "$COMP_CWORD" -ne 2 ] || candidates="-y --yes" ;;
    esac
  fi
  [ -n "$candidates" ] || return 0
  # Arrays from compgen keep Bash 3 compatibility on macOS.
  # shellcheck disable=SC2207
  COMPREPLY=( $(compgen -W "$candidates" -- "$cur") )
}
complete -F _crouter_complete crouter
