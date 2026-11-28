#!/bin/sh
# Real adapter against a loopback fixture, never an installed model runtime.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export ROOT_DIR
node --input-type=module - <<'NODE'
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
const capture = [];
const tool = { id: 'read_1', type: 'function', function: { name: 'Read', arguments: '{"file_path":"fixture.txt"}' } };
const upstream = http.createServer(async (req, res) => {
  let body = ''; for await (const chunk of req) body += chunk;
  const request = JSON.parse(body); capture.push(request);
  if (request.stream) {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write(`data: ${JSON.stringify({ choices: [{ delta: { tool_calls: [{ ...tool, index: 0 }] } }] })}\n\n`);
    res.write(`data: ${JSON.stringify({ choices: [{ delta: {}, finish_reason: 'tool_calls' }], usage: { prompt_tokens: 20, completion_tokens: 4 } })}\n\n`);
    res.end('data: [DONE]\n\n');
  } else {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ choices: [{ message: { tool_calls: [tool] }, finish_reason: 'tool_calls' }],
      usage: { prompt_tokens: 20, completion_tokens: 4, prompt_tokens_details: { cached_tokens: 8 } } }));
  }
});
upstream.listen(0, '127.0.0.1'); await once(upstream, 'listening');
let adapter;
try {
  for (const model of ['inkling-2-mini', 'inkling-2-mini:latest']) {
    const reserve = http.createServer(); reserve.listen(0, '127.0.0.1'); await once(reserve, 'listening');
    const port = reserve.address().port; await new Promise(resolve => reserve.close(resolve));
    adapter = spawn(process.execPath, [process.env.ROOT_DIR + '/lib/anthropic-openai-proxy.mjs'], {
      env: { ...process.env, MLX_PROXY_PORT: String(port), MLX_UPSTREAM_HOST: '127.0.0.1',
        MLX_UPSTREAM_PORT: String(upstream.address().port), MLX_MODEL: model, MLX_UPSTREAM_MODEL: '/native/Inkling-2-Mini',
        MLX_INHERIT_DEFAULTS: '1', MLX_TEMPERATURE: '99', MLX_TOP_P: '99', MLX_TOP_K: '99', MLX_MIN_P: '99',
        MLX_MAX_OUTPUT_TOKENS: '99', MLX_REASONING_EFFORT: 'xhigh' },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    await Promise.race([once(adapter.stdout, 'data'), once(adapter, 'exit').then(() => { throw Error('adapter exited before startup'); })]);
    const endpoint = `http://127.0.0.1:${port}/v1/messages`;
    const schema = { type: 'object', properties: { file_path: { type: 'string' } }, required: ['file_path'] };
    const base = { model, messages: [{ role: 'user', content: 'read the fixture' }],
      tools: [{ name: 'Read', description: 'Read a file', input_schema: schema }] };
    const send = body => fetch(endpoint, { method: 'POST', body: JSON.stringify(body) });
    const result = await (await send(base)).json();
    assert.equal(result.model, model); assert.equal(result.stop_reason, 'tool_use');
    assert.deepEqual(result.content[0], { type: 'tool_use', id: 'read_1', name: 'Read', input: { file_path: 'fixture.txt' } });
    assert.equal(result.usage.cache_read_input_tokens, 8);
    const forwarded = capture.at(-1);
    assert.deepEqual(Object.keys(forwarded).sort(), ['messages', 'model', 'stream', 'tool_choice', 'tools']);
    assert.equal(forwarded.model, '/native/Inkling-2-Mini');
    assert.deepEqual(forwarded.tools, [{ type: 'function', function: { name: 'Read', description: 'Read a file', parameters: schema } }]);
    const stream = await (await send({ ...base, stream: true, max_tokens: 64, temperature: 0, top_p: 0.8, top_k: 7,
      thinking: { type: 'disabled' } })).text();
    const events = stream.split('\n\n').flatMap(block => block.split('\n').filter(line => line.startsWith('data: ')).map(line => JSON.parse(line.slice(6))));
    assert.ok(events.some(event => event.content_block?.type === 'tool_use' && event.content_block.name === 'Read'));
    assert.ok(events.some(event => event.delta?.stop_reason === 'tool_use'));
    assert.ok(events.some(event => event.type === 'message_stop'));
    const streamed = capture.at(-1);
    assert.equal(streamed.model, '/native/Inkling-2-Mini');
    assert.equal(streamed.max_tokens, 64); assert.equal(streamed.temperature, 0);
    assert.equal(streamed.top_p, 0.8); assert.equal(streamed.top_k, 7);
    assert.deepEqual(streamed.chat_template_kwargs, { enable_thinking: false });
    assert.equal(streamed.reasoning_effort, undefined);
    assert.equal((await send({ ...base, model: 'wrong-model' })).status, 400);
    const exited = once(adapter, 'exit'); adapter.kill(); await exited; adapter = null;
  }
  console.log('ok    Inkling adapter preserves native defaults, tools, schema, streaming and cache counts');
} finally {
  if (adapter) { const exited = once(adapter, 'exit'); adapter.kill(); await exited; }
  upstream.closeAllConnections(); await new Promise(resolve => upstream.close(resolve));
}
NODE
