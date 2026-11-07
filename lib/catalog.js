'use strict';
// Model catalogs are data. No provider code, credentials store, or inference
// is executed here. HTTP reads are bounded and bound to one explicit origin.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const http = require('node:http');
const https = require('node:https');

const TTL = 86400000;
const MAX_BYTES = 8 * 1024 * 1024;
const safeId = (s) => typeof s === 'string' && s.length > 0 && s.length <= 512 && !/[\s\x00-\x1f\x7f]/u.test(s);
const positive = (v) => Number.isSafeInteger(Number(v)) && Number(v) > 0 && Number(v) <= 100000000 ? Number(v) : null;
const rate = (v) => v !== null && v !== undefined && String(v).trim() !== '' && Number.isFinite(Number(v)) && Number(v) >= 0 ? Number(v) : null;
const clamp = (...values) => { const n = values.map(positive).filter(Boolean); return n.length ? Math.min(...n) : 0; };

function pricingOf(model) {
  const p = model && model.pricing;
  const pair = (a, b) => ({prompt: rate(a), completion: rate(b)});
  if (p && !Array.isArray(p)) {
    for (const [a, b] of [['prompt', 'completion'], ['input', 'output'], ['per_input_token', 'per_output_token']]) {
      if (Object.hasOwn(p, a) || Object.hasOwn(p, b)) return pair(p[a], p[b]);
    }
  }
  if (Array.isArray(p) && p.length) {
    // Only an explicitly identified base tier can be displayed as the base
    // price. Preserve the original tiers; they are not a flat billing quote.
    const base = p.find((r) => r && Number(r.prompt_tokens_threshold) === 0);
    if (base) return pair(base.input_price, base.output_price);
  }
  return pair(null, null);
}
function isFree(model) {
  const p = pricingOf(model);
  // Slugs and model names are not billing proof. Unknown means unknown.
  return p.prompt === 0 && p.completion === 0;
}
function fmtPrice(model) {
  const p = pricingOf(model);
  if (p.prompt === null || p.completion === null) return 'unknown';
  return isFree(model) ? 'FREE' : `$${(p.prompt * 1e6).toFixed(2)}/$${(p.completion * 1e6).toFixed(2)}`;
}
function normalizeModels(payload) {
  if (!payload || typeof payload !== 'object') throw new Error('invalid catalog JSON');
  const rows = Array.isArray(payload) ? payload : (payload.data || payload.models);
  if (!Array.isArray(rows)) throw new Error('catalog must contain a model array');
  const seen = new Set();
  const models = [];
  for (const value of rows) {
    const m = typeof value === 'string' ? {id: value} : value;
    if (!m || typeof m !== 'object' || !safeId(m.id || m.model)) continue;
    const id = m.id || m.model;
    if (seen.has(id)) continue;
    // Explicit modality / endpoint restrictions take precedence over names.
    const out = m.output_modalities || (m.architecture && m.architecture.output_modalities);
    if (Array.isArray(out) && out.length && !out.includes('text')) continue;
    if (m.type && ['image', 'video', 'audio', 'embedding', 'embeddings', 'reranking'].includes(m.type)) continue;
    if (m.batch_only === true || /(?:^|[-/:])batch(?:$|[-/:])/i.test(id)) continue;
    const operations = Array.isArray(m.operations) ? m.operations : [];
    const chat = operations.find((op) => {
      if (!op || typeof op !== 'object') return false;
      const endpoints = Array.isArray(op.endpoints) ? op.endpoints : [];
      return endpoints.some((e) => /messages|chat|responses/.test(typeof e === 'string' ? e : String(e.path || e.type || '')));
    });
    if (operations.length && !chat) continue;
    const top = m.top_provider || {};
    const limits = (chat && chat.limits) || {};
    seen.add(id);
    models.push({
      id,
      name: typeof (m.name || m.display_name) === 'string' ? (m.name || m.display_name).slice(0, 512) : '',
      context_length: clamp(m.context_length || m.context_window || m.context_size || m.max_input_tokens, top.context_length, limits.context_window),
      max_output_tokens: clamp(m.max_output_tokens || m.max_tokens, top.max_completion_tokens, limits.max_output_tokens),
      pricing: m.pricing && typeof m.pricing === 'object' ? m.pricing : {},
      supported_parameters: Array.isArray(m.supported_parameters) ? m.supported_parameters.filter((x) => typeof x === 'string') : [],
      input_modalities: Array.isArray(m.input_modalities) ? m.input_modalities : (m.architecture?.input_modalities || []),
      output_modalities: Array.isArray(out) ? out : [],
      effort_levels: Array.isArray(m.effort?.supported_levels) ? m.effort.supported_levels : [],
      // Catalog listing is never evidence of this account's model entitlement.
      verification: 'catalog-only',
    });
  }
  return models;
}
function safeUrl(value) {
  const u = new URL(value);
  if (!['http:', 'https:'].includes(u.protocol) || u.username || u.password || u.hash) throw new Error('invalid catalog URL');
  return u;
}
function requestJson(url, options = {}) {
  const u = safeUrl(url);
  const {auth = 'none', token = '', signal, timeoutMs = 8000, maxBytes = MAX_BYTES} = options;
  if (!['none', 'bearer', 'x-api-key', 'both'].includes(auth)) return Promise.reject(new Error('unsupported catalog auth'));
  const headers = {Accept: 'application/json', 'User-Agent': 'crouter/catalog'};
  if (auth !== 'none' && token) {
    if (!options.authOrigin || u.origin !== new URL(options.authOrigin).origin) return Promise.reject(new Error('catalog credential origin mismatch'));
    if (auth === 'bearer' || auth === 'both') headers.Authorization = `Bearer ${token}`;
    if (auth === 'x-api-key' || auth === 'both') headers['x-api-key'] = token;
  }
  if (auth === 'x-api-key' && u.hostname === 'api.anthropic.com') headers['anthropic-version'] = '2023-06-01';
  if (u.hostname === 'api.naga.ac') headers['x-naga-supported-endpoint'] = 'messages';
  return new Promise((resolve, reject) => {
    if (signal && signal.aborted) return reject(new Error('catalog cancelled'));
    let done = false;
    let timer;
    const finish = (err, result) => {
      if (done) return;
      done = true;
      clearTimeout(timer);
      if (signal) signal.removeEventListener('abort', abort);
      if (err) reject(err); else resolve(result);
    };
    const req = (u.protocol === 'https:' ? https : http).request(u, {method: 'GET', headers}, (res) => {
      if (res.statusCode < 200 || res.statusCode >= 300) {
        // Never follow redirects with credentials, and never parse an error
        // body as a valid model list. Do not include URL queries in errors.
        const error = new Error(`catalog HTTP ${res.statusCode}`);
        error.status = res.statusCode;
        res.resume();
        finish(error);
        return;
      }
      const chunks = []; let size = 0;
      res.on('data', (chunk) => {
        size += chunk.length;
        if (size > maxBytes) { finish(new Error('catalog response too large')); req.destroy(); res.destroy(); return; }
        chunks.push(chunk);
      });
      res.on('aborted', () => finish(new Error('catalog response interrupted')));
      res.on('error', () => finish(new Error('catalog response failed')));
      res.on('end', () => {
        try { finish(null, JSON.parse(Buffer.concat(chunks).toString('utf8'))); }
        catch (_) { finish(new Error('invalid catalog JSON')); }
      });
    });
    function abort() { finish(new Error('catalog cancelled')); req.destroy(); }
    if (signal) signal.addEventListener('abort', abort, {once: true});
    req.on('error', () => finish(new Error('catalog connection failed')));
    timer = setTimeout(() => { finish(new Error('catalog deadline exceeded')); req.destroy(); }, timeoutMs);
    req.end();
  });
}
async function fetchCatalog(url, options = {}) {
  const start = Date.now();
  const deadline = options.deadlineMs || 12000;
  let next = safeUrl(url); const origin = next.origin;
  let all = [];
  for (let page = 0; page < 10; page++) {
    const left = deadline - (Date.now() - start);
    if (left <= 0) throw new Error('catalog deadline exceeded');
    let payload;
    for (let attempt = 0; attempt < 3; attempt++) {
      const remaining = deadline - (Date.now() - start);
      if (remaining <= 0 || options.signal?.aborted) throw new Error('catalog deadline exceeded or cancelled');
      try {
        payload = await requestJson(next, {...options, timeoutMs: Math.min(remaining, options.timeoutMs || 8000)});
        break;
      } catch (error) {
        const retryable = (error.status >= 500 && error.status <= 599) || /connection failed|deadline exceeded|interrupted/.test(error.message);
        if (!retryable || attempt === 2 || options.signal?.aborted) throw error;
        await new Promise((resolve) => {
          const abort = () => { clearTimeout(timer); resolve(); };
          const timer = setTimeout(() => { options.signal?.removeEventListener('abort', abort); resolve(); }, Math.min(200 * (attempt + 1), remaining));
          if (options.signal?.aborted) abort(); else options.signal?.addEventListener('abort', abort, {once: true});
        });
      }
    }
    all.push(...normalizeModels(payload));
    if (!payload.has_more) return [...new Map(all.map((m) => [m.id, m])).values()];
    // Anthropic pagination; an advertised arbitrary next URL is not trusted.
    if (!safeId(payload.last_id)) throw new Error('unsupported catalog pagination');
    next = new URL(url);
    if (next.origin !== origin) throw new Error('catalog origin changed');
    next.searchParams.set('after_id', payload.last_id);
  }
  throw new Error('catalog page limit exceeded');
}
function scopeKey({provider, url = '', surface = '', token = '', auth = 'none'}) {
  // Secret never appears in cache or filenames. A digest isolates catalog
  // entitlements after credential rotation (API keys must be high entropy).
  return crypto.createHash('sha256').update(JSON.stringify([provider, url, surface, auth, auth === 'none' ? '' : token])).digest('hex');
}
function atomicJson(file, value) {
  fs.mkdirSync(path.dirname(file), {recursive: true, mode: 0o700});
  const tmp = `${file}.${process.pid}.${crypto.randomBytes(6).toString('hex')}.tmp`;
  try {
    fs.writeFileSync(tmp, JSON.stringify(value, null, 2) + '\n', {mode: 0o600, flag: 'wx'});
    fs.renameSync(tmp, file);
  } finally { try { fs.unlinkSync(tmp); } catch (_) {} }
}
async function loadCatalog(options) {
  const {provider, urls = [], staticModels = [], cacheFile, force = false, now = Date.now()} = options;
  if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(provider || '')) throw new Error('invalid provider name');
  const scope = scopeKey({...options, url: urls.join('\n')});
  let cached;
  if (cacheFile) {
    try {
      if (!fs.lstatSync(cacheFile).isFile() || fs.statSync(cacheFile).size > MAX_BYTES) throw new Error('invalid cache file');
      const c = JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
      if (c.schema_version === 1 && c.scope === scope && Number.isFinite(c.fetched_at) && c.fetched_at <= now && Array.isArray(c.models)) {
        cached = {...c, models: normalizeModels(c.models)};
      }
    } catch (_) {}
  }
  if (!force && cached && now - cached.fetched_at < TTL) return {...cached, stale: false, source: 'cache'};
  const start = Date.now(); const deadlineMs = options.deadlineMs || 12000;
  for (const url of urls) {
    const left = deadlineMs - (Date.now() - start);
    if (left <= 0 || options.signal?.aborted) break;
    try {
      const models = await fetchCatalog(url, {...options, deadlineMs: left});
      if (!models.length) throw new Error('empty catalog');
      const result = {schema_version: 1, scope, fetched_at: now, models, source: 'remote', stale: false};
      if (cacheFile) {
        try { atomicJson(cacheFile, result); }
        catch (_) { result.cache_write_failed = true; if (options.onWarning) options.onWarning('catalog cache could not be saved'); }
      }
      return result;
    } catch (error) {
      if (options.signal?.aborted) throw new Error('catalog cancelled');
      if (options.onWarning) options.onWarning(error.message);
      // A credential rejection is not a reason to send the same secret to
      // another guessed URL. Static/offline fallback remains available.
      if (error.status === 401 || error.status === 403) break;
    }
  }
  if (cached) return {...cached, source: 'cache', stale: true};
  return {schema_version: 1, scope, fetched_at: null, models: normalizeModels(staticModels), source: 'static', stale: false};
}
module.exports = {normalizeModels, pricingOf, isFree, fmtPrice, safeId, positive, safeUrl, requestJson, fetchCatalog, scopeKey, atomicJson, loadCatalog};
