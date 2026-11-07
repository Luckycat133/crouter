#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {safeId, normalizeModels} = require('./catalog.js');
function cachedModels(file) {
  try {
    if (!fs.lstatSync(file).isFile() || fs.statSync(file).size > 8 * 1024 * 1024) return [];
    const value = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (value.schema_version !== 1) return [];
    return normalizeModels(value.models);
  } catch (_) { return []; }
}
if (process.argv[2] === '--models') {
  process.stdout.write(cachedModels(process.argv[3]).map((m) => m.id).join(' '));
} else {
  const env = process.env;
  const name = env.CR_NAME || '';
  if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name)) throw new Error('invalid provider');
  const words = (s) => (s || '').split(/\s+/).filter(safeId);
  const keys = [];
  for (const surface of ['PLAN', 'API']) for (const ref of words(env[`CR_KEYS_${surface}`])) {
    if (/^[A-Za-z0-9._:@+-]+$/.test(ref)) keys.push({surface: surface.toLowerCase(), ref});
  }
  if (['env', 'keychain', 'keypool'].includes(env.CR_AUTH_MODE)) {
    for (const ref of words(env.CR_KEYS_AUTH)) if (/^[A-Za-z0-9._:@+-]+$/.test(ref)) keys.push({surface: 'main', ref});
  }
  const state = path.join(env.XDG_STATE_HOME || path.join(os.homedir(), '.local', 'state'), 'crouter');
  const cache = cachedModels(path.join(state, `models-${name}.json`));
  const seeds = [...new Set(words(env.CR_MODELS))].map((id) => ({id, name: '', context_length: 0, pricing: {}, verification: 'declared-only'}));
  console.log(JSON.stringify({schema_version: 1, name, description: env.CR_DESC || '', status: env.CR_STATUS,
    model: env.CR_MODEL, hasPlan: env.CR_HAS_PLAN === '1', hasApi: env.CR_HAS_API === '1',
    authMode: env.CR_AUTH_MODE, keys, models: cache.length ? cache : seeds}));
}
