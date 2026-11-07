'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const {once} = require('node:events');
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
});
