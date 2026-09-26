#!/bin/sh
# Install crouter as a global command via a symlink.
set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
VERSION=$(cat "$ROOT_DIR/VERSION" 2>/dev/null || echo "unknown")
INSTALL_DIR=${INSTALL_DIR:-$HOME/.local/bin}

mkdir -p "$INSTALL_DIR"

# All compatibility shortcuts are symlinks to the single shared launcher, which
# derives the provider from the invoked name (strips the "claude-" prefix).
# The list is derived from providers/ so adding a provider needs no edit here.
SHORTCUTS=""
for f in "$ROOT_DIR"/providers/*.sh; do
  [ -f "$f" ] || continue
  name=$(basename -- "$f" .sh)
  SHORTCUTS="$SHORTCUTS claude-$name"
done
SHORTCUTS=$(echo "$SHORTCUTS" | sed 's/^ *//')

# Refuse command-name collisions before changing anything. Re-running crouter
# may replace links from another/moved crouter checkout, but never a regular
# file or an unrelated symlink.
_crouter_owned_link() {
  [ -L "$1" ] || return 1
  case $(readlink "$1" 2>/dev/null) in
    */bin/crouter|*/bin/crouter-compat) return 0 ;;
    *) return 1 ;;
  esac
}
_collisions=""
for target in crouter $SHORTCUTS; do
  destination="$INSTALL_DIR/$target"
  if { [ -e "$destination" ] || [ -L "$destination" ]; } && ! _crouter_owned_link "$destination"; then
    _collisions="${_collisions}${_collisions:+
}$destination"
  fi
done
if [ -n "$_collisions" ]; then
  printf 'crouter: install refused; these paths are not crouter-owned:\n%s\n' "$_collisions" >&2
  exit 1
fi

chmod +x "$ROOT_DIR/bin/crouter" "$ROOT_DIR/bin/crouter-compat"
ln -sf "$ROOT_DIR/bin/crouter" "$INSTALL_DIR/crouter"
for target in $SHORTCUTS; do
  ln -sf "$ROOT_DIR/bin/crouter-compat" "$INSTALL_DIR/$target"
done

# A provider can disappear between installs. Remove only this checkout's
# compatibility links whose provider declaration no longer exists; leave
# shortcuts belonging to another checkout or tool untouched.
for shortcut in "$INSTALL_DIR"/claude-*; do
  [ -L "$shortcut" ] || continue
  case $(readlink "$shortcut" 2>/dev/null) in
    "$ROOT_DIR/bin/crouter"|"$ROOT_DIR/bin/crouter-compat") ;;
    *) continue ;;
  esac
  provider=${shortcut##*/}
  provider=${provider#claude-}
  [ -f "$ROOT_DIR/providers/$provider.sh" ] || rm -f "$shortcut"
done

if [ ! -f "$ROOT_DIR/config.sh" ]; then
  cp "$ROOT_DIR/config.example.sh" "$ROOT_DIR/config.sh"
  echo "Created config.sh from config.example.sh (edit as needed; it is gitignored)."
fi

echo "Installed: $INSTALL_DIR/crouter -> $ROOT_DIR/bin/crouter"
echo "Installed compatibility shortcuts: $(echo "$SHORTCUTS" | tr ' ' ',' | sed 's/,/, /g')"
echo "crouter $VERSION"

# If the Antigravity proxy checkout is alongside this install, offer to apply
# the GPT-OSS family patch. This is what lets `crouter antigravity-claude
# --model gpt-oss-120b-medium` actually reach the proxy; without it the proxy
# rejects unknown-family names. Idempotent; safe to re-run.
chmod +x "$ROOT_DIR/bin/antigravity-proxy-patch"
if [ -d "$ROOT_DIR/antigravity-claude-proxy" ]; then
  "$ROOT_DIR/bin/antigravity-proxy-patch" --status >/dev/null 2>&1 || \
    "$ROOT_DIR/bin/antigravity-proxy-patch" 2>&1 | sed 's/^/  /'
else
  echo "Note: antigravity-claude-proxy/ not found next to this install."
  echo "      Run 'crouter antigravity-proxy-patch --proxy-dir <path>' after cloning it,"
  echo "      to enable GPT-OSS support in the proxy."
fi

case :$PATH: in
  *:"$INSTALL_DIR":*) ;;
  *) echo "NOTE: $INSTALL_DIR is not on your PATH." ;;
esac

echo "Try: crouter list"
echo "Optional: enable shell autocompletion - see README (completions/)."
