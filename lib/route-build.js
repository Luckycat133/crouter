#!/usr/bin/env node
// JSON builders for crouter's local proxies. Pure stdin/env -> stdout; no
// network, no filesystem writes except the explicit `combine` output path.
//
// Split out of bin/crouter so the route/candidate shapes live in one readable,
// testable place instead of several inline `node -e '...'` blocks.
//
//   candidates        One provider's gateway route object (NDJSON line) from
//                     the CR_* env contract below. Prints nothing when the
//                     provider has no usable credential.
//   dual-candidates   keypool-proxy candidate array for a dual-source direct
//                     launch (default account first, API key second).
//   combine <in> <out>  NDJSON route lines -> pretty-printed JSON array.
//   default-model <routes.json>  "<prefix>/<first model>" of the first route.
//
// Env contract (all optional, empty means "not configured"):
//   CR_PREFIX          provider name, used as the "<provider>/" model prefix
//   CR_MODELS          whitespace-separated model names (deduped here, order kept)
//   CR_KEYPOOL_KEYS    whitespace-separated keypool secrets; when non-empty every
//                      key becomes its own candidate and the surfaces below are
//                      ignored
//   CR_PLUS_KEYS       whitespace-separated plus-surface keys (tried first)
//   CR_PLUS_URL        plus-surface base URL (used with CR_PLUS_KEYS)
//   CR_DEFAULT_URL / CR_DEFAULT_TYPE / CR_DEFAULT_TOKEN   preferred surface
//   CR_API_URL / CR_API_TYPE / CR_API_KEY                 fallback surface
//   CR_AUTH_MODE       provider AUTH_MODE, only "none" is special-cased
//   CR_AUTH_SCHEME     provider _AUTH_SCHEME, used when CR_API_TYPE is unset
//   CR_NONE_TOKEN / CR_NONE_EXTRA   dummy token + KEY=VALUE pairs for AUTH_MODE=none

'use strict';

const fs = require('fs');

const env = (name) => process.env[name] || '';
const words = (value) => value.split(/\s+/).filter(Boolean);

// Candidates are tried in order; the proxy rotates to the next one on 401/429.
function buildCandidates() {
  const defaultUrl = env('CR_DEFAULT_URL');
  const apiUrl = env('CR_API_URL');
  const keypool = words(env('CR_KEYPOOL_KEYS'));
  const plusKeys = words(env('CR_PLUS_KEYS'));
  const plusUrl = env('CR_PLUS_URL');
  const keypoolAuthType = env('CR_KEYPOOL_AUTH_TYPE') || env('CR_AUTH_SCHEME') || 'x-api-key';

  // keypool with plus-first ordering: plus keys @ plusUrl first, then main keys @ apiUrl
  if (keypool.length || plusKeys.length) {
    if (plusKeys.length && !plusUrl) {
      process.stderr.write('route-build.js: CR_PLUS_KEYS set but CR_PLUS_URL is empty\n');
      process.exit(1);
    }
    const candidates = [];
    // Plus surface first
    for (const token of plusKeys) {
      candidates.push({
        url: plusUrl,
        auth: { type: keypoolAuthType, token },
        extra_env: [],
      });
    }
    // Main surface
    for (const token of keypool) {
      candidates.push({
        url: apiUrl,
        auth: { type: keypoolAuthType, token },
        extra_env: [],
      });
    }
    return candidates;
  }

  const candidates = [];
  // dual-source: preferred account first, API key fallback.
  if (env('CR_DEFAULT_TOKEN')) {
    candidates.push({
      url: defaultUrl,
      auth: { type: env('CR_DEFAULT_TYPE') || 'bearer', token: env('CR_DEFAULT_TOKEN') },
      extra_env: [],
    });
  }
  if (env('CR_API_KEY')) {
    // The provider may declare its header shape either as a dual-source
    // API_AUTH_TYPE or as the single-surface _AUTH_SCHEME; both mean the same
    // thing here.
    candidates.push({
      url: apiUrl,
      auth: {
        type: env('CR_API_TYPE') || env('CR_AUTH_SCHEME') || 'x-api-key',
        token: env('CR_API_KEY'),
      },
      extra_env: [],
    });
  } else if (env('CR_AUTH_MODE') === 'none') {
    // No credential at all (e.g. Ollama): pass the dummy token and whatever
    // EXTRA_ENV the provider needs on the wire.
    candidates.push({
      url: apiUrl,
      auth: { type: 'none', token: env('CR_NONE_TOKEN') },
      extra_env: words(env('CR_NONE_EXTRA')),
    });
  }
  return candidates;
}

function cmdCandidates() {
  const candidates = buildCandidates();
  if (candidates.length === 0) return; // no credential -> provider is skipped
  const models = [...new Set(words(env('CR_MODELS')))];
  process.stdout.write(
    JSON.stringify({ prefix: env('CR_PREFIX'), base_url: env('CR_API_URL'), candidates, models }) + '\n',
  );
}

// keypool-proxy's candidate-mode contract is a flatter shape than the gateway's.
function cmdDualCandidates() {
  const candidates = [];
  if (env('CR_DEFAULT_TOKEN')) {
    candidates.push({
      url: env('CR_DEFAULT_URL'),
      type: env('CR_DEFAULT_TYPE'),
      token: env('CR_DEFAULT_TOKEN'),
      label: 'default-account',
    });
  }
  if (env('CR_API_KEY')) {
    candidates.push({
      url: env('CR_API_URL'),
      type: env('CR_API_TYPE'),
      token: env('CR_API_KEY'),
      label: 'api-key',
    });
  }
  process.stdout.write(JSON.stringify(candidates));
}

function cmdCombine(inPath, outPath) {
  const routes = fs
    .readFileSync(inPath, 'utf8')
    .split('\n')
    .filter(Boolean)
    .map((line) => JSON.parse(line));
  fs.writeFileSync(outPath, JSON.stringify(routes, null, 2));
}

function cmdDefaultModel(routesPath) {
  const routes = JSON.parse(fs.readFileSync(routesPath, 'utf8'));
  const first = routes[0];
  const prefix = (first && first.prefix) || '';
  const model = (first && first.models && first.models[0]) || '';
  if (!prefix || !model) {
    process.stdout.write('');
    return;
  }
  process.stdout.write(prefix + '/' + model);
}

const [subcommand, ...args] = process.argv.slice(2);
switch (subcommand) {
  case 'candidates':
    cmdCandidates();
    break;
  case 'dual-candidates':
    cmdDualCandidates();
    break;
  case 'combine':
    cmdCombine(args[0], args[1]);
    break;
  case 'default-model':
    cmdDefaultModel(args[0]);
    break;
  default:
    process.stderr.write('route-build.js: unknown subcommand ' + JSON.stringify(subcommand || '') + '\n');
    process.exit(2);
}
