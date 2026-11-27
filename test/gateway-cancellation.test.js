'use strict';
// Real gateway processes and loopback HTTP transports only. No account access.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const http = require('node:http');
const {spawn} = require('node:child_process');

const ROOT = path.resolve(process.env.ROOT_DIR || path.join(__dirname, '..'));
const GATEWAY = path.resolve(process.env.CROUTER_TEST_GATEWAY_PATH || path.join(ROOT, 'bin/gateway'));
const LOCAL_TOKEN = 'fixture-local-gateway-token';
const pause = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function waitFor(predicate, message, timeout = 800) {
  const deadline = Date.now() + timeout;
  while (!predicate()) {
    assert.ok(Date.now() < deadline, message);
    await pause(5);
  }
}
function event(type, data) { return `event: ${type}\ndata: ${JSON.stringify({...data, type})}\n\n`; }
const FIRST_EVENT = event('message_start', {message: {id: 'fixture-msg', role: 'assistant', model: 'upstream-first', content: []}});
const LAST_EVENT = event('message_stop', {});

async function fixture(t, handler) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'crouter-gateway-cancel-'));
  const home = path.join(dir, 'home');
  fs.mkdirSync(home);
  const calls = [];
  const sockets = new Set();
  const clients = new Set();
  const timers = new Set();
  const errors = [];
  let child;
  let childExited = false;
  let stderr = '';
  const later = (fn, ms) => {
    const timer = setTimeout(() => { timers.delete(timer); fn(); }, ms);
    timers.add(timer);
    return timer;
  };
  const upstream = http.createServer((request, response) => {
    const call = {request, response, headers: request.headers, path: request.url,
      finished: false, closed: false, closedBeforeFinish: false, body: null};
    calls.push(call);
    response.once('finish', () => { call.finished = true; });
    response.once('close', () => {
      call.closed = true;
      call.closedBeforeFinish = !response.writableFinished;
    });
    const chunks = [];
    request.on('error', (error) => errors.push(error));
    request.on('data', (chunk) => chunks.push(chunk));
    request.on('end', () => {
      try {
        assert.equal(request.method, 'POST');
        assert.ok(['/first/v1/messages', '/second/v1/messages'].includes(request.url));
        call.body = JSON.parse(Buffer.concat(chunks).toString('utf8'));
        handler(call, {calls, later});
      } catch (error) {
        errors.push(error);
        response.destroy();
      }
    });
  });
  upstream.on('connection', (socket) => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
  });
  t.after(async () => {
    clients.forEach((client) => client.destroy());
    timers.forEach(clearTimeout);
    if (child && !childExited) {
      child.kill('SIGTERM');
      await Promise.race([
        new Promise((resolve) => child.once('exit', resolve)),
        pause(850),
      ]);
      if (!childExited) {
        child.kill('SIGKILL');
        await new Promise((resolve) => child.once('exit', resolve));
      }
    }
    upstream.closeAllConnections();
    sockets.forEach((socket) => socket.destroy());
    await new Promise((resolve) => upstream.close(resolve));
    fs.rmSync(dir, {recursive: true, force: true});
  });
  await new Promise((resolve) => upstream.listen(0, '127.0.0.1', resolve));
  const base = `http://127.0.0.1:${upstream.address().port}`;
  const routesFile = path.join(dir, 'routes.json');
  fs.writeFileSync(routesFile, JSON.stringify([{
    prefix: 'fixture', base_url: base + '/first', models: ['logical-model'],
    candidates: [
      {url: base + '/first', auth: {type: 'bearer', token: 'fixture-plan-token'},
        model_map: {'logical-model': 'upstream-first'}},
      {url: base + '/second', auth: {type: 'x-api-key', token: 'fixture-api-token'},
        model_map: {'logical-model': 'upstream-second'}},
    ],
  }]), {mode: 0o600});
  assert.equal(fs.statSync(routesFile).mode & 0o777, 0o600);
  child = spawn(process.execPath, [GATEWAY], {
    env: {PATH: process.env.PATH || '', LANG: 'C', HOME: home,
      XDG_CONFIG_HOME: path.join(home, '.config'), XDG_STATE_HOME: path.join(home, '.state'),
      CROUTER_ROUTES_FILE: routesFile, CROUTER_GATEWAY_PORT: '0', CROUTER_GATEWAY_TOKEN: LOCAL_TOKEN},
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.on('exit', () => { childExited = true; });
  child.stderr.setEncoding('utf8');
  child.stderr.on('data', (chunk) => { stderr += chunk; });
  let stdout = '';
  child.stdout.setEncoding('utf8');
  child.stdout.on('data', (chunk) => { stdout += chunk; });
  await waitFor(() => /CROUTER_GATEWAY_LISTENING_PORT=(\d+)/.test(stdout) || childExited,
    'gateway must start on a fixture port', 1500);
  assert.ok(!childExited, 'gateway exited before readiness: ' + stderr);
  const port = Number(stdout.match(/CROUTER_GATEWAY_LISTENING_PORT=(\d+)/)[1]);

  function client({stream = true, id = 'fixture-request', partialUpload = false, headers = {}} = {}) {
    const state = {text: '', status: null, response: null, ended: false, closed: false,
      aborted: false, requestFinished: false};
    const body = JSON.stringify({model: 'fixture/logical-model', stream, max_tokens: 42,
      messages: [{role: 'user', content: id}]});
    state.request = http.request({hostname: '127.0.0.1', port, path: '/v1/messages', method: 'POST',
      headers: {'Content-Type': 'application/json', Authorization: 'Bearer ' + LOCAL_TOKEN,
        'Content-Length': Buffer.byteLength(body), ...headers}}, (response) => {
      state.response = response;
      state.status = response.statusCode;
      response.setEncoding('utf8');
      response.on('data', (chunk) => { state.text += chunk; });
      response.on('end', () => { state.ended = true; });
      response.on('close', () => { state.closed = true; });
      response.on('aborted', () => { state.aborted = true; state.closed = true; });
      response.on('error', () => { state.closed = true; });
    });
    state.request.on('finish', () => { state.requestFinished = true; });
    state.request.on('error', () => { state.closed = true; });
    state.destroy = () => { state.request.destroy(); state.response?.destroy(); };
    clients.add(state);
    if (partialUpload) {
      state.request.flushHeaders();
      state.request.write(body.slice(0, 24));
    } else state.request.end(body);
    return state;
  }
  return {calls, errors, later, client, healthy: () => !childExited,
    diagnostics: () => stderr, assertNoErrors: () => assert.deepEqual(errors, [])};
}

test('gateway: disconnect before upstream headers closes the upstream request', {timeout: 5000}, async (t) => {
  const f = await fixture(t, () => {});
  const c = f.client();
  await waitFor(() => f.calls[0]?.body, 'upstream must receive the request');
  c.destroy();
  await waitFor(() => f.calls[0].closedBeforeFinish, 'cancel must close the silent upstream transport');
  await pause(450);
  assert.equal(f.calls.length, 1, 'no retry or candidate switch after cancellation');
  assert.ok(f.healthy(), f.diagnostics());
  f.assertNoErrors();
});

test('gateway: SSE client cancellation closes the streaming upstream', {timeout: 5000}, async (t) => {
  const f = await fixture(t, ({response}) => {
    response.writeHead(200, {'Content-Type': 'text/event-stream'});
    response.write(FIRST_EVENT);
  });
  const c = f.client();
  await waitFor(() => c.text.includes('message_start'), 'SSE must begin');
  c.destroy();
  await waitFor(() => f.calls[0].closedBeforeFinish, 'cancel must close upstream SSE');
  assert.equal(f.calls.length, 1);
  assert.ok(f.healthy(), f.diagnostics());
});

test('gateway: JSON-body client cancellation closes the unfinished upstream', {timeout: 5000}, async (t) => {
  const f = await fixture(t, ({response}) => {
    response.writeHead(200, {'Content-Type': 'application/json'});
    response.write('{"content":[');
  });
  const c = f.client({stream: false});
  await waitFor(() => c.text.length > 0, 'partial JSON response must arrive');
  c.destroy();
  await waitFor(() => f.calls[0].closedBeforeFinish, 'cancel must close upstream JSON body');
  assert.equal(f.calls.length, 1);
  assert.ok(f.healthy(), f.diagnostics());
});

test('gateway: cancelling a 5xx backoff prevents retry and candidate failover', {timeout: 5000}, async (t) => {
  const f = await fixture(t, ({response}) => {
    response.writeHead(503, {'Content-Type': 'application/json'});
    response.end('{"error":"fixture unavailable"}');
  });
  const c = f.client();
  await waitFor(() => f.calls[0]?.finished, 'first 503 response must finish');
  await pause(20);
  c.destroy();
  await pause(600);
  assert.equal(f.calls.length, 1, 'cancelled backoff must never retry or change candidates');
  assert.ok(f.healthy(), f.diagnostics());
});

test('gateway: an incomplete client upload never starts an upstream request', {timeout: 5000}, async (t) => {
  const f = await fixture(t, ({response}) => response.end('{}'));
  const c = f.client({partialUpload: true});
  await pause(35);
  assert.ok(!c.requestFinished, 'fixture upload must remain incomplete');
  c.destroy();
  await pause(100);
  assert.equal(f.calls.length, 0);
  assert.ok(f.healthy(), f.diagnostics());
});

test('gateway: an interrupted partial upstream response terminates the client without replay', {timeout: 5000}, async (t) => {
  const f = await fixture(t, ({response}, {later}) => {
    response.writeHead(200, {'Content-Type': 'text/event-stream'});
    response.write(FIRST_EVENT);
    later(() => response.socket?.destroy(), 35);
  });
  const c = f.client();
  await waitFor(() => c.text.includes('message_start'), 'partial upstream content must arrive');
  await waitFor(() => c.closed, 'interrupted upstream must close the downstream instead of hanging');
  assert.ok(!c.ended, 'truncated response must not report successful completion');
  assert.equal(f.calls.length, 1, 'partial responses cannot be replayed');
  assert.ok(f.healthy(), 'upstream disconnect must not crash gateway: ' + f.diagnostics());
});

test('gateway: normal request end/close does not cancel a delayed successful response', {timeout: 5000}, async (t) => {
  const f = await fixture(t, ({request, response}, {later}) => {
    assert.ok(request.complete);
    later(() => {
      response.writeHead(200, {'Content-Type': 'application/json'});
      response.end('{"content":[{"type":"text","text":"normal completion"}],"usage":{"output_tokens":2}}');
    }, 120);
  });
  const c = f.client({stream: false});
  await waitFor(() => c.ended, 'completed upload must allow delayed upstream success');
  assert.ok(c.requestFinished);
  assert.equal(c.status, 200);
  assert.equal(JSON.parse(c.text).content[0].text, 'normal completion');
  assert.equal(f.calls.length, 1);
  assert.ok(!f.calls[0].closedBeforeFinish);
  f.assertNoErrors();
});

test('gateway: cancelling one concurrent stream leaves the other running', {timeout: 5000}, async (t) => {
  const f = await fixture(t, ({body, response}, {later}) => {
    response.writeHead(200, {'Content-Type': 'text/event-stream'});
    response.write(FIRST_EVENT);
    if (body.messages[0].content === 'keep-me') later(() => response.end(LAST_EVENT), 150);
  });
  const cancelled = f.client({id: 'cancel-me'});
  const kept = f.client({id: 'keep-me'});
  await waitFor(() => cancelled.text.includes('message_start') && kept.text.includes('message_start'), 'both streams must begin');
  cancelled.destroy();
  const first = f.calls.find((call) => call.body.messages[0].content === 'cancel-me');
  const second = f.calls.find((call) => call.body.messages[0].content === 'keep-me');
  await waitFor(() => first.closedBeforeFinish, 'cancelled stream upstream must close');
  assert.ok(!second.closedBeforeFinish, 'other request must not be aborted');
  await waitFor(() => kept.ended, 'other request must finish');
  assert.ok(kept.text.includes('message_stop'));
  assert.equal(f.calls.length, 2);
  assert.ok(f.healthy(), f.diagnostics());
});

test('gateway: normal SSE text/tool/usage, route auth, model mapping and headers remain intact', {timeout: 5000}, async (t) => {
  const expected = FIRST_EVENT +
    event('content_block_start', {index: 0, content_block: {type: 'text', text: ''}}) +
    event('content_block_delta', {index: 0, delta: {type: 'text_delta', text: 'ready'}}) +
    event('content_block_stop', {index: 0}) +
    event('content_block_start', {index: 1, content_block: {type: 'tool_use', id: 'fixture-tool', name: 'read_file', input: {}}}) +
    event('content_block_delta', {index: 1, delta: {type: 'input_json_delta', partial_json: '{"path":"fixture.txt"}'}}) +
    event('content_block_stop', {index: 1}) +
    event('message_delta', {delta: {stop_reason: 'tool_use'}, usage: {output_tokens: 3}}) + LAST_EVENT;
  const f = await fixture(t, ({headers, body, response}) => {
    assert.equal(headers.authorization, 'Bearer fixture-plan-token');
    assert.equal(headers['x-api-key'], undefined);
    assert.equal(headers['anthropic-auth-token'], undefined);
    assert.equal(headers['anthropic-version'], '2023-06-01');
    assert.equal(body.model, 'upstream-first');
    assert.equal(body.max_tokens, 42);
    response.writeHead(200, {'Content-Type': 'text/event-stream', 'X-Fixture-Upstream': 'preserved'});
    response.end(expected);
  });
  const c = f.client({headers: {'x-api-key': 'fixture-client-key-must-not-leak',
    'anthropic-auth-token': 'fixture-client-auth-must-not-leak', 'anthropic-version': '2023-06-01'}});
  await waitFor(() => c.ended, 'normal SSE response must complete');
  assert.equal(c.status, 200);
  assert.equal(c.text, expected);
  assert.equal(c.response.headers['x-fixture-upstream'], 'preserved');
  assert.equal(f.calls.length, 1);
  f.assertNoErrors();
});

test('gateway: an ordinary pre-response auth failure still uses the next candidate credentials and map', {timeout: 5000}, async (t) => {
  const f = await fixture(t, ({headers, path: requestPath, body, response}) => {
    if (requestPath.startsWith('/first/')) {
      assert.equal(headers.authorization, 'Bearer fixture-plan-token');
      assert.equal(body.model, 'upstream-first');
      response.writeHead(401, {'Content-Type': 'application/json'});
      response.end('{"error":"fixture rejected"}');
    } else {
      assert.equal(headers.authorization, undefined);
      assert.equal(headers['x-api-key'], 'fixture-api-token');
      assert.equal(body.model, 'upstream-second');
      response.writeHead(200, {'Content-Type': 'application/json'});
      response.end('{"ok":true}');
    }
  });
  const c = f.client({stream: false});
  await waitFor(() => c.ended, 'ordinary auth failover must still succeed');
  assert.equal(c.status, 200);
  assert.deepEqual(JSON.parse(c.text), {ok: true});
  assert.equal(f.calls.length, 2);
  f.assertNoErrors();
});
