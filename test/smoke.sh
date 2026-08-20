#!/bin/sh
# Minimal offline smoke test for crouter.
# Requires no keychain entry or network access.
set -u
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
GATEWAY="$ROOT_DIR/bin/crouter"
fail=0

# Create a temporary mock claude binary so the test doesn't depend on a global installation.
MOCK_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'mock_claude')
MOCK_CLAUDE="$MOCK_DIR/claude"
cat > "$MOCK_CLAUDE" << 'EOF'
#!/bin/sh
# Scan every arg for --version/-V/--help/-h so we still answer when the
# gateway prepends --effort / env vars ahead of the user's args.
for _a in "$@"; do
  case "$_a" in
    --version|-V|--help|-h)
      printf 'ANTHROPIC_MODEL=%s\n' "${ANTHROPIC_MODEL:-}"
      printf 'CLAUDE_CODE_MAX_CONTEXT_TOKENS=%s\n' "${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-}"
      echo "0.2.0"
      exit 0
      ;;
  esac
done
exit 0
EOF
chmod +x "$MOCK_CLAUDE"

# Clean up on exit
trap 'rm -rf "$MOCK_DIR"' EXIT INT TERM

# Export CLAUDE_BIN for the launchers
export CLAUDE_BIN="$MOCK_CLAUDE"

ok()  { printf 'ok    %s\n' "$1"; }
bad() { printf 'FAIL  %s\n' "$1"; fail=1; }

# Legacy command names remain available as local compatibility launchers.
for legacy in claude-minimax claude-antigravity claude-antigravity-claude claude-anthropic claude-openrouter; do
  _out=$("$ROOT_DIR/bin/$legacy" --version 2>&1)
  _rc=$?
  if [ "$_rc" -eq 0 ] && printf '%s\n' "$_out" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+'; then
    ok "$legacy compatibility launcher forwards --version (exit 0)"
  else
    bad "$legacy compatibility launcher is unavailable (rc=$_rc, output: $_out)"
  fi
done

# --version prints a semver
if "$GATEWAY" --version 2>/dev/null | grep -qE '[0-9]+\.[0-9]+\.[0-9]+'; then
  ok "--version prints a semver"
else
  bad "--version did not print a semver"
fi

# -V short flag also prints a semver
if "$GATEWAY" -V 2>/dev/null | grep -qE '[0-9]+\.[0-9]+\.[0-9]+'; then
  ok "-V prints a semver"
else
  bad "-V did not print a semver"
fi

# list shows the known providers
if "$GATEWAY" list 2>/dev/null | grep -q 'minimax'; then
  ok "list shows minimax provider"
else
  bad "list missing minimax provider"
fi

# help exits 0
if "$GATEWAY" help >/dev/null 2>&1; then
  ok "help exits 0"
else
  bad "help failed"
fi

# A model option must have a real value instead of consuming the next flag.
_missing_model=$({ "$GATEWAY" anthropic --model --version; } 2>&1) && _missing_model_rc=0 || _missing_model_rc=$?
if [ "$_missing_model_rc" -ne 0 ] && printf '%s\n' "$_missing_model" | grep -q -- '--model requires'; then
  ok "--model rejects a missing value"
else
  bad "--model accepted a missing value (rc=$_missing_model_rc, output: $_missing_model)"
fi

# Exact Ollama profiles may override the provider-wide context without changing
# arbitrary user-selected models.
_deepseek_launch=$("$GATEWAY" ollama deepseek-v4-flash:q8 --version 2>&1)
if printf '%s\n' "$_deepseek_launch" | grep -q '^ANTHROPIC_MODEL=deepseek-v4-flash:q8$' && \
   printf '%s\n' "$_deepseek_launch" | grep -q '^CLAUDE_CODE_MAX_CONTEXT_TOKENS=373760$'; then
  ok "Ollama exact model context override is applied"
else
  bad "Ollama exact model context override failed"
fi

_ollama_default_launch=$("$GATEWAY" ollama --version 2>&1)
if printf '%s\n' "$_ollama_default_launch" | grep -q '^ANTHROPIC_MODEL=deepseek-v4-flash:q8$' && \
   printf '%s\n' "$_ollama_default_launch" | grep -q '^CLAUDE_CODE_MAX_CONTEXT_TOKENS=373760$'; then
  ok "Ollama defaults to the validated DeepSeek profile"
else
  bad "Ollama default DeepSeek profile is not applied"
fi

# an unknown subcommand is rejected (non-zero exit)
if "$GATEWAY" bogus-command >/dev/null 2>&1; then
  bad "unknown subcommand was accepted"
else
  ok "unknown subcommand rejected"
fi

# ---------------------------------------------------------------------------
# Key management subcommands (add / remove / list keys) on a fake
# keypool provider. Stubs security(1) with shell functions so no real Keychain
# is touched, and redirects AUTH_KEYS edits to a temporary provider file.
# ---------------------------------------------------------------------------

FAKE_PROVIDERS_DIR="$MOCK_DIR/providers"
mkdir -p "$FAKE_PROVIDERS_DIR"
cat > "$FAKE_PROVIDERS_DIR/demo.sh" << 'EOF'
PROVIDER_NAME="demo"
PROVIDER_DESC="Fake provider for key-management smoke tests"
BASE_URL="https://example.invalid/anthropic"
MODEL="demo-1"
MODEL_OPUS="demo-1"
MODEL_SONNET="demo-1"
MODEL_HAIKU="demo-1"
MODEL_SUBAGENT="demo-1"
AUTH_MODE="keypool"
AUTH_KEYS="demo-key-1"
PROVIDER_DESC="fake"
EOF

# Build a stand-in security(1) that records adds/deletes/finds and echoes
# fake secrets. Place it ahead of /usr/bin on PATH so the gateway sees it.
FAKE_BIN="$MOCK_DIR/bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/security" << 'EOF'
#!/bin/sh
# Fake security(1) for offline smoke tests. Stores secrets in $MOCK_DIR/kc.
_kc="$MOCK_DIR/kc"
mkdir -p "$_kc"
case "$1" in
  find-generic-password)
    while [ $# -gt 0 ]; do
      case "$1" in
        -s) _svc=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    if [ -f "$_kc/$_svc" ]; then
      cat "$_kc/$_svc"
      exit 0
    fi
    exit 44
    ;;
  add-generic-password)
    _user= _svc= _val=
    while [ $# -gt 0 ]; do
      case "$1" in
        -U|-a) shift 2 ;;
        -s) _svc=$2; shift 2 ;;
        -w) _val=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    [ -n "$_svc" ] && [ -n "$_val" ] || exit 1
    printf '%s' "$_val" > "$_kc/$_svc"
    exit 0
    ;;
  delete-generic-password)
    _svc=
    while [ $# -gt 0 ]; do
      case "$1" in
        -a) shift 2 ;;
        -s) _svc=$2; shift 2 ;;
        *) shift ;;
      esac
    done
    [ -n "$_svc" ] && rm -f "$_kc/$_svc"
    exit 0
    ;;
esac
exit 1
EOF
chmod +x "$FAKE_BIN/security"

# Override ROOT_DIR for the gateway so it sees our fake providers/, and
# prepend our fake security(1) to PATH. Use a wrapper script that re-execs
# the real gateway with these in place.
GATEWAY_SH="$MOCK_DIR/cg-wrap.sh"
cat > "$GATEWAY_SH" << EOF
#!/bin/sh
# Wrapper: point crouter at our temp tree + fake security.
export PATH="$FAKE_BIN:\$PATH"
export MOCK_DIR="$MOCK_DIR"
# Fake PROVIDERS_DIR via inline override: pass a fake config.sh that
# re-defines PROVIDERS_DIR before the rest of the script runs. We achieve
# this by sourcing a snippet that drops the original providers dir and
# uses ours instead.
exec "$GATEWAY" "\$@"
EOF
chmod +x "$GATEWAY_SH"

# To actually swap providers/, we point the gateway at our fake tree by
# overriding PROVIDERS_DIR via env. The gateway computes PROVIDERS_DIR
# from ROOT_DIR, so we use a tiny custom gateway copy rooted at FAKE_ROOT.
FAKE_ROOT="$MOCK_DIR/repo"
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/providers" "$FAKE_ROOT/lib"
cp "$GATEWAY" "$FAKE_ROOT/bin/crouter"
cp "$ROOT_DIR/lib/"*.sh "$ROOT_DIR/lib/"*.js "$FAKE_ROOT/lib/" 2>/dev/null || true
cp "$FAKE_PROVIDERS_DIR/demo.sh" "$FAKE_ROOT/providers/demo.sh"
printf '0.4.0\n' > "$FAKE_ROOT/VERSION"

# Stub keypool-proxy so start_keypool doesn't try to spawn node.
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/node" << 'EOF'
#!/bin/sh
echo "KEYPOOL_LISTENING_PORT=18765"
exit 0
EOF
chmod +x "$FAKE_BIN/node"

# Make a fake keypool-proxy too (in case the gateway shells out to it).
cp "$FAKE_BIN/node" "$FAKE_ROOT/bin/keypool-proxy"
chmod +x "$FAKE_ROOT/bin/keypool-proxy"

# Pre-populate the fake keychain so list keys finds demo-key-1.
mkdir -p "$MOCK_DIR/kc"
printf 'fake-secret-1' > "$MOCK_DIR/kc/demo-key-1"

# Copy the real providers into the fake root so non-keypool tests can run.
for _p in antigravity antigravity-claude deepseek minimax; do
  cp "$ROOT_DIR/providers/$_p.sh" "$FAKE_ROOT/providers/$_p.sh" 2>/dev/null || true
done
# antigravity.sh sources lib/antigravity-common.sh, which the lib/*.sh copy above
# already placed in the fake root.

# Wrapper that runs the fake-rooted gateway with our fake security/node on PATH.
FAKE_GW="$FAKE_ROOT/bin/crouter"
run_fake_gw() {
  # shellcheck disable=SC2317
  PATH="$FAKE_BIN:$PATH" MOCK_DIR="$MOCK_DIR" "$FAKE_GW" "$@"
}

# Re-source the wrapper each invocation? Just call directly:
fake_gw() {
  PATH="$FAKE_BIN:$PATH" MOCK_DIR="$MOCK_DIR" "$FAKE_ROOT/bin/crouter" "$@"
}

# happy path: add appends to AUTH_KEYS and stores the secret in our fake kc
echo "secret-add-1" > "$MOCK_DIR/keyring-input.txt"
# _prompt_secret reads from /dev/tty; we can't easily redirect that from
# a non-interactive shell. Stub _prompt_secret via env override: instead,
# use --name with a known value and feed the secret through the stdin of
# `security add-generic-password` indirectly. Since our prompt reads
# /dev/tty, skip that path here and test the public-facing subcommands that
# don't need a TTY: list keys + remove.

# list keys: should print our provider's AUTH_KEYS as present in keychain
if fake_gw list keys demo 2>&1 | grep -q 'demo-key-1' && \
   fake_gw list keys demo 2>&1 | grep -q 'in Keychain'; then
  ok "list keys shows existing AUTH_KEYS entry"
else
  bad "list keys missing demo-key-1"
fi

# list keys for a non-keypool provider (antigravity) — should still succeed
# (antigravity uses AUTH_MODE=static so the output mentions the placeholder).
if fake_gw list keys antigravity 2>&1 | grep -q 'auth_mode: static'; then
  ok "list keys handles non-keypool providers"
else
  bad "list keys failed for non-keypool provider"
fi

# remove: --name with -y (non-interactive) on a built-in service deletes the
# Keychain entry but leaves the immutable provider catalog declaration intact.
if fake_gw remove demo --name demo-key-1 -y 2>&1 | grep -q "removed 'demo-key-1'"; then
  ok "remove deletes a key (non-interactive)"
else
  bad "remove did not confirm"
fi
if grep -q '^AUTH_KEYS="demo-key-1"$' "$FAKE_ROOT/providers/demo.sh"; then
  ok "remove leaves the built-in provider declaration unchanged"
else
  bad "remove mutated the built-in provider declaration"
fi
if [ -f "$MOCK_DIR/kc/demo-key-1" ]; then
  bad "remove left Keychain entry for demo-key-1"
else
  ok "remove deleted the Keychain entry"
fi

# remove: missing --name is rejected
if fake_gw remove demo 2>&1 | grep -q -- '--name is required'; then
  ok "remove rejects missing --name"
else
  bad "remove accepted missing --name"
fi

# remove: removing a non-listed service is rejected
if fake_gw remove demo --name nope -y 2>&1 | grep -q "is not in"; then
  ok "remove rejects unknown service"
else
  bad "remove accepted unknown service"
fi

# add/remove: require a TTY, so we only check the failure path (non-keypool
# providers must reject; the same surface logic is what we really want to
# lock down without an interactive prompt). antigravity is AUTH_MODE=static
# (credentials live in the local proxy), so the new single-key error copy
# is the precise mode-specific rejection we want to assert against.
if fake_gw add antigravity 2>&1 | grep -q 'uses static auth'; then
  ok "add rejects non-keypool provider"
else
  bad "add accepted non-keypool provider"
fi
if fake_gw remove antigravity --name whatever -y 2>&1 | grep -q 'has no single-key to remove'; then
  ok "remove rejects non-keypool provider"
else
  bad "remove accepted non-keypool provider"
fi

# add: unknown --surface is rejected
if fake_gw add demo --surface bogus 2>&1 | grep -q "unknown surface"; then
  ok "add rejects unknown --surface"
else
  bad "add accepted unknown --surface"
fi

# ---------------------------------------------------------------------------
# Providers with explicit auth-surface assertions.
# ---------------------------------------------------------------------------
for _dp in anthropic openrouter codex 302ai aihubmix infini minimax dashscope moonshot ppio z-ai siliconflow stepfun volcengine tencent qianfan qianfan-team qianfan-coding qiniu huawei xiaomi; do
  if "$GATEWAY" list 2>/dev/null | grep -q "^$_dp "; then
    ok "$_dp provider is listed"
  else
    bad "$_dp provider is missing from list"
  fi
done

for _removed in openai baichuan; do
  if "$GATEWAY" list 2>/dev/null | grep -q "^$_removed "; then
    bad "invalid $_removed provider is still listed"
  else
    ok "$_removed is omitted without an official Anthropic Messages endpoint"
  fi
done

# Anthropic API keys and native Claude account login are separate, documented
# entry points; domestic providers use explicit plan/API surface labels.
if "$GATEWAY" list 2>/dev/null | awk '$1=="anthropic"{print $(NF-1)}' | grep -q '^env$'; then
  ok "anthropic reports official API-key auth"
else
  bad "anthropic did not report official API-key auth"
fi
# openrouter has a single API surface (env var, then Keychain fallback) -> never "dual".
if "$GATEWAY" list 2>/dev/null | awk '$1=="openrouter"{print $(NF-1)}' | grep -q '^env$'; then
  ok "openrouter reports single-surface auth"
else
  bad "openrouter did not report single-surface auth"
fi
if "$GATEWAY" list 2>/dev/null | awk '$1=="minimax"{print $(NF-1)}' | grep -q '^plan+api$'; then
  ok "minimax reports separate plan and API surfaces"
else
  bad "minimax did not report plan+api auth"
fi
if "$GATEWAY" list 2>/dev/null | awk '$1=="moonshot"{print $(NF-1)}' | grep -q '^plan$'; then
  ok "Kimi Code reports its membership-plan-only surface"
else
  bad "Kimi Code did not report plan-only auth"
fi

_ollama_show=$("$GATEWAY" provider show ollama 2>&1)
_ollama_show_rc=$?
if [ "$_ollama_show_rc" -eq 0 ] &&
   printf '%s\n' "$_ollama_show" | grep -q '^default:     deepseek-v4-flash:q8$' &&
   printf '%s\n' "$_ollama_show" | grep -q '^context:     373760 tokens$' &&
   printf '%s\n' "$_ollama_show" | grep -q '^effort:      high$'; then
  ok "ollama provider display applies the default model context override"
else
  bad "ollama provider display is inconsistent with its default model"
fi

_openrouter_show=$("$GATEWAY" provider show openrouter 2>&1)
_openrouter_show_rc=$?
if [ "$_openrouter_show_rc" -eq 0 ] &&
   printf '%s\n' "$_openrouter_show" | grep -q '^default:     nvidia/nemotron-3-ultra-550b-a55b:free$' &&
   printf '%s\n' "$_openrouter_show" | grep -q '^context:     1000000 tokens$' &&
   printf '%s\n' "$_openrouter_show" | grep -q '^effort:      high$'; then
  ok "openrouter exposes the pinned Nemotron free model and context"
else
  bad "openrouter provider display is stale"
fi

_antigravity_show=$("$GATEWAY" provider show antigravity 2>&1)
_antigravity_show_rc=$?
if [ "$_antigravity_show_rc" -eq 0 ] &&
   printf '%s\n' "$_antigravity_show" | grep -q '^default:     gemini-3\.7-flash-tiered$' &&
   printf '%s\n' "$_antigravity_show" | grep -q '^context:     1048576 tokens$' &&
   printf '%s\n' "$_antigravity_show" | grep -q '^  opus:      gemini-3\.7-flash-tiered$' &&
   printf '%s\n' "$_antigravity_show" | grep -q '^  sonnet:    gemini-3\.7-flash-tiered$' &&
   printf '%s\n' "$_antigravity_show" | grep -q '^  haiku:     gemini-3\.7-flash-tiered$' &&
   printf '%s\n' "$_antigravity_show" | grep -q '^  subagent:  gemini-3\.7-flash-tiered$' &&
   printf '%s\n' "$_antigravity_show" | grep -q '^  extras:    gemini-3\.7-flash-tiered gemini-3\.5-flash-medium gemini-3\.1-pro-low$'; then
  ok "antigravity exposes the supported Gemini catalog and context"
else
  bad "antigravity exposes an unsupported Gemini catalog or context"
fi

_antigravity_claude_show=$("$GATEWAY" provider show antigravity-claude 2>&1)
_antigravity_claude_show_rc=$?
if [ "$_antigravity_claude_show_rc" -eq 0 ] &&
   printf '%s\n' "$_antigravity_claude_show" | grep -q '^default:     claude-opus-4-6-thinking$' &&
   printf '%s\n' "$_antigravity_claude_show" | grep -q '^context:     200000 tokens$' &&
   printf '%s\n' "$_antigravity_claude_show" | grep -q '^  opus:      claude-opus-4-6-thinking$' &&
   printf '%s\n' "$_antigravity_claude_show" | grep -q '^  sonnet:    claude-sonnet-4-6$' &&
   printf '%s\n' "$_antigravity_claude_show" | grep -q '^  haiku:     claude-sonnet-4-6$' &&
   printf '%s\n' "$_antigravity_claude_show" | grep -q '^  subagent:  claude-sonnet-4-6$' &&
   printf '%s\n' "$_antigravity_claude_show" | grep -q '^  extras:    gpt-oss-120b-medium$'; then
  ok "antigravity-claude exposes the supported Claude catalog and context"
else
  bad "antigravity-claude exposes an unsupported Claude catalog or context"
fi

# Pin Codex's configured model tiers and context at the public provider view.
_codex_show=$("$GATEWAY" provider show codex 2>&1)
_codex_show_rc=$?
if [ "$_codex_show_rc" -eq 0 ] &&
   printf '%s\n' "$_codex_show" | grep -q '^default:     gpt-5\.6-sol$' &&
   printf '%s\n' "$_codex_show" | grep -q '^context:     1050000 tokens$' &&
   printf '%s\n' "$_codex_show" | grep -q '^  opus:      gpt-5\.6-sol$' &&
   printf '%s\n' "$_codex_show" | grep -q '^  sonnet:    gpt-5\.6-terra$' &&
   printf '%s\n' "$_codex_show" | grep -q '^  haiku:     gpt-5\.6-luna$' &&
   printf '%s\n' "$_codex_show" | grep -q '^  subagent:  gpt-5\.6-luna$'; then
  ok "codex exposes the configured model tiers and context"
else
  bad "codex exposes incorrect configured model tiers or context"
fi
# codex uses icebear's proxy auth -> AUTH_MODE=none, never "dual".
if "$GATEWAY" list 2>/dev/null | awk '$1=="codex"{print $(NF-1)}' | grep -q '^none$'; then
  ok "codex reports none auth"
else
  bad "codex did not report none auth"
fi

# provider show must reveal the official API contract without leaking secrets.
_show=$("$GATEWAY" provider anthropic 2>&1)
if printf '%s\n' "$_show" | grep -q '^auth:        env$' &&
   printf '%s\n' "$_show" | grep -q '^  reference: ANTHROPIC_API_KEY$' &&
   printf '%s\n' "$_show" | grep -q '^  keychain fallback: anthropic-api-key$' &&
   "$GATEWAY" help | grep -q 'crouter claude' &&
   "$GATEWAY" help | grep -q 'crouter all --check' &&
   "$GATEWAY" help | grep -q 'crouter --version'; then
  ok "provider show documents Anthropic API auth and help exposes native account login"
else
  bad "Anthropic API auth or native Claude account entry point is missing"
fi

# With no API key in the environment/Keychain, doctor must report MISSING.
if env -u ANTHROPIC_API_KEY -u ANTHROPIC_AUTH_TOKEN -u CLAUDE_CODE_OAUTH_TOKEN \
     CLAUDE_BIN="$MOCK_CLAUDE" "$GATEWAY" doctor anthropic 2>&1 | grep -q 'anthropic .*auth:MISSING'; then
  ok "doctor reports MISSING for an unconfigured Anthropic API provider"
else
  bad "doctor did not report MISSING for an unconfigured Anthropic API provider"
fi

# openrouter must explicitly blank ANTHROPIC_API_KEY (upstream requirement).
if "$GATEWAY" provider openrouter 2>&1 | grep -q '^  ANTHROPIC_API_KEY=$'; then
  ok "openrouter blanks ANTHROPIC_API_KEY via EXTRA_ENV"
else
  bad "openrouter does not blank ANTHROPIC_API_KEY"
fi

# --- local failover proxy: bearer default -> x-api-key fallback on 429 ------
NODE_FOR_TEST=$(command -v node 2>/dev/null || echo "")
[ -n "$NODE_FOR_TEST" ] || NODE_FOR_TEST=$(grep -m1 '^NODE_BIN=' "$ROOT_DIR/config.sh" 2>/dev/null | cut -d'"' -f2)
if [ -n "$NODE_FOR_TEST" ] && [ -x "$NODE_FOR_TEST" ]; then
  _tdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'crfail')
  cat > "$_tdir/mock.js" << 'MOCKEOF'
const http = require('http');
const seen = [];
const srv = http.createServer((req, res) => {
  const auth = req.headers['authorization'] || '';
  const xk = req.headers['x-api-key'] || '';
  seen.push(auth ? 'bearer' : (xk ? 'x-api-key' : 'none'));
  require('fs').writeFileSync(process.env.SEEN_FILE, seen.join(','));
  if (auth === 'Bearer def-token' && !xk) { res.writeHead(429).end('{}'); return; }
  if (xk === 'api-key' && !auth) { res.writeHead(200, {'content-type':'application/json'}).end('{"ok":true}'); return; }
  res.writeHead(400).end('{"error":"unexpected headers"}');
});
srv.listen(0, '127.0.0.1', () => {
  require('fs').writeFileSync(process.env.PORT_FILE, String(srv.address().port));
});
MOCKEOF
  SEEN_FILE="$_tdir/seen" PORT_FILE="$_tdir/port" "$NODE_FOR_TEST" "$_tdir/mock.js" >/dev/null 2>&1 &
  _mock_pid=$!
  _i=0; while [ $_i -lt 30 ] && [ ! -s "$_tdir/port" ]; do sleep 0.1; _i=$((_i+1)); done
  _mp=$(cat "$_tdir/port" 2>/dev/null)
  if [ -n "$_mp" ]; then
    _cands="[{\"url\":\"http://127.0.0.1:$_mp\",\"type\":\"bearer\",\"token\":\"def-token\",\"label\":\"default-account\"},{\"url\":\"http://127.0.0.1:$_mp\",\"type\":\"x-api-key\",\"token\":\"api-key\",\"label\":\"api-key\"}]"
    KEYPOOL_CANDIDATES="$_cands" KEYPOOL_PORT=0 "$NODE_FOR_TEST" "$ROOT_DIR/bin/keypool-proxy" > "$_tdir/proxy.out" 2>/dev/null &
    _px_pid=$!
    _i=0; _pp=""
    while [ $_i -lt 30 ]; do
      _pp=$(grep -m1 '^KEYPOOL_LISTENING_PORT=' "$_tdir/proxy.out" 2>/dev/null | cut -d= -f2)
      [ -n "$_pp" ] && break; sleep 0.1; _i=$((_i+1))
    done
    if [ -n "$_pp" ]; then
      _code=$(curl -s -o "$_tdir/body" -w '%{http_code}' -X POST "http://127.0.0.1:$_pp/v1/messages" \
        -H 'content-type: application/json' -d '{"model":"x"}' 2>/dev/null)
      _seen=$(cat "$_tdir/seen" 2>/dev/null)
      if [ "$_code" = "200" ]; then
        ok "dual-source failover: 429 on default account falls back to the API key"
      else
        bad "dual-source failover returned HTTP $_code (expected 200)"
      fi
      if [ "$_seen" = "bearer,x-api-key" ]; then
        ok "dual-source failover sends Bearer first, then x-api-key (never both)"
      else
        bad "dual-source failover sent the wrong header sequence: '$_seen'"
      fi
    else
      bad "dual-source failover proxy did not start"
    fi
    kill "$_px_pid" 2>/dev/null
  else
    bad "dual-source failover mock upstream did not start"
  fi
  kill "$_mock_pid" 2>/dev/null
  rm -rf "$_tdir"
else
  ok "dual-source failover test skipped (no node available)"
fi

[ "$fail" -eq 0 ] && echo "All smoke tests passed." || echo "Some smoke tests FAILED."
exit "$fail"
