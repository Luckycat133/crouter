#!/bin/sh
# Install must preflight command-name collisions before creating any symlink.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-install-owner)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

FAKE_ROOT="$TMP_DIR/repo"
INSTALL_DIR="$TMP_DIR/bin"
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/providers" "$INSTALL_DIR"
cp "$ROOT_DIR/install.sh" "$ROOT_DIR/config.example.sh" "$ROOT_DIR/VERSION" "$FAKE_ROOT/"
cp "$ROOT_DIR/bin/crouter" "$ROOT_DIR/bin/crouter-compat" \
  "$ROOT_DIR/bin/antigravity-proxy-patch" "$FAKE_ROOT/bin/"
printf 'PROVIDER_NAME="demo"\nBASE_URL="https://example.invalid"\nMODEL="demo"\n' \
  > "$FAKE_ROOT/providers/demo.sh"
printf 'user command\n' > "$INSTALL_DIR/crouter"

if INSTALL_DIR="$INSTALL_DIR" PATH="$PATH" sh "$FAKE_ROOT/install.sh" >/dev/null 2>&1; then
  printf 'FAIL  installer accepted a user-owned command collision\n' >&2
  exit 1
fi
grep -q '^user command$' "$INSTALL_DIR/crouter" || {
  printf 'FAIL  installer overwrote the user-owned command\n' >&2
  exit 1
}
[ ! -e "$INSTALL_DIR/claude-demo" ] && [ ! -L "$INSTALL_DIR/claude-demo" ] || {
  printf 'FAIL  installer made partial changes before collision failure\n' >&2
  exit 1
}

printf 'ok    installer preflights and preserves command-name collisions\n'

rm -f "$INSTALL_DIR/crouter"
if ! INSTALL_DIR="$INSTALL_DIR" PATH="$PATH" sh "$FAKE_ROOT/install.sh" >"$TMP_DIR/install.out" 2>&1; then
  printf 'FAIL  initial isolated install failed\n' >&2
  cat "$TMP_DIR/install.out" >&2
  exit 1
fi
[ "$(readlink "$INSTALL_DIR/claude-demo")" = "$FAKE_ROOT/bin/crouter-compat" ] || {
  printf 'FAIL  initial install omitted its provider shortcut\n' >&2
  exit 1
}

# Simulate removal of a provider, plus old shortcuts that target either owned
# launcher. Links to other checkouts and unrelated files must survive.
ln -s "$FAKE_ROOT/bin/crouter-compat" "$INSTALL_DIR/claude-retired-compat"
ln -s "$FAKE_ROOT/bin/crouter" "$INSTALL_DIR/claude-retired-main"
ln -s "$TMP_DIR/other/bin/crouter-compat" "$INSTALL_DIR/claude-other-checkout"
ln -s /usr/bin/true "$INSTALL_DIR/claude-external"
printf 'user shortcut\n' > "$INSTALL_DIR/claude-user"
rm -f "$FAKE_ROOT/providers/demo.sh"
printf 'PROVIDER_NAME="new"\nBASE_URL="https://example.invalid"\nMODEL="new"\n' \
  > "$FAKE_ROOT/providers/new.sh"

if ! INSTALL_DIR="$INSTALL_DIR" PATH="$PATH" sh "$FAKE_ROOT/install.sh" >"$TMP_DIR/reinstall.out" 2>&1; then
  printf 'FAIL  isolated reinstall failed\n' >&2
  cat "$TMP_DIR/reinstall.out" >&2
  exit 1
fi
for stale in demo retired-compat retired-main; do
  [ ! -e "$INSTALL_DIR/claude-$stale" ] && [ ! -L "$INSTALL_DIR/claude-$stale" ] || {
    printf 'FAIL  reinstall left owned retired shortcut: %s\n' "$stale" >&2
    exit 1
  }
done
[ "$(readlink "$INSTALL_DIR/claude-new")" = "$FAKE_ROOT/bin/crouter-compat" ] || {
  printf 'FAIL  reinstall omitted the new provider shortcut\n' >&2
  exit 1
}
[ -L "$INSTALL_DIR/claude-other-checkout" ] &&
[ "$(readlink "$INSTALL_DIR/claude-external")" = /usr/bin/true ] &&
grep -q '^user shortcut$' "$INSTALL_DIR/claude-user" || {
  printf 'FAIL  reinstall changed a shortcut outside this checkout\n' >&2
  exit 1
}
printf 'ok    reinstall prunes only retired shortcuts owned by this checkout\n'
