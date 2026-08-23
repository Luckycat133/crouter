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

const upstream = http.createServer((request, response) => {
  const chunks = [];
  request.on('data', chunk => chunks.push(chunk));
  request.on('end', () => {
    receivedBodies.push(Buffer.concat(chunks).toString('utf8'));
    setTimeout(() => {
      response.writeHead(200, { 'content-type': 'text/event-stream' });
      response.end('event: message_start\ndata: {"type":"message_start"}\n\n');
    }, 180);
  });
});
upstream.listen(0, '127.0.0.1');
await once(upstream, 'listening');
const upstreamPort = upstream.address().port;

const reservation = http.createServer();
reservation.listen(0, '127.0.0.1');
await once(reservation, 'listening');
const proxyPort = reservation.address().port;
await new Promise(resolve => reservation.close(resolve));

const child = spawn(process.execPath, [proxyPath], {
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

async function send(body) {
  return await new Promise((resolve, reject) => {
  const request = http.request({
    host: '127.0.0.1',
    port: proxyPort,
    path: '/v1/messages?beta=true',
    method: 'POST',
    headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(body) },
  }, response => {
    const chunks = [];
    response.on('data', chunk => chunks.push(chunk));
    response.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
  });
  request.on('error', reject);
    request.end(body);
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

assert.match(childOutput, /"requested_effort":"max","effective_effort":"ollama_think_enabled","rewritten":false/);
assert.match(childOutput, /"requested_effort":"xhigh","effective_effort":"ollama_think_enabled","rewritten":false/);
assert.match(childOutput, /"effective_effort":"disabled","rewritten":false/);
assert.match(childOutput, /"type":"image_fallback".*"images_downgraded":1/);

child.kill('SIGTERM');
await once(child, 'exit');
await new Promise(resolve => upstream.close(resolve));
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
