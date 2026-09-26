#!/bin/sh
# Native coding-agent CLIs keep their own login, argv and exit status.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-native-apps)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/capture"
cat > "$TMP_DIR/bin/codex" <<'EOF'
#!/bin/sh
printf '%s\000' "$@" > "$APP_CAPTURE_DIR/args"
printf '%s\n' "${0##*/}" > "$APP_CAPTURE_DIR/binary"
printf '%s\n' "${OPENAI_API_KEY:-}" > "$APP_CAPTURE_DIR/native-auth"
printf '%s\n' "${CLAUDE_CODE_OAUTH_TOKEN:-}" > "$APP_CAPTURE_DIR/claude-auth"
printf '%s\n' "${ANTHROPIC_BASE_URL:-}" > "$APP_CAPTURE_DIR/provider-url"
printf '%s\n' "${ANTHROPIC_MODEL:-}" > "$APP_CAPTURE_DIR/provider-model"
exit "${APP_EXIT_CODE:-0}"
EOF
for _cli in claude gemini opencode copilot agent cursor-agent kiro-cli qoder kimi qwen amp vibe muse kilo; do
  cp "$TMP_DIR/bin/codex" "$TMP_DIR/bin/$_cli"
done
chmod +x "$TMP_DIR/bin/"*

APP_CAPTURE_DIR="$TMP_DIR/capture" \
  OPENAI_API_KEY=native-auth-sentinel \
  PATH="$TMP_DIR/bin:/usr/bin:/bin" \
  "$ROOT_DIR/bin/crouter" app codex '' 'two words' '--model' 'a*b'
printf '%s\000' '' 'two words' '--model' 'a*b' > "$TMP_DIR/expected-args"
cmp "$TMP_DIR/expected-args" "$TMP_DIR/capture/args"
grep -qx 'native-auth-sentinel' "$TMP_DIR/capture/native-auth"
grep -qx '' "$TMP_DIR/capture/provider-url"
grep -qx '' "$TMP_DIR/capture/provider-model"

APP_CAPTURE_DIR="$TMP_DIR/capture" \
  CLAUDE_BIN="$TMP_DIR/bin/claude" \
  CLAUDE_CODE_OAUTH_TOKEN=claude-auth-sentinel \
  OPENAI_API_KEY=native-auth-sentinel \
  PATH="$TMP_DIR/bin:/usr/bin:/bin" \
  "$ROOT_DIR/bin/crouter" app claude '--version'
printf '%s\000' '--version' > "$TMP_DIR/expected-claude-args"
cmp "$TMP_DIR/expected-claude-args" "$TMP_DIR/capture/args"
grep -qx 'claude-auth-sentinel' "$TMP_DIR/capture/claude-auth"

for _mapping in \
  claude:claude codex:codex gemini:gemini opencode:opencode \
  copilot:copilot cursor:agent kiro:kiro-cli qoder:qoder \
  kimi:kimi qwen:qwen amp:amp vibe:vibe muse:muse kilo:kilo; do
  _app=${_mapping%%:*}
  _binary=${_mapping#*:}
  APP_CAPTURE_DIR="$TMP_DIR/capture" CLAUDE_BIN="$TMP_DIR/bin/claude" \
    PATH="$TMP_DIR/bin:/usr/bin:/bin" "$ROOT_DIR/bin/crouter" app "$_app" --probe
  grep -qx "$_binary" "$TMP_DIR/capture/binary"
done

_list=$(CLAUDE_BIN="$TMP_DIR/bin/claude" OPENAI_API_KEY=native-auth-sentinel \
  PATH="$TMP_DIR/bin:/usr/bin:/bin" "$ROOT_DIR/bin/crouter" app list)
printf '%s\n' "$_list" | grep -Eq '^codex +codex +available$'
printf '%s\n' "$_list" | grep -Eq '^claude +claude +available$'
printf '%s\n' "$_list" | grep -Eq '^cursor +agent +available$'
for _app in gemini opencode copilot kiro qoder kimi qwen amp vibe muse kilo; do
  printf '%s\n' "$_list" | grep -Eq "^$_app +[^ ]+ +available$"
done
if printf '%s\n' "$_list" | grep -q 'native-auth-sentinel'; then
  printf 'FAIL  app list printed native authentication\n' >&2
  exit 1
fi

# Older Cursor installations expose cursor-agent; current official installs
# expose agent. Prefer the current command when both are present.
rm "$TMP_DIR/bin/agent"
APP_CAPTURE_DIR="$TMP_DIR/capture" PATH="$TMP_DIR/bin:/usr/bin:/bin" \
  "$ROOT_DIR/bin/crouter" app cursor --probe
grep -qx cursor-agent "$TMP_DIR/capture/binary"
_list=$(PATH="$TMP_DIR/bin:/usr/bin:/bin" "$ROOT_DIR/bin/crouter" app list)
printf '%s\n' "$_list" | grep -Eq '^cursor +cursor-agent +available$'

# Native app dispatch happens before config.sh is sourced. A config file can
# contain shell side effects and exported provider credentials; neither may
# reach an unrelated native CLI or even `app list`.
FAKE_ROOT="$TMP_DIR/fake-root"
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/lib"
cp "$ROOT_DIR/bin/crouter" "$FAKE_ROOT/bin/crouter"
cp "$ROOT_DIR/lib/native-apps.sh" "$FAKE_ROOT/lib/native-apps.sh"
cat > "$FAKE_ROOT/config.sh" <<'EOF'
printf 'sourced\n' > "$APP_CAPTURE_DIR/config-sourced"
export ANTHROPIC_BASE_URL=https://wrong-provider.invalid
export OPENAI_API_KEY=config-secret-must-not-leak
CLAUDE_BIN=/nonexistent/config/claude
EOF
APP_CAPTURE_DIR="$TMP_DIR/capture" OPENAI_API_KEY=native-auth-sentinel \
  CLAUDE_BIN="$TMP_DIR/bin/claude" PATH="$TMP_DIR/bin:/usr/bin:/bin" \
  "$FAKE_ROOT/bin/crouter" app list > "$TMP_DIR/fake-list"
[ ! -e "$TMP_DIR/capture/config-sourced" ]
if grep -q 'config-secret-must-not-leak' "$TMP_DIR/fake-list"; then
  printf 'FAIL  app list leaked config authentication\n' >&2
  exit 1
fi
APP_CAPTURE_DIR="$TMP_DIR/capture" OPENAI_API_KEY=native-auth-sentinel \
  CLAUDE_BIN="$TMP_DIR/bin/claude" PATH="$TMP_DIR/bin:/usr/bin:/bin" \
  "$FAKE_ROOT/bin/crouter" app codex --probe
[ ! -e "$TMP_DIR/capture/config-sourced" ]
grep -qx native-auth-sentinel "$TMP_DIR/capture/native-auth"
grep -qx '' "$TMP_DIR/capture/provider-url"
APP_CAPTURE_DIR="$TMP_DIR/capture" CLAUDE_BIN="$TMP_DIR/bin/claude" \
  CLAUDE_CODE_OAUTH_TOKEN=claude-auth-sentinel \
  PATH="$TMP_DIR/bin:/usr/bin:/bin" "$FAKE_ROOT/bin/crouter" app claude --probe
[ ! -e "$TMP_DIR/capture/config-sourced" ]
grep -qx claude-auth-sentinel "$TMP_DIR/capture/claude-auth"

if CLAUDE_BIN="$TMP_DIR/missing" "$ROOT_DIR/bin/crouter" app claude >"$TMP_DIR/missing-out" 2>&1; then
  printf 'FAIL  app claude accepted a missing executable\n' >&2
  exit 1
else
  _rc=$?
fi
[ "$_rc" -eq 127 ]
grep -q 'claude is not installed or executable' "$TMP_DIR/missing-out"
_list=$(CLAUDE_BIN="$TMP_DIR/missing" PATH="$TMP_DIR/bin:/usr/bin:/bin" \
  "$ROOT_DIR/bin/crouter" app list)
printf '%s\n' "$_list" | grep -Eq '^claude +claude +missing$'

if "$ROOT_DIR/bin/crouter" app unknown >"$TMP_DIR/unknown-out" 2>&1; then
  printf 'FAIL  app accepted an unknown target\n' >&2
  exit 1
else
  _rc=$?
fi
[ "$_rc" -eq 2 ]
grep -q 'unknown native app: unknown' "$TMP_DIR/unknown-out"

if APP_CAPTURE_DIR="$TMP_DIR/capture" APP_EXIT_CODE=23 \
  PATH="$TMP_DIR/bin:/usr/bin:/bin" "$ROOT_DIR/bin/crouter" app codex >"$TMP_DIR/status-out" 2>&1; then
  printf 'FAIL  app discarded the native exit status\n' >&2
  exit 1
else
  _rc=$?
fi
[ "$_rc" -eq 23 ]

printf 'ok    native apps preserve args, auth and exit status without provider routing\n'
