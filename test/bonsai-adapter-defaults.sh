#!/bin/sh
# Loopback fixtures only; native model runtimes are never contacted.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export ROOT_DIR
node --input-type=module - <<'NODE'
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
const capture = [];
const upstream = http.createServer(async (req, res) => {
  let body = ''; for await (const chunk of req) body += chunk;
  capture.push(JSON.parse(body));
  res.writeHead(200, {'content-type':'application/json'});
  res.end(JSON.stringify({choices:[{message:{content:'ok'},finish_reason:'stop'}]}));
});
upstream.listen(0, '127.0.0.1'); await once(upstream, 'listening');
const probe = net.createServer(); probe.listen(0, '127.0.0.1'); await once(probe, 'listening');
const port = probe.address().port; await new Promise(resolve => probe.close(resolve));
const proxy = spawn(process.execPath, [process.env.ROOT_DIR + '/lib/anthropic-openai-proxy.mjs'], {
  env:{...process.env, MLX_PROXY_PORT:String(port), MLX_UPSTREAM_HOST:'127.0.0.1', MLX_UPSTREAM_PORT:String(upstream.address().port),
    MLX_MODEL:'ternary-bonsai-2.5-27b', MLX_UPSTREAM_MODEL:'/native/Bonsai25', MLX_INHERIT_DEFAULTS:'1',
    MLX_TEMPERATURE:'99', MLX_TOP_P:'99', MLX_TOP_K:'99', MLX_MIN_P:'99', MLX_MAX_OUTPUT_TOKENS:'999',
    MLX_REPETITION_PENALTY:'99', MLX_PRESENCE_PENALTY:'99', MLX_FREQUENCY_PENALTY:'99', MLX_REASONING_EFFORT:'xhigh'},
  stdio:['ignore','pipe','pipe']
});
try {
  await Promise.race([once(proxy.stdout, 'data'), once(proxy, 'exit').then(() => {throw Error('adapter exited before startup');})]);
  const endpoint = `http://127.0.0.1:${port}`;
  const health = await (await fetch(endpoint + '/health')).json();
  assert.equal(health.inherit_defaults, true); assert.equal(health.upstream_model, '/native/Bonsai25');
  const base = {model:'ternary-bonsai-2.5-27b',messages:[{role:'user',content:'fixture'}]};
  const send = data => fetch(endpoint + '/v1/messages', {method:'POST',body:JSON.stringify(data)});
  assert.equal((await (await send(base)).json()).model, base.model);
  assert.deepEqual(Object.keys(capture[0]).sort(), ['messages','model','stream']);
  assert.equal(capture[0].model, '/native/Bonsai25');
  await send({...base,max_tokens:32,temperature:0,top_p:0.8,top_k:7,thinking:{type:'disabled'}});
  assert.deepEqual(capture[1], {model:'/native/Bonsai25',messages:[{role:'user',content:'fixture'}],stream:false,
    max_tokens:32,temperature:0,top_p:0.8,top_k:7,chat_template_kwargs:{enable_thinking:false}});
  assert.equal((await send({...base,model:'wrong-model'})).status, 400);
  assert.equal(capture.length, 2);
  console.log('ok    Bonsai adapter inherits native defaults and preserves selected model identity');
} finally {
  proxy.kill(); await once(proxy, 'exit');
  await new Promise(resolve => upstream.close(resolve));
}
NODE
