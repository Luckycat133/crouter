#!/bin/sh
# Uninstall may remove only shortcuts owned by this crouter checkout.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-uninstall-owner)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

printf 'user command\n' > "$TMP_DIR/crouter"
ln -s /usr/bin/true "$TMP_DIR/claude-minimax"
ln -s "$ROOT_DIR/bin/crouter-compat" "$TMP_DIR/claude-deepseek"
ln -s "$ROOT_DIR/bin/crouter-compat" "$TMP_DIR/claude-retired-compat"
ln -s "$ROOT_DIR/bin/crouter" "$TMP_DIR/claude-retired-main"
ln -s "$TMP_DIR/other/bin/crouter-compat" "$TMP_DIR/claude-other-checkout"
printf 'user shortcut\n' > "$TMP_DIR/claude-user"

INSTALL_DIR="$TMP_DIR" CLAUDE_BIN=/usr/bin/true \
  "$ROOT_DIR/bin/crouter" uninstall -y >/dev/null

[ -f "$TMP_DIR/crouter" ] || {
  printf 'FAIL  uninstall removed a user-owned regular file\n' >&2
  exit 1
}
[ "$(readlink "$TMP_DIR/claude-minimax")" = /usr/bin/true ] || {
  printf 'FAIL  uninstall removed an unrelated symlink\n' >&2
  exit 1
}
[ ! -e "$TMP_DIR/claude-deepseek" ] && [ ! -L "$TMP_DIR/claude-deepseek" ] || {
  printf 'FAIL  uninstall left a crouter-owned shortcut\n' >&2
  exit 1
}
for stale in retired-compat retired-main; do
  [ ! -e "$TMP_DIR/claude-$stale" ] && [ ! -L "$TMP_DIR/claude-$stale" ] || {
    printf 'FAIL  uninstall left an owned retired shortcut: %s\n' "$stale" >&2
    exit 1
  }
done
[ -L "$TMP_DIR/claude-other-checkout" ] &&
grep -q '^user shortcut$' "$TMP_DIR/claude-user" || {
  printf 'FAIL  uninstall changed an external shortcut or user file\n' >&2
  exit 1
}

rm -f "$TMP_DIR/crouter"
ln -s "$ROOT_DIR/bin/crouter" "$TMP_DIR/crouter"
INSTALL_DIR="$TMP_DIR" CLAUDE_BIN=/usr/bin/true \
  "$TMP_DIR/crouter" uninstall -y >/dev/null
[ ! -e "$TMP_DIR/crouter" ] && [ ! -L "$TMP_DIR/crouter" ] || {
  printf 'FAIL  uninstall left this checkout crouter link\n' >&2
  exit 1
}

printf 'ok    uninstall preserves non-crouter files and links\n'
