#!/usr/bin/env node
'use strict';
// Environment -> route JSON. Account-live App policies may read only their
// existing loopback directory; --check disables those reads. Inspect hides secrets.
const fs = require('node:fs');
const {catalogOptions, readCatalogCache, sourceEndpoint, positive} = require('./catalog.js');
const {statePaths} = require('./model-state.js');
const {accountLiveEnabled, loadAccountLiveCatalog} = require('./account-live-catalog.js');
const env = (name) => process.env[name] || '';
const words = (value) => value.split(/\s+/).filter(Boolean);

function buildCandidates() {
  if (env('CR_SURFACE_CANDIDATES')) {
    const supplied = JSON.parse(env('CR_SURFACE_CANDIDATES'));
    if (!Array.isArray(supplied)) throw new Error('CR_SURFACE_CANDIDATES must be an array');
    return supplied.map((c) => ({url: c.url, auth: {type: c.type, token: c.token}, model_map: c.model_map || {}, label: c.label || '', surface: c.surface || 'auth', extra_env: []}));
  }
  const apiUrl = env('CR_API_URL');
  const keys = words(env('CR_KEYPOOL_KEYS'));
  if (keys.length) return keys.map((token, index) => ({url: apiUrl, auth: {type: 'x-api-key', token}, label: `key-${index + 1}`, extra_env: []}));
  const candidates = [];
  if (env('CR_DEFAULT_TOKEN')) candidates.push({url: env('CR_DEFAULT_URL'), auth: {type: env('CR_DEFAULT_TYPE') || 'bearer', token: env('CR_DEFAULT_TOKEN')}, label: 'default-account', surface: 'default', extra_env: []});
  if (env('CR_API_KEY')) candidates.push({url: apiUrl, auth: {type: env('CR_API_TYPE') || env('CR_AUTH_SCHEME') || 'both', token: env('CR_API_KEY')},
    label: env('CR_AUTH_MODE') === 'static' ? 'static-placeholder' : 'api-key', surface: env('CR_EXPLICIT_API') ? 'api' : 'auth', extra_env: []});
  else if (env('CR_AUTH_MODE') === 'none') candidates.push({url: apiUrl, auth: {type: 'none', token: env('CR_NONE_TOKEN')}, label: 'no-auth', surface: 'public', extra_env: []});
  return candidates;
}
function surfaceCandidates() {
  const candidates = [];
  const modelMap = (prefix) => {
    const map = {};
    const def = env(`CR_${prefix}_MODEL`);
    for (const suffix of ['', '_OPUS', '_SONNET', '_HAIKU', '_SUBAGENT']) {
      const logical = env('CR_MODEL' + suffix);
      const upstream = env(`CR_${prefix}_MODEL${suffix}`) || (suffix ? def : '');
      if (!logical || !upstream) continue;
      if (Object.hasOwn(map, logical) && map[logical] !== upstream) throw new Error(`${prefix.toLowerCase()} model map is ambiguous for ${JSON.stringify(logical)}`);
      map[logical] = upstream;
    }
    return map;
  };
  const append = (surface, prefix, tokens, map) => {
    const url = env(`CR_${prefix}_URL`);
    if (!url) return;
    words(tokens).forEach((token, i) => candidates.push({url, type: env(`CR_${prefix}_TYPE`) || 'bearer', token, model_map: map,
      label: `${surface}-${i + 1}`, surface: prefix.toLowerCase()}));
  };
  const plan = modelMap('PLAN');
  const api = modelMap('API');
  append('token-plan', 'PLAN', env('CR_PLAN_TOKENS'), plan);
  const hasPlan = candidates.length > 0;
  const paidAllowed = !hasPlan || env('CROUTER_ALLOW_PAID_FALLBACK') === '1';
  // An explicit fee opt-in is not permission to silently substitute a
  // different upstream model. Compare every declared logical tier, not names.
  const sameMapping = Object.keys(plan).every((key) => Object.hasOwn(api, key) && api[key] === plan[key]);
  const modelAllowed = !hasPlan || sameMapping || env('CROUTER_ALLOW_CROSS_MODEL_FALLBACK') === '1';
  if (paidAllowed && modelAllowed) append('api-key', 'API', env('CR_API_TOKENS'), api);
  return candidates;
}
function catalogBinding(candidates) {
  const opts = catalogOptions(process.env, candidates[0].auth.token);
  if (!opts.provider || !opts.urls.length) return null;
  // A directory may enumerate more models than an account can use. Publish
  // a scoped listing only if every fallback stays on the same binding.
  try {
    const source = sourceEndpoint(opts.sourceUrl);
    if (!candidates.every((c) => sourceEndpoint(c.url) === source &&
      c.surface === opts.surface && (opts.auth === 'none' ? c.auth.type === 'none' : c.auth.token === opts.token))) return null;
  } catch (_) { return null; }
  return opts;
}
function catalogRouteModels(candidates, declared) {
  const opts = catalogBinding(candidates);
  if (!opts) return [];
  const cache = readCatalogCache({...opts, cacheFile: statePaths(opts.provider).cache});
  const omit = new Set([...declared, ...words(env('CR_MODEL_BLOCKED'))]);
  return (cache?.models || []).map((m) => m.id).filter((id) => !omit.has(id));
}
function catalogModelMetadata(candidates) {
  // Directory metadata is scoped by provider, endpoint, origin, surface and
  // credential digest, so a stale cache or another account can never leak
  // into this route's models.
  const opts = catalogBinding(candidates);
  if (!opts) return new Map();
  const cache = readCatalogCache({...opts, cacheFile: statePaths(opts.provider).cache});
  const meta = new Map();
  for (const m of (cache?.models || [])) {
    const entry = meta.get(m.id) || {};
    if (m.context_length) entry.context_length = m.context_length;
    if (m.max_output_tokens) entry.max_output_tokens = m.max_output_tokens;
    meta.set(m.id, entry);
  }
  return meta;
}
function liveModelMetadata(live) {
  const meta = new Map();
  for (const m of (live.models || [])) {
    const entry = {};
    if (m.context_length) entry.context_length = m.context_length;
    if (m.max_output_tokens) entry.max_output_tokens = m.max_output_tokens;
    meta.set(m.id, entry);
  }
  return meta;
}
// Whitespace-separated name=value pairs, matching provider override semantics:
// exact match first, then a trailing ':' name matches that id family.
function parseModelOverrides(value) {
  const map = new Map();
  for (const pair of words(value)) {
    const eq = pair.indexOf('=');
    if (eq < 1) continue;
    const name = pair.slice(0, eq);
    const limit = positive(pair.slice(eq + 1));
    if (name && limit) map.set(name, limit);
  }
  return map;
}
function overrideLimit(map, model) {
  if (map.has(model)) return map.get(model);
  for (const [name, limit] of map) {
    if (name.endsWith(':') && model.startsWith(name)) return limit;
  }
  return null;
}
function declaredModelLimits() {
  return {
    context: positive(env('CR_CONTEXT_TOKENS')),
    output: positive(env('CR_MAX_OUTPUT_TOKENS')),
    overrides: parseModelOverrides(env('CR_MODEL_CONTEXT_OVERRIDES')),
    primary: words(env('CR_MODELS'))[0] || '',
  };
}
function modelMetadataMap(models, limits, catalog) {
  const meta = {};
  for (const m of models) {
    const entry = {};
    const overridden = overrideLimit(limits.overrides, m);
    if (overridden !== null) entry.context_length = overridden;
    else if (m === limits.primary && limits.context) entry.context_length = limits.context;
    if (limits.output && m === limits.primary) entry.max_output_tokens = limits.output;
    const row = catalog.get(m);
    if (row) {
      if (row.context_length) entry.context_length = Math.min(entry.context_length || row.context_length, row.context_length);
      if (row.max_output_tokens) entry.max_output_tokens = Math.min(entry.max_output_tokens || row.max_output_tokens, row.max_output_tokens);
    }
    if (Object.keys(entry).length) meta[m] = entry;
  }
  return meta;
}
function preferredRoute(routes) {
  return routes.find((r) => r.prefix === 'anthropic') || routes.find((r) => r.auth_mode && !['none', 'static'].includes(r.auth_mode)) || routes[0];
}
function redactedUrl(value) {
  const u = new URL(value); u.username = ''; u.password = ''; u.search = ''; u.hash = '';
  return u.toString().replace(/\/$/, u.pathname === '/' ? '/' : '');
}
function inspect(routes) {
  if (!Array.isArray(routes) || !routes.length) throw new Error('no configured HTTP routes');
  const selected = preferredRoute(routes);
  console.log(`default: ${selected.prefix}/${selected.models[0] || ''}`);
  console.log(`summary: ${routes.length} configured HTTP route(s), ${routes.reduce((s, r) => s + r.candidates.length, 0)} credential candidate(s)`);
  for (const route of routes) {
    if (!route.prefix || !Array.isArray(route.models) || !Array.isArray(route.candidates)) throw new Error('invalid route shape');
    console.log(`${route.prefix}: ${route.models.length} model(s), ${route.candidates.length} candidate(s)`);
    if (route.accountCatalog) console.log(`  account model availability: ${route.accountCatalog.status} (${route.accountCatalog.reason || 'live directory'})`);
    route.candidates.forEach((c, i) => console.log(`  ${i + 1}. ${c.label || 'candidate-' + (i + 1)} | ${c.auth?.type || 'none'} | ${redactedUrl(c.url)} | model-map=${Object.keys(c.model_map || {}).length}`));
  }
  console.log('secrets: redacted; network requests: 0; Claude launches: 0');
}
module.exports = {buildCandidates, surfaceCandidates, preferredRoute, redactedUrl, modelMetadataMap};
async function main() {
  try {
    const [cmd, ...args] = process.argv.slice(2);
    switch (cmd) {
      case 'surface-candidates': process.stdout.write(JSON.stringify(surfaceCandidates())); break;
      case 'candidates': {
        const candidates = buildCandidates();
        if (candidates.length) {
          const blocked = new Set(words(env('CR_MODEL_BLOCKED')));
          const models = [...new Set(words(env('CR_MODELS')))].filter((model) => !blocked.has(model));
          const live = accountLiveEnabled(process.env)
            ? await loadAccountLiveCatalog(process.env, {candidateUrls: candidates.map((candidate) => candidate.url)}) : null;
          const catalogModels = (live ? live.models.map((model) => model.id) : catalogRouteModels(candidates, models))
            .filter((model) => !blocked.has(model));
          const advertised = live ? catalogModels : [...models, ...catalogModels];
          const limits = declaredModelLimits();
          const catalog = live ? liveModelMetadata(live) : catalogModelMetadata(candidates);
          console.log(JSON.stringify({prefix: env('CR_PREFIX'), auth_mode: env('CR_AUTH_MODE'),
            base_url: env('CR_API_URL') || env('CR_PLAN_URL') || env('CR_DEFAULT_URL'), candidates, models: advertised, catalogModels,
            ...(blocked.size ? {blockedModels: [...blocked]} : {}),
            modelMetadata: modelMetadataMap(advertised, limits, catalog),
            ...(live ? {accountCatalog: {status: live.status, reason: live.reason}} : {})}));
        }
        break;
      }
      case 'dual-candidates': {
        const candidates = [];
        if (env('CR_DEFAULT_TOKEN')) candidates.push({url: env('CR_DEFAULT_URL'), type: env('CR_DEFAULT_TYPE'), token: env('CR_DEFAULT_TOKEN'), label: 'default-account'});
        if (env('CR_API_KEY')) candidates.push({url: env('CR_API_URL'), type: env('CR_API_TYPE'), token: env('CR_API_KEY'), label: 'api-key'});
        process.stdout.write(JSON.stringify(candidates)); break;
      }
      case 'combine': {
        const routes = fs.readFileSync(args[0], 'utf8').split('\n').filter(Boolean).map((line) => JSON.parse(line));
        fs.writeFileSync(args[1], JSON.stringify(routes, null, 2)); break;
      }
      case 'default-model': {
        const route = preferredRoute(JSON.parse(fs.readFileSync(args[0], 'utf8')));
        process.stdout.write((route?.prefix || '') + '/' + (route?.models?.[0] || '')); break;
      }
      case 'inspect': inspect(JSON.parse(fs.readFileSync(args[0], 'utf8'))); break;
      default: throw new Error('unknown subcommand ' + JSON.stringify(cmd || ''));
    }
  } catch (e) { console.error('route-build.js: ' + e.message); process.exitCode = 1; }
}

if (require.main === module) main();
