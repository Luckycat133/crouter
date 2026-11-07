#!/usr/bin/env node
// Package-local, offline checks. Not a general YAML parser, product test or LLM eval.
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const name = 'crouter-development';
const referenceNames = [
  'product-and-ux.md', 'runtime-contracts.md', 'adapters-and-claude.md',
  'roadmap.md', 'acceptance.md', 'baseline-and-sources.md',
];
const inside = (parent, child) => {
  const relative = path.relative(parent, child);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
};

// Exported for hermetic tests; importing this module performs no validation or writes.
export function validatePackage(repositoryRoot) {
  const root = path.resolve(repositoryRoot);
  const skill = path.join(root, '.agents', 'skills', name);
  const failures = [];
  const check = (ok, message) => { if (!ok) failures.push(message); };
  const read = (file) => {
    try {
      if (!inside(root, fs.realpathSync(file))) throw new Error('path escapes repository');
      return fs.readFileSync(file, 'utf8');
    } catch (error) {
      failures.push(`${path.relative(root, file)}: ${error.code || error.message}`);
      return '';
    }
  };
  const main = read(path.join(skill, 'SKILL.md'));
  // Intentionally supports this package's two unquoted single-line YAML scalars.
  // If the frontmatter format changes, extend both this check and its fixtures.
  const header = /^---\nname: ([a-z0-9-]+)\ndescription: ([^\n]+)\n---\n/.exec(main);
  check(Boolean(header), 'SKILL.md: expected name/description scalar frontmatter');
  if (header) {
    check(header[1] === name && header[1] === path.basename(skill), 'skill name must match directory');
    check(header[1].length <= 64 && !header[1].includes('--') && !/^-|-$/.test(header[1]), 'invalid skill name');
    check(header[2].trim().length > 0 && [...header[2]].length <= 1024, 'invalid description length');
    check(!/:\s|\s#|^[\[\]{}&*!|>'"%@`]/.test(header[2]), 'description is not a supported plain scalar');
  }
  check(main.split('\n').length <= 500, 'SKILL.md exceeds 500 lines');
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
      if (/^[a-z]+:/i.test(target)) { failures.push(`unsupported link scheme: ${target}`); continue; }
      const resolved = path.resolve(path.dirname(file), target.split('#')[0]);
      check(inside(skill, resolved), `local skill link escapes package: ${target}`);
      try {
        check(inside(skill, fs.realpathSync(resolved)), `resolved link escapes package: ${target}`);
      } catch { failures.push(`broken local link in ${path.relative(skill, file)}: ${target}`); }
    }
  }
  for (const host of ['.claude', '.codex']) {
    const entry = path.join(root, host, 'skills', name);
    try {
      check(fs.lstatSync(entry).isSymbolicLink(), `${host}: discovery entry must be a symlink`);
      check(fs.realpathSync(entry) === fs.realpathSync(skill), `${host}: discovery entry points to wrong skill`);
    } catch (error) { failures.push(`${host}: missing or broken discovery entry (${error.code})`); }
  }
  check(read(path.join(root, '.agents', 'SKILLS.md')).includes('skills/crouter-development/SKILL.md'), 'missing routing-table link');
  check(read(path.join(root, 'CLAUDE.md')).includes('crouter-development'), 'missing CLAUDE.md development routing');
  check(read(path.join(root, 'docs', 'development-plan.md')).includes('../.agents/skills/crouter-development/SKILL.md'), 'missing human-readable development entry');
  check(fs.existsSync(path.join(root, 'test', 'development-skill.sh')), 'missing offline test wrapper');

  const acceptance = docs.find(([file]) => file.endsWith('/acceptance.md'))?.[1] || '';
  const listedIds = [...acceptance.matchAll(/^\| ([A-Z]+-\d{2}) \|/gm)].map((match) => match[1]);
  const acceptanceIds = new Set(listedIds);
  check(listedIds.length > 0, 'acceptance matrix is empty');
  check(acceptanceIds.size === listedIds.length, 'duplicate acceptance ID');
  const roadmap = docs.find(([file]) => file.endsWith('/roadmap.md'))?.[1] || '';
  const tasks = new Map();
  for (const line of roadmap.split('\n').filter((value) => /^\| DEV-/.test(value))) {
    const cells = line.split('|').slice(1, -1).map((value) => value.trim());
    check(cells.length === 5, `invalid task row: ${cells[0]}`);
    const [id, status, , dependencies = ''] = cells;
    check(/^DEV-\d{2}$/.test(id), `invalid task ID: ${id}`);
    check(!tasks.has(id), `duplicate task ID: ${id}`);
    check(['TODO', 'IN_PROGRESS', 'BLOCKED', 'DONE'].includes(status), `invalid task status: ${id}`);
    tasks.set(id, {status, dependencies: dependencies.match(/DEV-\d{2}/g) || []});
  }
  check(tasks.size > 0, 'roadmap is empty');
  // Do not freeze the number of tasks: appending a justified task is supported.
  for (const match of roadmap.matchAll(/\b([A-Z]+-\d{2})\b/g)) {
    const id = match[1];
    check(id.startsWith('DEV-') ? tasks.has(id) : acceptanceIds.has(id), `unknown roadmap reference: ${id}`);
  }
  const visiting = new Set();
  const visited = new Set();
  const visit = (id) => {
    if (visiting.has(id)) { failures.push(`task dependency cycle: ${id}`); return; }
    if (visited.has(id) || !tasks.has(id)) return;
    visiting.add(id);
    for (const dependency of tasks.get(id).dependencies) visit(dependency);
    visiting.delete(id);
    visited.add(id);
  };
  for (const [id, task] of tasks) {
    visit(id);
    if (task.status === 'DONE') {
      const record = new RegExp(`^### ${id}\\b[^\\n]*\\n([\\s\\S]*?)(?=^### |$(?![\\s\\S]))`, 'm').exec(roadmap);
      check(Boolean(record && /\b[a-f0-9]{7,40}\b/.test(record[1])), `DONE task needs a delivery record and commit: ${id}`);
    }
  }

  let caseCount = 0;
  try {
    const data = JSON.parse(read(path.join(skill, 'evals', 'cases.json')));
    check(data.schema_version === 1 && Array.isArray(data.cases), 'invalid eval schema');
    const cases = Array.isArray(data.cases) ? data.cases : [];
    const ids = new Set();
    for (const item of cases) {
      if (!item || typeof item !== 'object') { failures.push('invalid eval item'); continue; }
      check(typeof item.id === 'string' && /^E\d{2}$/.test(item.id) && !ids.has(item.id), 'invalid or duplicate eval ID');
      ids.add(item.id);
      check(['positive', 'negative', 'boundary'].includes(item.kind), `invalid eval kind: ${item.id}`);
      check(typeof item.prompt === 'string' && item.prompt.trim().length > 0, `missing prompt: ${item.id}`);
      for (const field of ['must', 'must_not']) {
        check(Array.isArray(item[field]) && item[field].length > 0 && item[field].every((value) => typeof value === 'string' && value.trim()), `invalid ${field}: ${item.id}`);
      }
      if (item.acceptance_ids !== undefined) {
        check(Array.isArray(item.acceptance_ids) && item.acceptance_ids.length > 0 && item.acceptance_ids.every((id) => acceptanceIds.has(id)), `unknown eval acceptance reference: ${item.id}`);
      }
    }
    caseCount = ids.size;
    for (const kind of ['positive', 'negative', 'boundary']) check(cases.some((item) => item?.kind === kind), `missing ${kind} eval`);
  } catch (error) { failures.push(`cannot validate eval cases: ${error.message}`); }
  return {failures, references: referenceNames.length, tasks: tasks.size, acceptance: acceptanceIds.size, cases: caseCount};
}

const script = fs.realpathSync(fileURLToPath(import.meta.url));
if (process.argv[1] && fs.realpathSync(process.argv[1]) === script) {
  if (process.argv.length !== 2) {
    console.error('usage: node .agents/skills/crouter-development/scripts/validate.mjs');
    process.exitCode = 2;
  } else {
    const root = path.resolve(path.dirname(script), '../../../..');
    const result = validatePackage(root);
    if (result.failures.length) {
      for (const message of result.failures) console.error(`FAIL ${message}`);
      process.exitCode = 1;
    } else {
      console.log(`ok crouter-development: ${result.references} references, ${result.tasks} tasks, ${result.acceptance} acceptance IDs, ${result.cases} eval cases`);
      console.log('scope: package structure only; product, live-client and LLM evaluations were not executed');
    }
  }
}
