# Zsh completion for crouter.
# Source it from your .zshrc, or drop it into a directory on your $fpath
# (named `_crouter` there).

_crouter_providers() {
  local dir="${CROUTER_PROVIDERS_DIR:-$(cd "$(dirname "${(%):-%x}")/../providers" && pwd)}"
  [[ -d "$dir" ]] || return
  local f
  for f in "$dir"/*.sh; do
    [[ -f "$f" ]] || continue
    case "$(basename "$f")" in
      lib*) continue ;;
    esac
    basename "$f" .sh
  done
}

_crouter_complete() {
  local -a cmds providers native_apps candidates
  local app
  cmds=(run use claude app all list doctor add remove provider config logs uninstall help --version)
  providers=(${(f)"$(_crouter_providers)"})
  native_apps=(claude codex gemini opencode copilot cursor kiro qoder kimi qwen amp vibe muse kilo)
  if (( CURRENT == 2 )); then
    # Position 1 is either a subcommand or a provider name (`crouter deepseek`).
    compadd -- $cmds $providers
    return
  fi
  candidates=()
  case "$words[2]" in
    app)
      (( CURRENT != 3 )) || candidates=(list $native_apps) ;;
    use)
      if (( CURRENT == 3 )); then
        candidates=(--clear $providers)
        for app in $native_apps; do candidates+=("app/$app"); done
      fi ;;
    doctor)
      (( CURRENT != 3 )) || candidates=($providers) ;;
    remove)
      if (( CURRENT == 3 )); then
        candidates=($providers)
      elif [[ "${words[CURRENT-1]}" == --surface ]]; then
        candidates=(plan api)
      else
        candidates=(--surface --name -y --yes)
      fi ;;
    add)
      if (( CURRENT == 3 )); then
        candidates=(--all -a $providers)
      elif [[ "${words[CURRENT-1]}" == --surface ]]; then
        candidates=(plan api)
      else
        candidates=(--all --surface --name --stdin)
      fi ;;
    provider)
      if (( CURRENT == 3 )); then
        candidates=(show $providers)
      elif (( CURRENT == 4 )) && [[ "$words[3]" == show ]]; then
        candidates=($providers)
      fi ;;
    config)
      (( CURRENT != 3 )) || candidates=(show path) ;;
    logs)
      if (( CURRENT == 3 )); then
        candidates=(list tail)
      elif (( CURRENT == 4 )) && [[ "$words[3]" == tail ]]; then
        candidates=($providers)
      fi ;;
    list)
      if (( CURRENT == 3 )); then
        candidates=(--all -a keys $providers)
      elif (( CURRENT == 4 )) && [[ "$words[3]" == keys ]]; then
        candidates=($providers)
      fi ;;
    all)
      (( CURRENT != 3 )) || candidates=(--check) ;;
    uninstall)
      (( CURRENT != 3 )) || candidates=(-y --yes) ;;
  esac
  if (( ${#candidates} )); then compadd -- $candidates; fi
  return 0
}
compdef _crouter_complete crouter
