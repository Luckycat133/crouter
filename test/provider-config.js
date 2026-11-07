'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const fixture = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixtures/provider-config-2026-11-07.json'), 'utf8'));
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'crouter-provider-config-'));
try {
  const env = {PATH: process.env.PATH, HOME: tmp, XDG_STATE_HOME: tmp, ROOT_DIR: root, PROVIDERS_DIR: path.join(root, 'providers'), STATE_DIR: ''};
  // Generic API credentials must not be reclassified as subscription keys.
  for (const name of ['MINIMAX','HUAWEI','QIANFAN','BAIDU','TENCENT','TENCENTCLOUD','XIAOMI','Z_AI','ZHIPU','DASHSCOPE','STEPFUN','MOONSHOT']) env[name + '_API_KEY'] = 'test-api-only-not-a-plan';
  const actualNames = fs.readdirSync(env.PROVIDERS_DIR).filter((f) => f.endsWith('.sh')).map((f) => f.slice(0,-3)).sort();
  assert.deepEqual(actualNames, Object.keys(fixture.providers).sort(), 'review must cover every provider');
  for (const [name, expected] of Object.entries(fixture.providers)) {
    const fields = Object.keys(expected);
    const print = fields.map((f) => `printf '%s\\0' "\${${f}:-}";`).join('\n');
    const script = `die(){ echo "$*" >&2; exit 1; }; . "$ROOT_DIR/lib/provider.sh"; load_provider "$1";\n${print}\nif [ -n "$PLAN_KEY_ENV" ]; then test -z "$(printenv "$PLAN_KEY_ENV" 2>/dev/null)" || exit 8; fi`;
    const result = spawnSync(process.env.TEST_SHELL || 'sh', ['-c', script, 'fixture', name], {env, encoding: 'utf8', timeout: 5000});
    assert.equal(result.status, 0, `${name}: source failed or API key leaked into plan: ${result.stderr}`);
    const values = result.stdout.split('\0'); values.pop();
    assert.equal(values.length, fields.length);
    fields.forEach((field, i) => assert.equal(values[i], expected[field], `${name}.${field}`));
    console.log(`ok provider-config ${name}`);
  }
} finally { fs.rmSync(tmp, {recursive: true, force: true}); }
