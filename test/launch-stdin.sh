#!/bin/sh
# A managed background Claude child must receive the original stdin bytes.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT INT TERM
cat > "$TEST_DIR/claude" <<'CLAUDE'
#!/bin/sh
[ -z "${CROUTER_FORBIDDEN_ENV:-}" ] || exit 98
[ "$1" = -p ] && [ "$2" = --input-format ] && [ "$3" = stream-json ] || exit 97
cat
exit 7
CLAUDE
chmod +x "$TEST_DIR/claude"
cat > "$TEST_DIR/run" <<'RUN'
set -u
. "$ROOT_DIR/lib/launch.sh"
info() { :; }
die() { echo "$*" >&2; exit 1; }
CLAUDE_BIN="$TEST_DIR/claude"
MODEL_OPUS=demo MODEL_SONNET=demo MODEL_HAIKU=demo MODEL_SUBAGENT=demo
CONTEXT_TOKENS= EFFORT= EXTRA_ENV= AUTH_MODE=none AUTH_TOKEN= KEYPOOL_URL=
BASE_URL=https://example.invalid
POST_STOP='printf x >> "$TEST_DIR/stops"'
cleanup_provider_assets() { printf x >> "$TEST_DIR/assets-cleaned"; }
launch_claude demo 0 -p --input-format stream-json
RUN
export ROOT_DIR TEST_DIR CROUTER_FORBIDDEN_ENV=must-not-leak
printf '{"type":"user","message":{"role":"user","content":"你好 \\n test"}}\n\n' > "$TEST_DIR/input"
# Exceed a pipe buffer, include a NUL and omit the final newline: preservation
# cannot be accidentally satisfied by reading just one line or shell variable.
dd if=/dev/zero bs=1024 count=80 >> "$TEST_DIR/input" 2>/dev/null
printf 'tail' >> "$TEST_DIR/input"
set +e
cat "$TEST_DIR/input" | "${TEST_SHELL:-sh}" "$TEST_DIR/run" > "$TEST_DIR/output"
rc=$?
set -e
[ "$rc" -eq 7 ] || { printf 'FAIL  Claude exit status became %s\n' "$rc"; exit 1; }
cmp -s "$TEST_DIR/input" "$TEST_DIR/output" || { echo 'FAIL  piped stdin was lost or changed'; exit 1; }
[ "$(cat "$TEST_DIR/stops")" = x ] || { echo 'FAIL  POST_STOP did not run once'; exit 1; }
[ "$(cat "$TEST_DIR/assets-cleaned")" = x ] || { echo 'FAIL  asset cleanup did not run once'; exit 1; }
set +e
"${TEST_SHELL:-sh}" "$TEST_DIR/run" < "$TEST_DIR/input" > "$TEST_DIR/output"
rc=$?
set -e
[ "$rc" -eq 7 ] && cmp -s "$TEST_DIR/input" "$TEST_DIR/output" || {
  echo 'FAIL  redirected file stdin or exit status changed'; exit 1;
}
[ "$(cat "$TEST_DIR/stops")" = xx ] && [ "$(cat "$TEST_DIR/assets-cleaned")" = xx ] || {
  echo 'FAIL  redirected launch cleanup did not run once'; exit 1;
}
printf 'ok    piped stdin, isolated environment, exit status and cleanup are preserved\n'
