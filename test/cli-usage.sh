#!/bin/sh
# Every command answers -h/--help, and every command rejects arguments it does
# not understand. A help request must never launch a provider, run a diagnostic,
# or touch a local service; a typo must never be silently accepted.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
_sandbox=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-cli-usage)
trap 'rm -rf "$_sandbox"' EXIT INT TERM

mkdir -p "$_sandbox/repo/bin" "$_sandbox/repo/lib" "$_sandbox/repo/providers" \
         "$_sandbox/tools" "$_sandbox/home" "$_sandbox/logs"
cp "$ROOT_DIR/bin/crouter" "$_sandbox/repo/bin/"
cp "$ROOT_DIR"/lib/*.sh "$_sandbox/repo/lib/"
cp "$ROOT_DIR/VERSION" "$_sandbox/repo/"

# A launched helper drops a marker, so a help request that still spawned one is
# detectable rather than merely suspicious.
for _tool in claude node; do
  cat > "$_sandbox/tools/$_tool" <<SCRIPT
#!/bin/sh
touch "$_sandbox/launched-$_tool"
exit 0
SCRIPT
done
cat > "$_sandbox/tools/curl" <<'SCRIPT'
#!/bin/sh
exit 0
SCRIPT
cat > "$_sandbox/tools/security" <<'SCRIPT'
#!/bin/sh
exit 44
SCRIPT
chmod +x "$_sandbox"/tools/*

cat > "$_sandbox/repo/providers/demo.sh" <<'PROVIDER'
PROVIDER_NAME=demo
BASE_URL=http://127.0.0.1:9
MODEL=demo-model
AUTH_MODE=none
PROVIDER

export HOME="$_sandbox/home" PATH="$_sandbox/tools:$PATH"
export CLAUDE_BIN="$_sandbox/tools/claude" NODE_BIN="$_sandbox/tools/node"
export LOG_DIR="$_sandbox/logs" STATE_DIR="$_sandbox/state"
unset XDG_STATE_HOME 2>/dev/null || true

_cli="$_sandbox/repo/bin/crouter"
_out="$_sandbox/out"
_failures=0

# Commands that must explain themselves instead of doing work. `app` and `use`
# are dispatched before the shared usage helpers load, so they are checked here
# rather than assumed. One command per line: a line may carry its own arguments.
_check_help() {
  if ! "$_cli" "$@" > "$_out" 2>&1; then
    printf 'FAIL  help exited nonzero: crouter %s\n' "$*"
    sed 's/^/      /' "$_out"
    _failures=$((_failures + 1))
    return 0
  fi
  if ! grep -q '^usage:' "$_out"; then
    printf 'FAIL  no usage line for: crouter %s\n' "$*"
    sed 's/^/      /' "$_out"
    _failures=$((_failures + 1))
  fi
}

_check_rejected() {
  if "$_cli" "$@" > "$_out" 2>&1; then
    printf 'FAIL  accepted an invalid invocation: crouter %s\n' "$*"
    _failures=$((_failures + 1))
    return 0
  fi
  if ! grep -q '^crouter: ' "$_out"; then
    printf 'FAIL  rejection was not explained: crouter %s\n' "$*"
    sed 's/^/      /' "$_out"
    _failures=$((_failures + 1))
  fi
}

while IFS= read -r _command; do
  [ -n "$_command" ] || continue
  # Deliberate word splitting: a line may name a command plus its own arguments.
  # shellcheck disable=SC2086
  _check_help $_command --help
  # shellcheck disable=SC2086
  _check_help $_command -h
done <<'COMMANDS'
list
list --all
list keys
doctor
add
remove
provider
provider show
config
config show
config path
logs
logs list
logs tail
app
app list
all
uninstall
use
COMMANDS

_check_rejected list --bogus
_check_rejected list keys --bogus
_check_rejected doctor --bogus
_check_rejected config bogus
_check_rejected config show extra
_check_rejected config path extra
_check_rejected logs bogus
_check_rejected logs list extra
_check_rejected logs tail
_check_rejected provider
_check_rejected remove
_check_rejected app list extra
_check_rejected use one two

# Help and rejection must not reach a launcher or a diagnostic run.
for _marker in "$_sandbox/launched-claude" "$_sandbox/launched-node"; do
  if [ -e "$_marker" ]; then
    printf 'FAIL  a help or rejection path launched %s\n' "$(basename "$_marker")"
    _failures=$((_failures + 1))
  fi
done

# `crouter logs list` prints size, mtime, and the path exactly once per file.
printf 'first\n' > "$_sandbox/logs/demo.log"
printf 'second\n' >> "$_sandbox/logs/demo.log"
"$_cli" logs list > "$_out" 2>&1
if ! grep -q '^ *SIZE  *MODIFIED  *FILE$' "$_out"; then
  printf 'FAIL  logs list has no header row\n'
  _failures=$((_failures + 1))
fi
_occurrences=$(grep -c "$_sandbox/logs/demo.log" "$_out" || true)
if [ "$_occurrences" -ne 1 ]; then
  printf 'FAIL  logs list printed the path %s times (want 1)\n' "$_occurrences"
  sed 's/^/      /' "$_out"
  _failures=$((_failures + 1))
fi
_size=$(wc -c < "$_sandbox/logs/demo.log" | tr -d ' ')
if ! grep -q "^ *$_size  " "$_out"; then
  printf 'FAIL  logs list did not report the file size (%s bytes)\n' "$_size"
  sed 's/^/      /' "$_out"
  _failures=$((_failures + 1))
fi

# An empty log directory is a normal state, not a table with no rows.
rm -f "$_sandbox/logs/demo.log"
"$_cli" logs list > "$_out" 2>&1
if ! grep -q '(no logs yet)' "$_out"; then
  printf 'FAIL  logs list did not report an empty directory\n'
  _failures=$((_failures + 1))
fi

[ "$_failures" -eq 0 ] || exit 1
printf 'ok    every command answers --help and rejects unknown arguments\n'
