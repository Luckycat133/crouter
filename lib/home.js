#!/usr/bin/env node
'use strict';
// Interactive front end to existing application operations, not shell command
// strings. No key or login token is ever read by this process.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const readline = require('node:readline/promises');
const {spawn} = require('node:child_process');
const {picker} = require('../bin/crouter-models');
const {atomicJson} = require('./catalog.js');
const {statePaths, current, recent, readFavorites, toggleFavorite} = require('./model-state.js');
const root = process.argv[2];
const cli = path.join(root, 'bin', 'crouter');
const state = path.join(process.env.XDG_STATE_HOME || path.join(os.homedir(), '.local', 'state'), 'crouter');
const prefsFile = path.join(state, 'ui.json');
let prefs = {schema_version: 1, paidFallback: false};
try {
  const value = JSON.parse(fs.readFileSync(prefsFile, 'utf8'));
  if (value.schema_version === 1 && typeof value.paidFallback === 'boolean') prefs = value;
} catch (_) {}
function clean(s) { return String(s).replace(/[\x00-\x1f\x7f-\x9f]/g, ''); }
function run(args, capture = false) {
  return new Promise((resolve, reject) => {
    const child = spawn(cli, args, {env: {...process.env, CROUTER_SESSION_PAID_FALLBACK: prefs.paidFallback ? '1' : '0', CROUTER_SESSION_CROSS_MODEL_FALLBACK: '0'}, stdio: capture ? ['ignore', 'pipe', 'pipe'] : 'inherit'});
    let out = '', err = '', overflow = false;
    const abort = () => child.kill('SIGTERM');
    process.once('SIGINT', abort); process.once('SIGTERM', abort);
    if (capture) {
      child.stdout.setEncoding('utf8'); child.stderr.setEncoding('utf8');
      child.stdout.on('data', (s) => { out += s; if (out.length > 8 * 1024 * 1024) { overflow = true; child.kill(); } });
      child.stderr.on('data', (s) => { if (err.length < 16000) err += s; });
    }
    child.on('error', (e) => { process.removeListener('SIGINT', abort); process.removeListener('SIGTERM', abort); reject(e); });
    child.on('close', (code, signal) => {
      process.removeListener('SIGINT', abort); process.removeListener('SIGTERM', abort);
      if (overflow) return reject(new Error('来源列表过大'));
      if (capture && code !== 0) return reject(new Error('无法读取来源列表；请检查配置或运行诊断'));
      if (!capture && code) console.error(`操作未完成（退出码 ${code}${signal ? ', ' + signal : ''}）。`);
      resolve(capture ? out : code);
    });
  });
}
async function ask(prompt) {
  const rl = readline.createInterface({input: process.stdin, output: process.stdout});
  try { return (await rl.question(prompt)).trim(); } finally { rl.close(); }
}
async function choose(rows, title) {
  console.log(`\n${title}`);
  rows.forEach((x, i) => console.log(`  ${i + 1}. ${clean(x.label)}`));
  const value = await ask('输入编号；回车返回：');
  if (!value) return null;
  if (!/^\d+$/.test(value) || Number(value) < 1 || Number(value) > rows.length) { console.log('编号无效。'); return null; }
  return rows[Number(value) - 1].value;
}
async function inventory() {
  return (await run(['_inventory'], true)).trim().split('\n').filter(Boolean).map((s) => JSON.parse(s)).filter((p) => p.schema_version === 1);
}
function selection() {
  try {
    const name = fs.readFileSync(path.join(state, 'selection'), 'utf8').trim();
    return /^[A-Za-z0-9][A-Za-z0-9._-]*$/.test(name) ? name : '';
  } catch (_) { return ''; }
}
function providerState(provider) {
  const labels = {'no-key': '待配置凭证', ready: '已配置凭证', local: '无需配置 Key', native: '原生认证', unknown: '账号模型状态未知', unavailable: '账号模型不可用'};
  const surfaces = [provider.hasPlan && '订阅', provider.hasApi && '按量 API'].filter(Boolean).join('/');
  const state = labels[provider.status] || '配置状态未知';
  return surfaces ? `${state} · 支持${surfaces}` : state;
}
function selectProvider(providers, title, {includeAll = false, selected = ''} = {}) {
  const rows = providers.map((p) => ({
    id: p.name, name: p.description, label: [p.name, p.description, providerState(p)].filter(Boolean).join(' · '), provider: p,
  }));
  if (includeAll) rows.unshift({id: '', name: '全部来源', label: '全部来源'});
  return picker(rows, title, selected, '搜名称或说明', {plain: true});
}
async function selectModel(providers) {
  const ready = providers.filter((p) => p.status !== 'no-key' && p.models.length);
  const recents = new Map();
  for (const p of ready) {
    const last = recent(statePaths(p.name));
    if (last) recents.set(`${p.name}/${last.model}`, last.completedAt);
  }
  const models = ready.flatMap((p) => p.models.map((m) => ({
    ...m, id: `${p.name}/${m.id}`, provider: p.name, name: `${m.name} ${p.description}`, detail: providerState(p),
  })));
  if (!models.length) { console.log('尚无可用来源；请先添加 Key，或配置本地模型。'); return; }
  let favorites = new Set();
  try { favorites = readFavorites(state); }
  catch (error) { console.error(error.message); }
  const favorite = {
    has: (row) => favorites.has(row.id),
    toggle: (row) => { favorites = toggleFavorite(state, row.id); return favorites.has(row.id); },
  };
  const order = (a, b) => Number(favorite.has(b)) - Number(favorite.has(a)) || (recents.get(b.id) || 0) - (recents.get(a.id) || 0);
  const target = selection();
  const remembered = target ? current(statePaths(target)) : '';
  let scope = '', query = '', selectedId = '', freeOnly = false;
  if (!models.some((m) => favorite.has(m) || recents.has(m.id)) && remembered) selectedId = `${target}/${remembered}`;
  for (;;) {
    const visible = scope ? models.filter((m) => m.provider === scope) : models;
    const m = await picker(visible, 'crouter', selectedId, `来源：${scope || '全部'} · 目录权益待验证`,
      {allowSave: true, chooseSource: ready.length > 1, favorite, order, initialQuery: query, initialFreeOnly: freeOnly});
    if (!m) return;
    if (m.chooseSource) {
      const choice = await selectProvider(ready, '筛选模型来源', {includeAll: true, selected: scope});
      if (choice) {
        scope = choice.id;
        query = selectedId = '';
      } else {
        query = m.query;
        selectedId = m.selectedId;
      }
      freeOnly = m.freeOnly;
      continue;
    }
    const model = m.id.slice(m.provider.length + 1);
    await run([m.provider, '--model', model, m.saveDefault ? '--set-default' : '--once']);
    return;
  }
}
async function addKey(p) {
  let surface = p.hasPlan ? 'plan' : p.hasApi ? 'api' : '';
  if (p.hasPlan && p.hasApi) surface = await choose([{label: '订阅／套餐 Key', value: 'plan'}, {label: '按量付费 API Key', value: 'api'}], '请选择 Key 的实际用途，不自动猜测');
  if (surface === null) return;
  const args = ['add', p.name];
  if (surface) args.push('--surface', surface);
  await run(args);
}
async function configureBuiltInSource(providers) {
  const p = (await selectProvider(providers, '配置内置来源'))?.provider;
  if (!p) return;
  if (p.status === 'local' || p.status === 'native') {
    console.log(`${p.name} · ${providerState(p)}。从“选择模型”进入。`);
    return;
  }
  await addKey(p);
}
async function keys(providers) {
  const p = (await selectProvider(providers, '账号与 Key'))?.provider;
  if (!p) return;
  const action = await choose([{label: '添加或替换 Key', value: 'add'}, {label: '查看已登记 Key（不显示密钥）', value: 'list'}, {label: '删除登记的 Key', value: 'remove'}], p.name);
  if (action === 'list') { await run(['list', 'keys', p.name]); return; }
  if (action === 'add') { await addKey(p); return; }
  if (action === 'remove') {
    const key = await choose(p.keys.map((k) => ({label: `${k.surface} · ${k.ref}`, value: k})), '选择要删除的登记项');
    if (!key) return;
    const args = ['remove', p.name, '--name', key.ref];
    if (p.hasPlan || p.hasApi) args.push('--surface', key.surface);
    await run(args);
  }
}
async function main() {
  if (!process.stdin.isTTY || !process.stdout.isTTY) throw new Error('交互首页需要终端；脚本请直接指定 provider，例如 crouter minimax');
  for (;;) {
    const providers = await inventory();
    const selected = selection();
    const p = providers.find((x) => x.name === selected);
    console.log(`\ncrouter · Claude Code\n当前：${clean(selected || '未选择')} ${p ? clean(current(statePaths(p.name)) || p.model) : ''}\n订阅耗尽后按量兜底：${prefs.paidFallback ? '已明确允许（仍不跨模型）' : '关闭'}\n`);
    console.log('  Enter 继续使用当前模型\n  1 选择模型\n  2 账号、订阅与 Key\n  3 配置内置来源\n  4 刷新某个来源的模型目录\n  5 检查与修复\n  6 按量兜底设置\n  7 使用 Claude 原生登录\n  q 退出');
    const action = await ask('请选择：');
    if (action === 'q') return;
    if (action === '') {
      if (!p) { console.log('请先选择模型。遗留 app 选择不会被自动改写。'); continue; }
      await run([p.name, '--once']);
    } else if (action === '1') await selectModel(providers);
    else if (action === '2') await keys(providers);
    else if (action === '3') await configureBuiltInSource(providers);
    else if (action === '4') {
      const source = (await selectProvider(providers, '刷新目录'))?.provider;
      if (source) await run(['models', source.name, '--refresh']);
    } else if (action === '5') {
      const source = (await selectProvider(providers, '选择要检查的来源'))?.provider;
      if (source) await run(['doctor', source.name]);
    } else if (action === '6') {
      const answer = await choose([{label: '关闭订阅的 API 兜底（仅配置 API 的来源仍按量计费）', value: false}, {label: '允许同模型退回已配置 API Key（可能产生费用）', value: true}], '此设置用于从本首页启动的新会话');
      if (answer !== null) { prefs.paidFallback = answer; atomicJson(prefsFile, prefs); }
    } else if (action === '7') await run(['claude']);
    else console.log('请选择菜单项。');
  }
}
main().catch((e) => { console.error(`crouter: ${clean(e.message)}`); process.exitCode = 1; });
