#!/usr/bin/env node
'use strict';
const {safeId, catalogOptions, readCatalogCache} = require('./catalog.js');
const {statePaths} = require('./model-state.js');
const {accountLiveEnabled, loadAccountLiveCatalog} = require('./account-live-catalog.js');
const env = process.env;
const name = env.CR_NAME || '';
if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) throw new Error('invalid provider');
const words = (s) => (s || '').split(/\s+/).filter(Boolean);
const keys = [];
for (const surface of ['PLAN', 'API']) for (const ref of words(env[`CR_KEYS_${surface}`])) {
  if (/^[A-Za-z0-9._:@+-]+$/.test(ref)) keys.push({surface: surface.toLowerCase(), ref});
}
if (['env', 'keychain', 'keypool'].includes(env.CR_AUTH_MODE)) {
  for (const ref of words(env.CR_KEYS_AUTH)) if (/^[A-Za-z0-9._:@+-]+$/.test(ref)) keys.push({surface: 'main', ref});
}
async function main() {
  if (accountLiveEnabled(env)) {
    const live = await loadAccountLiveCatalog(env);
    console.log(JSON.stringify({schema_version: 1, name, description: env.CR_DESC || '',
      status: live.status === 'available' ? 'ready' : live.status,
      model: env.CR_MODEL, hasPlan: env.CR_HAS_PLAN === '1', hasApi: env.CR_HAS_API === '1',
      authMode: env.CR_AUTH_MODE, keys,
      catalog: {source: live.source, status: live.status, reason: live.reason}, models: live.models}));
    return;
  }
  const cache = readCatalogCache({...catalogOptions(env), cacheFile: statePaths(name).cache, allowStale: true});
  const blocked = new Set(words(env.CR_MODEL_BLOCKED));
  const cached = (cache?.models || []).filter((m) => !blocked.has(m.id))
    .map((m) => ({...m, verification: cache.stale ? 'stale-catalog' : 'catalog-only'}));
  const cachedIds = new Set(cached.map((m) => m.id));
  const seeds = [...new Set(words(env.CR_MODELS))].filter((id) => safeId(id) && !blocked.has(id) && !cachedIds.has(id))
    .map((id) => ({id, name: '', context_length: 0, pricing: {}, verification: 'declared-only'}));
  console.log(JSON.stringify({schema_version: 1, name, description: env.CR_DESC || '', status: env.CR_STATUS,
    model: env.CR_MODEL, hasPlan: env.CR_HAS_PLAN === '1', hasApi: env.CR_HAS_API === '1',
    authMode: env.CR_AUTH_MODE, keys, catalog: cache ? {source: cache.source, stale: cache.stale, fetchedAt: cache.fetched_at} : null,
    models: [...seeds, ...cached]}));
}
main().catch((error) => { console.error('catalog-inventory.js: ' + error.message); process.exitCode = 1; });
