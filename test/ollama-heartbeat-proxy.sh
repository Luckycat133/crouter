#!/bin/sh
# The Ollama transport relay must keep a silent SSE response alive without
# changing request bytes or upstream model events.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node 2>/dev/null || true)}
[ -n "$NODE_BIN" ] || { printf 'skip  node not available\n'; exit 0; }

CROUTER_TEST_ROOT=$ROOT_DIR "$NODE_BIN" --input-type=module <<'NODE'
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn } from 'node:child_process';
import { once } from 'node:events';

const root = process.env.CROUTER_TEST_ROOT;
const proxyPath = `${root}/lib/ollama-heartbeat-proxy.mjs`;
const expectedBody = JSON.stringify({ model: 'deepseek-v4-flash:q8', stream: true, messages: [{ role: 'user', content: 'ping' }] });
const receivedBodies = [];
const receivedHeaders = [];

const upstream = http.createServer((request, response) => {
  const chunks = [];
  request.on('data', chunk => chunks.push(chunk));
  request.on('end', () => {
    receivedBodies.push(Buffer.concat(chunks).toString('utf8'));
    receivedHeaders.push(request.headers);
    setTimeout(() => {
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      response.end('event: message_start\ndata: {"type":"message_start"}\n\n');
    }, 180);
  });
});
let child;
try {
upstream.listen(0, '127.0.0.1');
await once(upstream, 'listening');
const upstreamPort = upstream.address().port;

const reservation = http.createServer();
reservation.listen(0, '127.0.0.1');
await once(reservation, 'listening');
const proxyPort = reservation.address().port;
await new Promise(resolve => reservation.close(resolve));

child = spawn(process.execPath, [proxyPath], {
  env: {
    ...process.env,
    OLLAMA_HEARTBEAT_PORT: String(proxyPort),
    OLLAMA_UPSTREAM_PORT: String(upstreamPort),
    OLLAMA_HEARTBEAT_INTERVAL_MS: '40',
  },
  stdio: ['ignore', 'pipe', 'pipe'],
});

let childError = '';
let childOutput = '';
child.stderr.on('data', chunk => { childError += chunk.toString(); });
child.stdout.on('data', chunk => { childOutput += chunk.toString(); });
await Promise.race([
  once(child.stdout, 'data'),
  once(child, 'exit').then(([code]) => { throw new Error(`proxy exited early (${code}): ${childError}`); }),
  new Promise((_, reject) => setTimeout(() => reject(new Error('proxy startup timed out')), 2000)),
]);

const health = await new Promise((resolve, reject) => {
  http.get(`http://127.0.0.1:${proxyPort}/health`, response => {
    const chunks = [];
    response.on('data', chunk => chunks.push(chunk));
    response.on('end', () => resolve(JSON.parse(Buffer.concat(chunks).toString('utf8'))));
  }).on('error', reject);
});
assert.equal(health.service, 'crouter-ollama-heartbeat');
assert.equal(health.heartbeat_ms, 40);
assert.equal(health.effort_rewrite, 'deepseek-anthropic-pass-through-v2');
assert.equal(health.image_fallback, 'deepseek-text-image-v1');

async function send(body, chunked = false) {
  return await new Promise((resolve, reject) => {
  const request = http.request({
    host: '127.0.0.1',
    port: proxyPort,
    path: '/v1/messages?beta=true',
    method: 'POST',
    headers: { 'content-type': 'application/json', ...(chunked
      ? { 'transfer-encoding': 'chunked', trailer: 'x-test-trailer' }
      : { 'content-length': Buffer.byteLength(body) }) },
  }, response => {
    const chunks = [];
    response.on('data', chunk => chunks.push(chunk));
    response.on('end', () => {
      if (response.statusCode !== 200) reject(new Error(`proxy returned HTTP ${response.statusCode}`));
      else resolve(Buffer.concat(chunks).toString('utf8'));
    });
  });
  request.on('error', reject);
    request.setTimeout(2000, () => request.destroy(new Error('proxy request timed out')));
    if (chunked) {
      const bytes = Buffer.from(body);
      request.write(bytes.subarray(0, 13));
      request.write(bytes.subarray(13));
      request.addTrailers({ 'x-test-trailer': 'complete' });
      request.end();
    } else {
      request.end(body);
    }
  });
}

const responseBody = await send(expectedBody);

assert.equal(receivedBodies[0], expectedBody);
assert.match(responseBody, /event: message_start/);
assert.ok((responseBody.match(/: crouter-ollama-heartbeat/g) || []).length >= 3, responseBody);

const maxBody = JSON.stringify({
  model: 'deepseek-v4-flash:q8', stream: true, max_tokens: 32000,
  thinking: { type: 'enabled', budget_tokens: 16000 },
  output_config: { effort: 'max' },
  messages: [{ role: 'assistant', content: [{ type: 'thinking', thinking: 'keep me' }] }, { role: 'user', content: 'ping' }],
});
await send(maxBody);
const maxForwarded = JSON.parse(receivedBodies[1]);
assert.equal(maxForwarded.output_config.effort, 'max');
assert.deepEqual(maxForwarded.thinking, { type: 'enabled', budget_tokens: 16000 });
assert.equal(maxForwarded.messages[0].content[0].thinking, 'keep me');

const xhighBody = JSON.stringify({
  model: 'deepseek-v4-flash:q8', stream: false, max_tokens: 1000,
  thinking: { type: 'enabled' }, output_config: { effort: 'xhigh' }, messages: [],
});
await send(xhighBody);
const xhighForwarded = JSON.parse(receivedBodies[2]);
assert.equal(xhighForwarded.output_config.effort, 'xhigh');
assert.deepEqual(xhighForwarded.thinking, { type: 'enabled' });

const disabledBody = JSON.stringify({
  model: 'deepseek-v4-flash:q8', stream: false,
  thinking: { type: 'disabled' }, output_config: { effort: 'max' }, messages: [],
});
await send(disabledBody);
assert.equal(receivedBodies[3], disabledBody);

const otherModelBody = JSON.stringify({
  model: 'qwen3', stream: false,
  thinking: { type: 'enabled' }, output_config: { effort: 'max' }, messages: [],
});
await send(otherModelBody);
assert.equal(receivedBodies[4], otherModelBody);

const imageBody = JSON.stringify({
  model: 'deepseek-v4-flash:q8', stream: false,
  output_config: { effort: 'max' },
  messages: [{
    role: 'user',
    content: [{
      type: 'tool_result', tool_use_id: 'read-1',
      content: [
        { type: 'text', text: 'before' },
        { type: 'image', source: { type: 'base64', media_type: 'image/png', data: 'secret-image-bytes' } },
      ],
    }],
  }],
});
await send(imageBody);
const imageForwarded = JSON.parse(receivedBodies[5]);
const downgradedContent = imageForwarded.messages[0].content[0].content;
assert.equal(downgradedContent[0].text, 'before');
assert.equal(downgradedContent[1].type, 'text');
assert.match(downgradedContent[1].text, /local DeepSeek model is text-only/);
assert.doesNotMatch(receivedBodies[5], /secret-image-bytes/);

const otherModelImageBody = JSON.stringify({
  model: 'llava', stream: false,
  messages: [{ role: 'user', content: [{ type: 'image', source: { type: 'base64', data: 'keep-me' } }] }],
});
await send(otherModelImageBody);
assert.equal(receivedBodies[6], otherModelImageBody);

// Buffering a chunked request must replace its framing, including when a
// DeepSeek image fallback changes the byte length and SSE starts early.
for (const stream of [false, true]) {
  const chunkedBody = JSON.stringify({
    model: 'deepseek-v4-flash:q8', stream,
    messages: [{ role: 'user', content: [
      { type: 'text', text: '你好' },
      { type: 'image', source: { type: 'base64', data: 'chunked-image' } },
    ] }],
  });
  const before = receivedBodies.length;
  const result = await send(chunkedBody, true);
  assert.equal(receivedBodies.length, before + 1, 'chunked request must reach the upstream handler');
  assert.match(result, /event: message_start/);
  assert.doesNotMatch(result, /event: error/);
  assert.equal(receivedHeaders.at(-1)['transfer-encoding'], undefined);
  assert.equal(receivedHeaders.at(-1).trailer, undefined);
  assert.equal(Number(receivedHeaders.at(-1)['content-length']), Buffer.byteLength(receivedBodies.at(-1)));
  assert.equal(JSON.parse(receivedBodies.at(-1)).messages[0].content[1].type, 'text');
  if (stream) assert.match(result, /: crouter-ollama-heartbeat/);
}

// Only Anthropic content positions are eligible for image fallback. Tool
// input and metadata may legitimately use the same type discriminator.
const scopedImages = {
  model: 'deepseek-v4-flash:q8', stream: false,
  thinking: { type: 'enabled', budget_tokens: 16000 },
  output_config: { effort: 'max' },
  metadata: { type: 'image', path: 'request.png' },
  messages: [{
    role: 'assistant', metadata: { type: 'image', path: 'message.png' },
    content: [{ type: 'tool_use', id: 'tool-1', name: 'render', input: {
      type: 'image', path: 'poster.png', layers: [{ type: 'image', path: 'layer.png' }],
    } }],
  }, {
    role: 'user', content: [
      { type: 'image', source: { type: 'base64', data: 'direct-image' }, cache_control: { type: 'ephemeral' } },
      { type: 'tool_result', tool_use_id: 'tool-1', metadata: { type: 'image', path: 'result.png' }, content: [
        { type: 'text', text: 'keep text', metadata: { type: 'image', path: 'text.png' } },
        { type: 'image', source: { type: 'base64', data: 'nested-image' } },
      ] },
    ],
  }],
};
await send(JSON.stringify(scopedImages));
const scopedForwarded = JSON.parse(receivedBodies.at(-1));
assert.deepEqual(scopedForwarded.messages[0], scopedImages.messages[0], 'image fallback must preserve tool input and message metadata');
assert.deepEqual(scopedForwarded.metadata, scopedImages.metadata);
assert.deepEqual(scopedForwarded.thinking, scopedImages.thinking);
assert.deepEqual(scopedForwarded.output_config, scopedImages.output_config);
const [directImage, toolResult] = scopedForwarded.messages[1].content;
assert.equal(directImage.type, 'text');
assert.deepEqual(directImage.cache_control, { type: 'ephemeral' });
assert.deepEqual(toolResult.metadata, scopedImages.messages[1].content[1].metadata);
assert.deepEqual(toolResult.content[0], scopedImages.messages[1].content[1].content[0]);
assert.equal(toolResult.content[1].type, 'text');
assert.doesNotMatch(receivedBodies.at(-1), /direct-image|nested-image/);

assert.match(childOutput, /"requested_effort":"max","effective_effort":"ollama_think_enabled","rewritten":false/);
assert.match(childOutput, /"requested_effort":"xhigh","effective_effort":"ollama_think_enabled","rewritten":false/);
assert.match(childOutput, /"effective_effort":"disabled","rewritten":false/);
assert.match(childOutput, /"type":"image_fallback".*"images_downgraded":1/);

} finally {
  if (child && child.exitCode === null && child.signalCode === null) {
    const exited = once(child, 'exit');
    child.kill('SIGTERM');
    const forceKill = setTimeout(() => child.kill('SIGKILL'), 1000);
    await exited;
    clearTimeout(forceKill);
  }
  upstream.closeAllConnections();
  await new Promise(resolve => upstream.close(resolve));
}
console.log('ok    Ollama heartbeat proxy preserves bytes and DeepSeek thinking requests, emits SSE comments, and downgrades unsupported images');
NODE

# The provider hook may reap only the relay PID recorded by its own PRE_START.
# An empty ownership variable represents a healthy relay that predated the
# session and must remain untouched.
. "$ROOT_DIR/providers/ollama.sh"
sleep 30 &
_owned_pid=$!
_OLLAMA_HEARTBEAT_PROXY_PID=$_owned_pid
eval "$POST_STOP"
if kill -0 "$_owned_pid" 2>/dev/null; then
  kill "$_owned_pid" 2>/dev/null || true
  wait "$_owned_pid" 2>/dev/null || true
  printf 'FAIL  Ollama provider left its session-owned relay running\n' >&2
  exit 1
fi

sleep 30 &
_preexisting_pid=$!
_OLLAMA_HEARTBEAT_PROXY_PID=
eval "$POST_STOP"
if ! kill -0 "$_preexisting_pid" 2>/dev/null; then
  printf 'FAIL  Ollama provider stopped a pre-existing relay\n' >&2
  exit 1
fi
kill "$_preexisting_pid" 2>/dev/null || true
wait "$_preexisting_pid" 2>/dev/null || true
printf 'ok    Ollama provider cleans up only its session-owned relay\n'
