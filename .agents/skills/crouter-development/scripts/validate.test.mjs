#!/usr/bin/env node
// Positive and deliberately broken package fixtures. No provider code or secrets.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {validatePackage} from './validate.mjs';

const skillRelative = '.agents/skills/crouter-development';
const root = path.resolve(path.dirname(fs.realpathSync(fileURLToPath(import.meta.url))), '../../../..');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'crouter skill fixtures '));
let count = 0;
function fixture() {
  const destination = path.join(temp, String(count++));
  fs.mkdirSync(path.join(destination, '.agents/skills'), {recursive: true});
  fs.cpSync(path.join(root, skillRelative), path.join(destination, skillRelative), {recursive: true});
  for (const file of ['AGENTS.md', '.agents/SKILLS.md', 'CLAUDE.md', 'docs/development-plan.md', 'test/development-skill.sh']) {
    fs.mkdirSync(path.dirname(path.join(destination, file)), {recursive: true});
    fs.copyFileSync(path.join(root, file), path.join(destination, file));
  }
  for (const host of ['.claude', '.codex']) {
    const entry = path.join(destination, host, 'skills', 'crouter-development');
    fs.mkdirSync(path.dirname(entry), {recursive: true});
    fs.symlinkSync('../../.agents/skills/crouter-development', entry);
  }
  return destination;
}
function edit(directory, relative, transform) {
  const file = path.join(directory, skillRelative, relative);
  fs.writeFileSync(file, transform(fs.readFileSync(file, 'utf8')));
}
function rejects(label, mutate, expected) {
  const directory = fixture();
  mutate(directory);
  const failures = validatePackage(directory).failures;
  assert(failures.some((message) => message.includes(expected)), `${label}: expected ${expected}; got ${failures.join('; ')}`);
  console.log(`ok rejects ${label}`);
}
try {
  assert.deepEqual(validatePackage(root).failures, [], 'source package must be valid');
  assert.deepEqual(validatePackage(fixture()).failures, [], 'package works under a path with spaces');
  const direct = fixture();
  fs.writeFileSync(path.join(direct, 'CLAUDE.md'), '# crouter development entry\n\ncrouter-development\n');
  fs.writeFileSync(path.join(direct, 'AGENTS.md'), '# AGENTS\nno routing here\n');
  assert.deepEqual(validatePackage(direct).failures, [], 'direct CLAUDE.md route still passes');
  const extension = fixture();
  edit(extension, 'references/roadmap.md', (text) => `${text}\n| DEV-16 | TODO | Additional scoped task | DEV-15 | UX-01 |\n`);
  assert.deepEqual(validatePackage(extension).failures, [], 'new tasks do not require a frozen count change');
  rejects('missing delegated Claude route', (dir) => fs.writeFileSync(path.join(dir, 'AGENTS.md'), '# unrelated\n'), 'missing CLAUDE.md development routing');
  rejects('missing reference', (dir) => fs.unlinkSync(path.join(dir, skillRelative, 'references/product-and-ux.md')), 'ENOENT');
  rejects('missing handoff', (dir) => fs.unlinkSync(path.join(dir, skillRelative, 'references/implementation-handoff.md')), 'ENOENT');
  rejects('broken handoff link', (dir) => edit(dir, 'references/implementation-handoff.md', (text) => `${text}\n[missing](missing.md)\n`), 'broken local link');
  rejects('broken local link', (dir) => edit(dir, 'SKILL.md', (text) => `${text}\n[missing](references/missing.md)\n`), 'broken local link');
  rejects('escaping link', (dir) => edit(dir, 'SKILL.md', (text) => `${text}\n[outside](../../SKILLS.md)\n`), 'escapes package');
  rejects('duplicate acceptance', (dir) => edit(dir, 'references/acceptance.md', (text) => `${text}\n| UX-01 | duplicate | duplicate |\n`), 'duplicate acceptance ID');
  rejects('duplicate task', (dir) => edit(dir, 'references/roadmap.md', (text) => `${text}\n| DEV-15 | TODO | duplicate | 无 | UX-01 |\n`), 'duplicate task ID');
  rejects('unknown dependency', (dir) => edit(dir, 'references/roadmap.md', (text) => text.replace('| DEV-01, DEV-15 |', '| DEV-99 |')), 'unknown roadmap reference: DEV-99');
  rejects('dependency cycle', (dir) => edit(dir, 'references/roadmap.md', (text) => text.replace(/^(\| DEV-15 \|[^\n]*?)\| 无 \|/m, '$1| DEV-02 |')), 'task dependency cycle');
  rejects('unknown acceptance', (dir) => edit(dir, 'references/roadmap.md', (text) => text.replace('BUILD-01, CLI-01', 'BUILD-99, CLI-01')), 'unknown roadmap reference: BUILD-99');
  rejects('invalid task status', (dir) => edit(dir, 'references/roadmap.md', (text) => text.replace('| TODO |', '| FINISHED |')), 'invalid task status');
  rejects('duplicate eval', (dir) => edit(dir, 'evals/cases.json', (text) => { const data = JSON.parse(text); data.cases.push(data.cases[0]); return JSON.stringify(data); }), 'duplicate eval ID');
  rejects('unknown eval reference', (dir) => edit(dir, 'evals/cases.json', (text) => text.replace('"BUILD-01"', '"BUILD-99"')), 'unknown eval acceptance reference');
  rejects('missing DONE evidence', (dir) => edit(dir, 'references/roadmap.md', (text) => text.replace('### DEV-01 ', '### Historical ')), 'DONE task needs a delivery record');
  rejects('no route at all', (dir) => {
    fs.writeFileSync(path.join(dir, 'CLAUDE.md'), '# crouter\n\n');
  }, 'missing CLAUDE.md development routing');
  rejects('indirect route target missing', (dir) => {
    fs.writeFileSync(path.join(dir, 'CLAUDE.md'), '@AGENTS.md\n');
    fs.unlinkSync(path.join(dir, 'AGENTS.md'));
  }, 'missing CLAUDE.md development routing');
  rejects('indirect route without target', (dir) => {
    fs.writeFileSync(path.join(dir, 'CLAUDE.md'), '@AGENTS.md\n');
    fs.writeFileSync(path.join(dir, 'AGENTS.md'), '# AGENTS\nno routing here\n');
  }, 'missing CLAUDE.md development routing');
  rejects('unrelated indirection', (dir) => {
    fs.writeFileSync(path.join(dir, 'CLAUDE.md'), '@../../.claude/CLAUDE.md\n');
  }, 'missing CLAUDE.md development routing');
  rejects('indirection filename suffix', (dir) => {
    fs.writeFileSync(path.join(dir, 'CLAUDE.md'), '@AGENTS.md.backup\n');
  }, 'missing CLAUDE.md development routing');
  rejects('copied discovery entry', (dir) => {
    const entry = path.join(dir, '.claude/skills/crouter-development');
    fs.unlinkSync(entry); fs.mkdirSync(entry);
  }, 'discovery entry must be a symlink');
  rejects('wrong frontmatter name', (dir) => edit(dir, 'SKILL.md', (text) => text.replace('name: crouter-development', 'name: another-skill')), 'skill name must match directory');
  console.log(`ok validator self-tests: ${count} isolated fixtures (3 positive, ${count - 3} negative)`);
} finally {
  fs.rmSync(temp, {recursive: true, force: true});
}
