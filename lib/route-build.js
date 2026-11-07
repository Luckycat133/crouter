#!/usr/bin/env node
'use strict';
// Pure environment -> route JSON. Secrets are never logged by inspect.
const fs = require('node:fs');
const env = (name) => process.env[name] || '';
const words = (value) => value.split(/\s+/).filter(Boolean);

function buildCandidates() {
  if (env('CR_SURFACE_CANDIDATES')) {
    const supplied = JSON.parse(env('CR_SURFACE_CANDIDATES'));
    if (!Array.isArray(supplied)) throw new Error('CR_SURFACE_CANDIDATES must be an array');
    return supplied.map((c) => ({url: c.url, auth: {type: c.type, token: c.token}, model_map: c.model_map || {}, label: c.label || '', extra_env: []}));
  }
  const apiUrl = env('CR_API_URL');
  const keys = words(env('CR_KEYPOOL_KEYS'));
  if (keys.length) return keys.map((token, index) => ({url: apiUrl, auth: {type: 'x-api-key', token}, label: `key-${index + 1}`, extra_env: []}));
  const candidates = [];
  if (env('CR_DEFAULT_TOKEN')) candidates.push({url: env('CR_DEFAULT_URL'), auth: {type: env('CR_DEFAULT_TYPE') || 'bearer', token: env('CR_DEFAULT_TOKEN')}, label: 'default-account', extra_env: []});
  if (env('CR_API_KEY')) candidates.push({url: apiUrl, auth: {type: env('CR_API_TYPE') || env('CR_AUTH_SCHEME') || 'both', token: env('CR_API_KEY')}, label: env('CR_AUTH_MODE') === 'static' ? 'static-placeholder' : 'api-key', extra_env: []});
  else if (env('CR_AUTH_MODE') === 'none') candidates.push({url: apiUrl, auth: {type: 'none', token: env('CR_NONE_TOKEN')}, label: 'no-auth', extra_env: []});
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
    words(tokens).forEach((token, i) => candidates.push({url, type: env(`CR_${prefix}_TYPE`) || 'bearer', token, model_map: map, label: `${surface}-${i + 1}`}));
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
    route.candidates.forEach((c, i) => console.log(`  ${i + 1}. ${c.label || 'candidate-' + (i + 1)} | ${c.auth?.type || 'none'} | ${redactedUrl(c.url)} | model-map=${Object.keys(c.model_map || {}).length}`));
  }
  console.log('secrets: redacted; network requests: 0; Claude launches: 0');
}
module.exports = {buildCandidates, surfaceCandidates, preferredRoute, redactedUrl};
if (require.main === module) {
  try {
    const [cmd, ...args] = process.argv.slice(2);
    switch (cmd) {
      case 'surface-candidates': process.stdout.write(JSON.stringify(surfaceCandidates())); break;
      case 'candidates': {
        const candidates = buildCandidates();
        if (candidates.length) console.log(JSON.stringify({prefix: env('CR_PREFIX'), auth_mode: env('CR_AUTH_MODE'), base_url: env('CR_API_URL') || env('CR_PLAN_URL') || env('CR_DEFAULT_URL'), candidates, models: [...new Set(words(env('CR_MODELS')))]}));
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
