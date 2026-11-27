#!/bin/sh
# Install crouter as a global command via a symlink.
set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERSION=$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo "unknown")
INSTALL_DIR=${INSTALL_DIR:-$HOME/.local/bin}

mkdir -p "$INSTALL_DIR"

# The only command installed is `crouter` itself. Providers are launched with
# `crouter <provider>`; there are no per-provider compatibility shortcuts.
# Refuse command-name collisions before changing anything. Re-running crouter
# may replace links from another/moved crouter checkout, but never a regular
# file or an unrelated symlink.
_crouter_owned_link() {
  [ -L "$1" ] || return 1
  case $(readlink "$1" 2>/dev/null) in
    */bin/crouter) return 0 ;;
    *) return 1 ;;
  esac
}
destination="$INSTALL_DIR/crouter"
if { [ -e "$destination" ] || [ -L "$destination" ]; } && ! _crouter_owned_link "$destination"; then
  printf 'crouter: install refused; this path is not crouter-owned:\n%s\n' "$destination" >&2
  exit 1
fi

chmod +x "$ROOT_DIR/bin/crouter"
ln -sf "$ROOT_DIR/bin/crouter" "$INSTALL_DIR/crouter"

if [ ! -f "$ROOT_DIR/config.sh" ]; then
  cp "$ROOT_DIR/config.example.sh" "$ROOT_DIR/config.sh"
  echo "Created config.sh from config.example.sh (edit as needed; it is gitignored)."
fi

echo "Installed: $INSTALL_DIR/crouter -> $ROOT_DIR/bin/crouter"
echo "crouter $VERSION"

case :$PATH: in
  *:"$INSTALL_DIR":*) ;;
  *) echo "NOTE: $INSTALL_DIR is not on your PATH." ;;
esac

echo "Try: crouter list"
echo "Optional: enable shell autocompletion - see README (completions/)."
