#!/bin/sh
# Exact per-provider retirements must not reach an upstream, even if hand typed.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export ROOT_DIR
node --input-type=module - <<'NODE'
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'crouter-blocked-models-'));
const requests = [];
const upstream = http.createServer(async (req, res) => {
  let body = ''; for await (const chunk of req) body += chunk;
  requests.push(JSON.parse(body));
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ model: requests.at(-1).model }));
});
let gateway;
try {
  upstream.listen(0, '127.0.0.1'); await once(upstream, 'listening');
  const candidates = [{ url: `http://127.0.0.1:${upstream.address().port}`, auth: { type: 'none', token: '' } }];
  const blockedModels = ['inkling-2-mini', 'inkling-2-mini:latest'];
  const routes = [
    { prefix: 'ollama', candidates, models: ['qwen', ...blockedModels], blockedModels },
    { prefix: 'mlx-vlm', candidates, models: ['inkling-2-mini:latest'] },
  ];
  const file = path.join(directory, 'routes.json'); fs.writeFileSync(file, JSON.stringify(routes));
  gateway = spawn(process.execPath, [process.env.ROOT_DIR + '/bin/gateway'], {
    env: { PATH: process.env.PATH, HOME: directory, CROUTER_ROUTES_FILE: file,
      CROUTER_GATEWAY_PORT: '0', CROUTER_GATEWAY_TOKEN: 'fixture-token' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const port = await new Promise((resolve, reject) => {
    let output = '';
    const timer = setTimeout(() => reject(Error('gateway startup timeout')), 10000);
    gateway.stdout.on('data', chunk => {
      output += chunk;
      const match = output.match(/CROUTER_GATEWAY_LISTENING_PORT=(\d+)/);
      if (match) { clearTimeout(timer); resolve(Number(match[1])); }
    });
    gateway.once('exit', code => { clearTimeout(timer); reject(Error(`gateway exited ${code}`)); });
  });
  const origin = `http://127.0.0.1:${port}`;
  const catalog = await (await fetch(origin + '/v1/models')).json();
  assert.deepEqual(catalog.data.map(row => row.id), ['ollama/qwen', 'mlx-vlm/inkling-2-mini:latest']);
  const send = model => fetch(origin + '/v1/messages', { method: 'POST',
    headers: { authorization: 'Bearer fixture-token', 'content-type': 'application/json' },
    body: JSON.stringify({ model, max_tokens: 1, messages: [] }) });
  for (const model of blockedModels) {
    const rejected = await send('ollama/' + model);
    assert.equal(rejected.status, 400); assert.equal((await rejected.json()).error.type, 'unknown_model');
  }
  assert.equal(requests.length, 0, 'blocked requests must never reach an upstream');
  for (const [model, expected] of [
    ['mlx-vlm/inkling-2-mini:latest', 'inkling-2-mini:latest'],
    ['ollama/unlisted-custom-model', 'unlisted-custom-model'],
  ]) {
    const allowed = await send(model); assert.equal(allowed.status, 200);
    assert.equal((await allowed.json()).model, expected);
  }
  assert.equal(requests.length, 2);
  console.log('ok    gateway rejects exact blocked provider/model pairs and preserves other routes');
} finally {
  if (gateway && gateway.exitCode === null) { const ended = once(gateway, 'exit'); gateway.kill(); await ended; }
  upstream.closeAllConnections(); await new Promise(resolve => upstream.close(resolve));
  fs.rmSync(directory, { recursive: true, force: true });
}
NODE
