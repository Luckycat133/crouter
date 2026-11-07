#!/bin/sh
# Catalog, pricing, terminal cancellation and prelaunch isolation. No real keys.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node 2>/dev/null || true)}
[ -n "$NODE_BIN" ] || { echo 'skip node missing'; exit 0; }
command -v python3 >/dev/null 2>&1 || { echo 'skip python3 missing'; exit 0; }
TMP_DIR=$(mktemp -d)
UPSTREAM_PID=
cleanup() {
  if [ -n "$UPSTREAM_PID" ]; then kill "$UPSTREAM_PID" 2>/dev/null || true; wait "$UPSTREAM_PID" 2>/dev/null || true; fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM
export XDG_STATE_HOME="$TMP_DIR/state" ROOT_DIR NODE_BIN
CR_STATE="$XDG_STATE_HOME/crouter"
mkdir -p "$CR_STATE"
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
# A real argv-building wrapper replaces env $(picker_env): no word splitting,
# no suppression of ShellCheck SC2046, and paths containing spaces survive.
cat > "$TMP_DIR/picker" <<'EOF'
#!/bin/sh
exec env CR_PROVIDER=demo CR_BASE_URL="http://127.0.0.1:$UPSTREAM_PORT" \
 CR_MODELS_API_URL= CR_MODELS_API_AUTH=none CR_MODELS_API_SURFACE=public \
 CR_MODELS_DISCOVERY=auto CR_API_KEY= CR_STATIC_MODELS= \
 "$NODE_BIN" "$ROOT_DIR/bin/crouter-models" --provider demo "$@"
EOF
chmod +x "$TMP_DIR/picker"
cat > "$TMP_DIR/server.js" <<'EOF'
const http = require('node:http'), fs = require('node:fs');
http.createServer((req,res) => {
  if (req.url.startsWith('/v1/models')) {res.writeHead(200, {'content-type':'application/json'}); res.end(JSON.stringify({data:JSON.parse(fs.readFileSync(process.env.CATALOG_FILE,'utf8'))}));}
  else {res.writeHead(404);res.end('{}');}
}).listen(0,'127.0.0.1',function(){fs.writeFileSync(process.env.PORT_FILE,String(this.address().port));});
EOF
CATALOG_FILE="$TMP_DIR/catalog.json" PORT_FILE="$TMP_DIR/port"
export CATALOG_FILE PORT_FILE
printf '[]' > "$CATALOG_FILE"
"$NODE_BIN" "$TMP_DIR/server.js" &
UPSTREAM_PID=$!
i=0
while [ ! -s "$PORT_FILE" ]; do i=$((i+1)); [ "$i" -lt 50 ] || fail 'catalog start timeout'; sleep 0.1; done
UPSTREAM_PORT=$(cat "$PORT_FILE"); export UPSTREAM_PORT
catalog() { printf '%s' "$1" > "$CATALOG_FILE"; rm -f "$CR_STATE/models-demo.json"; }
run_picker() { "$TMP_DIR/picker" "$@"; }
pty_run() { python3 "$ROOT_DIR/test/model-picker-tty.py" --timeout 12 "$@"; }
catalog '[{"id":"local-model","context_length":4096}]'
run_picker --list | grep -q 'local-model' || fail 'BASE_URL catalog'
printf 'ok CAT-01 BASE_URL directory\n'
printf 'old\n' > "$CR_STATE/last-model-demo"; printf '200000\n' > "$CR_STATE/demo-context"
catalog '[{"id":"unknown","context_length":0}]'
run_picker --set unknown >/dev/null
[ ! -e "$CR_STATE/demo-context" ] || fail 'stale context retained'
printf 'ok CFG-04 unknown context cleared\n'
catalog '[{"id":"unknown"},{"id":"paid-output","pricing":{"prompt":"0","completion":"0.000002"}},{"id":"free","pricing":{"prompt":"0","completion":"0"}}]'
run_picker --list-free > "$TMP_DIR/free"
grep -q '"free"' "$TMP_DIR/free" || fail 'free absent'
if grep -Eq 'unknown|paid-output' "$TMP_DIR/free"; then fail 'unknown/paid reported free'; fi
out=$(pty_run --keys "$(printf '\033')" -- "$TMP_DIR/picker")
printf '%s' "$out" | grep -q 'unknown' || fail 'unknown price display'
printf '%s' "$out" | grep -q 'exit=2' || fail 'Esc did not cancel'
printf 'ok CAT-03 missing rates and charged output\n'
catalog '[{"id":"tier","pricing":[{"prompt_tokens_threshold":0,"input_price":0.0000005,"output_price":0.0000025}]},{"id":"per-token","pricing":{"per_input_token":0.000001,"per_output_token":0.000005}},{"id":"input-output","pricing":{"input":"0.00000012","output":"0.00000024"}},{"id":"tier-free","pricing":[{"prompt_tokens_threshold":0,"input_price":0,"output_price":0}]},{"id":"per-free","pricing":{"per_input_token":0,"per_output_token":0}}]'
out=$(pty_run --keys "$(printf '\033')" -- "$TMP_DIR/picker")
for price in '$0.50/$2.50' '$1.00/$5.00' '$0.12/$0.24'; do printf '%s' "$out" | grep -Fq "$price" || fail "price shape: $price"; done
run_picker --list-free > "$TMP_DIR/free"
for id in tier-free per-free; do grep -q "$id" "$TMP_DIR/free" || fail "$id absent"; done
printf 'ok CAT-03 rate shapes\n'
catalog '[{"id":"qwen","name":"Qwen"}]'
out=$(pty_run --keys "$(printf 'q\033')" -- "$TMP_DIR/picker")
printf '%s' "$out" | grep -q 'Filter: q' || fail 'q was not a search character'
printf '%s' "$out" | grep -q 'exit=2' || fail 'cancel status'
printf 'ok UX-02 q filters\n'
out=$(pty_run --stdin /dev/null -- "$TMP_DIR/picker")
printf '%s' "$out" | grep -q 'exit=2' || fail 'EOF cancellation'
out=$(pty_run --hangup-after 1 -- "$TMP_DIR/picker")
printf '%s' "$out" | grep -q 'exit=2' || fail 'HUP cancellation'
printf 'ok UX-01 EOF and HUP cancel\n'
FAKE_ROOT="$TMP_DIR/repo"
mkdir -p "$FAKE_ROOT/bin" "$FAKE_ROOT/lib" "$FAKE_ROOT/providers"
cp "$ROOT_DIR/bin/crouter" "$ROOT_DIR/bin/crouter-models" "$FAKE_ROOT/bin/"
for f in "$ROOT_DIR"/lib/*.sh "$ROOT_DIR"/lib/*.js "$ROOT_DIR"/lib/*.mjs; do [ ! -f "$f" ] || cp "$f" "$FAKE_ROOT/lib/"; done
printf 'test\n' > "$FAKE_ROOT/VERSION"
# These boundaries must not be reached on cancellation. Use spies instead of
# real credential stores or background services, even on a configured host.
for module in auth assets key-mgmt; do printf ':\n' > "$FAKE_ROOT/lib/$module.sh"; done
cat > "$FAKE_ROOT/lib/auth.sh" <<'EOF'
is_dual_source() { return 1; }
resolve_auth() { printf auth > "$HOOK_SPY"; }
EOF
cat > "$FAKE_ROOT/lib/assets.sh" <<'EOF'
prepare_provider_assets() { printf assets > "$HOOK_SPY"; }
cleanup_provider_assets() { :; }
EOF
cat > "$FAKE_ROOT/lib/launch.sh" <<'EOF'
launch_claude() { shift 2; "$CLAUDE_BIN" "$@"; }
EOF
cat > "$FAKE_ROOT/providers/demo.sh" <<'EOF'
PROVIDER_NAME=demo
BASE_URL=https://example.invalid
MODEL=old-model
AUTH_MODE=none
MODELS_DISCOVERY=static
PRE_START='printf started > "$HOOK_SPY"'
EOF
cat > "$TMP_DIR/claude" <<EOF
#!/bin/sh
printf launched > '$TMP_DIR/claude-spy'
EOF
chmod +x "$TMP_DIR/claude"
printf 'old-model\n' > "$CR_STATE/last-model-demo"
out=$(pty_run --keys "$(printf '\033')" -- env HOOK_SPY="$TMP_DIR/hook-spy" CLAUDE_BIN="$TMP_DIR/claude" CROUTER_PROVIDER_ASSETS=0 "${TEST_SHELL:-sh}" "$FAKE_ROOT/bin/crouter" demo --browse)
[ ! -e "$TMP_DIR/claude-spy" ] || fail 'cancel launched Claude'
[ ! -e "$TMP_DIR/hook-spy" ] || fail 'cancel ran PRE_START'
[ "$(cat "$CR_STATE/last-model-demo")" = old-model ] || fail 'cancel changed state'
printf '%s' "$out" | grep -q 'exit=0' || fail 'dispatcher cancel failed'
printf 'ok CFG-03 cancel has no launch/hook side effects\n'
