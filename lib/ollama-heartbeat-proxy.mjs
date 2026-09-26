#!/usr/bin/env node

import http from 'node:http';

const listenHost = process.env.OLLAMA_HEARTBEAT_HOST || '127.0.0.1';
const listenPort = Number(process.env.OLLAMA_HEARTBEAT_PORT || 11435);
const upstreamHost = process.env.OLLAMA_UPSTREAM_HOST || '127.0.0.1';
const upstreamPort = Number(process.env.OLLAMA_UPSTREAM_PORT || 11434);
const heartbeatMs = Number(process.env.OLLAMA_HEARTBEAT_INTERVAL_MS || 60000);
const effortRewriteVersion = 'deepseek-anthropic-pass-through-v2';
const imageFallbackVersion = 'deepseek-text-image-v1';
const imageFallbackText = '[Image omitted by crouter: this local DeepSeek model is text-only. Continue without native vision; use browser DOM, console output, Canvas pixel statistics, or other text-based inspection instead.]';

for (const [name, value] of Object.entries({ listenPort, upstreamPort, heartbeatMs })) {
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`${name} must be a positive number`);
  }
}

function copyHeaders(headers, overrides = {}) {
  const result = {};
  for (const [name, value] of Object.entries(headers)) {
    if (value !== undefined && !['connection', 'content-length', 'transfer-encoding', 'trailer'].includes(name.toLowerCase())) {
      result[name] = value;
    }
  }
  return { ...result, ...overrides };
}

function downgradeImageBlocks(content, counter, allowToolResults = true) {
  if (!Array.isArray(content)) return content;
  return content.map(block => {
    if (!block || typeof block !== 'object') return block;
    if (block.type === 'image') {
      counter.count += 1;
      return {
        type: 'text',
        text: imageFallbackText,
        ...(block.cache_control ? { cache_control: block.cache_control } : {}),
      };
    }
    if (allowToolResults && block.type === 'tool_result' && Array.isArray(block.content)) {
      return { ...block, content: downgradeImageBlocks(block.content, counter, false) };
    }
    return block;
  });
}

function normalizeDeepSeekRequest(body, method, url) {
  if (method !== 'POST' || !url?.startsWith('/v1/messages')) {
    return { body, parsed: null, effortTelemetry: null, imageTelemetry: null };
  }

  let parsed;
  try {
    parsed = JSON.parse(body.toString('utf8'));
  } catch {
    return { body, parsed: null, effortTelemetry: null, imageTelemetry: null };
  }

  const model = typeof parsed.model === 'string' ? parsed.model : '';
  if (!/^deepseek-v4(?:-|:)/i.test(model)) {
    return { body, parsed, effortTelemetry: null, imageTelemetry: null };
  }

  const requested = typeof parsed.output_config?.effort === 'string'
    ? parsed.output_config.effort.trim().toLowerCase()
    : '';
  // Keep Claude Code's Anthropic thinking request intact. Current Ollama
  // releases collapse thinking.type=enabled to their boolean local thinking
  // mode and do not enforce Anthropic budget_tokens or true effort tiers. A
  // previous rewrite deleted that bounded request and turned max into an
  // effectively unlimited 2^31-1-token reasoning budget, which could starve
  // tool calls. Telemetry is observational only; it must not overstate the
  // effective local capability.
  const effortTelemetry = requested
    ? {
        model,
        requested_effort: requested,
        effective_effort: parsed.thinking?.type === 'disabled' ? 'disabled' : 'ollama_think_enabled',
        rewritten: false,
      }
    : null;

  // Claude Code's Read tool returns screenshots as nested Anthropic image
  // blocks. A text-only Ollama runner rejects the entire request with HTTP 500
  // before the model can choose a non-visual fallback. Replace only those
  // blocks for DeepSeek V4; multimodal Ollama models remain untouched.
  const imageCounter = { count: 0 };
  if (Array.isArray(parsed.messages)) {
    parsed.messages = parsed.messages.map(message => {
      if (!message || typeof message !== 'object' || !Array.isArray(message.content)) return message;
      return { ...message, content: downgradeImageBlocks(message.content, imageCounter) };
    });
  }
  const imageTelemetry = imageCounter.count > 0
    ? { model, images_downgraded: imageCounter.count }
    : null;

  const normalizedBody = Buffer.from(JSON.stringify(parsed));
  return {
    body: body.equals(normalizedBody) ? body : normalizedBody,
    parsed,
    effortTelemetry,
    imageTelemetry,
  };
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
      effort_rewrite: effortRewriteVersion,
      image_fallback: imageFallbackVersion,
    }));
    return;
  }

  const chunks = [];
  clientRequest.on('data', (chunk) => chunks.push(chunk));
  clientRequest.on('end', () => {
    const incomingBody = Buffer.concat(chunks);
    const normalized = normalizeDeepSeekRequest(incomingBody, clientRequest.method, clientRequest.url);
    const body = normalized.body;
    if (normalized.effortTelemetry) {
      process.stdout.write(`${JSON.stringify({ type: 'effort_rewrite', version: effortRewriteVersion, ...normalized.effortTelemetry, max_tokens: normalized.parsed?.max_tokens ?? null })}\n`);
    }
    if (normalized.imageTelemetry) {
      process.stdout.write(`${JSON.stringify({ type: 'image_fallback', version: imageFallbackVersion, ...normalized.imageTelemetry })}\n`);
    }
    let isStreamingMessages = false;
    if (clientRequest.method === 'POST' && clientRequest.url?.startsWith('/v1/messages')) {
      isStreamingMessages = normalized.parsed?.stream === true;
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

    const upstreamHeaders = copyHeaders(clientRequest.headers, {
      host: `${upstreamHost}:${upstreamPort}`,
      'content-length': String(body.length),
    });
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
