#!/bin/sh
# The model picker is the selection surface of crouter: which catalog it shows,
# which state it writes, and the difference between "selected" and "cancelled"
# must all be observable and correct.
#
# Covered here:
#   CAT-01  a provider that declares only BASE_URL still gets its catalog probed
#   CFG-04  selecting a model with an unknown window clears the previous window
#   CAT-03  a missing fee rate shows as unknown, "free input, paid output" is
#           not reported as free, and a rate is read in every shape the real
#           catalogs use (prompt/completion, input/output, per-token, tiered)
#   UX-02   "q" is an ordinary filter character; Esc and stdin EOF cancel
#   CFG-03  cancelling the picker launches nothing and changes no state
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node 2>/dev/null || true)}
[ -n "$NODE_BIN" ] || { printf 'skip  node not available\n'; exit 0; }
command -v python3 >/dev/null 2>&1 || { printf 'skip  python3 not available; no pty fixture\n'; exit 0; }

TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-model-picker)
UPSTREAM_PID=
trap 'rm -rf "$TMP_DIR"; [ -n "$UPSTREAM_PID" ] && kill "$UPSTREAM_PID" 2>/dev/null || true' EXIT INT TERM

STATE_DIR="$TMP_DIR/state"
export XDG_STATE_HOME="$STATE_DIR"
CR_STATE="$STATE_DIR/crouter"
mkdir -p "$CR_STATE"

PICKER_TIMEOUT=${PICKER_TIMEOUT:-20}

fail() { printf 'FAIL  %s\n' "$1" >&2; exit 1; }
strip_ansi() { sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g'; }

# Run the picker on a pseudo terminal. The helper reports a timeout instead of
# letting the suite hang, so a stuck picker names the case that stuck.
drive_picker() {
  _label=$1
  shift
  _out=$(python3 "$ROOT_DIR/test/model-picker-tty.py" --timeout "$PICKER_TIMEOUT" "$@" 2>&1) || _rc=$?
  _rc=${_rc:-0}
  if [ "$_rc" -eq 124 ]; then
    fail "$_label: the picker did not finish within ${PICKER_TIMEOUT}s"
  fi
  _rc=
  printf '%s' "$_out" | strip_ansi
}

# --- a local catalog endpoint -----------------------------------------------
cat > "$TMP_DIR/catalog.js" <<'EOF'
const http = require('http');
const fs = require('fs');
const catalog = JSON.parse(fs.readFileSync(process.env.CATALOG_FILE, 'utf8'));
const server = http.createServer((req, res) => {
  if (req.url.startsWith('/v1/models')) {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ data: catalog }));
    return;
  }
  res.writeHead(404, { 'content-type': 'application/json' });
  res.end('{"error":"not found"}');
});
server.listen(0, '127.0.0.1', () => {
  fs.writeFileSync(process.env.PORT_FILE, String(server.address().port));
});
EOF

start_catalog() {
  CATALOG_FILE="$TMP_DIR/catalog.json"
  printf '%s' "$1" > "$CATALOG_FILE"
  # Each case starts from an empty catalog cache: the picker caches for a day,
  # which would otherwise hide the catalog a case just published.
  rm -f "$CR_STATE/models-demo.json" "$CR_STATE/openrouter-models-cache.json"
  rm -f "$TMP_DIR/upstream-port"
  CATALOG_FILE="$CATALOG_FILE" PORT_FILE="$TMP_DIR/upstream-port" \
    "$NODE_BIN" "$TMP_DIR/catalog.js" >/dev/null 2>&1 &
  UPSTREAM_PID=$!
  _i=0
  while [ $_i -lt 50 ]; do
    [ -s "$TMP_DIR/upstream-port" ] && break
    sleep 0.1
    _i=$((_i + 1))
  done
  UPSTREAM_PORT=$(cat "$TMP_DIR/upstream-port" 2>/dev/null || true)
  [ -n "$UPSTREAM_PORT" ] || fail 'the local catalog did not start'
}

run_picker() {
  env CR_PROVIDER=demo "CR_BASE_URL=http://127.0.0.1:$UPSTREAM_PORT" \
    CR_MODELS_API_URL= CR_MODELS_API_AUTH=none CR_API_KEY= CR_STATIC_MODELS= "$NODE_BIN" "$ROOT_DIR/bin/crouter-models" --provider demo "$@"
}

# --- CAT-01: a provider with only BASE_URL still gets its catalog ----------
start_catalog '[{"id":"local-model","name":"Local Model","context_length":4096,
                  "pricing":{"prompt":"0.000001","completion":"0.000002"}}]'
out=$(run_picker --list 2>/dev/null || true)
printf '%s' "$out" | grep -q 'local-model' || \
  fail 'CAT-01: a provider that declares only BASE_URL was not probed for its catalog'
printf 'ok    CAT-01  a BASE_URL-only provider is probed for its catalog\n'

# --- CFG-04: an unknown window clears the previous window -------------------
printf 'old-model\n' > "$CR_STATE/last-model-demo"
printf '200000\n' > "$CR_STATE/demo-context"
start_catalog '[{"id":"new-model","name":"New Model","context_length":0,"pricing":{}}]'
run_picker --set new-model >/dev/null 2>&1 || fail 'CFG-04: --set did not apply the model'
[ "$(cat "$CR_STATE/last-model-demo")" = 'new-model' ] || fail 'CFG-04: the model was not recorded'
if [ -s "$CR_STATE/demo-context" ]; then
  fail 'CFG-04: the previous window survived a model whose window is unknown'
fi
printf 'ok    CFG-04  selecting a model with an unknown window clears the old one\n'

# --- CAT-03: unknown fees stay unknown, paid output is not free ------------
start_catalog '[{"id":"no-price","name":"No Price","context_length":1000},
                  {"id":"paid-output","name":"Paid Output","context_length":1000,
                   "pricing":{"prompt":"0","completion":"0.000002"}},
                  {"id":"real-free","name":"Real Free","context_length":1000,
                   "pricing":{"prompt":"0","completion":"0"}}]'
free_list=$(run_picker --list-free 2>/dev/null || true)
printf '%s' "$free_list" | grep -q 'real-free' || fail 'CAT-03: a genuinely free model was filtered out'
printf '%s' "$free_list" | grep -q 'paid-output' && \
  fail 'CAT-03: a model with paid output was reported as free'
printf '%s' "$free_list" | grep -q 'no-price' && \
  fail 'CAT-03: a model without pricing was reported as free'
printf 'ok    CAT-03  free filtering needs both input and output to be free\n'

# --- CAT-03 (display): the picker shows unknown instead of a zero price -----
start_catalog '[{"id":"no-price","name":"No Price","context_length":1000},
                  {"id":"paid-output","name":"Paid Output","context_length":1000,
                   "pricing":{"prompt":"0","completion":"0.000002"}},
                  {"id":"real-free","name":"Real Free","context_length":1000,
                   "pricing":{"prompt":"0","completion":"0"}}]'
tui_out=$(drive_picker 'CAT-03 display' --keys "$(printf '\033')" -- \
  env CR_PROVIDER=demo "CR_BASE_URL=http://127.0.0.1:$UPSTREAM_PORT" \
    CR_MODELS_API_URL= CR_MODELS_API_AUTH=none CR_API_KEY= CR_STATIC_MODELS= "$NODE_BIN" "$ROOT_DIR/bin/crouter-models" --provider demo)
printf '%s' "$tui_out" | grep -q 'Cancelled\.' || fail 'CAT-03: Esc did not cancel the picker'
line=$(printf '%s' "$tui_out" | grep 'no-price' | tail -1)
[ -n "$line" ] || fail 'CAT-03: the picker did not render the model without pricing'
printf '%s' "$line" | grep -q 'unknown' || \
  fail 'CAT-03: a model without pricing was displayed with a price'
line=$(printf '%s' "$tui_out" | grep 'paid-output' | tail -1)
printf '%s' "$line" | grep -q 'FREE' && \
  fail 'CAT-03: a model with paid output was displayed as FREE'
printf 'ok    CAT-03  the picker shows an unknown fee instead of a zero price\n'

# --- CAT-03 (shapes): the rate shapes the real catalogs use ------------------
# OpenRouter reports prompt/completion, Vercel reports input/output, NagaAI
# reports per_input_token/per_output_token, and Requesty lists tiered rows.
# A rate written in any of those shapes is a known rate; only a shape the
# picker cannot read stays unknown.
start_catalog '[{"id":"tier-free","name":"Tier Free","context_length":1000,
                  "pricing":[{"prompt_tokens_threshold":0,"input_price":0,"output_price":0}]},
                 {"id":"tier-paid","name":"Tier Paid","context_length":1000,
                  "pricing":[{"prompt_tokens_threshold":0,"input_price":5e-7,"output_price":2.5e-6}]},
                 {"id":"v-input","name":"V Input","context_length":1000,
                  "pricing":{"input":"0.00000012","output":"0.00000024"}},
                 {"id":"n-per-token","name":"N Per Token","context_length":1000,
                  "pricing":{"per_input_token":0,"per_cached_input_token":0,"per_output_token":0}},
                 {"id":"n-paid","name":"N Paid","context_length":1000,
                  "pricing":{"per_input_token":1e-6,"per_output_token":5e-6}},
                 {"id":"empty-price","name":"Empty Price","context_length":1000,"pricing":{}}]'
free_list=$(run_picker --list-free 2>/dev/null || true)
for id in tier-free n-per-token; do
  printf '%s' "$free_list" | grep -q "\"$id\"" || \
    fail "CAT-03: $id was not recognised as free"
done
for id in tier-paid v-input n-paid empty-price; do
  printf '%s' "$free_list" | grep -q "\"$id\"" && \
    fail "CAT-03: $id was reported as free"
done
tui_out=$(drive_picker 'CAT-03 shapes' --keys "$(printf '\033')" -- \
  env CR_PROVIDER=demo "CR_BASE_URL=http://127.0.0.1:$UPSTREAM_PORT" \
    CR_MODELS_API_URL= CR_MODELS_API_AUTH=none CR_API_KEY= CR_STATIC_MODELS= "$NODE_BIN" "$ROOT_DIR/bin/crouter-models" --provider demo)
line=$(printf '%s' "$tui_out" | grep 'n-paid' | tail -1)
printf '%s' "$line" | grep -q '\$1\.00/\$5\.00' || \
  fail 'CAT-03: a per-token rate was not displayed as a price'
line=$(printf '%s' "$tui_out" | grep 'tier-paid' | tail -1)
printf '%s' "$line" | grep -q '\$0\.50/\$2\.50' || \
  fail 'CAT-03: a tiered rate was not displayed as a price'
line=$(printf '%s' "$tui_out" | grep 'v-input' | tail -1)
printf '%s' "$line" | grep -q '\$0\.12/\$0\.24' || \
  fail 'CAT-03: an input/output rate was not displayed as a price'
line=$(printf '%s' "$tui_out" | grep 'empty-price' | tail -1)
printf '%s' "$line" | grep -q 'unknown' || \
  fail 'CAT-03: an unreadable rate was not shown as unknown'
printf 'ok    CAT-03  rates are read in every shape the catalogs use\n'

# --- UX-02: "q" filters, Esc cancels ----------------------------------------
# "q" is typed into the filter, Esc then cancels: the picker must not treat "q"
# as a quit key, and the filter line must show the typed character.
start_catalog '[{"id":"quokka","name":"Quokka","context_length":1000,"pricing":{}}]'
tui_out=$(drive_picker 'UX-02' --keys "$(printf 'q\033')" -- \
  env CR_PROVIDER=demo "CR_BASE_URL=http://127.0.0.1:$UPSTREAM_PORT" \
    CR_MODELS_API_URL= CR_MODELS_API_AUTH=none CR_API_KEY= CR_STATIC_MODELS= "$NODE_BIN" "$ROOT_DIR/bin/crouter-models" --provider demo)
printf '%s' "$tui_out" | grep -q 'Filter: q' || \
  fail 'UX-02: typing "q" did not filter the list'
printf '%s' "$tui_out" | grep -q 'Cancelled\.' || \
  fail 'UX-02: Esc did not cancel the picker'
printf 'ok    UX-02  "q" is an ordinary filter character\n'

# --- UX-01: the end of the input stream cancels ----------------------------
# Two ways the input can end without a decision: a pipe that reaches its end
# (stdin is not a terminal, so no raw mode) and a terminal that goes away
# (raw mode cannot deliver an EOF, so it arrives as a hangup). Both must
# cancel the picker instead of leaving it waiting for a key.
start_catalog '[{"id":"quokka","name":"Quokka","context_length":1000,"pricing":{}}]'
tui_out=$(drive_picker 'UX-01 pipe EOF' --stdin /dev/null -- \
  env CR_PROVIDER=demo "CR_BASE_URL=http://127.0.0.1:$UPSTREAM_PORT" \
    CR_MODELS_API_URL= CR_MODELS_API_AUTH=none CR_API_KEY= CR_STATIC_MODELS= "$NODE_BIN" "$ROOT_DIR/bin/crouter-models" --provider demo)
printf '%s' "$tui_out" | grep -q 'Cancelled\.' || \
  fail 'UX-01: the end of the input stream did not cancel the picker'
printf '%s' "$tui_out" | grep -q 'exit=2' || \
  fail 'UX-01: the picker did not report a cancelled exit code'
tui_out=$(drive_picker 'UX-01 terminal hangup' --hangup-after 1 -- \
  env CR_PROVIDER=demo "CR_BASE_URL=http://127.0.0.1:$UPSTREAM_PORT" \
    CR_MODELS_API_URL= CR_MODELS_API_AUTH=none CR_API_KEY= CR_STATIC_MODELS= "$NODE_BIN" "$ROOT_DIR/bin/crouter-models" --provider demo)
printf '%s' "$tui_out" | grep -q 'Cancelled\.' || \
  fail 'UX-01: a terminal that went away did not cancel the picker'
printf '%s' "$tui_out" | grep -q 'exit=2' || \
  fail 'UX-01: the picker did not report a cancelled exit code'
printf 'ok    UX-01  the end of the input stream cancels the picker\n'

# --- CFG-03: cancelling the picker launches nothing ------------------------
FAKE_ROOT="$TMP_DIR/repo"
FAKE_BIN="$TMP_DIR/bin"
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/lib" "$FAKE_ROOT/providers" "$FAKE_BIN"
cp "$ROOT_DIR/bin/crouter" "$ROOT_DIR/bin/crouter-models" "$FAKE_ROOT/bin/"
cp "$ROOT_DIR/lib/"*.sh "$ROOT_DIR/lib/"*.js "$ROOT_DIR/lib/"*.mjs "$FAKE_ROOT/lib/" 2>/dev/null || true
printf 'test\n' > "$FAKE_ROOT/VERSION"

cat > "$FAKE_ROOT/providers/demo.sh" <<'EOF'
PROVIDER_NAME="demo"
BASE_URL="https://demo.example.invalid/anthropic"
MODEL="demo-model"
AUTH_MODE="none"
PRE_START='printf started > "$HOOK_SPY"'
EOF

cat > "$FAKE_BIN/claude" <<'EOF'
#!/bin/sh
printf launched > "$CLAUDE_SPY"
exit 0
EOF
chmod +x "$FAKE_BIN/claude"

printf 'old-model\n' > "$CR_STATE/last-model-demo"
rm -f "$TMP_DIR/claude-spy"
# shellcheck disable=SC2086
drive_picker 'CFG-03' --keys "$(printf '\033')" -- \
  env HOOK_SPY="$TMP_DIR/hook-spy" CLAUDE_SPY="$TMP_DIR/claude-spy" NODE_BIN="$NODE_BIN" \
      PATH="$FAKE_BIN:$PATH" XDG_STATE_HOME="$STATE_DIR" \
      sh "$FAKE_ROOT/bin/crouter" demo --browse \
  >/dev/null

[ -e "$TMP_DIR/claude-spy" ] && fail 'CFG-03: cancelling the picker still launched Claude Code'
[ "$(cat "$CR_STATE/last-model-demo")" = 'old-model' ] || \
  fail 'CFG-03: cancelling the picker changed the selected model'
printf 'ok    CFG-03  cancelling the picker launches nothing and changes no state\n'
