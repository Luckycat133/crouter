#!/usr/bin/env node
// Offline structural checks for this package, not an Agent Skills/YAML parser
// and not product or LLM behavioral evaluation. Never reads user credentials.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const skill = fs.realpathSync(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'));
const root = path.resolve(skill, '../../..');
const name = 'crouter-development';
const failures = [];
const check = (ok, message) => { if (!ok) failures.push(message); };
const read = (file) => {
  try { return fs.readFileSync(file, 'utf8'); }
  catch (error) { failures.push(`${path.relative(root, file)}: ${error.code || 'read failed'}`); return ''; }
};
const inside = (parent, child) => {
  const relative = path.relative(parent, child);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
};

if (process.argv.length !== 2) {
  console.error('usage: node .agents/skills/crouter-development/scripts/validate.mjs');
  process.exit(2);
}

const main = read(path.join(skill, 'SKILL.md'));
// This package intentionally uses only two single-line scalar fields. Fail
// closed if its format changes; update the validator deliberately at that time.
const header = /^---\nname: ([a-z0-9-]+)\ndescription: ([^\n]+)\n---\n/.exec(main);
check(Boolean(header), 'SKILL.md: expected name/description scalar frontmatter');
if (header) {
  check(header[1] === name && header[1] === path.basename(skill), 'skill name must match directory');
  check(header[1].length <= 64 && !header[1].includes('--') && !/^-|-$/.test(header[1]), 'invalid skill name');
  check(header[2].trim().length > 0 && [...header[2]].length <= 1024, 'description must contain 1..1024 characters');
}
check(main.split('\n').length <= 500, 'SKILL.md exceeds 500 lines; move detail to references');

const referenceNames = [
  'product-and-ux.md', 'runtime-contracts.md', 'adapters-and-claude.md',
  'roadmap.md', 'acceptance.md', 'baseline-and-sources.md',
];
const docs = [[path.join(skill, 'SKILL.md'), main]];
for (const file of referenceNames) {
  const full = path.join(skill, 'references', file);
  docs.push([full, read(full)]);
  check(main.includes(`references/${file}`), `SKILL.md does not link directly to ${file}`);
}
for (const [file, text] of docs) {
  check(text.endsWith('\n'), `${path.relative(skill, file)}: missing final newline`);
  check(!/\r|[\t ]+$/m.test(text), `${path.relative(skill, file)}: CR or trailing whitespace`);
  for (const match of text.matchAll(/\[[^\]\n]+\]\(([^)\s]+)\)/g)) {
    const target = match[1];
    if (/^https?:\/\//.test(target) || target.startsWith('#')) continue;
    if (/^[a-z]+:/i.test(target)) { failures.push(`unsupported link scheme in ${file}`); continue; }
    const resolved = path.resolve(path.dirname(file), target.split('#')[0]);
    check(inside(skill, resolved), `local skill link escapes package: ${target}`);
    if (fs.existsSync(resolved)) {
      check(inside(skill, fs.realpathSync(resolved)), `resolved link escapes package: ${target}`);
    } else failures.push(`broken local link in ${path.relative(skill, file)}: ${target}`);
  }
}

for (const host of ['.claude', '.codex']) {
  const entry = path.join(root, host, 'skills', name);
  try {
    check(fs.lstatSync(entry).isSymbolicLink(), `${host}: discovery entry must be a symlink, not a second copy`);
    check(fs.realpathSync(entry) === skill, `${host}: discovery entry points to wrong skill`);
  } catch (error) { failures.push(`${host}: missing or broken discovery entry (${error.code})`); }
}
check(read(path.join(root, '.agents', 'SKILLS.md')).includes('skills/crouter-development/SKILL.md'), 'missing routing-table link');
check(read(path.join(root, 'CLAUDE.md')).includes('crouter-development'), 'missing CLAUDE.md development routing');
check(read(path.join(root, 'docs', 'development-plan.md')).includes('../.agents/skills/crouter-development/SKILL.md'), 'missing human-readable development entry');
check(fs.existsSync(path.join(root, 'test', 'development-skill.sh')), 'missing offline test wrapper');

const acceptance = read(path.join(skill, 'references', 'acceptance.md'));
const acceptanceIds = new Set([...acceptance.matchAll(/^\| ([A-Z]+-\d{2}) \|/gm)].map((m) => m[1]));
check(acceptanceIds.size >= 30, 'acceptance matrix is unexpectedly incomplete');
const roadmap = read(path.join(skill, 'references', 'roadmap.md'));
const tasks = [...roadmap.matchAll(/^\| (DEV-\d{2}) \| (TODO|IN_PROGRESS|BLOCKED|DONE) \|/gm)].map((m) => m[1]);
check(tasks.length === 14 && new Set(tasks).size === 14, 'roadmap must contain DEV-01..DEV-14 once each');
for (let i = 1; i <= 14; i++) check(tasks.includes(`DEV-${String(i).padStart(2, '0')}`), `missing DEV-${i}`);
for (const match of roadmap.matchAll(/\b([A-Z]+-\d{2})\b/g)) {
  check(match[1].startsWith('DEV-') || acceptanceIds.has(match[1]), `unknown acceptance ID: ${match[1]}`);
}

let caseCount = 0;
try {
  const data = JSON.parse(read(path.join(skill, 'evals', 'cases.json')));
  check(data.schema_version === 1 && Array.isArray(data.cases), 'invalid eval schema');
  const ids = new Set();
  for (const item of data.cases || []) {
    check(typeof item.id === 'string' && /^E\d{2}$/.test(item.id) && !ids.has(item.id), 'invalid or duplicate eval ID');
    ids.add(item.id);
    check(['positive', 'negative', 'boundary'].includes(item.kind), `invalid eval kind: ${item.id}`);
    check(typeof item.prompt === 'string' && item.prompt.trim().length > 0, `missing prompt: ${item.id}`);
    for (const field of ['must', 'must_not']) {
      check(Array.isArray(item[field]) && item[field].length > 0 && item[field].every((v) => typeof v === 'string' && v.trim()), `invalid ${field}: ${item.id}`);
    }
  }
  caseCount = ids.size;
  check(caseCount >= 10, 'eval set must cover positive, negative and boundary scenarios');
  for (const kind of ['positive', 'negative', 'boundary']) check(data.cases.some((item) => item.kind === kind), `missing ${kind} eval`);
} catch (error) { failures.push(`cannot validate eval cases: ${error.message}`); }

if (failures.length) {
  for (const message of failures) console.error(`FAIL ${message}`);
  process.exitCode = 1;
} else {
  console.log(`ok crouter-development: frontmatter, ${referenceNames.length} references, discovery links, ${tasks.length} tasks, ${acceptanceIds.size} acceptance IDs, ${caseCount} eval cases`);
  console.log('scope: package structure only; product tests and agent behavioral evaluations were not executed');
}
