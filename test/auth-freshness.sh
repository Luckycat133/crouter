#!/bin/sh
# Doctor must reflect Keychain changes made outside crouter, without a disk cache.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-auth-freshness)
trap 'rm -rf "$TEST_DIR"' EXIT INT TERM

FAKE_ROOT="$TEST_DIR/repo"
FAKE_BIN="$TEST_DIR/bin"
KEYCHAIN_STATE_FILE="$TEST_DIR/keychain-state"
KEYCHAIN_CALLS_FILE="$TEST_DIR/keychain-calls"
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/lib" "$FAKE_ROOT/providers" "$FAKE_BIN"
cp "$ROOT_DIR/bin/crouter" "$FAKE_ROOT/bin/"
cp "$ROOT_DIR/lib/"*.sh "$ROOT_DIR/lib/"*.js "$FAKE_ROOT/lib/"
printf 'test\n' > "$FAKE_ROOT/VERSION"
cat > "$FAKE_ROOT/providers/demo.sh" <<'EOF'
PROVIDER_NAME="demo"
BASE_URL="https://example.invalid/anthropic"
MODEL="demo-model"
AUTH_MODE="keychain"
AUTH_REFERENCE="demo-key"
EOF
cat > "$FAKE_BIN/security" <<'EOF'
#!/bin/sh
[ "$1" = find-generic-password ] || exit 2
printf 'called\n' >> "$KEYCHAIN_CALLS_FILE"
[ "$(cat "$KEYCHAIN_STATE_FILE")" = present ]
EOF
cat > "$FAKE_BIN/claude" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$FAKE_BIN/security" "$FAKE_BIN/claude"

check_doctor() {
  _expected=$1
  _label=$2
  if PATH="$FAKE_BIN:$PATH" CLAUDE_BIN="$FAKE_BIN/claude" USER=tester KEYCHAIN_STATE_FILE="$KEYCHAIN_STATE_FILE" \
    KEYCHAIN_CALLS_FILE="$KEYCHAIN_CALLS_FILE" "$FAKE_ROOT/bin/crouter" doctor demo \
    > "$TEST_DIR/doctor.out" 2> "$TEST_DIR/doctor.err"; then
    _status=ok
  else
    _status=MISSING
  fi
  [ "$_status" = "$_expected" ] && grep -q "auth:$_expected" "$TEST_DIR/doctor.out" || {
    printf 'FAIL  doctor reported stale Keychain state after %s\n' "$_label" >&2
    cat "$TEST_DIR/doctor.out" "$TEST_DIR/doctor.err" >&2
    exit 1
  }
}

printf 'missing\n' > "$KEYCHAIN_STATE_FILE"
check_doctor MISSING 'missing item'
printf 'present\n' > "$KEYCHAIN_STATE_FILE"
check_doctor ok 'external item addition'
printf 'missing\n' > "$KEYCHAIN_STATE_FILE"
check_doctor MISSING 'external item removal'

[ "$(wc -l < "$KEYCHAIN_CALLS_FILE" | tr -d ' ')" -eq 3 ] &&
[ ! -e "$FAKE_ROOT/logs/.kc-cache" ] || {
  printf 'FAIL  doctor skipped a live lookup or wrote a Keychain state cache\n' >&2
  exit 1
}
printf 'ok    doctor sees external Keychain additions and removals immediately\n'
