#!/bin/sh
# Diagnostics must report actionable failures without printing config source.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
_sandbox=$(mktemp -d)
trap 'rm -rf "$_sandbox"' EXIT INT TERM
mkdir -p "$_sandbox/repo/bin" "$_sandbox/repo/lib" "$_sandbox/repo/providers" "$_sandbox/tools" "$_sandbox/home"
cp "$ROOT_DIR/bin/crouter" "$_sandbox/repo/bin/"
cp "$ROOT_DIR"/lib/*.sh "$_sandbox/repo/lib/"
cp "$ROOT_DIR/VERSION" "$_sandbox/repo/"
cat > "$_sandbox/tools/claude" <<'SCRIPT'
#!/bin/sh
exit 0
SCRIPT
cat > "$_sandbox/tools/security" <<'SCRIPT'
#!/bin/sh
exit 44
SCRIPT
cat > "$_sandbox/tools/curl" <<'SCRIPT'
#!/bin/sh
exit "${REVIEW_CURL_RC:-0}"
SCRIPT
chmod +x "$_sandbox"/tools/*
cat > "$_sandbox/repo/providers/mock.sh" <<'PROVIDER'
PROVIDER_NAME=mock
BASE_URL=http://127.0.0.1:9
MODEL=mock
AUTH_MODE=env
AUTH_REFERENCE=CROUTER_DIAGNOSTIC_TEST_KEY
HEALTH_CHECK_URL=http://127.0.0.1:9/health
PROVIDER
cat > "$_sandbox/repo/config.sh" <<'CONFIG'
# private-comment-sentinel
unknown_value='private-unknown-sentinel'
API_KEY='private-first-sentinel
private-second-sentinel'
BYPASS_PERMISSIONS=0
CROUTER_PROVIDER_ASSETS=0
CROUTER_STRICT_PROVIDER_MCP=private-flag-sentinel
CONFIG
export HOME="$_sandbox/home" PATH="$_sandbox/tools:$PATH" CLAUDE_BIN="$_sandbox/tools/claude"
export LOG_DIR="$_sandbox/logs" STATE_DIR="$_sandbox/state"
unset CROUTER_DIAGNOSTIC_TEST_KEY
_failures=0
_expect_failure() {
  if "$@" > "$_sandbox/output" 2>&1; then
    printf 'FAIL: expected nonzero: %s\n' "$*"
    _failures=$((_failures + 1))
  fi
}
_check_output() {
  if ! grep -F "$1" "$_sandbox/output" >/dev/null; then
    printf 'FAIL: missing diagnostic: %s\n' "$1"
    _failures=$((_failures + 1))
  fi
}
_cli="$_sandbox/repo/bin/crouter"
_expect_failure "$_cli" doctor mock
_check_output 'auth:MISSING'
_check_output 'CROUTER_DIAGNOSTIC_TEST_KEY'
# The summary remains useful when some optional providers lack credentials.
"$_cli" doctor > "$_sandbox/output"
_check_output 'auth:MISSING'
export CROUTER_DIAGNOSTIC_TEST_KEY=fake-local-test-value REVIEW_CURL_RC=1
_expect_failure "$_cli" doctor mock
_check_output 'health:DOWN'
_check_output 'configured health URL'
export REVIEW_CURL_RC=0
"$_cli" doctor mock > "$_sandbox/output"
_check_output 'auth:ok'
cat > "$_sandbox/repo/providers/surface.sh" <<'PROVIDER'
PROVIDER_NAME=surface
BASE_URL=http://127.0.0.1:9
MODEL=mock
AUTH_MODE=surfaces
API_URL=$BASE_URL
API_KEY_ENV=CROUTER_DIAGNOSTIC_TEST_KEY
PROVIDER
_expect_failure env NODE_BIN=/definitely/missing/node "$_cli" doctor surface
_check_output 'node unavailable'
_check_output 'NODE_BIN'
cp "$_sandbox/tools/claude" "$_sandbox/tools/node"
NODE_BIN=node "$_cli" doctor surface > "$_sandbox/output"
_check_output 'auth:ok(api)'
# Known path fields are user-controlled too; even multiline values must stay private.
cat >> "$_sandbox/repo/config.sh" <<'CONFIG'
LOG_DIR='private-known-path-sentinel
private-path-second-line'
INSTALL_DIR=private-install-sentinel
STATE_DIR=private-state-sentinel
CLAUDE_BIN=private-claude-sentinel
NODE_BIN=private-node-sentinel
CONFIG
"$_cli" config show > "$_sandbox/output"
if grep -E 'private-|unknown_value|API_KEY|config.sh source' "$_sandbox/output" >/dev/null; then
  printf 'FAIL: config show disclosed config source or unknown settings\n'
  _failures=$((_failures + 1))
fi
_check_output 'CONFIG_FILE:   <present; use crouter config path>'
_check_output 'LOG_DIR:       <configured>'
_check_output 'STATE_DIR:     <configured>'
_check_output 'CLAUDE_BIN:    <configured>'
_check_output 'NODE_BIN:      <configured>'
_check_output 'BYPASS_PERMISSIONS: 0'
_check_output 'CROUTER_PROVIDER_ASSETS: 0'
_check_output 'CROUTER_STRICT_PROVIDER_MCP: 0'
# Without a local file, the safe default switches and missing-config state remain visible.
mv "$_sandbox/repo/config.sh" "$_sandbox/config.saved"
unset BYPASS_PERMISSIONS CROUTER_PROVIDER_ASSETS CROUTER_STRICT_PROVIDER_MCP
"$_cli" config show > "$_sandbox/output"
_check_output 'CONFIG_FILE:   <none; using built-in defaults>'
_check_output 'BYPASS_PERMISSIONS: 0'
_check_output 'CROUTER_PROVIDER_ASSETS: 1'
_check_output 'CROUTER_STRICT_PROVIDER_MCP: 1'
# A provider may put credentials in environment assignments or hook commands.
# Showing that provider must reveal only presence, never their raw values.
cat > "$_sandbox/repo/providers/private.sh" <<'PROVIDER'
PROVIDER_NAME=private
BASE_URL=https://example.invalid
MODEL=private-model
AUTH_MODE=static
AUTH_REFERENCE=private-static-sentinel
EXTRA_ENV='PRIVATE_TOKEN=private-extra-sentinel'
PRE_START='printf private-pre-sentinel'
POST_STOP='printf private-post-sentinel'
HEALTH_CHECK_URL='https://example.invalid/health?token=private-health-sentinel'
PROVIDER
"$_cli" provider show private > "$_sandbox/output"
if grep -E 'private-(extra|pre|post|health|static)-sentinel' "$_sandbox/output" >/dev/null; then
  printf 'FAIL: provider show disclosed environment or hook values\n'
  _failures=$((_failures + 1))
fi
_check_output 'PRIVATE_TOKEN=<redacted>'
_check_output 'reference: <redacted>'
_check_output 'PRE_START:        <configured>'
_check_output 'HEALTH_CHECK_URL: <configured>'
unset LOG_DIR STATE_DIR
"$_cli" config show > "$_sandbox/output"
_check_output 'LOG_DIR:       <default: repository logs>'
_check_output 'STATE_DIR:     <default: repository .state>'
[ "$_failures" -eq 0 ] || exit 1
printf 'ok    diagnostics report provider failures and expose only safe effective settings\n'
