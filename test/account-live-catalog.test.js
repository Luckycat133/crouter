'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const {once} = require('node:events');
const {execFile} = require('node:child_process');
const {promisify} = require('node:util');
const {ACCOUNT_LIVE_DEADLINE_MS, loadAccountLiveCatalog, accountLiveEnabled} = require('../lib/account-live-catalog.js');
const {atomicJson, catalogOptions, scopeKey} = require('../lib/catalog.js');

async function fixtureServer(t, handler) {
  const server = http.createServer(handler);
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  return `http://127.0.0.1:${server.address().port}`;
}
function policy(base, provider = 'antigravity') {
  return {CR_PROVIDER: provider, CR_MODELS_ACCOUNT_LIVE: '1',
    CR_CATALOG_SOURCE_URL: base, CR_MODELS_API_URL: base + '/v1/models', CR_MODELS_API_AUTH: 'none',
    CR_MODEL_BLOCKED: 'gemini-fixture-blocked',
    CR_STATIC_MODELS: 'gemini-4-neon-xhigh claude-opus-5-5-max',
    CR_CATALOG_TOKEN: 'never-send-fixture-secret'};
}

test('account-live: exact returned variants only, family split, blocked/disabled/retired filtering, unknown price', async (t) => {
  let hits = 0;
  const base = await fixtureServer(t, (req, res) => {
    hits++;
    assert.equal(req.method, 'GET'); assert.equal(req.url, '/v1/models');
    assert.equal(req.headers.authorization, undefined); assert.equal(req.headers['x-api-key'], undefined);
    res.end(JSON.stringify({data: [
      {id: 'gemini-4-carbon-medium', description: 'Carbon Medium'},
      {id: 'claude-opus-5-5-high'},
      {id: 'gpt-oss-120b-medium'},
      {id: 'gemini-4-neon-high', disabled: true},
      {id: 'gemini-4-neon-medium', enabled: false},
      {id: 'gemini-4-hydrogen-high', available: false},
      {id: 'gemini-4-hydrogen-low', retired: true},
      {id: 'gemini-4-argon-high'},
      {id: 'gemini-fixture-blocked'},
      {id: 'gemini-4-carbon-high-disabled'},
      {id: 'gemini-4-carbon-low', status: 'unsupported'},
      {id: 'gemini-4-orchestrator-medium'},
    ]}));
  });
  const gemini = await loadAccountLiveCatalog(policy(base), {candidateUrls: [base]});
  assert.deepEqual(gemini.models.map((m) => m.id), ['gemini-4-carbon-medium', 'gemini-4-argon-high']);
  assert.equal(gemini.models[0].name, 'Carbon Medium');
  assert.deepEqual(gemini.models[0].pricing, {});
  assert.equal(gemini.models[0].verification, 'account-directory');
  const claude = await loadAccountLiveCatalog(policy(base, 'antigravity-claude'));
  assert.deepEqual(claude.models.map((m) => m.id), ['claude-opus-5-5-high']);
  assert.equal(hits, 2, 'one GET per call, no probes');
});

test('account-live: strict local binding and zero-network check; other providers cannot opt in', async (t) => {
  let hits = 0;
  const base = await fixtureServer(t, (_req, res) => { hits++; res.end('{"data":[]}'); });
  assert.equal(accountLiveEnabled(policy(base, 'openrouter')), false);
  for (const override of [
    {CR_CATALOG_SOURCE_URL: 'https://127.0.0.1:18080'},
    {CR_CATALOG_SOURCE_URL: 'http://example.com:18080'},
    {CR_CATALOG_SOURCE_URL: base + '/other'},
    {CR_MODELS_API_URL: base + '/other'},
    {CR_MODELS_API_AUTH: 'bearer'},
    {CR_ACCOUNT_LIVE_NETWORK: '0'},
  ]) {
    const result = await loadAccountLiveCatalog({...policy(base), ...override});
    assert.equal(result.status, 'unknown'); assert.deepEqual(result.models, []);
  }
  const mismatch = await loadAccountLiveCatalog(policy(base), {candidateUrls: [base + '/different-inference']});
  assert.equal(mismatch.reason, 'invalid-local-binding');
  assert.equal(hits, 0);
});

test('account-live: 401/503/redirect/malformed/empty/timeout never restore static models or cached account', async (t) => {
  let mode = 'ok', hits = 0;
  const base = await fixtureServer(t, (req, res) => {
    hits++; assert.equal(req.method, 'GET'); assert.equal(req.url, '/v1/models');
    if (mode === 'timeout') return;
    if (mode === 'redirect') { res.writeHead(302, {Location: base + '/must-not-follow'}); res.end(); return; }
    if (mode === 'bad-json') { res.end('{'); return; }
    if (mode === 'bad-shape') { res.end('{"models":[{"id":"gemini-wrong"}]}'); return; }
    if (mode === '401' || mode === '503') { res.writeHead(Number(mode)); res.end('{"error":"unavailable"}'); return; }
    res.end(JSON.stringify({data: mode === 'empty' ? [] : [{id: 'gemini-4-carbon-medium'}]}));
  });
  const env = policy(base);
  assert.equal((await loadAccountLiveCatalog(env)).models.length, 1);
  for (mode of ['401', '503', 'redirect', 'bad-json', 'bad-shape', 'empty', 'timeout']) {
    const before = hits, started = Date.now();
    const result = await loadAccountLiveCatalog(env, {timeoutMs: 40});
    assert.deepEqual(result.models, [], mode);
    assert.notEqual(result.status, 'available', mode);
    assert.equal(hits - before, 1, 'no retry or redirect: ' + mode);
    assert.ok(Date.now() - started < 1000, 'injected test deadline is honored: ' + mode);
  }
});

test('account-live: the default 7s deadline accepts the proxy cold response beyond 2s', async (t) => {
  assert.equal(ACCOUNT_LIVE_DEADLINE_MS, 7000);
  let hits = 0;
  const base = await fixtureServer(t, (_req, res) => {
    hits++;
    setTimeout(() => res.end('{"data":[{"id":"gemini-4-carbon-medium"}]}'), 2200);
  });
  const result = await loadAccountLiveCatalog(policy(base));
  assert.equal(result.status, 'available');
  assert.deepEqual(result.models.map((model) => model.id), ['gemini-4-carbon-medium']);
  assert.equal(hits, 1);
});

test('real CLI: inventory, models and unified honor account switch and failures; all --check never reads network', async (t) => {
  const root = path.join(__dirname, '..');
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'crouter-account-live-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  for (const folder of ['bin', 'lib']) fs.cpSync(path.join(root, folder), path.join(dir, folder), {recursive: true});
  for (const folder of ['providers', 'stubs', 'home', 'state']) fs.mkdirSync(path.join(dir, folder));
  for (const name of ['antigravity', 'antigravity-claude']) fs.copyFileSync(path.join(root, 'providers', name + '.sh'), path.join(dir, 'providers', name + '.sh'));
  fs.writeFileSync(path.join(dir, 'VERSION'), 'test\n');
  fs.writeFileSync(path.join(dir, 'providers', 'openrouter.sh'), [
    'PROVIDER_NAME=openrouter', 'MODEL=nvidia/nemotron-3.5-super-vl:free', 'BASE_URL=http://127.0.0.1:9',
    'AUTH_MODE=env', 'AUTH_REFERENCE=FIXTURE_OR_KEY',
  ].join('\n') + '\n');
  const securityLog = path.join(dir, 'security.log');
  fs.writeFileSync(path.join(dir, 'stubs', 'security'), '#!/bin/sh\nprintf forbidden >> "$FIXTURE_SECURITY_LOG"\nexit 99\n', {mode: 0o700});
  const claude = path.join(dir, 'stubs', 'claude');
  fs.writeFileSync(claude, '#!/bin/sh\nexec curl -fsS "$ANTHROPIC_BASE_URL/v1/models"\n', {mode: 0o700});
  let account = 'a', code = 200, hits = 0;
  const base = await fixtureServer(t, (req, res) => {
    hits++; assert.equal(req.method, 'GET'); assert.equal(req.url, '/v1/models');
    assert.equal(req.headers.authorization, undefined); assert.equal(req.headers['x-api-key'], undefined);
    res.writeHead(code);
    const ids = account === 'a'
      ? ['gemini-4-carbon-medium', 'gemini-4-argon-medium', 'claude-sonnet-5-5-medium']
      : ['gemini-4-hydrogen-xhigh', 'claude-opus-5-5-max'];
    res.end(JSON.stringify({data: code === 200 ? ids.map((id) => ({id})) : []}));
  });
  const env = {PATH: path.join(dir, 'stubs') + ':' + process.env.PATH, LANG: 'C.UTF-8', USER: 'fixture',
    HOME: path.join(dir, 'home'), XDG_STATE_HOME: path.join(dir, 'state'), XDG_DATA_HOME: path.join(dir, 'data'), TMPDIR: dir,
    NODE_BIN: process.execPath, CLAUDE_BIN: claude, ANTIGRAVITY_PORT: new URL(base).port,
    FIXTURE_SECURITY_LOG: securityLog, FIXTURE_OR_KEY: 'fixture-not-real', CROUTER_GATEWAY_PORT: '0', CROUTER_PROVIDER_ASSETS: '0'};
  // A fully scoped, fresh old-account cache must not leak extra variants.
  const cacheFile = path.join(env.XDG_STATE_HOME, 'crouter', 'models-antigravity.json');
  const cacheScope = catalogOptions(policy(base));
  atomicJson(cacheFile, {schema_version: 2, scope: scopeKey(cacheScope), fetched_at: Date.now(),
    models: [{id: 'gemini-4-neon-xhigh'}, {id: 'gemini-4-argon-medium'}]});
  const oldCache = fs.readFileSync(cacheFile, 'utf8');
  const exec = promisify(execFile);
  const run = (args) => exec(process.env.TEST_SHELL || 'sh', [path.join(dir, 'bin', 'crouter'), ...args], {cwd: dir, env, timeout: 12000});
  const inventory = async () => (await run(['_inventory'])).stdout.trim().split('\n').map(JSON.parse).filter((p) => p.name.startsWith('antigravity'));
  const models = async (provider) => JSON.parse((await run(['models', provider, '--list'])).stdout);
  const gateway = async () => {
    const lines = (await run(['all'])).stdout.trim().split('\n');
    return JSON.parse(lines.at(-1)).data;
  };
  const beforeCheck = hits;
  const check = await run(['all', '--check']);
  assert.equal(hits, beforeCheck);
  assert.match(check.stdout, /antigravity: 0 model/);
  assert.match(check.stdout, /account model availability: unknown \(not-queried\)/);
  for (const [value, expected] of [
    ['a', ['antigravity/gemini-4-carbon-medium', 'antigravity/gemini-4-argon-medium', 'antigravity-claude/claude-sonnet-5-5-medium']],
    ['b', ['antigravity/gemini-4-hydrogen-xhigh', 'antigravity-claude/claude-opus-5-5-max']],
  ]) {
    account = value;
    const rows = await inventory();
    assert.equal(rows.length, 2);
    assert.ok(rows.every((p) => p.status === 'ready'));
    assert.deepEqual(rows.flatMap((p) => p.models.map((m) => p.name + '/' + m.id)).sort(), expected.sort());
    for (const p of rows) assert.deepEqual((await models(p.name)).map((m) => m.id), p.models.map((m) => m.id));
    const listed = await gateway();
    assert.deepEqual(listed.filter((m) => m.id.startsWith('antigravity')).map((m) => m.id).sort(), expected.sort());
    assert.ok(listed.some((m) => m.id === 'openrouter/nvidia/nemotron-3.5-super-vl:free'));
  }
  for (code of [503, 401]) {
    const rows = await inventory();
    assert.ok(rows.every((p) => p.status === 'unavailable' && p.models.length === 0));
    assert.deepEqual(await models('antigravity'), []);
    const listed = await gateway();
    assert.ok(!listed.some((m) => m.id.startsWith('antigravity')));
    assert.ok(listed.some((m) => m.id === 'openrouter/nvidia/nemotron-3.5-super-vl:free'));
  }
  assert.equal(fs.existsSync(securityLog), false, 'no Keychain credential discovery');
  assert.equal(fs.readFileSync(cacheFile, 'utf8'), oldCache, 'live reads neither consume nor overwrite an old-account cache');
});
