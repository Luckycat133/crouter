#!/bin/sh
# User-managed key pools live in ignored state, never in tracked provider
# declarations. The first add fills a declared Keychain slot; later keys are
# registered in the local state file.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node)}
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-key-registry)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

FAKE_ROOT="$TMP_DIR/repo"
FAKE_BIN="$TMP_DIR/bin"
STATE_DIR="$TMP_DIR/state"
KEYCHAIN_DIR="$TMP_DIR/keychain"
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/lib" "$FAKE_ROOT/providers" "$FAKE_BIN" "$KEYCHAIN_DIR"
cp "$ROOT_DIR/bin/crouter" "$FAKE_ROOT/bin/"
cp "$ROOT_DIR/lib/"*.sh "$ROOT_DIR/lib/"*.js "$FAKE_ROOT/lib/"
printf 'test\n' > "$FAKE_ROOT/VERSION"

cat > "$FAKE_ROOT/providers/demo.sh" <<'EOF'
PROVIDER_NAME="demo"
BASE_URL="https://example.invalid/anthropic"
MODEL="demo-model"
AUTH_MODE="surfaces"
PLAN_URL="https://plan.example.invalid/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEYS="demo-plan-primary"
API_URL="https://api.example.invalid/anthropic"
API_AUTH_TYPE="bearer"
API_KEYS="demo-api-primary"
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
            IFS= read -r _value || exit 91
            IFS= read -r _confirm || exit 92
            [ "$_value" = "$_confirm" ] || exit 93
          fi ;;
        *) shift ;;
      esac
    done
    [ "${FAIL_ADD:-0}" != 1 ] || exit 94
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
    [ "${FAIL_DELETE:-0}" != 1 ] || exit 95
    rm -f "$KEYCHAIN_DIR/$_service"
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$FAKE_BIN/security"

before=$(cksum "$FAKE_ROOT/providers/demo.sh")
run_crouter() {
  PATH="$FAKE_BIN:$PATH" KEYCHAIN_DIR="$KEYCHAIN_DIR" STATE_DIR="$STATE_DIR" \
    USER=test CLAUDE_BIN=/usr/bin/true NODE_BIN="$NODE_BIN" \
    "$FAKE_ROOT/bin/crouter" "$@"
}

printf 'plan-one\n' | run_crouter add demo --surface plan --stdin >/dev/null
[ "$(cat "$KEYCHAIN_DIR/demo-plan-primary")" = plan-one ]
[ "$before" = "$(cksum "$FAKE_ROOT/providers/demo.sh")" ]
[ ! -e "$STATE_DIR/keypools/demo.tsv" ]

printf 'plan-two\n' | run_crouter add demo --surface plan --stdin >/dev/null
[ "$(cat "$KEYCHAIN_DIR/demo-plan-2")" = plan-two ]
grep -qx 'plan[[:space:]]demo-plan-2' "$STATE_DIR/keypools/demo.tsv"
if _registry_mode=$(stat -f '%Lp' "$STATE_DIR/keypools/demo.tsv" 2>/dev/null); then
  :
else
  _registry_mode=$(stat -c '%a' "$STATE_DIR/keypools/demo.tsv")
fi
[ "$_registry_mode" = 600 ]
[ "$before" = "$(cksum "$FAKE_ROOT/providers/demo.sh")" ]

_listed=$(run_crouter list demo)
printf '%s\n' "$_listed" | grep -q 'demo-plan-primary.*in Keychain'
printf '%s\n' "$_listed" | grep -q 'demo-plan-2.*in Keychain'

FAIL_DELETE=1
export FAIL_DELETE
if run_crouter remove demo --surface plan --name demo-plan-2 -y >/dev/null 2>&1; then
  printf 'FAIL  crouter reported success after Keychain rejected the delete\n' >&2
  exit 1
fi
unset FAIL_DELETE
[ -e "$KEYCHAIN_DIR/demo-plan-2" ]
grep -q 'demo-plan-2' "$STATE_DIR/keypools/demo.tsv"

run_crouter remove demo --surface plan --name demo-plan-2 -y >/dev/null
[ ! -e "$KEYCHAIN_DIR/demo-plan-2" ]
if grep -q 'demo-plan-2' "$STATE_DIR/keypools/demo.tsv"; then
  printf 'FAIL  removed key remained in the local registry\n' >&2
  exit 1
fi
[ "$before" = "$(cksum "$FAKE_ROOT/providers/demo.sh")" ]

FAIL_ADD=1
export FAIL_ADD
if printf 'must-not-store\n' | run_crouter add demo --surface plan --name demo-plan-failed --stdin >/dev/null 2>&1; then
  printf 'FAIL  crouter reported success after Keychain rejected the add\n' >&2
  exit 1
fi
unset FAIL_ADD
[ ! -e "$KEYCHAIN_DIR/demo-plan-failed" ]
if grep -q 'demo-plan-failed' "$STATE_DIR/keypools/demo.tsv"; then
  printf 'FAIL  failed Keychain add mutated the local registry\n' >&2
  exit 1
fi

printf 'ok    key add/remove uses Keychain plus local registry without editing providers\n'
