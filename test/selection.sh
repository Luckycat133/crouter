#!/bin/sh
# Persistent target selection is data-only and native apps bypass config.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-selection)
trap 'rm -rf "$TEST_DIR"' EXIT INT TERM
FAKE_ROOT=$TEST_DIR/repo
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/lib" "$FAKE_ROOT/providers" \
  "$FAKE_ROOT/capture" "$TEST_DIR/xdg"
cp "$ROOT_DIR/bin/crouter" "$FAKE_ROOT/bin/crouter"
cp "$ROOT_DIR/lib/"*.sh "$FAKE_ROOT/lib/"
printf 'test\n' > "$FAKE_ROOT/VERSION"
cat > "$FAKE_ROOT/providers/demo.sh" <<'EOF'
BASE_URL=https://demo.example.invalid
MODEL=demo-model
AUTH_MODE=none
EOF
cp "$FAKE_ROOT/providers/demo.sh" "$TEST_DIR/demo-provider.sh"
cat > "$FAKE_ROOT/config.sh" <<'EOF'
printf 'sourced\n' > "$ROOT_DIR/config-sourced"
CLAUDE_BIN=$ROOT_DIR/bin/claude
export ANTHROPIC_BASE_URL=https://wrong.example.invalid
export OPENAI_API_KEY=config-secret-must-not-leak
EOF
cat > "$FAKE_ROOT/bin/codex" <<'EOF'
#!/bin/sh
_capture_dir=$(CDPATH= cd -- "$(dirname -- "$0")/../capture" && pwd)
printf '%s\n' "${0##*/}" > "$_capture_dir/binary"
printf '%s\000' "$@" > "$_capture_dir/args"
printf '%s\n' "${ANTHROPIC_BASE_URL:-}" > "$_capture_dir/url"
printf '%s\n' "${ANTHROPIC_MODEL:-}" > "$_capture_dir/model"
printf '%s\n' "${OPENAI_API_KEY:-}" > "$_capture_dir/openai-key"
exit "${APP_EXIT_CODE:-0}"
EOF
cp "$FAKE_ROOT/bin/codex" "$FAKE_ROOT/bin/gemini"
cp "$FAKE_ROOT/bin/codex" "$FAKE_ROOT/bin/claude"
chmod +x "$FAKE_ROOT/bin/"*
# A fake provider helper records any accidental sourcing on the native path.
# shellcheck disable=SC2016
sed '2a\
printf "sourced\\n" > "$ROOT_DIR/provider-lib-sourced"' \
  "$FAKE_ROOT/lib/provider.sh" > "$TEST_DIR/provider-modified.sh"
cp "$TEST_DIR/provider-modified.sh" "$FAKE_ROOT/lib/provider.sh"

export XDG_STATE_HOME=$TEST_DIR/xdg
export PATH=$FAKE_ROOT/bin:/usr/bin:/bin
export CROUTER_PROVIDER_ASSETS=0
CLI=$FAKE_ROOT/bin/crouter
STATE=$XDG_STATE_HOME/crouter/selection

fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }
assert_no_setup() {
  [ ! -e "$FAKE_ROOT/config-sourced" ] || fail 'native launch sourced config.sh'
  [ ! -e "$FAKE_ROOT/provider-lib-sourced" ] || fail 'native launch sourced provider helpers'
}
assert_rejected() {
  _reason=$1; shift
  if "$CLI" "$@" > "$TEST_DIR/rejected.out" 2>&1; then
    fail "accepted $_reason"
  fi
}

[ "$("$CLI" use)" = none ] || fail 'unselected state not shown'
assert_rejected 'bare launch without selection'
grep -q 'run crouter use' "$TEST_DIR/rejected.out"
assert_rejected 'run without selection' run --help
assert_no_setup

[ "$("$CLI" use app/codex)" = 'selected: app/codex' ] || fail 'app selection output'
[ "$(cat "$STATE")" = app/codex ] || fail 'app selection state'
[ "$(find "$STATE" -perm 600 -print)" = "$STATE" ] || fail 'selection mode is not 600'
[ "$("$CLI" use)" = app/codex ] || fail 'app selection not shown'
assert_no_setup
OPENAI_API_KEY=native-secret "$CLI"
grep -qx codex "$FAKE_ROOT/capture/binary"
grep -qx native-secret "$FAKE_ROOT/capture/openai-key"
grep -qx '' "$FAKE_ROOT/capture/url"
grep -qx '' "$FAKE_ROOT/capture/model"
assert_no_setup

OPENAI_API_KEY=native-secret "$CLI" run '' 'two words' --model 'a*b'
printf '%s\000' '' 'two words' --model 'a*b' > "$TEST_DIR/expected-args"
cmp "$TEST_DIR/expected-args" "$FAKE_ROOT/capture/args"
assert_no_setup
if APP_EXIT_CODE=23 "$CLI" run --probe > "$TEST_DIR/status.out" 2>&1; then
  fail 'native exit status was dropped'
else
  _status=$?
fi
[ "$_status" -eq 23 ] || fail 'native exit status changed'

# Only catalog providers and whitelisted apps may be recorded. Rejected writes
# leave the previous valid selection intact.
for _invalid in missing app/missing ../demo app/../../demo 'app/codex;touch'; do
  assert_rejected "target $_invalid" use "$_invalid"
  [ "$(cat "$STATE")" = app/codex ] || fail 'invalid write changed selection'
done
assert_rejected 'extra use arguments' use demo extra
[ "$(cat "$STATE")" = app/codex ] || fail 'extra args changed selection'

# A whitelisted name is selectable only while its CLI can be executed. If an
# already selected binary disappears, reads and launches reject stale state.
if CLAUDE_BIN=$TEST_DIR/missing "$CLI" use app/claude > "$TEST_DIR/missing-app.out" 2>&1; then
  fail 'selected a supported but missing native CLI'
fi
grep -q 'not installed or executable' "$TEST_DIR/missing-app.out"
[ "$(cat "$STATE")" = app/codex ] || fail 'missing app write changed selection'
CLAUDE_BIN=$FAKE_ROOT/bin/claude "$CLI" use app/claude > /dev/null
rm "$FAKE_ROOT/bin/claude"
if CLAUDE_BIN=$FAKE_ROOT/bin/claude "$CLI" use > "$TEST_DIR/removed-app.out" 2>&1; then
  fail 'show accepted a removed selected CLI'
fi
grep -q 'not installed or executable' "$TEST_DIR/removed-app.out"
grep -q 'crouter use --clear' "$TEST_DIR/removed-app.out"
if CLAUDE_BIN=$FAKE_ROOT/bin/claude "$CLI" run --probe > "$TEST_DIR/removed-app.out" 2>&1; then
  fail 'run accepted a removed selected CLI'
fi
grep -q 'not installed or executable' "$TEST_DIR/removed-app.out"
[ "$(cat "$STATE")" = app/claude ] || fail 'removed CLI changed saved selection'
assert_no_setup
cp "$FAKE_ROOT/bin/codex" "$FAKE_ROOT/bin/claude"
"$CLI" use app/codex > /dev/null

# Switching apps changes only future launches; direct app launches do not
# rewrite the saved target.
"$CLI" use app/gemini > /dev/null
"$CLI" run --probe
grep -qx gemini "$FAKE_ROOT/capture/binary"
"$CLI" app codex --probe
[ "$(cat "$STATE")" = app/gemini ] || fail 'direct app launch changed selection'
assert_no_setup
"$CLI" demo --help > /dev/null
[ "$(cat "$STATE")" = app/gemini ] || fail 'direct provider launch changed selection'

# A provider selection uses the existing config and cmd_run environment.
"$CLI" use demo > /dev/null
rm -f "$FAKE_ROOT/config-sourced" "$FAKE_ROOT/provider-lib-sourced"
"$CLI" run --model custom -p 'two words'
grep -qx sourced "$FAKE_ROOT/config-sourced"
grep -qx sourced "$FAKE_ROOT/provider-lib-sourced"
grep -qx claude "$FAKE_ROOT/capture/binary"
grep -qx https://demo.example.invalid "$FAKE_ROOT/capture/url"
grep -qx custom "$FAKE_ROOT/capture/model"
printf '%s\000' --model custom -p 'two words' > "$TEST_DIR/expected-args"
cmp "$TEST_DIR/expected-args" "$FAKE_ROOT/capture/args"
"$CLI" > /dev/null
grep -qx demo-model "$FAKE_ROOT/capture/model"
"$CLI" run alternate -p prompt > /dev/null
grep -qx alternate "$FAKE_ROOT/capture/model"
printf '%s\000' -p prompt > "$TEST_DIR/expected-args"
cmp "$TEST_DIR/expected-args" "$FAKE_ROOT/capture/args"
"$CLI" app gemini --probe
[ "$(cat "$STATE")" = demo ] || fail 'direct app launch changed provider selection'

# Replacing an existing loose-permission file still produces mode 600.
chmod 644 "$STATE"
"$CLI" use demo > /dev/null
[ "$(find "$STATE" -perm 600 -print)" = "$STATE" ] || fail 'rewrite did not restore mode 600'

# A removed provider and malformed records fail with a repair instruction;
# stored shell syntax must never execute.
rm "$FAKE_ROOT/providers/demo.sh"
assert_rejected 'removed provider' run
grep -q 'run crouter use' "$TEST_DIR/rejected.out"
cp "$TEST_DIR/demo-provider.sh" "$FAKE_ROOT/providers/demo.sh"
rm -f "$FAKE_ROOT/config-sourced" "$FAKE_ROOT/provider-lib-sourced"
printf 'app/codex\nextra\n' > "$STATE"
assert_rejected 'multiline state' run
grep -q 'crouter use --clear' "$TEST_DIR/rejected.out"
assert_no_setup
# shellcheck disable=SC2016
printf '\$(touch "$ROOT_DIR/selection-pwned")\n' > "$STATE"
assert_rejected 'shell syntax in state' run
[ ! -e "$FAKE_ROOT/selection-pwned" ] || fail 'stored state was executed'
printf 'app/codex\000\n' > "$STATE"
assert_rejected 'NUL in state' run
ln -s "$TEST_DIR/symlink-target" "$TEST_DIR/symlink-record"
rm "$STATE"
ln -s "$TEST_DIR/symlink-record" "$STATE"
assert_rejected 'symlink state' run
assert_no_setup

"$CLI" use --clear > /dev/null
[ ! -e "$STATE" ] && [ ! -L "$STATE" ] || fail 'clear left selection state'
[ "$("$CLI" use)" = none ] || fail 'clear did not reset displayed selection'
assert_rejected 'run after clear' run
grep -q 'no target selected' "$TEST_DIR/rejected.out"
"$CLI" use --clear > /dev/null

if XDG_STATE_HOME=relative "$CLI" use > "$TEST_DIR/relative.out" 2>&1; then
  fail 'relative XDG state directory accepted'
fi
grep -q 'XDG_STATE_HOME must be an absolute path' "$TEST_DIR/relative.out"
HOME=$TEST_DIR/home XDG_STATE_HOME= "$CLI" use app/codex > /dev/null
[ "$(cat "$TEST_DIR/home/.local/state/crouter/selection")" = app/codex ] ||
  fail 'HOME fallback state path'

printf 'ok    persistent provider and native-app target selection\n'
