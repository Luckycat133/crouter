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
let receivedBody = '';

const upstream = http.createServer((request, response) => {
  const chunks = [];
  request.on('data', chunk => chunks.push(chunk));
  request.on('end', () => {
    receivedBody = Buffer.concat(chunks).toString('utf8');
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
child.stderr.on('data', chunk => { childError += chunk.toString(); });
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

const responseBody = await new Promise((resolve, reject) => {
  const request = http.request({
    host: '127.0.0.1',
    port: proxyPort,
    path: '/v1/messages?beta=true',
    method: 'POST',
    headers: { 'content-type': 'application/json', 'content-length': Buffer.byteLength(expectedBody) },
  }, response => {
    const chunks = [];
    response.on('data', chunk => chunks.push(chunk));
    response.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
  });
  request.on('error', reject);
  request.end(expectedBody);
});

assert.equal(receivedBody, expectedBody);
assert.match(responseBody, /event: message_start/);
assert.ok((responseBody.match(/: crouter-ollama-heartbeat/g) || []).length >= 3, responseBody);

child.kill('SIGTERM');
await once(child, 'exit');
await new Promise(resolve => upstream.close(resolve));
console.log('ok    Ollama heartbeat proxy preserves bytes and emits SSE comments');
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
