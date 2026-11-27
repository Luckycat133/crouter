'use strict';
// Account-scoped local App catalogs must never be reconstructed from static
// provider seeds or a cache captured before the App's account changed.
const {requestJson, normalizeModels, sourceEndpoint} = require('./catalog.js');

const ACCOUNT_LIVE_DEADLINE_MS = 7000;
const PROVIDERS = new Set(['antigravity', 'antigravity-claude']);
function accountLiveEnabled(env = process.env) {
  return env.CR_MODELS_ACCOUNT_LIVE === '1' && PROVIDERS.has(env.CR_PROVIDER);
}
function empty(status, reason) {
  return {models: [], source: 'account-live', stale: false, status, reason};
}
function liveEndpoint(env, candidateUrls) {
  const source = new URL(env.CR_CATALOG_SOURCE_URL || '');
  // This policy is for an already-running, local Antigravity proxy only. Do
  // not turn account detection into a remote request or send auth headers.
  if (source.protocol !== 'http:' || source.hostname !== '127.0.0.1' || !source.port ||
      source.username || source.password || source.search || source.hash ||
      !['', '/'].includes(source.pathname)) throw new Error('invalid local endpoint');
  const expected = `${source.origin}/v1/models`;
  if (env.CR_MODELS_API_AUTH !== 'none' || env.CR_MODELS_API_URL !== expected) throw new Error('invalid local directory binding');
  if (candidateUrls && (!candidateUrls.length || !candidateUrls.every((url) => sourceEndpoint(url) === sourceEndpoint(source.href)))) {
    throw new Error('inference endpoint differs from local directory');
  }
  return expected;
}
function acceptedModel(model, env) {
  const id = model && typeof model === 'object' && model.id;
  if (typeof id !== 'string' || id.endsWith('-disabled') || /orchestrator/i.test(id)) return false;
  if (model.disabled === true || model.enabled === false || model.available === false || model.retired === true ||
      /^(?:disabled|retired|unsupported|unavailable)$/i.test(String(model.status || ''))) return false;
  const blocked = new Set((env.CR_MODEL_BLOCKED || '').split(/\s+/).filter(Boolean));
  if (blocked.has(id)) return false;
  return env.CR_PROVIDER === 'antigravity' ? id.startsWith('gemini-') : id.startsWith('claude-');
}
async function loadAccountLiveCatalog(env = process.env, {candidateUrls, signal, timeoutMs = ACCOUNT_LIVE_DEADLINE_MS} = {}) {
  if (!accountLiveEnabled(env)) throw new Error('account-live policy is not enabled for this provider');
  let url;
  try { url = liveEndpoint(env, candidateUrls); }
  catch (_) { return empty('unknown', 'invalid-local-binding'); }
  if (env.CR_ACCOUNT_LIVE_NETWORK === '0') return empty('unknown', 'not-queried');
  try {
    // One GET, no retries, redirects or provider secrets. The proxy bounds its
    // cold account check to 6s and reuses its account metadata cache for 5min.
    // Allow 7s here so its first eligible response can reach this consumer.
    const payload = await requestJson(url, {auth: 'none', timeoutMs, maxBytes: 2 * 1024 * 1024, signal});
    if (!payload || !Array.isArray(payload.data)) return empty('unknown', 'invalid-directory');
    const rows = payload.data.filter((model) => acceptedModel(model, env));
    const models = normalizeModels({data: rows.map((model) => ({...model,
      name: model.name || model.display_name || model.description || ''}))})
      .map((model) => ({...model, verification: 'account-directory'}));
    return {models, source: 'account-live', stale: false, status: models.length ? 'available' : 'unavailable',
      reason: models.length ? '' : 'no-available-models'};
  } catch (error) {
    if (signal?.aborted) throw new Error('catalog cancelled');
    return empty(error.status === 401 || error.status === 403 || error.status === 503 ? 'unavailable' : 'unknown',
      error.status ? `catalog-http-${error.status}` : 'local-directory-unreachable');
  }
}
module.exports = {ACCOUNT_LIVE_DEADLINE_MS, accountLiveEnabled, loadAccountLiveCatalog};
