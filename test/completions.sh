#!/bin/sh
# Completion should follow command depth and inspect provider filenames only.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-completions)
trap 'rm -rf "$TEST_DIR"' EXIT INT TERM
FAKE_ROOT="$TEST_DIR/repo"
FAKE_PROVIDERS="$FAKE_ROOT/providers"
MARKER_FILE="$TEST_DIR/provider-sourced"
CONFIG_MARKER_FILE="$TEST_DIR/config-sourced"
RESULT_FILE="$TEST_DIR/completions"
mkdir -p "$FAKE_PROVIDERS" "$FAKE_ROOT/completions"
cp "$ROOT_DIR/completions/crouter.bash" "$ROOT_DIR/completions/crouter.zsh" "$FAKE_ROOT/completions/"
printf 'touch "%s"\n' "$MARKER_FILE" > "$FAKE_PROVIDERS/demo.sh"
printf 'touch "%s"\n' "$CONFIG_MARKER_FILE" > "$FAKE_ROOT/config.sh"

if command -v bash >/dev/null 2>&1; then
  CROUTER_PROVIDERS_DIR="$FAKE_PROVIDERS" MARKER_FILE="$MARKER_FILE" \
    COMPLETION_FILE="$FAKE_ROOT/completions/crouter.bash" bash -c '
    set -e
    source "$COMPLETION_FILE"
    complete_at() {
      COMP_WORDS=("$@")
      COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
      _crouter_complete
    }
    contains() { printf "%s\n" "${COMPREPLY[@]}" | grep -qx -- "$1"; }
    excludes() { ! printf "%s\n" "${COMPREPLY[@]}" | grep -qx -- "$1"; }
    complete_at crouter config ""
    contains show && contains path && excludes demo
    complete_at crouter logs ""
    contains list && contains tail && excludes demo
    complete_at crouter provider ""
    contains show && contains demo
    complete_at crouter provider show ""
    contains demo && excludes show
    complete_at crouter logs tail ""
    contains demo && excludes list
    complete_at crouter list keys ""
    contains demo
    complete_at crouter list ""
    contains keys && contains --all && contains demo
    complete_at crouter add ""
    contains --all && contains demo
    complete_at crouter add demo ""
    contains --all && contains --surface
    complete_at crouter add demo --surface ""
    contains plan && contains api && excludes demo
    complete_at crouter remove demo --surface ""
    contains plan && contains api && excludes demo
    complete_at crouter app ""
    contains muse && contains kilo
    complete_at crouter use ""
    contains app/muse && contains app/kilo
  ' || {
    printf 'FAIL  Bash completion returned incorrect command-depth candidates\n' >&2
    exit 1
  }
  printf 'ok    Bash completion follows subcommand depth\n'
fi

if command -v zsh >/dev/null 2>&1; then
  CROUTER_PROVIDERS_DIR="$FAKE_PROVIDERS" MARKER_FILE="$MARKER_FILE" \
    RESULT_FILE="$RESULT_FILE" COMPLETION_FILE="$FAKE_ROOT/completions/crouter.zsh" zsh -fc '
    set -e
    compdef() { :; }
    compadd() {
      [[ "$1" == -- ]] && shift
      print -rl -- "$@" > "$RESULT_FILE"
    }
    source "$COMPLETION_FILE"
    complete_at() {
      words=("$@")
      CURRENT=${#words}
      : > "$RESULT_FILE"
      _crouter_complete
    }
    contains() { grep -qx -- "$1" "$RESULT_FILE"; }
    excludes() { ! grep -qx -- "$1" "$RESULT_FILE"; }
    complete_at crouter config ""
    contains show && contains path && excludes demo
    complete_at crouter logs ""
    contains list && contains tail && excludes demo
    complete_at crouter provider ""
    contains show && contains demo
    complete_at crouter provider show ""
    contains demo && excludes show
    complete_at crouter logs tail ""
    contains demo && excludes list
    complete_at crouter list keys ""
    contains demo
    complete_at crouter list ""
    contains keys && contains --all && contains demo
    complete_at crouter add ""
    contains --all && contains demo
    complete_at crouter add demo ""
    contains --all && contains --surface
    complete_at crouter add demo --surface ""
    contains plan && contains api && excludes demo
    complete_at crouter remove demo --surface ""
    contains plan && contains api && excludes demo
    complete_at crouter app ""
    contains muse && contains kilo
    complete_at crouter use ""
    contains app/muse && contains app/kilo
  ' || {
    printf 'FAIL  Zsh completion returned incorrect command-depth candidates\n' >&2
    exit 1
  }
  printf 'ok    Zsh completion follows subcommand depth\n'
fi

[ ! -e "$MARKER_FILE" ] && [ ! -e "$CONFIG_MARKER_FILE" ] || {
  printf 'FAIL  completion executed provider or local config source\n' >&2
  exit 1
}
printf 'ok    completion does not source provider declarations or config\n'
