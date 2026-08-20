#!/bin/sh
# Hermetic crouter-all route/catalog regressions. No real Keychain or network.
set -u

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node 2>/dev/null || true)}
[ -n "$NODE_BIN" ] || { printf 'skip  node not available\n'; exit 0; }

TEST_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-unified-routes)
trap 'rm -rf "$TEST_DIR"' EXIT INT TERM
FAKE_ROOT="$TEST_DIR/repo"
FAKE_BIN="$TEST_DIR/bin"
CAPTURE_FILE="$TEST_DIR/models.json"
TOKEN_CAPTURE="$TEST_DIR/gateway-token"
MODEL_CAPTURE="$TEST_DIR/default-model"
CHECK_CLAUDE_MARKER="$TEST_DIR/check-launched-claude"
MCP_ARGS_CAPTURE="$TEST_DIR/mcp-args"
MCP_CONFIG_CAPTURE="$TEST_DIR/mcp-config.json"
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/lib" "$FAKE_ROOT/providers" "$FAKE_BIN"
cp "$ROOT_DIR/bin/crouter" "$ROOT_DIR/bin/gateway" "$FAKE_ROOT/bin/"
cp "$ROOT_DIR/lib/"*.sh "$ROOT_DIR/lib/"*.js "$FAKE_ROOT/lib/"
cp "$ROOT_DIR/providers/openrouter.sh" "$ROOT_DIR/providers/antigravity.sh" \
  "$ROOT_DIR/providers/antigravity-claude.sh" "$ROOT_DIR/providers/anthropic.sh" \
  "$FAKE_ROOT/providers/"
cat > "$FAKE_ROOT/providers/zz-demo.sh" <<'EOF'
PROVIDER_NAME="zz-demo"
PROVIDER_DESC="Alias-leak sentinel"
BASE_URL="http://127.0.0.1:9"
MODEL="demo-only"
AUTH_MODE="static"
AUTH_REFERENCE="local-test"
EOF
cat > "$FAKE_ROOT/providers/aa-surface.sh" <<'EOF'
PROVIDER_NAME="aa-surface"
PROVIDER_DESC="Surface route sentinel"
BASE_URL="https://plan.example/anthropic"
MODEL="logical-model"
MODEL_HAIKU="logical-fast"
AUTH_MODE="surfaces"
PLAN_URL="https://plan.example/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="DEMO_PLAN_KEY"
PLAN_MODEL="plan-model"
PLAN_MODEL_HAIKU="plan-fast"
PLAN_MODEL_SUBAGENT="plan-fast"
EOF
cat > "$FAKE_ROOT/providers/native-demo.sh" <<'EOF'
PROVIDER_NAME="native-demo"
PROVIDER_DESC="Native backends cannot be proxied by crouter all"
BASE_URL="native://demo"
MODEL="sonnet"
AUTH_MODE="native"
NATIVE_BACKEND="demo"
EOF
printf 'test\n' > "$FAKE_ROOT/VERSION"

cat > "$FAKE_BIN/security" <<'EOF'
#!/bin/sh
case "$1" in
  find-generic-password)
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -s) service=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    case ${service:-} in
      openrouter-api-key) printf 'fake-openrouter-secret' ;;
      anthropic-api-key) printf 'fake-anthropic-secret' ;;
      *) exit 44 ;;
    esac
    ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$FAKE_BIN/security"

cat > "$FAKE_BIN/claude" <<EOF
#!/bin/sh
printf '%s' "\$ANTHROPIC_AUTH_TOKEN" > "$TOKEN_CAPTURE"
printf '%s' "\$ANTHROPIC_MODEL" > "$MODEL_CAPTURE"
printf '%s\n' "\$@" > "$MCP_ARGS_CAPTURE"
_next_is_mcp=0
for _arg in "\$@"; do
  if [ "\$_next_is_mcp" -eq 1 ]; then
    cp "\$_arg" "$MCP_CONFIG_CAPTURE"
    _next_is_mcp=0
  elif [ "\$_arg" = --mcp-config ]; then
    _next_is_mcp=1
  fi
done
curl -sS "\$ANTHROPIC_BASE_URL/v1/models" > "$CAPTURE_FILE"
EOF
chmod +x "$FAKE_BIN/claude"

if env -u OPENROUTER_API_KEY DEMO_PLAN_KEY=plan-secret PATH="$FAKE_BIN:$PATH" NODE_BIN="$NODE_BIN" \
  CLAUDE_BIN="$FAKE_BIN/claude" "$FAKE_ROOT/bin/crouter" all >"$TEST_DIR/all.out" 2>"$TEST_DIR/all.err"; then
  :
else
  printf 'FAIL  crouter all did not start with OpenRouter Keychain fallback\n'
  sed -n '1,120p' "$TEST_DIR/all.err" >&2
  exit 1
fi

if [ "$(cat "$MODEL_CAPTURE")" = 'anthropic/claude-sonnet-5' ]; then
  printf 'ok    crouter all prefers configured Anthropic API as its default route\n'
else
  printf 'FAIL  crouter all selected unexpected default model: %s\n' "$(cat "$MODEL_CAPTURE")" >&2
  exit 1
fi

_mcp_source=$(awk 'take {print; exit} $0 == "--mcp-config" {take=1}' "$MCP_ARGS_CAPTURE")
if grep -qx -- '--strict-mcp-config' "$MCP_ARGS_CAPTURE" &&
   [ -n "$_mcp_source" ] && [ ! -e "$_mcp_source" ] &&
   MCP_CONFIG_CAPTURE="$MCP_CONFIG_CAPTURE" "$NODE_BIN" - <<'EOF'
const fs = require('fs');
const profile = JSON.parse(fs.readFileSync(process.env.MCP_CONFIG_CAPTURE, 'utf8'));
if (!profile.mcpServers || Object.keys(profile.mcpServers).length !== 0) process.exit(1);
EOF
then
  printf 'ok    crouter all suppresses stale provider MCPs with a strict empty profile\n'
else
  printf 'FAIL  crouter all did not isolate provider MCPs\n' >&2
  exit 1
fi

# --check proves the configured route/candidate graph without starting a gateway,
# launching Claude, printing credentials, or issuing a paid request.
cat > "$FAKE_BIN/claude-check-sentinel" <<EOF
#!/bin/sh
touch "$CHECK_CLAUDE_MARKER"
exit 99
EOF
chmod +x "$FAKE_BIN/claude-check-sentinel"
if env -u OPENROUTER_API_KEY DEMO_PLAN_KEY=plan-secret PATH="$FAKE_BIN:$PATH" NODE_BIN="$NODE_BIN" \
  CLAUDE_BIN="$FAKE_BIN/claude-check-sentinel" "$FAKE_ROOT/bin/crouter" all --check \
  >"$TEST_DIR/check.out" 2>"$TEST_DIR/check.err" &&
  grep -q '^default: anthropic/claude-sonnet-5$' "$TEST_DIR/check.out" &&
  grep -q '^anthropic:' "$TEST_DIR/check.out" &&
  grep -q '^aa-surface:' "$TEST_DIR/check.out" &&
  ! grep -q 'fake-anthropic-secret\|plan-secret\|fake-openrouter-secret' "$TEST_DIR/check.out" &&
  [ ! -e "$CHECK_CLAUDE_MARKER" ]; then
  printf 'ok    crouter all --check prints a redacted route proof without launching Claude\n'
else
  printf 'FAIL  crouter all --check is missing, leaks a token, or launched Claude\n' >&2
  sed -n '1,160p' "$TEST_DIR/check.out" >&2
  sed -n '1,160p' "$TEST_DIR/check.err" >&2
  exit 1
fi

if grep -Eq '^[0-9a-f]{64}$' "$TOKEN_CAPTURE" && [ "$(cat "$TOKEN_CAPTURE")" != crouter ]; then
  printf 'ok    crouter all injects a random per-session gateway token\n'
else
  printf 'FAIL  crouter all did not inject a random gateway token\n' >&2
  exit 1
fi

cat > "$TEST_DIR/default-priority.json" <<'EOF'
[
  {"prefix":"local","auth_mode":"none","models":["local-model"],"candidates":[{"url":"http://127.0.0.1:9","auth":{"type":"none","token":"local"}}]},
  {"prefix":"remote","auth_mode":"surfaces","models":["remote-model"],"candidates":[{"url":"https://example.invalid","auth":{"type":"bearer","token":"secret"}}]}
]
EOF
if [ "$("$NODE_BIN" "$FAKE_ROOT/lib/route-build.js" default-model "$TEST_DIR/default-priority.json")" = remote/remote-model ]; then
  printf 'ok    crouter all prefers credentialed remote routes over unprobed local routes\n'
else
  printf 'FAIL  crouter all chose an unprobed local route over a credentialed remote route\n' >&2
  exit 1
fi

_static_route=$(CR_PREFIX=local-static CR_MODELS=static-model \
  CR_API_URL=http://127.0.0.1:9 CR_API_KEY=placeholder CR_AUTH_MODE=static \
  "$NODE_BIN" "$FAKE_ROOT/lib/route-build.js" candidates)
if STATIC_ROUTE="$_static_route" "$NODE_BIN" - <<'EOF'
const route = JSON.parse(process.env.STATIC_ROUTE);
const candidate = route.candidates[0];
if (candidate.auth.type !== 'both' || candidate.label !== 'static-placeholder') process.exit(1);
EOF
then
  printf 'ok    unified static routes match direct-launch auth compatibility\n'
else
  printf 'FAIL  unified static route auth differs from direct launch\n' >&2
  exit 1
fi

if CAPTURE_FILE="$CAPTURE_FILE" "$NODE_BIN" <<'EOF'
const fs = require('fs');
const body = JSON.parse(fs.readFileSync(process.env.CAPTURE_FILE, 'utf8'));
const ids = body.data.map((entry) => entry.id);
if (!ids.includes('openrouter/nvidia/nemotron-3-ultra-550b-a55b:free')) process.exit(1);
EOF
then
  printf 'ok    crouter all includes OpenRouter from the Keychain fallback\n'
else
  printf 'FAIL  crouter all omitted OpenRouter despite its Keychain fallback\n'
  exit 1
fi

if CAPTURE_FILE="$CAPTURE_FILE" "$NODE_BIN" <<'EOF'
const fs = require('fs');
const body = JSON.parse(fs.readFileSync(process.env.CAPTURE_FILE, 'utf8'));
const ids = body.data.map((entry) => entry.id);
const expected = [
  'openrouter/nvidia/nemotron-3-ultra-550b-a55b:free',
  'antigravity/gemini-3.7-flash-tiered',
  'antigravity/gemini-3.5-flash-medium',
  'antigravity/gemini-3.1-pro-low',
  'antigravity-claude/claude-opus-4-6-thinking',
  'antigravity-claude/claude-sonnet-4-6',
  'antigravity-claude/gpt-oss-120b-medium',
  'aa-surface/logical-model',
  'aa-surface/logical-fast',
  'zz-demo/demo-only',
];
if (expected.some((id) => !ids.includes(id))) process.exit(1);
if (ids.some((id) => id.startsWith('native-demo/'))) process.exit(4);
if (new Set(ids).size !== ids.length) process.exit(2);
if (ids.some((id) => id.startsWith('zz-demo/') && id !== 'zz-demo/demo-only')) process.exit(3);
EOF
then
  printf 'ok    unified catalog includes aliases once without cross-provider leakage\n'
else
  printf 'FAIL  unified catalog omitted, duplicated, or leaked model aliases\n'
  exit 1
fi

# Sequential loading exercises load_provider's reset contract independently of
# build_all_routes' per-provider subshells.
if ROOT_DIR="$FAKE_ROOT" PROVIDERS_DIR="$FAKE_ROOT/providers" sh <<'EOF'
die() { printf '%s\n' "$*" >&2; exit 1; }
. "$ROOT_DIR/lib/provider.sh"
load_provider antigravity
[ "$MODEL_ALIASES" = 'gemini-3.7-flash-tiered gemini-3.5-flash-medium gemini-3.1-pro-low' ] || exit 1
load_provider zz-demo
[ -z "${MODEL_ALIASES:-}" ]
EOF
then
  printf 'ok    sequential provider loading resets model aliases\n'
else
  printf 'FAIL  model aliases leaked across sequential provider loads\n'
  exit 1
fi

# A malformed provider must fail the unified build instead of disappearing
# silently from an otherwise usable catalog.
cat > "$FAKE_ROOT/providers/broken-surface.sh" <<'EOF'
PROVIDER_NAME="broken-surface"
PROVIDER_DESC="Ambiguous model-map sentinel"
BASE_URL="https://broken.example/anthropic"
MODEL="broken-default"
MODEL_HAIKU="broken-fast"
MODEL_SUBAGENT="broken-fast"
AUTH_MODE="surfaces"
PLAN_URL="https://broken.example/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="BROKEN_PLAN_KEY"
PLAN_MODEL="upstream-default"
PLAN_MODEL_HAIKU="upstream-haiku"
PLAN_MODEL_SUBAGENT="upstream-subagent"
EOF
if BROKEN_PLAN_KEY=broken-secret env -u OPENROUTER_API_KEY DEMO_PLAN_KEY=plan-secret \
  PATH="$FAKE_BIN:$PATH" NODE_BIN="$NODE_BIN" CLAUDE_BIN="$FAKE_BIN/claude" \
  "$FAKE_ROOT/bin/crouter" all >"$TEST_DIR/broken.out" 2>"$TEST_DIR/broken.err"; then
  printf 'FAIL  crouter all silently ignored an invalid provider route\n' >&2
  exit 1
elif grep -q 'ambiguous' "$TEST_DIR/broken.err"; then
  printf 'ok    unified route-build errors propagate to the caller\n'
else
  printf 'FAIL  crouter all failed without the provider route diagnostic\n' >&2
  sed -n '1,120p' "$TEST_DIR/broken.err" >&2
  exit 1
fi
