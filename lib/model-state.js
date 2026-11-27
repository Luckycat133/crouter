'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {createHash} = require('node:crypto');
const {atomicJson, catalogOptions, positive, readCatalogCache, safeId} = require('./catalog.js');
function statePaths(provider) {
  const dir = path.join(process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local', 'state'), 'crouter');
  return {dir, cache: path.join(dir, `models-${provider}.json`), model: path.join(dir, `last-model-${provider}`),
    context: path.join(dir, `${provider}-context`), record: path.join(dir, `selection-${provider}.json`),
    recent: path.join(dir, `recent-${provider}.json`)};
}
function current(paths) {
  try { return fs.readFileSync(paths.model, 'utf8').trim(); } catch (_) { return ''; }
}
function recent(paths) {
  try {
    const value = JSON.parse(fs.readFileSync(paths.recent, 'utf8'));
    if (value.schema_version === 1 && safeId(value.model) && Number.isSafeInteger(value.completedAt)) return value;
  } catch (_) {}
  return null;
}

const MAX_FAVORITES = 256;
function validFavorite(id) {
  if (typeof id !== 'string') return false;
  const slash = id.indexOf('/');
  return slash > 0 && slash <= 128 && /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(id.slice(0, slash)) && safeId(id.slice(slash + 1));
}
function readFavorites(dir) {
  const file = path.join(dir, 'favorites.json');
  try {
    const stat = fs.lstatSync(file);
    if (!stat.isFile() || stat.size > 256 * 1024) throw new Error('invalid favorites file');
    const value = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (value.schema_version !== 1 || !Array.isArray(value.models) || value.models.length > MAX_FAVORITES ||
        !value.models.every(validFavorite)) throw new Error('invalid schema');
    return new Set(value.models);
  } catch (error) {
    if (error.code === 'ENOENT') return new Set();
    throw new Error('无法读取收藏，请检查收藏文件。');
  }
}
function toggleFavorite(dir, id) {
  if (!validFavorite(id)) throw new Error('无效的收藏模型。');
  fs.mkdirSync(dir, {recursive: true, mode: 0o700});
  const lock = path.join(dir, '.favorites.lock');
  try { fs.mkdirSync(lock, {mode: 0o700}); }
  catch (_) { throw new Error('收藏正在更新，请稍后重试。'); }
  try {
    const favorites = readFavorites(dir);
    if (!favorites.delete(id)) {
      if (favorites.size >= MAX_FAVORITES) throw new Error('已达到收藏上限。');
      favorites.add(id);
    }
    atomicJson(path.join(dir, 'favorites.json'), {schema_version: 1, models: [...favorites]});
    return favorites;
  } finally { fs.rmdirSync(lock); }
}
function writeText(file, text) {
  const tmp = `${file}.${process.pid}.tmp`;
  try { fs.writeFileSync(tmp, text, {mode: 0o600, flag: 'wx'}); fs.renameSync(tmp, file); }
  finally { try { fs.unlinkSync(tmp); } catch (_) {} }
}
function selectionRevision(paths) {
  const marks = [paths.model, paths.context, paths.record].map((file) => {
    try {
      const stat = fs.lstatSync(file, {bigint: true});
      return `${stat.dev}:${stat.ino}:${stat.size}:${stat.mtimeNs}:${stat.ctimeNs}`;
    } catch (e) { if (e.code === 'ENOENT') return '-'; throw e; }
  });
  return createHash('sha256').update(marks.join('\n')).digest('hex');
}
function saveSelection(paths, provider, model, {makeDefault = false, expectedRevision} = {}) {
  const target = path.join(paths.dir, 'selection');
  if (makeDefault) {
    if (!path.isAbsolute(paths.dir)) throw new Error('XDG_STATE_HOME must be an absolute path');
    try {
      if (!fs.lstatSync(target).isFile()) throw new Error('default target state must be a regular file');
    } catch (e) { if (e.code !== 'ENOENT') throw e; }
  }
  fs.mkdirSync(paths.dir, {recursive: true, mode: 0o700});
  const lock = path.join(paths.dir, `.selection-${provider}.lock`);
  try { fs.mkdirSync(lock, {mode: 0o700}); } catch (_) { throw new Error('selection is locked; retry after the other writer exits'); }
  const previous = new Map();
  try {
    // A browse or local launch can last hours. A newer explicit save wins.
    if (expectedRevision && selectionRevision(paths) !== expectedRevision) return false;
    for (const file of [paths.model, paths.context, paths.record]) {
      try {
        if (!fs.lstatSync(file).isFile()) throw new Error('selection state must be a regular file');
        previous.set(file, fs.readFileSync(file));
      } catch (e) { if (e.code === 'ENOENT') previous.set(file, null); else throw e; }
    }
    writeText(paths.model, model.id + '\n');
    if (positive(model.context_length)) writeText(paths.context, String(model.context_length) + '\n');
    else { try { fs.unlinkSync(paths.context); } catch (e) { if (e.code !== 'ENOENT') throw e; } }
    // The versioned record binds limits to the exact model; legacy files are
    // compatibility mirrors and must never override a different selection.
    atomicJson(paths.record, {schema_version: 1, provider, model: model.id, context_length: positive(model.context_length), max_output_tokens: positive(model.max_output_tokens), updated_at: Date.now()});
    // Commit the default target last. A failed write leaves its previous value
    // and rolls back this provider's selection under the same provider lock.
    if (makeDefault) writeText(target, provider + '\n');
    return true;
  } catch (e) {
    for (const [file, old] of previous) {
      try { if (old === null) fs.unlinkSync(file); else writeText(file, old); } catch (_) {}
    }
    throw e;
  } finally { fs.rmdirSync(lock); }
}

function readLimits(provider, model) {
  const paths = statePaths(provider);
  try {
    const record = JSON.parse(fs.readFileSync(paths.record, 'utf8'));
    if (record.schema_version === 1 && record.provider === provider && record.model === model) {
      return {context: positive(record.context_length), output: positive(record.max_output_tokens)};
    }
    // A new-format record is authoritative: never resurrect a stale mirror.
    return {};
  } catch (e) { if (e.code !== 'ENOENT') return {}; }
  if (current(paths) !== model) return {};
  try { return {context: positive(fs.readFileSync(paths.context, 'utf8').trim())}; } catch (_) { return {}; }
}
function readContext(provider, model) { return readLimits(provider, model).context || null; }

function describePlan(provider, model, context, output, compact) {
  const e = process.env;
  const refs = (value) => [...new Set(value.trim().split(/\s+/).filter((x) => /^[A-Za-z0-9._:@+-]+$/.test(x)))];
  const origin = (url) => {
    try { const u = new URL(url); return ['https:', 'http:'].includes(u.protocol) ? u.origin : null; } catch (_) { return null; }
  };
  const scope = (surface, url, names) => ({surface, origin: origin(url), credentialRefs: refs(names)});
  const tiers = e.LP_NATIVE ? null : {opus: e.LP_TIER_OPUS, sonnet: e.LP_TIER_SONNET, haiku: e.LP_TIER_HAIKU, subagent: e.LP_TIER_SUBAGENT};
  const candidates = [];
  if (e.LP_DEFAULT_URL) candidates.push(scope('default', e.LP_DEFAULT_URL, e.LP_DEFAULT_REFS));
  if (e.LP_PLAN_URL) candidates.push(scope('plan', e.LP_PLAN_URL, e.LP_PLAN_REFS));
  if (e.LP_API_URL) candidates.push(scope('api', e.LP_API_URL, e.LP_API_REFS));
  if (!candidates.length) candidates.push(scope('direct', e.LP_SOURCE, e.LP_AUTH_REFS));
  const effort = ['low', 'medium', 'high', 'xhigh', 'max'].includes(e.LP_EFFORT) ? e.LP_EFFORT : null;
  const warnings = [];
  if (!positive(context)) warnings.push('Model context is unknown');
  if (!effort && (e.LP_EFFORT || e.LP_EFFORT_SOURCE === 'caller')) warnings.push('Effort is delegated to Claude Code');
  const assets = e.LP_ASSETS_ENABLED === '0' ? null : {
    profile: e.LP_ASSET_PROFILE || (e.LP_AUTH_MODE === 'surfaces' ? 'empty' : null),
    plugins: e.LP_PLUGINS.split('\n').filter(Boolean).map((dir) => path.basename(dir)),
    planPlugins: e.LP_PLAN_PLUGINS.split('\n').filter(Boolean).map((dir) => path.basename(dir)),
    apiPlugins: e.LP_API_PLUGINS.split('\n').filter(Boolean).map((dir) => path.basename(dir)),
  };
  return {
    schemaVersion: 1, model, source: {provider, authMode: e.LP_AUTH_MODE, origin: origin(e.LP_SOURCE), candidates},
    tiers, contextTokens: positive(context), maxOutputTokens: positive(output), compactAtTokens: positive(compact),
    effort, effortSource: e.LP_EFFORT_SOURCE,
    constraints: {paidFallback: e.LP_PAID_FALLBACK === '1', crossModelFallback: e.LP_CROSS_MODEL_FALLBACK === '1'},
    services: e.LP_SERVICE ? [e.LP_SERVICE] : [], assets,
    client: {name: 'claude-code', nativeBackend: e.LP_NATIVE || null, strictMcp: Boolean(assets && assets.profile && e.LP_STRICT_MCP === '1')},
    warnings,
  };
}
module.exports = {statePaths, current, recent, readFavorites, toggleFavorite, saveSelection, readContext};
if (require.main === module) {
  try {
    const [action, provider, model, context, output, compact] = process.argv.slice(2);
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(provider || '') || !safeId(model)) throw new Error('invalid model selection');
    if (['write', 'write-default', 'write-if-current'].includes(action)) {
      if (action === 'write-if-current' && !/^[a-f0-9]{64}$/.test(compact || '')) throw new Error('invalid selection revision');
      saveSelection(statePaths(provider), provider, {id: model, context_length: positive(context), max_output_tokens: positive(output)},
        {makeDefault: action === 'write-default', expectedRevision: action === 'write-if-current' ? compact : undefined});
    }
    else if (action === 'context') process.stdout.write(String(readContext(provider, model) || ''));
    else if (action === 'limits') {
      const limits = readLimits(provider, model);
      const paths = statePaths(provider);
      const cache = readCatalogCache({...catalogOptions(), provider, cacheFile: paths.cache});
      const row = cache?.models.find((entry) => entry.id === model);
      const bounds = [limits.context, limits.output, row?.context_length, row?.max_output_tokens].map((value) => value || 0);
      process.stdout.write(`${bounds.join(' ')} ${selectionRevision(paths)}`);
    }
    else if (action === 'plan') console.log(JSON.stringify(describePlan(provider, model, context, output, compact), null, 2));
    else if (action === 'recent') atomicJson(statePaths(provider).recent, {schema_version: 1, model, completedAt: Date.now()});
    else throw new Error('unsupported model-state operation');
  } catch (e) { console.error('model-state: ' + e.message); process.exitCode = 1; }
}
