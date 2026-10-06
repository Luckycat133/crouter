#!/bin/sh
# `crouter list` answers "what can I launch right now": providers whose
# credential is present, plus the routes that need no credential at all.
# --all restores the full catalog, and the key-listing back-compat forms stay.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node 2>/dev/null || true)}
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-list-status)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

FAKE_ROOT="$TMP_DIR/repo"
FAKE_BIN="$TMP_DIR/bin"
KEYCHAIN_DIR="$TMP_DIR/keychain"
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/lib" "$FAKE_ROOT/providers" "$FAKE_BIN" "$KEYCHAIN_DIR"
cp "$ROOT_DIR/bin/crouter" "$FAKE_ROOT/bin/"
cp "$ROOT_DIR/lib/"*.sh "$ROOT_DIR/lib/"*.js "$FAKE_ROOT/lib/"
printf 'test\n' > "$FAKE_ROOT/VERSION"

cat > "$FAKE_ROOT/providers/readyenv.sh" <<'EOF'
PROVIDER_NAME="readyenv"
BASE_URL="https://ready.example.invalid/anthropic"
MODEL="ready-model"
AUTH_MODE="env"
AUTH_REFERENCE="CROUTER_TEST_READY_KEY"
EOF

cat > "$FAKE_ROOT/providers/missingenv.sh" <<'EOF'
PROVIDER_NAME="missingenv"
BASE_URL="https://missing.example.invalid/anthropic"
MODEL="missing-model"
AUTH_MODE="env"
AUTH_REFERENCE="CROUTER_TEST_MISSING_KEY"
EOF

cat > "$FAKE_ROOT/providers/localone.sh" <<'EOF'
PROVIDER_NAME="localone"
BASE_URL="http://127.0.0.1:11499"
MODEL="local-model"
AUTH_MODE="none"
EOF

cat > "$FAKE_ROOT/providers/kcone.sh" <<'EOF'
PROVIDER_NAME="kcone"
BASE_URL="https://keychain.example.invalid/anthropic"
MODEL="keychain-model"
AUTH_MODE="keychain"
AUTH_REFERENCE="crouter-test-kc"
EOF

cat > "$FAKE_ROOT/providers/nativeone.sh" <<'EOF'
PROVIDER_NAME="nativeone"
BASE_URL="native://example"
MODEL="native-model"
AUTH_MODE="native"
NATIVE_BACKEND="bedrock"
EOF

cat > "$FAKE_BIN/security" <<'EOF'
#!/bin/sh
case $1 in
  find-generic-password)
    shift
    _service=
    while [ $# -gt 0 ]; do
      case $1 in
        -s) _service=$2; shift 2 ;;
        -a) shift 2 ;;
        -w) shift ;;
        *) shift ;;
      esac
    done
    [ -f "$KEYCHAIN_DIR/$_service" ] || exit 44
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$FAKE_BIN/security"

printf 'stored\n' > "$KEYCHAIN_DIR/crouter-test-kc"

run_crouter() {
  PATH="$FAKE_BIN:$PATH" KEYCHAIN_DIR="$KEYCHAIN_DIR" \
    USER=test CLAUDE_BIN=/usr/bin/true NODE_BIN="$NODE_BIN" \
    CROUTER_TEST_READY_KEY=present \
    "$FAKE_ROOT/bin/crouter" "$@"
}

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

before=$(cksum "$FAKE_ROOT/providers/readyenv.sh")

# Default view: credential present, no credential needed, or native login.
_default=$(run_crouter list)
printf '%s\n' "$_default" | grep -q '^readyenv  *ready ' || fail 'a provider with a credential must be listed as ready'
printf '%s\n' "$_default" | grep -q '^kcone  *ready ' || fail 'a Keychain-backed provider must be listed as ready'
printf '%s\n' "$_default" | grep -q '^localone  *local ' || fail 'a credential-free local route must be listed as local'
printf '%s\n' "$_default" | grep -q '^nativeone  *native ' || fail 'a native Claude Code backend must be listed as native'
if printf '%s\n' "$_default" | grep -q 'missingenv'; then
  fail 'a provider without a credential must not be listed by default'
fi
printf '%s\n' "$_default" | grep -q '1 of 5 providers have no credential yet' || fail 'the default view must report how many providers are hidden'
printf '%s\n' "$_default" | grep -q 'crouter list --all' || fail 'the default view must point at --all'

# --all restores the full inventory, with the missing credential labelled.
_all=$(run_crouter list --all)
for _p in readyenv missingenv localone kcone nativeone; do
  printf '%s\n' "$_all" | grep -q "^$_p " || fail "--all must list $_p"
done
printf '%s\n' "$_all" | grep -q '^missingenv  *no-key ' || fail 'a missing credential must be labelled no-key'
if printf '%s\n' "$_all" | grep -q 'providers have no credential yet'; then
  fail '--all must not print the hidden-provider note'
fi
[ "$(printf '%s\n' "$_all" | grep -c .)" -eq 6 ] || fail '--all must print exactly one header and one row per provider'

# Back-compat: `list keys <provider>` and `list <provider>` still list keys.
run_crouter list keys kcone | grep -q 'crouter-test-kc' || fail 'list keys <provider> must still work'
run_crouter list kcone | grep -q 'crouter-test-kc' || fail 'list <provider> must still resolve to its keys'

# Bad arguments and missing arguments keep failing loudly instead of printing.
if run_crouter list --bogus >/dev/null 2>&1; then
  fail 'an unknown list argument must fail'
fi
if run_crouter list keys >/dev/null 2>&1; then
  fail 'list keys without a provider must fail'
fi

[ "$before" = "$(cksum "$FAKE_ROOT/providers/readyenv.sh")" ] || fail 'listing must not modify provider declarations'

# With nothing configured, the default view explains itself instead of printing
# a bare header.
rm -f "$FAKE_ROOT/providers/readyenv.sh" "$FAKE_ROOT/providers/localone.sh" \
      "$FAKE_ROOT/providers/kcone.sh" "$FAKE_ROOT/providers/nativeone.sh"
_empty=$(run_crouter list)
printf '%s\n' "$_empty" | grep -q 'no provider is configured yet' || fail 'an empty default view must say so'
if printf '%s\n' "$_empty" | grep -q '^missingenv '; then
  fail 'the empty default view must not fall back to listing unconfigured providers'
fi

printf 'ok    crouter list separates launchable providers from the unconfigured catalog\n'
