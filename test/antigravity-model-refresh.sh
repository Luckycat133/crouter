#!/bin/sh
# Standalone model IDs only: no account, proxy startup, GPU or inference.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROVIDERS_DIR="$ROOT_DIR/providers"
_refresh_tmp=$(mktemp -d)
trap 'rm -rf "$_refresh_tmp"' EXIT INT TERM
HOME="$_refresh_tmp/home"
XDG_STATE_HOME="$_refresh_tmp/state"
XDG_DATA_HOME="$_refresh_tmp/data"
export HOME XDG_STATE_HOME XDG_DATA_HOME
mkdir -p "$HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"
die() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
. "$ROOT_DIR/lib/provider.sh"
has_word() { case " $2 " in *" $1 "*) ;; *) die "missing model $1" ;; esac; }

load_provider antigravity
[ "$MODELS_ACCOUNT_LIVE" = 1 ] || die 'Antigravity selectable models must use the live account directory'
[ "$MODEL" = gemini-3.8-flash ] || die 'unexpected change to Gemini default'
for model in \
  gemini-4-neon-low gemini-4-neon-medium gemini-4-neon-high gemini-4-neon-xhigh \
  gemini-4-carbon-low gemini-4-carbon-medium gemini-4-carbon-high \
  gemini-4-argon-low gemini-4-argon-medium gemini-4-argon-high \
  gemini-4-hydrogen-low gemini-4-hydrogen-medium gemini-4-hydrogen-high gemini-4-hydrogen-xhigh \
  gemini-3.8-flash-low gemini-3.8-flash-medium gemini-3.8-flash-high; do
  has_word "$model" "$MODEL_ALIASES"
done
[ "$(resolve_model_id gemini-4-argon)" = gemini-4-argon-medium ] || die 'Argon alias'
for level in low medium high; do
  [ "$(resolve_model_id "gemini-4-argon-$level")" = "gemini-4-argon-$level" ] || die 'Argon must remain selectable when the account directory offers it'
done
[ "$(resolve_model_id gemini-4-neon)" = gemini-4-neon-high ] || die 'Neon alias'
[ "$(resolve_model_id gemini-4-carbon)" = gemini-4-carbon-medium ] || die 'Carbon alias'
for level in low medium high xhigh; do
  load_provider antigravity
  apply_model_context_override "gemini-4-neon-$level"
  [ "$CONTEXT_TOKENS" = 1048576 ] || die "stale Neon context for $level"
done
for family in carbon argon hydrogen; do
  load_provider antigravity
  apply_model_context_override "gemini-4-$family-high"
  [ "$CONTEXT_TOKENS" = 1048576 ] || die "Gemini context mismatch for $family"
done
case "$MODEL $MODEL_ALIASES $MODEL_ID_ALIASES" in *orchestrator*) die 'Orchestrator is not a standalone Messages model' ;; esac

load_provider antigravity-claude
[ "$MODELS_ACCOUNT_LIVE" = 1 ] || die 'Claude selectable models must use the live account directory'
[ "$MODEL" = claude-opus-5-5-medium ] || die 'Claude default'
[ "$MODEL_SONNET" = claude-sonnet-5-5-medium ] || die 'Claude Sonnet tier'
[ "$CONTEXT_TOKENS" = 1000000 ] || die 'stale Claude 5.5 default context'
for family in opus sonnet; do
  [ "$(resolve_model_id "claude-$family-5-5")" = "claude-$family-5-5-medium" ] || die 'bare Claude 5.5 must not reach legacy proxy alias'
  for level in low medium high max; do
    id="claude-$family-5-5-$level"
    has_word "$id" "$MODEL $MODEL_OPUS $MODEL_SONNET $MODEL_ALIASES"
    # max remains a historical compatibility seed, not an account entitlement.
    if [ "$level" != max ]; then
      apply_model_context_override "$id"
      [ "$CONTEXT_TOKENS" = 1000000 ] || die "Claude 5.5 context mismatch $id"
    fi
    apply_model_effort_override "$id"
    [ "$EFFORT" = "$level" ] || die "effort mismatch $id"
  done
done
apply_model_self_route claude-opus-5-5-medium
[ "$MODEL_SONNET" = claude-sonnet-5-5-medium ] || die 'default cheap tier was collapsed'
case "$MODEL $MODEL_ALIASES" in *orchestrator*) die 'Orchestrator catalog leak' ;; esac
case "$MODEL $MODEL_ALIASES $MODEL_SELF_ROUTE_MODELS" in *gpt-oss*) die 'Removed GPT-OSS integration leaked into provider declarations' ;; esac
[ ! -e "$ROOT_DIR/bin/antigravity-proxy-patch" ] || die 'Removed proxy patch installer is still present'

load_provider openrouter
[ -z "$MODELS_ACCOUNT_LIVE" ] || die 'account-live policy leaked to an unrelated provider'

# Resolve the installed copy without changing explicit or old nested installs.
_refresh_old_root=$ROOT_DIR
ROOT_DIR="$_refresh_tmp/repo"
mkdir -p "$ROOT_DIR"
[ "$(antigravity_proxy_dir)" = "$XDG_DATA_HOME/crouter/antigravity-claude-proxy" ] || die 'installed path fallback'
mkdir -p "$ROOT_DIR/antigravity-claude-proxy"
[ "$(antigravity_proxy_dir)" = "$ROOT_DIR/antigravity-claude-proxy" ] || die 'nested path compatibility'
ANTIGRAVITY_PROXY_DIR="$_refresh_tmp/custom"
[ "$(antigravity_proxy_dir)" = "$ANTIGRAVITY_PROXY_DIR" ] || die 'explicit path precedence'
ROOT_DIR=$_refresh_old_root

# Fixed metadata snapshot from the reviewed local account directory. Exercise
# the real account-live reader through loopback; no account or inference calls.
if command -v node >/dev/null 2>&1; then
  node - "$ROOT_DIR" <<'EOF'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const {once} = require('node:events');
const root = process.argv[2];
const {loadAccountLiveCatalog} = require(root + '/lib/account-live-catalog.js');
const fixture = JSON.parse(fs.readFileSync(root + '/test/fixtures/antigravity-model-limits-2026-11-28.json', 'utf8'));
async function main() {
  const server = http.createServer((request, response) => {
    assert.equal(request.url, '/v1/models');
    assert.equal(request.headers.authorization, undefined);
    assert.equal(request.headers['x-api-key'], undefined);
    response.end(JSON.stringify({data: fixture.models}));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    for (const [provider, prefix, count] of [['antigravity', 'gemini-', 21], ['antigravity-claude', 'claude-', 6]]) {
      const result = await loadAccountLiveCatalog({
        CR_PROVIDER: provider, CR_MODELS_ACCOUNT_LIVE: '1',
        CR_CATALOG_SOURCE_URL: base, CR_MODELS_API_URL: base + '/v1/models', CR_MODELS_API_AUTH: 'none'
      }, {candidateUrls: [base]});
      const expected = fixture.models.filter(model => model.id.startsWith(prefix));
      assert.equal(result.status, 'available');
      assert.equal(result.models.length, count);
      assert.deepEqual(result.models.map(({id, context_length, max_output_tokens}) => ({id, context_length, max_output_tokens})), expected);
    }
  } finally {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
EOF
else
  printf '%s\n' 'skip Antigravity metadata fixture: node unavailable'
fi
printf '%s\n' 'ok Antigravity standalone Gemini 4 / Claude 5.5 IDs, exact aliases, limits, effort, and installed path'
