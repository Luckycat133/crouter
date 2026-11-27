'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const {execFile, execFileSync} = require('node:child_process');
const {once} = require('node:events');
const {promisify} = require('node:util');
const {normalizeModels, pricingOf, isFree, fmtPrice, requestJson, loadCatalog, scopeKey} = require('../lib/catalog.js');
const {statePaths, saveSelection, readContext} = require('../lib/model-state.js');

test('catalog normalization: IDs, modalities, provider caps and API capabilities', () => {
  const models = normalizeModels({data: [
    {id: 'chat', context_length: 1000000, top_provider: {context_length: 262144}, pricing: {prompt: '0', completion: '0.1'}},
    {id: 'image-only', architecture: {output_modalities: ['image']}},
    {id: 'emb', type: 'embedding'}, {id: 'chat:batch'}, {name: 'not-an-id'},
    {id: 'chat'}, {id: '\x1b[2J'},
    {id: 'claude', display_name: 'Claude', max_input_tokens: 1000000, max_tokens: 128000},
  ]});
  assert.deepEqual(models.map((m) => m.id), ['chat', 'claude']);
  assert.equal(models[0].context_length, 262144);
  assert.equal(models[1].context_length, 1000000);
  assert.equal(models[1].max_output_tokens, 128000);
});
test('prices: no slug inference, no partial/free or malformed-number inference', () => {
  assert.equal(isFree({id: 'unknown:free'}), false);
  assert.equal(isFree({pricing: {prompt: '0', completion: '0.1'}}), false);
  assert.equal(isFree({pricing: {prompt: '0', completion: '0'}}), true);
  assert.equal(fmtPrice({pricing: {input: '0.000001', output: '0.000002'}}), '$1.00/$2.00');
  assert.equal(fmtPrice({pricing: {prompt: '0garbage', completion: '0'}}), 'unknown');
  assert.equal(fmtPrice({pricing: [{prompt_tokens_threshold: 0, input_price: 0, output_price: 0}]}), 'FREE');
  assert.equal(pricingOf({pricing: {prompt: -1, completion: 0}}).prompt, null);
});
async function server(t, handler) {
  const srv = http.createServer(handler);
  srv.listen(0, '127.0.0.1'); await once(srv, 'listening');
  t.after(() => { srv.closeAllConnections(); srv.close(); });
  return `http://127.0.0.1:${srv.address().port}`;
}
test('query and explicit x-api-key are preserved; origin mismatches do not send', async (t) => {
  let hits = 0;
  const base = await server(t, (req, res) => {
    hits++; assert.equal(req.url, '/v1/models?scope=one'); assert.equal(req.headers['x-api-key'], 'test-secret');
    assert.equal(req.headers.authorization, undefined); res.end('{"data":[{"id":"m"}]}');
  });
  await requestJson(base + '/v1/models?scope=one', {auth: 'x-api-key', token: 'test-secret', authOrigin: base});
  await assert.rejects(requestJson(base, {auth: 'bearer', token: 'test-secret', authOrigin: 'https://wrong.invalid'}), /origin mismatch/);
  assert.equal(hits, 1);
});
test('non-2xx and redirect do not become model catalogs; public mode omits key', async (t) => {
  const base = await server(t, (req, res) => {
    assert.equal(req.headers.authorization, undefined);
    res.writeHead(req.url === '/bad' ? 401 : 302, {Location: 'https://other.invalid'});
    res.end('{"data":[{"id":"not-success"}]}');
  });
  await assert.rejects(requestJson(base + '/bad', {auth: 'none', token: 'never-send'}), /401/);
  await assert.rejects(requestJson(base + '/redirect'), /302/);
});
test('bounded response, total timeout and abort', async (t) => {
  const base = await server(t, (req, res) => {
    if (req.url === '/big') res.end('x'.repeat(200));
  });
  await assert.rejects(requestJson(base + '/big', {maxBytes: 10}), /too large/);
  await assert.rejects(requestJson(base + '/slow', {timeoutMs: 20}), /deadline/);
  const controller = new AbortController();
  const pending = requestJson(base + '/slow', {signal: controller.signal});
  controller.abort(); await assert.rejects(pending, /cancelled/);
});
test('failed refresh retains last good scoped cache; another account cannot reuse it', async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'catalog-test-')); t.after(() => fs.rmSync(dir, {recursive: true}));
  let ok = true;
  const base = await server(t, (req, res) => {
    res.writeHead(ok ? 200 : 401); res.end(JSON.stringify(ok ? {data: [{id: 'real'}]} : {data: [{id: 'bad'}]}));
  });
  const options = {provider: 'demo', urls: [base], authOrigin: base, auth: 'bearer', token: 'account-one-test-key', surface: 'api', cacheFile: path.join(dir, 'models.json'), staticModels: ['seed']};
  const first = await loadCatalog(options); assert.equal(first.source, 'remote');
  const bytes = fs.readFileSync(options.cacheFile, 'utf8'); assert.equal(bytes.includes('account-one-test-key'), false);
  ok = false;
  const stale = await loadCatalog({...options, force: true}); assert.equal(stale.stale, true); assert.equal(stale.models[0].id, 'real');
  assert.equal(fs.readFileSync(options.cacheFile, 'utf8'), bytes);
  const other = await loadCatalog({...options, token: 'account-two-test-key'}); assert.equal(other.source, 'static'); assert.equal(other.models[0].id, 'seed');
  assert.notEqual(scopeKey(options), scopeKey({...options, surface: 'plan'}));
});
test('paginated catalogs are combined and deduplicated', async (t) => {
  const base = await server(t, (req, res) => res.end(JSON.stringify(req.url.includes('after_id=one') ? {data: [{id: 'two'}], has_more: false} : {data: [{id: 'one'}], has_more: true, last_id: 'one'})));
  const result = await loadCatalog({provider: 'pages', urls: [base], staticModels: []});
  assert.deepEqual(result.models.map((m) => m.id), ['one', 'two']);
});
test('model state binds context to exact selected model and clears unknown', (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'state-test-')); t.after(() => fs.rmSync(dir, {recursive: true}));
  const previous = process.env.XDG_STATE_HOME; process.env.XDG_STATE_HOME = dir;
  t.after(() => { if (previous === undefined) delete process.env.XDG_STATE_HOME; else process.env.XDG_STATE_HOME = previous; });
  const paths = statePaths('demo');
  saveSelection(paths, 'demo', {id: 'large', context_length: 1000000});
  assert.equal(readContext('demo', 'large'), 1000000); assert.equal(readContext('demo', 'other'), null);
  saveSelection(paths, 'demo', {id: 'unknown'});
  assert.equal(fs.existsSync(paths.context), false); assert.equal(readContext('demo', 'unknown'), null);
  assert.equal(fs.statSync(paths.record).mode & 0o777, 0o600);

  const stateCli = path.join(__dirname, '..', 'lib', 'model-state.js');
  const state = (...args) => execFileSync(process.execPath, [stateCli, ...args], {
    encoding: 'utf8', env: {HOME: dir, XDG_STATE_HOME: dir},
  });
  const revision = state('limits', 'demo', 'unknown').trim().split(' ').at(-1);
  saveSelection(paths, 'demo', {id: 'later-default', context_length: 4096});
  state('write-if-current', 'demo', 'slow-launch', '', '', revision);
  assert.equal(fs.readFileSync(paths.model, 'utf8'), 'later-default\n');
  assert.equal(readContext('demo', 'later-default'), 4096);
});

test('CAT-06: directory, home inventory, plan and live unified list share one scoped cache', async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'catalog-consumers-'));
  t.after(() => fs.rmSync(dir, {recursive: true, force: true}));
  for (const folder of ['bin', 'lib']) fs.cpSync(path.join(__dirname, '..', folder), path.join(dir, folder), {recursive: true});
  for (const folder of ['providers', 'stubs', 'home', 'state']) fs.mkdirSync(path.join(dir, folder));
  fs.writeFileSync(path.join(dir, 'VERSION'), 'test\n');
  const provider = [
    'PROVIDER_NAME=demo', 'MODEL=declared', 'PROVIDER_DESC="Fixture source"', 'AUTH_MODE=surfaces',
    'BASE_URL="$FIXTURE_BASE/inference-a"', 'API_URL="$FIXTURE_BASE/${FIXTURE_API_PATH:-inference-a}"',
    'API_KEY_ENV=FIXTURE_API_KEY', 'API_KEYS=fixture-api', 'API_AUTH_TYPE=x-api-key',
    'PLAN_URL="$FIXTURE_BASE/plan"', 'PLAN_AUTH_TYPE=bearer', 'PLAN_KEY_ENV=FIXTURE_PLAN_KEY',
    'MODELS_DISCOVERY=remote', 'MODELS_API_URL="$FIXTURE_BASE/catalog?scope=${FIXTURE_QUERY:-one}"',
    'MODELS_API_AUTH="${FIXTURE_CATALOG_AUTH:-bearer}"', 'MODELS_API_SURFACE="${FIXTURE_SURFACE:-api}"',
  ];
  fs.writeFileSync(path.join(dir, 'providers', 'demo.sh'), provider.join('\n') + '\n');
  const security = path.join(dir, 'stubs', 'security');
  const decryptLog = path.join(dir, 'decrypt.log');
  fs.writeFileSync(security, `#!/bin/sh
case " $* " in
  *" -w "*) printf 'decrypt\\n' >> "$FIXTURE_DECRYPT_LOG";;
esac
[ -n "$FIXTURE_KEYCHAIN_TOKEN" ] || exit 44
case " $* " in
  *" -w "*) printf '%s' "$FIXTURE_KEYCHAIN_TOKEN";;
esac
`, {mode: 0o700});
  const claude = path.join(dir, 'stubs', 'claude');
  fs.writeFileSync(claude, '#!/bin/sh\nexec curl -fsS "$ANTHROPIC_BASE_URL/v1/models"\n', {mode: 0o700});

  let hits = 0, refused = false;
  const base = await server(t, (req, res) => {
    hits++;
    assert.match(req.url, /^\/catalog\?scope=/);
    const authorization = req.headers.authorization;
    if (refused || (authorization && authorization !== 'Bearer fixture-api-account-a')) {
      res.writeHead(401); res.end('{"data":[]}'); return;
    }
    const model = authorization ? 'account-a' : 'public-discovery';
    res.end(JSON.stringify({data: [{id: model, context_length: 32000, max_output_tokens: 2048}]}));
  });
  const env = {PATH: path.join(dir, 'stubs') + ':' + process.env.PATH, LANG: 'C.UTF-8', USER: 'fixture',
    HOME: path.join(dir, 'home'), XDG_STATE_HOME: path.join(dir, 'state'), TMPDIR: dir,
    NODE_BIN: process.execPath, CLAUDE_BIN: claude, FIXTURE_BASE: base, FIXTURE_DECRYPT_LOG: decryptLog,
    FIXTURE_API_KEY: 'fixture-api-account-a', CROUTER_GATEWAY_PORT: '0', CROUTER_PROVIDER_ASSETS: '0'};
  const exec = promisify(execFile);
  const run = (args, envOverrides) => exec(process.env.TEST_SHELL || 'sh', [path.join(dir, 'bin', 'crouter'), ...args], {
    cwd: dir, env: {...env, ...envOverrides}, timeout: 12000,
  });
  const inventory = async (override) => JSON.parse((await run(['_inventory'], override)).stdout);
  const gateway = async (override) => {
    const lines = (await run(['all'], override)).stdout.trim().split('\n');
    return JSON.parse(lines[lines.length - 1]).data;
  };
  const plan = async (override) => JSON.parse((await run(['demo', '--plan', '--model', 'account-a'], override)).stdout);
  await run(['models', 'demo', '--list']);
  assert.equal(hits, 1);
  const cache = path.join(env.XDG_STATE_HOME, 'crouter', 'models-demo.json');
  const raw = fs.readFileSync(cache, 'utf8');
  assert.equal(raw.includes(env.FIXTURE_API_KEY), false);
  assert.equal((await inventory()).models.find((m) => m.id === 'account-a').verification, 'catalog-only');
  assert.equal(fs.existsSync(decryptLog), false);
  const advertised = (await gateway()).find((m) => m.id === 'demo/account-a');
  assert.equal(advertised.verification, 'catalog-only');
  assert.equal((await plan()).maxOutputTokens, 2048);
  assert.equal((await plan()).contextTokens, 32000);
  await run(['demo', '--model', 'account-a', '--apply-only']);
  const record = JSON.parse(fs.readFileSync(path.join(env.XDG_STATE_HOME, 'crouter', 'selection-demo.json'), 'utf8'));
  assert.equal(record.context_length, null, 'directory context was persisted as unscoped state');
  assert.equal(record.max_output_tokens, null, 'directory output was persisted as unscoped state');

  for (const override of [
    {FIXTURE_API_KEY: 'fixture-api-account-b'},
    {FIXTURE_API_PATH: 'inference-b'},
    {FIXTURE_QUERY: 'two'},
    {FIXTURE_SURFACE: 'plan', FIXTURE_PLAN_KEY: env.FIXTURE_API_KEY},
  ]) {
    assert.equal((await inventory(override)).models.some((m) => m.id === 'account-a'), false);
    assert.equal((await gateway(override)).some((m) => m.id === 'demo/account-a'), false);
    assert.equal((await plan(override)).contextTokens, null);
    assert.equal((await plan(override)).maxOutputTokens, null);
  }
  fs.rmSync(decryptLog, {force: true});
  const keychainOnly = {FIXTURE_API_KEY: '', FIXTURE_KEYCHAIN_TOKEN: env.FIXTURE_API_KEY};
  assert.equal((await inventory(keychainOnly)).models.some((m) => m.id === 'account-a'), false);
  assert.equal((await plan(keychainOnly)).contextTokens, null);
  assert.equal(fs.existsSync(decryptLog), false, 'home inventory or plan decrypted Keychain');
  assert.equal((await gateway(keychainOnly)).some((m) => m.id === 'demo/account-a'), true);
  assert.equal((await gateway({...keychainOnly, FIXTURE_KEYCHAIN_TOKEN: 'fixture-second-keychain-account'})).some((m) => m.id === 'demo/account-a'), false);
  assert.equal(hits, 1, 'cache-only consumers contacted the directory');

  const old = {...JSON.parse(raw), fetched_at: Date.now() - 2 * 86400000};
  fs.writeFileSync(cache, JSON.stringify(old));
  assert.equal((await inventory()).models.find((m) => m.id === 'account-a').verification, 'stale-catalog');
  assert.equal((await gateway()).some((m) => m.id === 'demo/account-a'), false);
  assert.equal((await plan()).maxOutputTokens, null);
  refused = true;
  const offline = await run(['models', 'demo', '--list']);
  assert.match(offline.stderr, /offline cache · stale/);
  assert.equal(JSON.parse(offline.stdout)[0].id, 'account-a');
  assert.equal(hits, 2);

  refused = false;
  const publicly = {FIXTURE_CATALOG_AUTH: 'none', FIXTURE_SURFACE: 'public'};
  await run(['models', 'demo', '--list'], publicly);
  assert.equal((await inventory(publicly)).models.find((m) => m.id === 'public-discovery').verification, 'catalog-only');
  assert.equal((await gateway(publicly)).some((m) => m.id === 'demo/public-discovery'), false);
  assert.equal(hits, 3);
});
