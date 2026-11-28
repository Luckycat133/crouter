#!/bin/sh
# Real protocol adapter against an ephemeral loopback mock; never load a model.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export ROOT_DIR
node --input-type=module - <<'NODE'
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
const captured = [];
const upstream = http.createServer(async (req, res) => {
  let body = ''; for await (const chunk of req) body += chunk;
  captured.push(JSON.parse(body));
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ choices: [{ message: { content: 'fixture' }, finish_reason: 'stop' }] }));
});
upstream.listen(0, '127.0.0.1'); await once(upstream, 'listening');
let adapter;
async function start(model, inherit = true) {
  const reserve = net.createServer(); reserve.listen(0, '127.0.0.1'); await once(reserve, 'listening');
  const port = reserve.address().port; await new Promise(resolve => reserve.close(resolve));
  adapter = spawn(process.execPath, [process.env.ROOT_DIR + '/lib/anthropic-openai-proxy.mjs'], {
    env: { ...process.env, MLX_PROXY_PORT: String(port), MLX_UPSTREAM_HOST: '127.0.0.1',
      MLX_UPSTREAM_PORT: String(upstream.address().port), MLX_MODEL: model,
      MLX_UPSTREAM_MODEL: '/native/selected-pack', MLX_INHERIT_DEFAULTS: inherit ? '1' : '0',
      MLX_REASONING_EFFORT: 'low' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  await Promise.race([once(adapter.stdout, 'data'), once(adapter, 'exit').then(() => { throw Error('adapter exited before startup'); })]);
  return body => fetch(`http://127.0.0.1:${port}/v1/messages`, { method: 'POST', body: JSON.stringify(body) });
}
async function stop() {
  const exit = once(adapter, 'exit'); adapter.kill(); await exit; adapter = null;
}
try {
  for (const model of ['ternary-bonsai-2-27b', 'ternary-bonsai-2.5-27b', 'inkling-2-mini', 'inkling-2-mini:latest', 'inkling-2-mini-unbound-v3']) {
    const send = await start(model);
    const base = { model, messages: [{ role: 'user', content: 'fixture' }] };
    await send(base);
    assert.deepEqual(Object.keys(captured.at(-1)).sort(), ['messages', 'model', 'stream']);
    for (const effort of ['low', 'medium', 'high', 'xhigh', 'max']) {
      const res = await send({ ...base, output_config: { effort }, thinking: { type: 'adaptive' }, temperature: 0 });
      assert.equal(res.status, 200);
      const expected = model.startsWith('ternary-bonsai-') && ['high', 'xhigh', 'max'].includes(effort) ? 'xhigh' : effort;
      assert.equal(captured.at(-1).reasoning_effort, expected);
      assert.deepEqual(captured.at(-1).chat_template_kwargs, { enable_thinking: true, reasoning_effort: expected });
      assert.equal(captured.at(-1).temperature, 0);
      assert.equal(captured.at(-1).thinking_budget, undefined);
      assert.equal(captured.at(-1).thinking_budget_tokens, undefined);
    }
    for (const effort of ['unsupported', null, 1]) {
      const count = captured.length;
      const res = await send({ ...base, output_config: { effort }, stream: true });
      assert.equal(res.status, 400);
      assert.match(JSON.stringify(await res.json()), /output_config\.effort/);
      assert.equal(captured.length, count, 'invalid effort must not reach a template or upstream');
    }
    await send({ ...base, output_config: {} });
    assert.equal(captured.at(-1).reasoning_effort, undefined);
    assert.equal(captured.at(-1).chat_template_kwargs, undefined);
    await stop();
  }
  // An explicit request overrides the existing legacy env default, too.
  {
    const model = 'ternary-bonsai-2-27b'; const send = await start(model, false);
    const base = { model, messages: [{ role: 'user', content: 'fixture' }] };
    await send(base); assert.equal(captured.at(-1).reasoning_effort, 'low');
    await send({ ...base, output_config: { effort: 'medium' } });
    assert.equal(captured.at(-1).reasoning_effort, 'medium');
    assert.equal(captured.at(-1).chat_template_kwargs.reasoning_effort, 'medium');
    await stop();
  }
  // Similar names do not opt arbitrary backends into model-specific translation.
  for (const model of ['ternary-bonsai-2.5-27b-custom', 'unlisted-local-model']) {
    const send = await start(model);
    await send({ model, messages: [{ role: 'user', content: 'fixture' }], output_config: { effort: 'max' } });
    assert.deepEqual(Object.keys(captured.at(-1)).sort(), ['messages', 'model', 'stream']);
    await stop();
  }
  console.log('ok    explicit local reasoning effort is model-scoped, validated and preserves native defaults');
} finally {
  if (adapter) await stop();
  upstream.closeAllConnections(); await new Promise(resolve => upstream.close(resolve));
}
NODE
