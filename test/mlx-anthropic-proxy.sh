#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node)}
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-mlx-media)
UPSTREAM_PORT=19481
PROXY_PORT=19482
UPSTREAM_PID=
PROXY_PID=
cleanup() {
  [ -z "$PROXY_PID" ] || kill "$PROXY_PID" 2>/dev/null || true
  [ -z "$UPSTREAM_PID" ] || kill "$UPSTREAM_PID" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

CAPTURE_PATH="$TMP_DIR/request.json" UPSTREAM_PORT="$UPSTREAM_PORT" "$NODE_BIN" - <<'NODE' &
const fs = require('fs');
const http = require('http');
http.createServer((request, response) => {
  const chunks = [];
  request.on('data', chunk => chunks.push(chunk));
  request.on('end', () => {
    fs.writeFileSync(process.env.CAPTURE_PATH, Buffer.concat(chunks));
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(JSON.stringify({id:'mock', choices:[{message:{content:'ok'}, finish_reason:'stop'}], usage:{prompt_tokens:10,completion_tokens:1}}));
  });
}).listen(Number(process.env.UPSTREAM_PORT), '127.0.0.1');
NODE
UPSTREAM_PID=$!

MLX_PROXY_PORT="$PROXY_PORT" MLX_UPSTREAM_HOST=127.0.0.1 MLX_UPSTREAM_PORT="$UPSTREAM_PORT" \
  MLX_MODEL=qwen3.8-27b "$NODE_BIN" "$ROOT_DIR/lib/anthropic-openai-proxy.mjs" >"$TMP_DIR/proxy.log" 2>&1 &
PROXY_PID=$!

for _try in 1 2 3 4 5 6 7 8 9 10; do
  curl -fsS "http://127.0.0.1:$PROXY_PORT/health" >/dev/null 2>&1 && break
  sleep 0.1
done

curl -fsS -X POST "http://127.0.0.1:$PROXY_PORT/v1/messages" \
  -H 'content-type: application/json' \
  --data-binary '{"model":"qwen3.8-27b","max_tokens":32,"messages":[{"role":"user","content":[{"type":"text","text":"inspect"},{"type":"image","source":{"type":"base64","media_type":"image/png","data":"aW1hZ2U="}},{"type":"video","source":{"type":"url","url":"file:///tmp/sample.mp4"}}]},{"role":"assistant","content":[{"type":"tool_use","id":"read_1","name":"Read","input":{"file_path":"/tmp/tool.png"}}]},{"role":"user","content":[{"type":"tool_result","tool_use_id":"read_1","content":[{"type":"text","text":"Image dimensions: 10x10"},{"type":"image","source":{"type":"base64","media_type":"image/jpeg","data":"dG9vbC1pbWFnZQ=="}}]}]}]}' \
  >"$TMP_DIR/response.json"

CAPTURE_PATH="$TMP_DIR/request.json" "$NODE_BIN" - <<'NODE'
const assert = require('assert');
const fs = require('fs');
const body = JSON.parse(fs.readFileSync(process.env.CAPTURE_PATH, 'utf8'));
assert.strictEqual(body.model, 'qwen3.8-27b');
assert.strictEqual(body.max_tokens, Number(process.env.MLX_MAX_OUTPUT_TOKENS || 32));
if (process.env.MLX_TOP_K !== undefined) assert.strictEqual(body.top_k, Number(process.env.MLX_TOP_K));
if (process.env.MLX_MIN_P !== undefined) assert.strictEqual(body.min_p, Number(process.env.MLX_MIN_P));
if (process.env.MLX_REASONING_EFFORT !== undefined) {
  assert.strictEqual(body.reasoning_effort, process.env.MLX_REASONING_EFFORT);
  assert.strictEqual(body.chat_template_kwargs.reasoning_effort, process.env.MLX_REASONING_EFFORT);
}
const content = body.messages[0].content;
assert.deepStrictEqual(content[0], {type:'text', text:'inspect'});
assert.deepStrictEqual(content[1], {type:'image_url', image_url:{url:'data:image/png;base64,aW1hZ2U='}});
assert.deepStrictEqual(content[2], {type:'video_url', video_url:{url:'file:///tmp/sample.mp4'}});
assert.strictEqual(body.messages[1].tool_calls[0].function.name, 'Read');
assert.deepStrictEqual(body.messages[2], {role:'tool', tool_call_id:'read_1', content:'Image dimensions: 10x10'});
assert.deepStrictEqual(body.messages[3], {role:'user', content:[{type:'image_url', image_url:{url:'data:image/jpeg;base64,dG9vbC1pbWFnZQ=='}}]});
NODE

printf 'ok    MLX adapter preserves Anthropic image and video media\n'
