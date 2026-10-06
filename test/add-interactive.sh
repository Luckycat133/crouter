#!/bin/sh
# `crouter add` with no provider must offer the providers that still need a key,
# accept a number or a name, then reuse the non-interactive store path. The
# secret keeps its keychain-only contract: never in argv, never in a file.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node 2>/dev/null || true)}
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-add-interactive)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

FAKE_ROOT="$TMP_DIR/repo"
FAKE_BIN="$TMP_DIR/bin"
KEYCHAIN_DIR="$TMP_DIR/keychain"
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/lib" "$FAKE_ROOT/providers" "$FAKE_BIN" "$KEYCHAIN_DIR"
cp "$ROOT_DIR/bin/crouter" "$FAKE_ROOT/bin/"
cp "$ROOT_DIR/lib/"*.sh "$ROOT_DIR/lib/"*.js "$FAKE_ROOT/lib/"
printf 'test\n' > "$FAKE_ROOT/VERSION"

# One provider already has a credential, so it must not be offered.
cat > "$FAKE_ROOT/providers/configured.sh" <<'EOF'
PROVIDER_NAME="configured"
BASE_URL="https://configured.example.invalid/anthropic"
MODEL="configured-model"
AUTH_MODE="env"
AUTH_REFERENCE="CROUTER_TEST_CONFIGURED_KEY"
EOF

cat > "$FAKE_ROOT/providers/singlekey.sh" <<'EOF'
PROVIDER_NAME="singlekey"
BASE_URL="https://single.example.invalid/anthropic"
MODEL="single-model"
AUTH_MODE="keychain"
AUTH_REFERENCE="crouter-test-single"
EOF

cat > "$FAKE_ROOT/providers/twosurface.sh" <<'EOF'
PROVIDER_NAME="twosurface"
BASE_URL="https://two.example.invalid/anthropic"
MODEL="two-model"
AUTH_MODE="surfaces"
PLAN_URL="https://plan.example.invalid/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEYS="two-plan-primary"
API_URL="https://api.example.invalid/anthropic"
API_AUTH_TYPE="bearer"
API_KEYS="two-api-primary"
EOF

cat > "$FAKE_ROOT/providers/notmanageable.sh" <<'EOF'
PROVIDER_NAME="notmanageable"
BASE_URL="http://127.0.0.1:11498"
MODEL="local-model"
AUTH_MODE="none"
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
    cat "$KEYCHAIN_DIR/$_service"
    ;;
  add-generic-password)
    shift
    # Leak guard: the secret must never travel in the child argv (world
    # readable via ps). Real security(1) takes it over a /dev/tty prompt.
    printf '%s\n' "$@" > "$KEYCHAIN_DIR/add-argv"
    _service= _value=
    while [ $# -gt 0 ]; do
      case $1 in
        -U) shift ;;
        -a) shift 2 ;;
        -s) _service=$2; shift 2 ;;
        -w)
          shift
          if [ $# -gt 0 ]; then
            _value=$1; shift
          else
            printf 'password data for new item: '
            IFS= read -r _value || exit 91
            printf 'retype password for new item: '
            IFS= read -r _confirm || exit 92
            [ "$_value" = "$_confirm" ] || exit 93
          fi ;;
        *) shift ;;
      esac
    done
    printf '%s' "$_value" > "$KEYCHAIN_DIR/$_service"
    ;;
  delete-generic-password)
    shift
    _service=
    while [ $# -gt 0 ]; do
      case $1 in
        -a) shift 2 ;;
        -s) _service=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    rm -f "$KEYCHAIN_DIR/$_service"
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$FAKE_BIN/security"

run_crouter() {
  PATH="$FAKE_BIN:$PATH" KEYCHAIN_DIR="$KEYCHAIN_DIR" \
    USER=test CLAUDE_BIN=/usr/bin/true NODE_BIN="$NODE_BIN" \
    CROUTER_TEST_CONFIGURED_KEY=present \
    "$FAKE_ROOT/bin/crouter" "$@"
}

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

# The menu lists only providers that still need a key, never the configured one
# and never a route that needs no credential at all.
_menu=$(printf '\n' | run_crouter add --stdin)
printf '%s\n' "$_menu" | grep -q 'singlekey' || fail 'the menu must offer a provider without a credential'
printf '%s\n' "$_menu" | grep -q 'twosurface' || fail 'the menu must offer a surface provider without a credential'
if printf '%s\n' "$_menu" | grep -q 'configured'; then
  fail 'the menu must not offer an already configured provider'
fi
if printf '%s\n' "$_menu" | grep -q 'notmanageable'; then
  fail 'the menu must not offer a route whose auth needs no key'
fi
printf '%s\n' "$_menu" | grep -q 'cancelled' || fail 'an empty selection must cancel'

# A selection outside the menu, an unknown name, and an unknown flag must all
# fail without storing anything.
if printf '99\n' | run_crouter add --stdin >/dev/null 2>&1; then
  fail 'an out-of-range selection must fail'
fi
if printf 'nosuchprovider\n' | run_crouter add --stdin >/dev/null 2>&1; then
  fail 'an unknown provider name must fail'
fi
if run_crouter add --bogus --stdin >/dev/null 2>&1; then
  fail 'an unknown add flag must fail'
fi
[ -z "$(ls -A "$KEYCHAIN_DIR")" ] || fail 'a failed selection must not touch the Keychain'

# Choosing by number stores the key in the declared Keychain service.
printf '1\nfirst-secret\n' | run_crouter add --stdin >/dev/null
[ "$(cat "$KEYCHAIN_DIR/crouter-test-single")" = first-secret ] || fail 'the numeric selection must store the key'
if grep -q 'first-secret' "$KEYCHAIN_DIR/add-argv" 2>/dev/null; then
  fail 'the Keychain child argv contained the secret'
fi

# Choosing by name works too, and the surface question routes the key. The first
# key fills the declared Keychain slot, so no local registry is allocated yet.
printf 'twosurface\n2\nsecond-secret\n' | run_crouter add --stdin >/dev/null
[ "$(cat "$KEYCHAIN_DIR/two-api-primary")" = second-secret ] || fail 'the surface selection must store the key on that surface'
[ ! -e "$KEYCHAIN_DIR/two-plan-primary" ] || fail 'the unselected surface must stay empty'
[ ! -e "$FAKE_ROOT/.state/keypools/twosurface.tsv" ] || fail 'the declared slot must not allocate a registry entry'

# A second key on the same surface is registered in the state file. The default
# menu hides configured providers, so --all is what exposes them for rotation.
printf 'twosurface\n2\nthird-secret\n' | run_crouter add --all --stdin >/dev/null
[ "$(cat "$KEYCHAIN_DIR/twosurface-api-2")" = third-secret ] || fail 'a second key must get the next service name'
grep -qx 'api[[:space:]]twosurface-api-2' "$FAKE_ROOT/.state/keypools/twosurface.tsv" ||
  fail 'a key beyond the declared slot must be registered in the state file'

# The non-interactive contract is unchanged.
printf 'fourth-secret\n' | run_crouter add singlekey --stdin >/dev/null
[ "$(cat "$KEYCHAIN_DIR/crouter-test-single")" = fourth-secret ] || fail 'crouter add <provider> --stdin must keep working'

# --all widens the menu to configured providers instead of hiding them.
_all_menu=$(printf '\n' | run_crouter add --all --stdin)
printf '%s\n' "$_all_menu" | grep -q 'configured' || fail '--all must offer an already configured provider'
printf '%s\n' "$_all_menu" | grep -q 'notmanageable' || fail '--all must offer credential-free routes too'

# Once every provider has a credential, the default wizard says so instead of
# prompting, and points at --all for rotation.
_all_set=$(run_crouter add --stdin)
printf '%s\n' "$_all_set" | grep -q 'already has a credential' ||
  fail 'a fully configured catalog must not prompt for a provider'
printf '%s\n' "$_all_set" | grep -q 'crouter add --all' ||
  fail 'the fully configured note must point at --all'

printf 'ok    crouter add offers unconfigured providers and reuses the keychain store path\n'
