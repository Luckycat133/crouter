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
MODEL_ALIASES='success-model failure-model saved-model favorite-model'
MODEL_CONTEXT_OVERRIDES='success-model=9000 failure-model=4000 favorite-model=6100'
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

out=$(pty_run --send-after 'Enter 确认' "$(printf 'success-model\r')" -- env HOOK_SPY="$TMP_DIR/hook-spy" \
  CLAUDE_BIN="$TMP_DIR/claude" "${TEST_SHELL:-sh}" "$FAKE_ROOT/bin/crouter" demo --browse --plan)
printf '%s' "$out" | grep -Fq '"model": "success-model"' || fail 'browse did not produce the selected plan'
printf '%s' "$out" | grep -Fq '"contextTokens": 9000' || fail 'browse did not share the explicit model context'
[ "$(cat "$CR_STATE/last-model-demo")" = old-model ] || fail 'browse preview wrote an unconfirmed model'
[ ! -e "$TMP_DIR/hook-spy" ] || fail 'browse preview ran PRE_START'
printf 'ok CFG-01 browse and explicit selection use the same planner\n'

# Start at the bare dispatcher with a PTY. The real launcher drops ambient
# variables; its Claude stand-in returns distinct statuses from the child env.
cp "$ROOT_DIR/lib/launch.sh" "$FAKE_ROOT/lib/"
cat > "$TMP_DIR/claude" <<'EOF'
#!/bin/sh
printf 'child:%s:%s\n' "$ANTHROPIC_MODEL" "${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-}"
[ "$ANTHROPIC_MODEL" != failure-model ] || exit 7
[ -t 0 ] || cat
EOF
cat > "$FAKE_ROOT/lib/auth.sh" <<'EOF'
is_dual_source() { return 1; }
resolve_auth() { :; }
EOF
runner() { env HOOK_SPY="$TMP_DIR/hook-spy" CLAUDE_BIN="$TMP_DIR/claude" "${TEST_SHELL:-sh}" "$FAKE_ROOT/bin/crouter" "$@"; }
runner demo --model old-model --set-default >/dev/null
before=$(cksum "$CR_STATE/selection" "$CR_STATE/last-model-demo" "$CR_STATE/selection-demo.json")
home_action() {
  pty_run --send-after '请选择：' "$(printf '1\r')" --send-after 'Ctrl-S 保存为默认' "$1" \
    --send-after '请选择：' "$(printf 'q\r')" -- env HOOK_SPY="$TMP_DIR/hook-spy" CLAUDE_BIN="$TMP_DIR/claude" \
    "${TEST_SHELL:-sh}" "$FAKE_ROOT/bin/crouter"
}
out=$(home_action "$(printf 'failure-model\r')")
printf '%s' "$out" | grep -Fq 'child:failure-model:4000' || fail 'home did not dispatch the selection'
printf '%s' "$out" | grep -Fq '退出码 7' || fail 'home hid Claude failure'
[ "$before" = "$(cksum "$CR_STATE/selection" "$CR_STATE/last-model-demo" "$CR_STATE/selection-demo.json")" ] || fail 'home launch failure changed default'
[ ! -e "$CR_STATE/recent-demo.json" ] || fail 'failed launch recorded a recent success'
out=$(home_action "$(printf 'success-model\r')")
printf '%s' "$out" | grep -Fq 'child:success-model:9000' || fail 'one-time launch lost its model context'
grep -Fq '"model": "success-model"' "$CR_STATE/recent-demo.json" || fail 'successful launch not recorded'
[ "$before" = "$(cksum "$CR_STATE/selection" "$CR_STATE/last-model-demo" "$CR_STATE/selection-demo.json")" ] || fail 'one-time launch changed default'
rm "$TMP_DIR/hook-spy"
recent_before=$(cksum "$CR_STATE/recent-demo.json")
out=$(home_action "$(printf 'saved-model\023')")
printf '%s' "$out" | grep -Fq 'applied saved-model' || fail 'home save did not call the dispatcher'
[ "$(cat "$CR_STATE/last-model-demo")" = saved-model ] || fail 'explicit default was not saved'
[ ! -e "$TMP_DIR/hook-spy" ] || fail 'home default save ran startup'
[ "$recent_before" = "$(cksum "$CR_STATE/recent-demo.json")" ] || fail 'home default save was counted as a launch'
printf 'ok UX-08 bare home failure recovery, one-time launch and explicit default save\n'

# A second source's identically named model stays a separate choice.
cat > "$FAKE_ROOT/providers/second.sh" <<'EOF'
PROVIDER_NAME=second
PROVIDER_DESC='第二来源 fixture'
BASE_URL=http://127.0.0.1:9
MODEL=favorite-model
CONTEXT_TOKENS=7600
AUTH_MODE=none
MODELS_DISCOVERY=static
PRE_START='printf "second\n" >> "$HOOK_SPY"'
EOF
printf '%s\n' '{"schema_version":1,"paidFallback":false}' > "$CR_STATE/ui.json"
original_state=$(cksum "$CR_STATE/selection" "$CR_STATE/last-model-demo" "$CR_STATE/selection-demo.json" "$CR_STATE/ui.json")
home_steps() {
  pty_run "$@" -- env HOOK_SPY="$TMP_DIR/hook-spy" CLAUDE_BIN="$TMP_DIR/claude" \
    "${TEST_SHELL:-sh}" "$FAKE_ROOT/bin/crouter"
}
out=$(home_steps --timeout 5 --send-after '请选择：' "$(printf '1\r')" \
  --send-after 'Ctrl-F 收藏' "$(printf 'demo/favorite-model\006')" \
  --send-after '已收藏' "$(printf '\033')" --send-after '请选择：' "$(printf 'q\r')")
"$NODE_BIN" - "$CR_STATE/favorites.json" <<'NODE'
const assert = require('node:assert/strict');
const fs = require('node:fs');
const file = process.argv[2];
assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')), {schema_version: 1, models: ['demo/favorite-model']});
assert.equal(fs.statSync(file).mode & 0o777, 0o600);
NODE
[ ! -e "$TMP_DIR/hook-spy" ] || fail 'favorite toggle launched a provider'
out=$(home_steps --send-after '请选择：' "$(printf '1\r')" \
  --send-after 'Ctrl-R 选择来源' "$(printf 'favorite\022')" --send-after '筛选模型来源' "$(printf '\033')" \
  --send-after 'Ctrl-R 选择来源' "$(printf '\033')" --send-after '请选择：' "$(printf 'q\r')")
printf '%s' "$out" | grep -Fq '> ★ demo/favorite-model' || fail 'saved favorite did not lead the model list on reopening'
! printf '%s' "$out" | grep -Fq '★ second/favorite-model' || fail 'favorite crossed a source boundary'
[ "$(printf '%s' "$out" | grep -Fc 'Filter: favorite')" -ge 2 ] || fail 'source cancel lost the search query'
[ ! -e "$TMP_DIR/hook-spy" ] || fail 'source cancel started a model'
printf 'ok UX-05 source-scoped favorites persist and source cancel keeps selection\n'

out=$(home_steps --send-after '请选择：' "$(printf '1\r')" \
  --send-after 'Ctrl-R 选择来源' "$(printf '\022')" --send-after '筛选模型来源' "$(printf '\033[B\033[B\r')" \
  --send-after '来源：second' "$(printf '\r')" --send-after '请选择：' "$(printf 'q\r')")
printf '%s' "$out" | grep -Fq 'child:favorite-model:7600' || fail 'source filter did not launch the selected source'
printf '%s' "$out" | grep -Fq '第二来源 fixture' || fail 'source chooser did not show the display name'
[ "$(cksum "$CR_STATE/selection" "$CR_STATE/last-model-demo" "$CR_STATE/selection-demo.json" "$CR_STATE/ui.json")" = "$original_state" ] || fail 'source choice or favorite changed default or billing preference'
rm "$TMP_DIR/hook-spy"
out=$(home_steps --send-after '请选择：' "$(printf '1\r')" --send-after 'Ctrl-F 收藏' "$(printf '\006')" \
  --send-after '已取消收藏' "$(printf '\033')" --send-after '请选择：' "$(printf 'q\r')")
"$NODE_BIN" -p 'JSON.parse(require("fs").readFileSync(process.argv[1])).models.length' "$CR_STATE/favorites.json" | grep -Fxq 0 || fail 'favorite removal did not persist'
favorite_before=$(cksum "$CR_STATE/favorites.json")
mkdir "$CR_STATE/.favorites.lock"
out=$(home_steps --send-after '请选择：' "$(printf '1\r')" --send-after 'Ctrl-F 收藏' "$(printf '\006')" \
  --send-after '收藏正在更新' "$(printf '\033')" --send-after '请选择：' "$(printf 'q\r')")
rmdir "$CR_STATE/.favorites.lock"
[ "$favorite_before" = "$(cksum "$CR_STATE/favorites.json")" ] || fail 'favorite lock allowed a concurrent overwrite'
out=$(home_steps --send-after '请选择：' "$(printf '3\r')" --send-after '配置内置来源 ·' "$(printf '\033')" \
  --send-after '请选择：' "$(printf 'q\r')")
[ ! -e "$TMP_DIR/hook-spy" ] || fail 'built-in source cancellation launched a provider'
printf '%s' "$out" | grep -Fq '3 配置内置来源' || fail 'built-in source menu was mislabeled'
[ "$(cksum "$CR_STATE/selection" "$CR_STATE/last-model-demo" "$CR_STATE/selection-demo.json" "$CR_STATE/ui.json")" = "$original_state" ] || fail 'source cancellation or favorite removal changed default'
printf 'ok UX-05/07 source arrows launch the selected provider; built-in source setup and favorite removal return safely\n'

printf 'stdin fixture payload\n' > "$TMP_DIR/prompt.txt"
out=$(home_steps --stdin "$TMP_DIR/prompt.txt")
printf '%s' "$out" | grep -Fq 'child:saved-model:' || fail 'stdout-only TTY did not launch the default'
printf '%s' "$out" | grep -Fq 'stdin fixture payload' || fail 'stdout-only TTY lost the piped prompt'
! printf '%s' "$out" | grep -Fq '请选择：' || fail 'stdout-only TTY entered the interactive menu'
printf 'ok UX-01 bare home needs TTY stdin and stdout; piped prompt reaches Claude unchanged\n'
