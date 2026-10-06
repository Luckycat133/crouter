#!/usr/bin/env node

import http from 'node:http';

const listenHost = process.env.OLLAMA_HEARTBEAT_HOST || '127.0.0.1';
const listenPort = Number(process.env.OLLAMA_HEARTBEAT_PORT || 11435);
const upstreamHost = process.env.OLLAMA_UPSTREAM_HOST || '127.0.0.1';
const upstreamPort = Number(process.env.OLLAMA_UPSTREAM_PORT || 11434);
const heartbeatMs = Number(process.env.OLLAMA_HEARTBEAT_INTERVAL_MS || 60000);
const effortRewriteVersion = 'deepseek-anthropic-pass-through-v2';
const imageFallbackVersion = 'deepseek-text-image-v1';
const effortClampVersion = 'ollama-effort-clamp-v1';
// Highest reasoning effort the selected local model accepts. Empty means "leave
// whatever Claude Code sends untouched", which is the right default for models
// whose chat template does accept every level.
const effortCap = (process.env.OLLAMA_EFFORT_MAX || '').trim().toLowerCase();
const effortOrder = ['low', 'medium', 'high', 'xhigh', 'max'];
const imageFallbackText = '[Image omitted by crouter: this local DeepSeek model is text-only. Continue without native vision; use browser DOM, console output, Canvas pixel statistics, or other text-based inspection instead.]';

for (const [name, value] of Object.entries({ listenPort, upstreamPort, heartbeatMs })) {
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`${name} must be a positive number`);
  }
}
if (effortCap && !effortOrder.includes(effortCap)) {
  throw new Error(`OLLAMA_EFFORT_MAX must be one of ${effortOrder.join('|')}`);
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

function contentText(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content
    .map(block => (block?.type === 'text' ? (block.text || '') : ''))
    .filter(Boolean)
    .join('\n');
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

// Ollama's Anthropic-compatible endpoint copies `output_config.effort` into the
// model's Jinja chat template after collapsing `xhigh` to `high`. Local
// templates commonly reject anything above the level they implement — the
// Qwen3.8 template raises on both `high` and `max` — and Ollama answers that
// with HTTP 500 whose body never mentions `output_config`. Claude Code can only
// downgrade effort when it sees that field name in the error, so the session
// otherwise retries the same rejected request with exponential backoff for up
// to half an hour. Clamp to the cap the provider declared for this model.
function clampLocalEffort(parsed) {
  if (!effortCap) return null;
  const requested = typeof parsed.output_config?.effort === 'string'
    ? parsed.output_config.effort.trim().toLowerCase()
    : '';
  if (!requested || requested === effortCap) return null;
  const requestedRank = effortOrder.indexOf(requested);
  if (requestedRank > -1 && requestedRank <= effortOrder.indexOf(effortCap)) return null;
  parsed.output_config = { ...parsed.output_config, effort: effortCap };
  return { requested_effort: requested, effective_effort: effortCap, cap: effortCap };
}

function normalizeDeepSeekRequest(body, method, url) {
  if (method !== 'POST' || !url?.startsWith('/v1/messages')) {
    return { body, parsed: null, effortTelemetry: null, imageTelemetry: null, effortClampTelemetry: null };
  }

  let parsed;
  try {
    parsed = JSON.parse(body.toString('utf8'));
  } catch {
    return { body, parsed: null, effortTelemetry: null, imageTelemetry: null, effortClampTelemetry: null };
  }

  const model = typeof parsed.model === 'string' ? parsed.model : '';
  if (!/^deepseek-v4(?:-|:)/i.test(model)) {
    // Qwen's Jinja chat template raises as soon as a system turn follows any
    // other turn, and Ollama emits the top-level `system` field ahead of
    // `messages`. A system-role message left inside `messages` therefore can
    // never be first; fold those turns into the top-level field instead so the
    // template sees exactly one system turn at the start.
    let modified = false;
    if (Array.isArray(parsed.messages)) {
      const systemMsgs = parsed.messages.filter(m => m?.role === 'system');
      if (systemMsgs.length > 0) {
        const systemText = systemMsgs.map(m => contentText(m.content)).filter(Boolean).join('\n\n');
        const declaredSystem = Array.isArray(parsed.system)
          ? parsed.system
          : (typeof parsed.system === 'string' && parsed.system ? [{ type: 'text', text: parsed.system }] : []);
        parsed.system = systemText
          ? [...declaredSystem, { type: 'text', text: systemText }]
          : declaredSystem;
        parsed.messages = parsed.messages.filter(m => m?.role !== 'system');
        modified = true;
        process.stdout.write(`${JSON.stringify({ type: 'system_fold', model, system_msgs_folded: systemMsgs.length })}\\n`);
      }
    }
    const clamped = clampLocalEffort(parsed);
    if (clamped) modified = true;
    const resBody = modified ? Buffer.from(JSON.stringify(parsed)) : body;
    return { body: resBody, parsed, effortTelemetry: null, imageTelemetry: null, effortClampTelemetry: clamped };
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
    effortClampTelemetry: null,
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
      effort_clamp: effortClampVersion,
      effort_cap: effortCap,
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
    if (normalized.effortClampTelemetry) {
      process.stdout.write(`${JSON.stringify({ type: 'effort_clamp', version: effortClampVersion, ...normalized.effortClampTelemetry })}\n`);
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
