#!/bin/sh
# Only a real Ollama launch may change the remembered Ollama model.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT INT TERM
mkdir -p "$TEST_DIR/repo/bin" "$TEST_DIR/repo/lib" "$TEST_DIR/repo/providers"
cp "$ROOT_DIR/bin/crouter" "$TEST_DIR/repo/bin/"
cp "$ROOT_DIR/lib/"*.sh "$TEST_DIR/repo/lib/"
cp "$ROOT_DIR/providers/ollama.sh" "$TEST_DIR/repo/providers/"
printf '\nPRE_START=\nPOST_STOP=\n' >> "$TEST_DIR/repo/providers/ollama.sh"
printf 'test\n' > "$TEST_DIR/repo/VERSION"
cat > "$TEST_DIR/repo/providers/demo.sh" <<'PROVIDER'
PROVIDER_NAME=demo
BASE_URL=https://example.invalid
MODEL=remote-model
AUTH_MODE=none
PROVIDER
cat > "$TEST_DIR/claude" <<'CLAUDE'
#!/bin/sh
printf '%s\n' "$ANTHROPIC_MODEL"
CLAUDE
chmod +x "$TEST_DIR/claude"
export CLAUDE_BIN="$TEST_DIR/claude" XDG_STATE_HOME="$TEST_DIR/state" CROUTER_PROVIDER_ASSETS=0
mkdir -p "$XDG_STATE_HOME/crouter"
STATE_FILE="$XDG_STATE_HOME/crouter/last-model-ollama"
fail=0
run() { "${TEST_SHELL:-sh}" "$TEST_DIR/repo/bin/crouter" "$@"; }
unchanged() {
  printf 'saved-model\n' > "$STATE_FILE"
  run "$@" >/dev/null
  if [ "$(cat "$STATE_FILE")" != saved-model ]; then
    printf 'FAIL  %s changed the remembered Ollama model\n' "$*" >&2
    fail=1
  fi
}
unchanged demo -p prompt
for flag in --help -h --version -V; do
  unchanged demo "$flag"
  unchanged ollama new-model "$flag"
done
rm "$STATE_FILE"
run ollama ignored-model --help >/dev/null
[ ! -e "$STATE_FILE" ] || { echo 'FAIL  help created remembered state'; fail=1; }
run ollama selected-model -p prompt >/dev/null
[ "$(cat "$STATE_FILE")" = selected-model ] || { echo 'FAIL  Ollama selection was not saved'; fail=1; }
[ "$(run ollama --version)" = selected-model ] || { echo 'FAIL  remembered selection was not loaded'; fail=1; }
# Validation failures must not persist a selection either.
printf 'saved-model\n' > "$STATE_FILE"
if CLAUDE_BIN="$TEST_DIR/missing" run ollama invalid-launch >/dev/null 2>&1; then
  echo 'FAIL  missing Claude executable was accepted'; fail=1
fi
[ "$(cat "$STATE_FILE")" = saved-model ] || { echo 'FAIL  invalid launch changed remembered selection'; fail=1; }
printf '\nPRE_START=false\n' >> "$TEST_DIR/repo/providers/ollama.sh"
if run ollama failed-prelaunch >/dev/null 2>&1; then
  echo 'FAIL  failed prelaunch was accepted'; fail=1
fi
[ "$(cat "$STATE_FILE")" = saved-model ] || { echo 'FAIL  prelaunch failure changed remembered selection'; fail=1; }
[ "$fail" -eq 0 ] || exit 1
printf 'ok    model persistence is isolated to valid Ollama launches\n'
