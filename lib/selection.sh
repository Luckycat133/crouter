#!/bin/sh
# Persistent default target for `crouter` and `crouter run`. Sourced before
# config.sh so a selected native app follows the same isolated dispatch as
# `crouter app <name>`. The file is data, never shell code.

selection_state_file() {
  _crouter_selection_base=${XDG_STATE_HOME:-}
  if [ -z "$_crouter_selection_base" ]; then
    [ -n "${HOME:-}" ] || {
      CROUTER_SELECTION_ERROR='HOME or XDG_STATE_HOME is required for target selection'
      return 2
    }
    _crouter_selection_base=$HOME/.local/state
  fi
  case $_crouter_selection_base in
    /*) ;;
    *) CROUTER_SELECTION_ERROR='XDG_STATE_HOME must be an absolute path'; return 2 ;;
  esac
  CROUTER_SELECTION_DIR=$_crouter_selection_base/crouter
  CROUTER_SELECTION_FILE=$CROUTER_SELECTION_DIR/selection
}

selection_validate() {
  CROUTER_SELECTION_TARGET=$1
  CROUTER_SELECTION_KIND=
  CROUTER_SELECTION_NAME=
  CROUTER_SELECTION_ERROR=
  case $1 in
    app/*)
      CROUTER_SELECTION_KIND=app
      CROUTER_SELECTION_NAME=${1#app/} ;;
    *)
      CROUTER_SELECTION_KIND=provider
      CROUTER_SELECTION_NAME=$1 ;;
  esac
  case $CROUTER_SELECTION_NAME in
    ''|[!A-Za-z0-9]*|*[!A-Za-z0-9._-]*)
      CROUTER_SELECTION_ERROR='invalid target; choose a provider from crouter list or an app from crouter app list'
      return 2 ;;
  esac
  if [ "$CROUTER_SELECTION_KIND" = app ]; then
    if ! native_app_binary "$CROUTER_SELECTION_NAME" >/dev/null 2>&1; then
      CROUTER_SELECTION_ERROR="unknown native app '$CROUTER_SELECTION_NAME'; try crouter app list"
      return 2
    fi
    if ! native_app_resolve "$CROUTER_SELECTION_NAME" >/dev/null 2>&1; then
      CROUTER_SELECTION_ERROR="native app '$CROUTER_SELECTION_NAME' is not installed or executable; install it or choose another target with crouter use <provider|app/name>"
      return 2
    fi
  elif [ ! -f "$PROVIDERS_DIR/$CROUTER_SELECTION_NAME.sh" ]; then
    CROUTER_SELECTION_ERROR="unknown provider '$CROUTER_SELECTION_NAME'; try crouter list"
    return 2
  fi
}

selection_read() {
  CROUTER_SELECTION_ERROR=
  selection_state_file || return 2
  if [ ! -e "$CROUTER_SELECTION_FILE" ] && [ ! -L "$CROUTER_SELECTION_FILE" ]; then
    return 1
  fi
  if [ -d "$CROUTER_SELECTION_FILE" ]; then
    CROUTER_SELECTION_ERROR="selection state path is a directory; remove $CROUTER_SELECTION_FILE and retry"
    return 2
  fi
  if [ -L "$CROUTER_SELECTION_FILE" ] || [ ! -f "$CROUTER_SELECTION_FILE" ]; then
    CROUTER_SELECTION_ERROR='selection state is not a regular file; run crouter use --clear'
    return 2
  fi
  if ! IFS= read -r _crouter_selection_value < "$CROUTER_SELECTION_FILE"; then
    CROUTER_SELECTION_ERROR='selection state is malformed; run crouter use --clear'
    return 2
  fi
  # A canonical record has exactly one newline-terminated target. Comparing
  # byte counts also catches hidden data (including NULs ignored by some sh).
  _crouter_selection_expected=$(printf '%s\n' "$_crouter_selection_value" | wc -c)
  _crouter_selection_actual=$(wc -c < "$CROUTER_SELECTION_FILE") || {
    CROUTER_SELECTION_ERROR='selection state could not be read; run crouter use --clear'
    return 2
  }
  if [ "$_crouter_selection_expected" -ne "$_crouter_selection_actual" ]; then
    CROUTER_SELECTION_ERROR='selection state is malformed; run crouter use --clear'
    return 2
  fi
  if ! selection_validate "$_crouter_selection_value"; then
    CROUTER_SELECTION_ERROR="saved $CROUTER_SELECTION_ERROR; run crouter use <target> or crouter use --clear"
    return 2
  fi
}

selection_write() {
  selection_validate "$1" || {
    printf 'crouter: %s\n' "$CROUTER_SELECTION_ERROR" >&2
    return 2
  }
  selection_state_file || {
    printf 'crouter: %s\n' "$CROUTER_SELECTION_ERROR" >&2
    return 2
  }
  (umask 077 && mkdir -p "$CROUTER_SELECTION_DIR") || {
    printf 'crouter: cannot create selection state directory\n' >&2
    return 1
  }
  if [ -d "$CROUTER_SELECTION_FILE" ]; then
    printf 'crouter: selection state path is a directory; remove it and retry\n' >&2
    return 1
  fi
  _crouter_selection_tmp=$(mktemp "$CROUTER_SELECTION_DIR/.selection.XXXXXXXX") || {
    printf 'crouter: cannot create temporary selection state\n' >&2
    return 1
  }
  if ! chmod 600 "$_crouter_selection_tmp" ||
     ! printf '%s\n' "$CROUTER_SELECTION_TARGET" > "$_crouter_selection_tmp" ||
     ! mv -f "$_crouter_selection_tmp" "$CROUTER_SELECTION_FILE"; then
    rm -f "$_crouter_selection_tmp"
    printf 'crouter: cannot save selection state\n' >&2
    return 1
  fi
  printf 'selected: %s\n' "$CROUTER_SELECTION_TARGET"
}

selection_clear() {
  selection_state_file || {
    printf 'crouter: %s\n' "$CROUTER_SELECTION_ERROR" >&2
    return 2
  }
  rm -f "$CROUTER_SELECTION_FILE" || {
    printf 'crouter: cannot clear selection state\n' >&2
    return 1
  }
  printf 'selection cleared\n'
}

selection_show() {
  if selection_read; then
    printf '%s\n' "$CROUTER_SELECTION_TARGET"
  else
    _crouter_selection_status=$?
    if [ "$_crouter_selection_status" -eq 1 ]; then
      printf 'none\n'
    else
      printf 'crouter: %s\n' "$CROUTER_SELECTION_ERROR" >&2
      return "$_crouter_selection_status"
    fi
  fi
}

selection_require() {
  if selection_read; then
    return 0
  else
    _crouter_selection_status=$?
  fi
  if [ "$_crouter_selection_status" -eq 1 ]; then
    printf 'crouter: no target selected; run crouter use <provider> or crouter use app/<name>\n' >&2
  else
    printf 'crouter: %s\n' "$CROUTER_SELECTION_ERROR" >&2
  fi
  return "$_crouter_selection_status"
}

selection_dispatch() {
  case $# in
    0) selection_show ;;
    1)
      case $1 in
        --clear) selection_clear ;;
        -h|--help)
          # Runs before the main usage helpers are defined, so keep this local.
          printf 'usage: crouter use [<provider>|app/<name>|--clear]\n'
          printf '\n'
          printf 'With no argument, prints the current selection (none if nothing is set).\n' ;;
        *) selection_write "$1" ;;
      esac ;;
    *) printf 'crouter: usage: crouter use [<provider>|app/<name>|--clear]\n' >&2; return 2 ;;
  esac
}
