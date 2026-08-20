#!/usr/bin/env node

import http from 'node:http';

const listenHost = process.env.OLLAMA_HEARTBEAT_HOST || '127.0.0.1';
const listenPort = Number(process.env.OLLAMA_HEARTBEAT_PORT || 11435);
const upstreamHost = process.env.OLLAMA_UPSTREAM_HOST || '127.0.0.1';
const upstreamPort = Number(process.env.OLLAMA_UPSTREAM_PORT || 11434);
const heartbeatMs = Number(process.env.OLLAMA_HEARTBEAT_INTERVAL_MS || 60000);

for (const [name, value] of Object.entries({ listenPort, upstreamPort, heartbeatMs })) {
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`${name} must be a positive number`);
  }
}

function copyHeaders(headers, overrides = {}) {
  const result = {};
  for (const [name, value] of Object.entries(headers)) {
    if (value !== undefined && !['connection', 'content-length', 'transfer-encoding'].includes(name.toLowerCase())) {
      result[name] = value;
    }
  }
  return { ...result, ...overrides };
}

const server = http.createServer((clientRequest, clientResponse) => {
  // A recorder, CLI, or caller may close its socket while Ollama is still
  // generating.  Treat that as request-local cancellation, never as a process
  // level exception.
  clientResponse.on('error', () => {});
  clientRequest.on('error', () => {});
  if (clientRequest.method === 'GET' && clientRequest.url === '/health') {
    clientResponse.writeHead(200, { 'content-type': 'application/json' });
    clientResponse.end(JSON.stringify({
      ok: true,
      service: 'crouter-ollama-heartbeat',
      upstream: `${upstreamHost}:${upstreamPort}`,
      heartbeat_ms: heartbeatMs,
    }));
    return;
  }

  const chunks = [];
  clientRequest.on('data', (chunk) => chunks.push(chunk));
  clientRequest.on('end', () => {
    const body = Buffer.concat(chunks);
    let isStreamingMessages = false;
    if (clientRequest.method === 'POST' && clientRequest.url?.startsWith('/v1/messages')) {
      try {
        isStreamingMessages = JSON.parse(body.toString('utf8')).stream === true;
      } catch {
        isStreamingMessages = false;
      }
    }

    let heartbeat = null;
    let upstreamRequest = null;
    let finished = false;

    const finishHeartbeat = () => {
      if (heartbeat !== null) clearInterval(heartbeat);
      heartbeat = null;
    };

    if (isStreamingMessages) {
      clientResponse.writeHead(200, {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        connection: 'keep-alive',
        'x-crouter-ollama-heartbeat': '1',
      });
      clientResponse.flushHeaders();
      clientResponse.write(': crouter-ollama-heartbeat\n\n');
      heartbeat = setInterval(() => {
        if (!clientResponse.destroyed) clientResponse.write(': crouter-ollama-heartbeat\n\n');
      }, heartbeatMs);
      heartbeat.unref();
    }

    const upstreamHeaders = { ...clientRequest.headers, host: `${upstreamHost}:${upstreamPort}`, 'content-length': String(body.length) };
    upstreamRequest = http.request({
      host: upstreamHost,
      port: upstreamPort,
      method: clientRequest.method,
      path: clientRequest.url,
      headers: upstreamHeaders,
    }, (upstreamResponse) => {
      if (!isStreamingMessages) {
        clientResponse.writeHead(upstreamResponse.statusCode || 502, copyHeaders(upstreamResponse.headers));
      } else if ((upstreamResponse.statusCode || 500) >= 400) {
        clientResponse.write(`event: error\ndata: ${JSON.stringify({ type: 'error', error: { type: 'api_error', message: `Ollama returned HTTP ${upstreamResponse.statusCode}` } })}\n\n`);
      }
      upstreamResponse.on('data', (chunk) => clientResponse.write(chunk));
      upstreamResponse.on('end', () => {
        finished = true;
        finishHeartbeat();
        clientResponse.end();
      });
      upstreamResponse.on('error', (error) => {
        finishHeartbeat();
        if (!clientResponse.destroyed) clientResponse.destroy(error);
      });
    });

    upstreamRequest.on('error', (error) => {
      finishHeartbeat();
      if (isStreamingMessages) {
        clientResponse.write(`event: error\ndata: ${JSON.stringify({ type: 'error', error: { type: 'api_error', message: error.message } })}\n\n`);
        clientResponse.end();
      } else if (!clientResponse.headersSent) {
        clientResponse.writeHead(502, { 'content-type': 'application/json' });
        clientResponse.end(JSON.stringify({ error: error.message }));
      } else {
        clientResponse.destroy(error);
      }
    });
    upstreamRequest.end(body);

    clientResponse.on('close', () => {
      finishHeartbeat();
      if (!finished && upstreamRequest && !upstreamRequest.destroyed) upstreamRequest.destroy();
    });
  });
});

server.on('clientError', (_error, socket) => {
  if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n');
  else socket.destroy();
});

server.on('error', (error) => {
  process.stderr.write(`ollama heartbeat proxy server error: ${error.stack || error.message}\n`);
  process.exitCode = 1;
});

server.listen(listenPort, listenHost, () => {
  process.stdout.write(`ollama heartbeat proxy listening on http://${listenHost}:${listenPort}\n`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
