'use strict';
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {atomicJson, positive, safeId} = require('./catalog.js');
function statePaths(provider) {
  const dir = path.join(process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local', 'state'), 'crouter');
  return {dir, cache: path.join(dir, `models-${provider}.json`), model: path.join(dir, `last-model-${provider}`), context: path.join(dir, `${provider}-context`), record: path.join(dir, `selection-${provider}.json`)};
}
function current(paths) {
  try { return fs.readFileSync(paths.model, 'utf8').trim(); } catch (_) { return ''; }
}
function writeText(file, text) {
  const tmp = `${file}.${process.pid}.tmp`;
  try { fs.writeFileSync(tmp, text, {mode: 0o600, flag: 'wx'}); fs.renameSync(tmp, file); }
  finally { try { fs.unlinkSync(tmp); } catch (_) {} }
}
function saveSelection(paths, provider, model) {
  fs.mkdirSync(paths.dir, {recursive: true, mode: 0o700});
  const lock = path.join(paths.dir, `.selection-${provider}.lock`);
  try { fs.mkdirSync(lock, {mode: 0o700}); } catch (_) { throw new Error('selection is locked; retry after the other writer exits'); }
  const previous = new Map();
  try {
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
  } catch (e) {
    for (const [file, old] of previous) {
      try { if (old === null) fs.unlinkSync(file); else writeText(file, old); } catch (_) {}
    }
    throw e;
  } finally { fs.rmdirSync(lock); }
}

function readContext(provider, model) {
  const paths = statePaths(provider);
  try {
    const record = JSON.parse(fs.readFileSync(paths.record, 'utf8'));
    if (record.schema_version === 1 && record.provider === provider && record.model === model) return positive(record.context_length);
    // A new-format record is authoritative: never resurrect a stale mirror.
    return null;
  } catch (e) { if (e.code !== 'ENOENT') return null; }
  if (current(paths) !== model) return null;
  try { return positive(fs.readFileSync(paths.context, 'utf8').trim()); } catch (_) { return null; }
}
module.exports = {statePaths, current, saveSelection, readContext};
if (require.main === module) {
  try {
    const [action, provider, model, context] = process.argv.slice(2);
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(provider || '') || !safeId(model)) throw new Error('invalid model selection');
    if (action === 'write') saveSelection(statePaths(provider), provider, {id: model, context_length: positive(context)});
    else if (action === 'context') process.stdout.write(String(readContext(provider, model) || ''));
    else throw new Error('unsupported model-state operation');
  } catch (e) { console.error('model-state: ' + e.message); process.exitCode = 1; }
}
