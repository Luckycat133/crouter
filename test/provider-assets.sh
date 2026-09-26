#!/bin/sh
# Provider-owned MCP profiles are rendered per session with unique names. They
# never edit ~/.claude.json, and secrets live only in a mode-600 temp file.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node)}
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-assets)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM

render() {
  _profile=$1
  _out=$2
  CR_PLAN_TOKEN=plan-secret CR_API_TOKEN=api-secret \
    "$NODE_BIN" "$ROOT_DIR/lib/provider-assets.js" render "$_profile" "$_out"
}

render minimax "$TMP_DIR/minimax.json"
render zai "$TMP_DIR/zai.json"
render dashscope "$TMP_DIR/dashscope.json"
render volcengine "$TMP_DIR/volcengine.json"
render volcengine-coding "$TMP_DIR/volcengine-coding.json"
render stepfun "$TMP_DIR/stepfun.json"
render aihubmix "$TMP_DIR/aihubmix.json"
render ppio "$TMP_DIR/ppio.json"
CR_TENCENT_MCP_URL=https://mcp-api.tencent-cloud.com/sse/example \
  CR_PLAN_TOKEN=plan-secret CR_API_TOKEN=api-secret \
  "$NODE_BIN" "$ROOT_DIR/lib/provider-assets.js" render tencent "$TMP_DIR/tencent.json"
CR_QINIU_MCP_URLS='https://api.qnaigc.com/v1/mcp/http-streamable/first
https://api.qnaigc.com/v1/mcp/http-streamable/second' \
  CR_PLAN_TOKEN=plan-secret CR_API_TOKEN=api-secret \
  "$NODE_BIN" "$ROOT_DIR/lib/provider-assets.js" render qiniu "$TMP_DIR/qiniu.json"

ASSET_DIR="$TMP_DIR" "$NODE_BIN" - <<'NODE'
const assert = require('assert');
const fs = require('fs');
const path = require('path');
const load = (name) => JSON.parse(fs.readFileSync(path.join(process.env.ASSET_DIR, name + '.json')));

const minimax = load('minimax').mcpServers;
assert.deepStrictEqual(minimax['crouter-minimax-token-plan'], {
  command: 'uvx',
  args: ['minimax-coding-plan-mcp==0.0.4', '-y'],
  env: {MINIMAX_API_KEY: 'plan-secret', MINIMAX_API_HOST: 'https://api.minimax.cn'},
});

const zai = load('zai').mcpServers;
assert.deepStrictEqual(zai['crouter-zai-vision'], {
  type: 'stdio',
  command: 'npx',
  args: ['-y', '@z_ai/mcp-server@0.1.4'],
  env: {Z_AI_API_KEY: 'plan-secret', Z_AI_MODE: 'ZAI'},
});
assert.strictEqual(zai['crouter-zai-web-search'].url, 'https://api.z.ai/api/mcp/web_search_prime/mcp');
assert.strictEqual(zai['crouter-zai-web-reader'].url, 'https://api.z.ai/api/mcp/web_reader/mcp');
assert.strictEqual(zai['crouter-zai-zread'].url, 'https://api.z.ai/api/mcp/zread/mcp');
for (const server of Object.values(zai).filter((value) => value.type === 'http')) {
  assert.strictEqual(server.headers.Authorization, 'Bearer plan-secret');
}

const dashscope = load('dashscope').mcpServers;
assert.deepStrictEqual(dashscope['crouter-dashscope-web-search'], {
  type: 'http',
  url: 'https://dashscope.aliyuncs.com/api/v1/mcps/WebSearch/mcp',
  headers: {Authorization: 'Bearer api-secret'},
});

const volcengine = load('volcengine').mcpServers;
assert.deepStrictEqual(volcengine['crouter-volcengine-docs'], {
  type: 'http',
  url: 'https://sd6j8o9hu8aldae0o6es0.apigateway-cn-beijing.volceapi.com/mcp',
});
assert.deepStrictEqual(volcengine['crouter-volcengine-doubao-search'], {
  command: 'uvx',
  args: ['--from', 'mcp-server-askecho-search-infinity>=0.2.0', 'mcp-server-askecho-search-infinity'],
  env: {ASK_ECHO_SEARCH_INFINITY_API_KEY: 'plan-secret'},
});
assert.deepStrictEqual(volcengine['crouter-volcengine-datapro'], {
  type: 'http',
  url: 'https://datapro.hqd.cn-beijing.volces.com/mcp',
  headers: {'X-Agent-Plan-Key': 'plan-secret', Accept: 'application/json'},
});
assert.deepStrictEqual(volcengine['crouter-volcengine-openviking'], {
  command: 'uvx',
  args: [
    '--from',
    'git+https://github.com/volcengine/mcp-server#subdirectory=server/mcp_server_openviking_controlplane',
    'mcp-server-openviking-controlplane',
  ],
  env: {AGENTPLAN_API_KEY: 'plan-secret'},
});

const volcengineCoding = load('volcengine-coding').mcpServers;
assert.deepStrictEqual(volcengineCoding['crouter-volcengine-docs'], {
  type: 'http',
  url: 'https://sd6j8o9hu8aldae0o6es0.apigateway-cn-beijing.volceapi.com/mcp',
});
assert.strictEqual(volcengineCoding['crouter-volcengine-doubao-search'], undefined);

const stepfun = load('stepfun').mcpServers;
assert.deepStrictEqual(stepfun['crouter-stepfun-web-search'], {
  type: 'http',
  url: 'https://api.stepfun.com/step_plan/v1/mcp/web_search/mcp',
  headers: {Authorization: 'Bearer plan-secret'},
});

const aihubmix = load('aihubmix').mcpServers;
assert.deepStrictEqual(aihubmix['crouter-aihubmix-api'], {
  type: 'http',
  url: 'https://aihubmix.com/mcp/',
  headers: {Authorization: 'Bearer plan-secret'},
});

const ppio = load('ppio').mcpServers;
assert.deepStrictEqual(ppio['crouter-ppio-cloud'], {
  type: 'http',
  url: 'https://mcp.ppio.com/mcp',
});

const tencent = load('tencent').mcpServers;
assert.deepStrictEqual(tencent['crouter-tencent-web-search'], {
  type: 'sse',
  url: 'https://mcp-api.tencent-cloud.com/sse/example',
});

const qiniu = load('qiniu').mcpServers;
assert.deepStrictEqual(qiniu['crouter-qiniu-managed-1'], {
  type: 'http',
  url: 'https://api.qnaigc.com/v1/mcp/http-streamable/first',
  headers: {Authorization: 'Bearer plan-secret'},
});
assert.deepStrictEqual(qiniu['crouter-qiniu-managed-2'], {
  type: 'http',
  url: 'https://api.qnaigc.com/v1/mcp/http-streamable/second',
  headers: {Authorization: 'Bearer plan-secret'},
});

const names = [minimax, zai, dashscope, volcengine, stepfun, aihubmix, ppio, tencent, qiniu]
  .flatMap((servers) => Object.keys(servers));
assert.strictEqual(new Set(names).size, names.length, 'provider MCP names must never collide');
NODE

if CR_QINIU_MCP_URLS=https://attacker.example/v1/mcp/http-streamable/stolen \
  CR_API_TOKEN=api-secret \
  "$NODE_BIN" "$ROOT_DIR/lib/provider-assets.js" render qiniu "$TMP_DIR/qiniu-invalid.json" \
  >/dev/null 2>&1; then
  printf 'FAIL  Qiniu MCP accepted an untrusted credential destination\n' >&2
  exit 1
fi

ROOT_DIR=$ROOT_DIR
LIB_DIR="$ROOT_DIR/lib"
STATE_DIR="$TMP_DIR/state"
ASSET_PROFILE=minimax
ASSET_PLUGIN_DIRS=
ASSET_PLAN_PLUGIN_DIRS="$ROOT_DIR/assets/plugins/minimax-token-plan"
ASSET_API_PLUGIN_DIRS=
_PLAN_FIRST_TOKEN=plan-secret
_API_FIRST_TOKEN=api-secret
PROVIDER_MCP_CONFIG=
PROVIDER_PLUGIN_DIRS=
PROVIDER_ASSET_ENV=
info() { :; }
die() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
. "$ROOT_DIR/lib/assets.sh"
prepare_provider_assets
[ -f "$PROVIDER_MCP_CONFIG" ] || { printf 'FAIL  session MCP config not created\n' >&2; exit 1; }
if _mcp_mode=$(stat -f '%Lp' "$PROVIDER_MCP_CONFIG" 2>/dev/null); then
  :
else
  _mcp_mode=$(stat -c '%a' "$PROVIDER_MCP_CONFIG")
fi
[ "$_mcp_mode" = 600 ] || {
  printf 'FAIL  session MCP config is not mode 600\n' >&2; exit 1;
}
[ "$PROVIDER_PLUGIN_DIRS" = "$ASSET_PLAN_PLUGIN_DIRS" ] || {
  printf 'FAIL  provider plugin directory not activated\n' >&2; exit 1;
}
printf '%s\n' "$PROVIDER_ASSET_ENV" | grep -q '^MINIMAX_API_KEY=plan-secret$' || {
  printf 'FAIL  MiniMax CLI did not receive the active plan token\n' >&2; exit 1;
}
_config=$PROVIDER_MCP_CONFIG
cleanup_provider_assets
[ ! -e "$_config" ] || { printf 'FAIL  session MCP secret file was not removed\n' >&2; exit 1; }

# Every explicit surface provider gets a managed config, even when the vendor
# offers no MCP. Strict mode then suppresses a stale MCP from the prior plan.
AUTH_MODE=surfaces
ASSET_PROFILE=
ASSET_PLAN_PLUGIN_DIRS=
_PLAN_FIRST_TOKEN=
_API_FIRST_TOKEN=api-secret
prepare_provider_assets
[ -f "$PROVIDER_MCP_CONFIG" ] || { printf 'FAIL  empty strict MCP profile missing\n' >&2; exit 1; }
EMPTY_CONFIG="$PROVIDER_MCP_CONFIG" "$NODE_BIN" - <<'NODE'
const assert = require('assert');
const fs = require('fs');
const config = JSON.parse(fs.readFileSync(process.env.EMPTY_CONFIG, 'utf8'));
assert.deepStrictEqual(config, {mcpServers: {}});
NODE
cleanup_provider_assets

# A plan-only skill must not be activated for an API-key-only session.
ASSET_PROFILE=minimax
ASSET_PLAN_PLUGIN_DIRS="$ROOT_DIR/assets/plugins/minimax-token-plan"
prepare_provider_assets
[ -z "$PROVIDER_PLUGIN_DIRS" ] || { printf 'FAIL  plan skill leaked into API-only session\n' >&2; exit 1; }
cleanup_provider_assets

[ -f "$ROOT_DIR/assets/plugins/minimax-token-plan/.claude-plugin/plugin.json" ] || {
  printf 'FAIL  MiniMax session plugin manifest missing\n' >&2; exit 1;
}
[ -f "$ROOT_DIR/assets/plugins/minimax-token-plan/skills/minimax-cli/SKILL.md" ] || {
  printf 'FAIL  MiniMax CLI session skill missing\n' >&2; exit 1;
}
[ -f "$ROOT_DIR/assets/plugins/stepfun-plan/.claude-plugin/plugin.json" ] || {
  printf 'FAIL  StepFun session plugin manifest missing\n' >&2; exit 1;
}
[ -f "$ROOT_DIR/assets/plugins/stepfun-plan/skills/step-search/SKILL.md" ] || {
  printf 'FAIL  StepFun search skill missing\n' >&2; exit 1;
}
[ -f "$ROOT_DIR/assets/plugins/dashscope-token-plan/.claude-plugin/plugin.json" ] || {
  printf 'FAIL  DashScope Token Plan session plugin manifest missing\n' >&2; exit 1;
}
[ -f "$ROOT_DIR/assets/plugins/dashscope-token-plan/skills/dashscope-media/SKILL.md" ] || {
  printf 'FAIL  DashScope Token Plan media skill missing\n' >&2; exit 1;
}

printf 'ok    provider MCP/skill profiles are isolated and session-scoped\n'
