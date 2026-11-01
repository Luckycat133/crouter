#!/bin/sh
# Install must preflight command-name collisions before creating any symlink.
# Providers are launched with `crouter <provider>` or `crouter claude
# <provider>`; there are no per-provider `claude-<provider>` compatibility
# shortcuts anymore.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-install-owner)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

FAKE_ROOT="$TMP_DIR/repo"
INSTALL_DIR="$TMP_DIR/bin"
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/providers" "$INSTALL_DIR"
cp "$ROOT_DIR/install.sh" "$ROOT_DIR/config.example.sh" "$ROOT_DIR/VERSION" "$FAKE_ROOT/"
cp "$ROOT_DIR/bin/crouter" "$FAKE_ROOT/bin/"
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

printf 'ok    installer preflights and preserves command-name collisions\n'

rm -f "$INSTALL_DIR/crouter"
if ! INSTALL_DIR="$INSTALL_DIR" PATH="$PATH" sh "$FAKE_ROOT/install.sh" >"$TMP_DIR/install.out" 2>&1; then
  printf 'FAIL  initial isolated install failed\n' >&2
  cat "$TMP_DIR/install.out" >&2
  exit 1
fi
[ "$(readlink "$INSTALL_DIR/crouter")" = "$FAKE_ROOT/bin/crouter" ] || {
  printf 'FAIL  initial install omitted crouter\n' >&2
  exit 1
}

# Reinstall is idempotent: it refreshes crouter owned by this checkout and
# leaves everything else alone.
ln -s "$TMP_DIR/other/bin/crouter" "$INSTALL_DIR/crouter-other-checkout"
ln -s /usr/bin/true "$INSTALL_DIR/crouter-external"
printf 'user shortcut\n' > "$INSTALL_DIR/crouter-user"

if ! INSTALL_DIR="$INSTALL_DIR" PATH="$PATH" sh "$FAKE_ROOT/install.sh" >"$TMP_DIR/reinstall.out" 2>&1; then
  printf 'FAIL  isolated reinstall failed\n' >&2
  cat "$TMP_DIR/reinstall.out" >&2
  exit 1
fi
[ "$(readlink "$INSTALL_DIR/crouter")" = "$FAKE_ROOT/bin/crouter" ] || {
  printf 'FAIL  reinstall did not refresh crouter\n' >&2
  exit 1
}
[ -L "$INSTALL_DIR/crouter-other-checkout" ] &&
[ "$(readlink "$INSTALL_DIR/crouter-external")" = /usr/bin/true ] &&
grep -q '^user shortcut$' "$INSTALL_DIR/crouter-user" || {
  printf 'FAIL  reinstall changed a shortcut outside this checkout\n' >&2
  exit 1
}
printf 'ok    reinstall prunes only retired shortcuts owned by this checkout\n'
