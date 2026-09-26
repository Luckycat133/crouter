#!/bin/sh
# The MLX probe, spawned adapter, and reused adapter must agree on one upstream.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
NODE_BIN=${NODE_BIN:-$(command -v node 2>/dev/null || true)}
TEST_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-mlx-upstream)
trap 'rm -rf "$TEST_DIR"' EXIT INT TERM
mkdir "$TEST_DIR/bin"
PROBE_FILE=$TEST_DIR/probe
NODE_ENV_FILE=$TEST_DIR/node-env
export PROBE_FILE NODE_ENV_FILE

cat > "$TEST_DIR/bin/curl" <<'SH'
#!/bin/sh
for arg do url=$arg; done
case $url in
  */v1/models) printf '%s\n' "$url" >> "$PROBE_FILE" ;;
  */health)
    [ -f "$NODE_ENV_FILE" ] || exit 7
    IFS='|' read -r host port model < "$NODE_ENV_FILE"
    printf '{"service":"crouter-mlx-anthropic-adapter","upstream":"%s:%s","model":"%s"}\n' "$host" "$port" "$model"
    ;;
  *) exit 8 ;;
esac
SH
cat > "$TEST_DIR/bin/node" <<'SH'
#!/bin/sh
printf '%s|%s|%s\n' "$MLX_UPSTREAM_HOST" "$MLX_UPSTREAM_PORT" "$MLX_MODEL" > "$NODE_ENV_FILE"
exec sleep 30
SH
chmod +x "$TEST_DIR/bin/curl" "$TEST_DIR/bin/node"
PATH=$TEST_DIR/bin:$PATH
export PATH

load_last_selected_model() { return 1; }
die() { printf '%s\n' "$*" >&2; exit 1; }
. "$ROOT_DIR/providers/ollama.sh"

check_upstream() (
  expected_host=$1 expected_port=$2
  rm -f "$PROBE_FILE" "$NODE_ENV_FILE"
  # PRE_START and POST_STOP are repository-owned shell hook strings.
  # shellcheck disable=SC2090
  trap 'eval "$POST_STOP"' EXIT
  eval "$PRE_START"
  [ "$BASE_URL" = http://127.0.0.1:11436 ] || die 'Qwen did not select the MLX adapter'
  [ "$(cat "$PROBE_FILE")" = "http://$expected_host:$expected_port/v1/models" ] || die 'MLX probe used another endpoint'
  [ "$(cat "$NODE_ENV_FILE")" = "$expected_host|$expected_port|qwen3.8-27b" ] || die 'MLX adapter received another endpoint'
)

(
  unset MLX_UPSTREAM_HOST MLX_UPSTREAM_PORT
  check_upstream 10.211.55.2 18080
)
(
  MLX_UPSTREAM_HOST=127.0.0.1 MLX_UPSTREAM_PORT=08080
  export MLX_UPSTREAM_HOST MLX_UPSTREAM_PORT
  check_upstream 127.0.0.1 8080
)
cat > "$TEST_DIR/config.sh" <<'SH'
MLX_UPSTREAM_HOST=mlx.internal.example
MLX_UPSTREAM_PORT=12345
SH
(
  unset MLX_UPSTREAM_HOST MLX_UPSTREAM_PORT
  . "$TEST_DIR/config.sh"
  check_upstream mlx.internal.example 12345
)

for invalid_port in 0 65536 abc 1.5 '80/path' -1; do
  rm -f "$PROBE_FILE" "$NODE_ENV_FILE"
  if (MLX_UPSTREAM_PORT=$invalid_port; eval "$PRE_START") 2>"$TEST_DIR/error"; then
    die "accepted invalid MLX port: $invalid_port"
  fi
  grep -q 'MLX_UPSTREAM_PORT must be an integer from 1 to 65535' "$TEST_DIR/error" || die 'invalid MLX port gave an unclear error'
  [ ! -e "$PROBE_FILE" ] || die 'invalid MLX port reached the network probe'
done

printf '%s|%s|%s\n' stale.example 18080 qwen3.8-27b > "$NODE_ENV_FILE"
MLX_UPSTREAM_HOST=127.0.0.1 MLX_UPSTREAM_PORT=8080
if (eval "$PRE_START") 2>"$TEST_DIR/error"; then
  die 'reused an adapter connected to another upstream'
fi
grep -q 'uses another upstream' "$TEST_DIR/error" || die 'stale adapter gave an unclear error'
[ "$(cat "$NODE_ENV_FILE")" = 'stale.example|18080|qwen3.8-27b' ] || die 'stale adapter was replaced'

if [ -n "$NODE_BIN" ]; then
  CROUTER_TEST_ROOT=$ROOT_DIR "$NODE_BIN" --input-type=module <<'NODE'
import assert from 'node:assert/strict';
import http from 'node:http';
import { spawn, spawnSync } from 'node:child_process';
import { once } from 'node:events';

const path = `${process.env.CROUTER_TEST_ROOT}/lib/anthropic-openai-proxy.mjs`;
for (const invalid of ['0', '65536', 'abc', '1.5', '1e3']) {
  const result = spawnSync(process.execPath, [path], {
    env: { ...process.env, MLX_UPSTREAM_PORT: invalid }, encoding: 'utf8', timeout: 2000,
  });
  assert.notEqual(result.status, 0, `accepted ${invalid}`);
  assert.match(result.stderr, /MLX_UPSTREAM_PORT must be an integer from 1 to 65535/);
}

let upstreamPath = '';
let upstreamModel = '';
const upstream = http.createServer((request, response) => {
  upstreamPath = request.url;
  const chunks = [];
  request.on('data', chunk => chunks.push(chunk));
  request.on('end', () => {
    upstreamModel = JSON.parse(Buffer.concat(chunks).toString()).model;
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ choices: [{ message: { content: 'ok' }, finish_reason: 'stop' }], usage: { prompt_tokens: 1, completion_tokens: 1 } }));
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
  const adapterPort = reservation.address().port;
  await new Promise(resolve => reservation.close(resolve));

  child = spawn(process.execPath, [path], {
    env: { ...process.env, MLX_PROXY_PORT: String(adapterPort), MLX_UPSTREAM_HOST: '127.0.0.1', MLX_UPSTREAM_PORT: String(upstreamPort) },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let error = '';
  child.stderr.on('data', chunk => { error += chunk.toString(); });
  await Promise.race([
    once(child.stdout, 'data'),
    once(child, 'exit').then(([code]) => { throw new Error(`adapter exited (${code}): ${error}`); }),
    new Promise((_, reject) => setTimeout(() => reject(new Error('adapter startup timed out')), 2000)),
  ]);

  const request = (method, route, body) => new Promise((resolve, reject) => {
    const client = http.request({ host: '127.0.0.1', port: adapterPort, method, path: route, headers: { 'content-type': 'application/json' } }, response => {
      const chunks = [];
      response.on('data', chunk => chunks.push(chunk));
      response.on('end', () => resolve(JSON.parse(Buffer.concat(chunks).toString())));
    });
    client.on('error', reject);
    client.setTimeout(2000, () => client.destroy(new Error('adapter request timed out')));
    client.end(body ? JSON.stringify(body) : undefined);
  });
  const health = await request('GET', '/health');
  assert.equal(health.upstream, `127.0.0.1:${upstreamPort}`);
  const response = await request('POST', '/v1/messages', { model: 'qwen3.8-27b', stream: false, messages: [{ role: 'user', content: 'ping' }] });
  assert.equal(response.content[0].text, 'ok');
  assert.equal(upstreamPath, '/v1/chat/completions');
  assert.equal(upstreamModel, 'qwen3.8-27b');
} finally {
  if (child && child.exitCode === null && child.signalCode === null) {
    const exited = once(child, 'exit');
    child.kill('SIGTERM');
    const timeout = setTimeout(() => child.kill('SIGKILL'), 1000);
    await exited;
    clearTimeout(timeout);
  }
  upstream.closeAllConnections();
  await new Promise(resolve => upstream.close(resolve));
}
NODE
fi

printf 'ok    MLX override, probe, adapter upstream and port validation\n'
