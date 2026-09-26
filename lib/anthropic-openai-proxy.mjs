#!/usr/bin/env node

import http from 'node:http';

const listenHost = process.env.MLX_PROXY_HOST || '127.0.0.1';
function port(name, value) {
  if (!/^[0-9]+$/.test(value)) throw new Error(`${name} must be an integer from 1 to 65535`);
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 1 || parsed > 65535) {
    throw new Error(`${name} must be an integer from 1 to 65535`);
  }
  return parsed;
}

const listenPort = port('MLX_PROXY_PORT', process.env.MLX_PROXY_PORT || '11436');
const upstreamHost = process.env.MLX_UPSTREAM_HOST || '10.211.55.2';
const upstreamPort = port('MLX_UPSTREAM_PORT', process.env.MLX_UPSTREAM_PORT || '18080');
const model = process.env.MLX_MODEL || 'qwen3.8-27b';
const heartbeatMs = Number(process.env.MLX_HEARTBEAT_INTERVAL_MS || 60000);
const imageFallbackText = '[Image omitted by crouter: qwen3.8-27b is configured as a text-only local model. Continue with text-based inspection.]';

if (!Number.isFinite(heartbeatMs) || heartbeatMs <= 0) throw new Error('heartbeatMs must be a positive number');

function contentText(content) {
  if (typeof content === 'string') return content;
  if (!Array.isArray(content)) return '';
  return content.map((block) => {
    if (typeof block === 'string') return block;
    if (!block || typeof block !== 'object') return '';
    if (block.type === 'text') return block.text || '';
    if (block.type === 'image') return imageFallbackText;
    return '';
  }).filter(Boolean).join('\n');
}

function convertMessages(messages) {
  const converted = [];
  for (const message of Array.isArray(messages) ? messages : []) {
    if (!message || !['user', 'assistant'].includes(message.role)) continue;
    if (typeof message.content === 'string') {
      converted.push({ role: message.role, content: message.content });
      continue;
    }
    const blocks = Array.isArray(message.content) ? message.content : [];
    if (message.role === 'assistant') {
      const text = blocks.filter((block) => block?.type === 'text').map((block) => block.text || '').join('');
      const reasoning = blocks.filter((block) => block?.type === 'thinking').map((block) => block.thinking || '').join('');
      const toolCalls = blocks.filter((block) => block?.type === 'tool_use').map((block, index) => ({
        id: block.id || `call_${index}`,
        type: 'function',
        function: {
          name: block.name || 'unknown_tool',
          arguments: JSON.stringify(block.input && typeof block.input === 'object' ? block.input : {}),
        },
      }));
      const output = { role: 'assistant', content: text || null };
      if (reasoning) output.reasoning_content = reasoning;
      if (toolCalls.length > 0) output.tool_calls = toolCalls;
      converted.push(output);
      continue;
    }

    const text = [];
    for (const block of blocks) {
      if (!block || typeof block !== 'object') continue;
      if (block.type === 'tool_result') {
        converted.push({
          role: 'tool',
          tool_call_id: block.tool_use_id || 'unknown_tool_call',
          content: contentText(block.content),
        });
      } else if (block.type === 'text') {
        text.push(block.text || '');
      } else if (block.type === 'image') {
        text.push(imageFallbackText);
      }
    }
    if (text.length > 0) converted.push({ role: 'user', content: text.join('\n') });
  }
  return converted;
}

function convertToolChoice(choice) {
  if (!choice || choice.type === 'auto') return 'auto';
  if (choice.type === 'any') return 'required';
  if (choice.type === 'none') return 'none';
  if (choice.type === 'tool' && choice.name) {
    return { type: 'function', function: { name: choice.name } };
  }
  return 'auto';
}

function toOpenAI(request) {
  const messages = [];
  const system = contentText(request.system);
  if (system) messages.push({ role: 'system', content: system });
  messages.push(...convertMessages(request.messages));
  const converted = {
    model,
    messages,
    stream: request.stream === true,
    max_tokens: Number.isInteger(request.max_tokens) ? request.max_tokens : 65536,
    chat_template_kwargs: { enable_thinking: request.thinking?.type !== 'disabled' },
  };
  if (converted.stream) converted.stream_options = { include_usage: true };
  if (typeof request.temperature === 'number') converted.temperature = request.temperature;
  if (typeof request.top_p === 'number') converted.top_p = request.top_p;
  if (Array.isArray(request.stop_sequences) && request.stop_sequences.length > 0) converted.stop = request.stop_sequences;
  if (Array.isArray(request.tools) && request.tools.length > 0) {
    converted.tools = request.tools.map((tool) => ({
      type: 'function',
      function: {
        name: tool.name,
        description: tool.description || '',
        parameters: tool.input_schema || { type: 'object', properties: {} },
      },
    }));
    converted.tool_choice = convertToolChoice(request.tool_choice);
  }
  return converted;
}

function parseInput(value) {
  try {
    const parsed = typeof value === 'string' ? JSON.parse(value || '{}') : value;
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

function stopReason(finishReason, hasTools) {
  if (hasTools || finishReason === 'tool_calls') return 'tool_use';
  if (finishReason === 'length') return 'max_tokens';
  return 'end_turn';
}

function toAnthropic(response) {
  const choice = response.choices?.[0] || {};
  const message = choice.message || {};
  const content = [];
  if (message.reasoning) content.push({ type: 'thinking', thinking: message.reasoning, signature: 'local-mlx' });
  if (message.content) content.push({ type: 'text', text: message.content });
  for (const call of message.tool_calls || []) {
    content.push({
      type: 'tool_use',
      id: call.id || `call_${content.length}`,
      name: call.function?.name || 'unknown_tool',
      input: parseInput(call.function?.arguments),
    });
  }
  const usage = response.usage || {};
  const cached = usage.prompt_tokens_details?.cached_tokens || 0;
  return {
    id: response.id || `msg_${Date.now()}`,
    type: 'message',
    role: 'assistant',
    model,
    content,
    stop_reason: stopReason(choice.finish_reason, (message.tool_calls || []).length > 0),
    stop_sequence: null,
    usage: {
      input_tokens: Math.max(0, (usage.prompt_tokens || 0) - cached),
      output_tokens: usage.completion_tokens || 0,
      cache_read_input_tokens: cached,
      cache_creation_input_tokens: 0,
    },
  };
}

function event(response, name, data) {
  if (!response.destroyed) response.write(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`);
}

function anthropicStream(response, id) {
  let blockIndex = -1;
  let openBlock = null;
  let finishReason = null;
  let usage = {};
  let done = false;
  const toolCalls = new Map();

  event(response, 'message_start', {
    type: 'message_start',
    message: {
      id,
      type: 'message',
      role: 'assistant',
      model,
      content: [],
      stop_reason: null,
      stop_sequence: null,
      usage: { input_tokens: 0, output_tokens: 0 },
    },
  });

  const closeBlock = () => {
    if (openBlock === 'thinking') {
      event(response, 'content_block_delta', {
        type: 'content_block_delta',
        index: blockIndex,
        delta: { type: 'signature_delta', signature: 'local-mlx' },
      });
    }
    if (openBlock !== null) {
      event(response, 'content_block_stop', { type: 'content_block_stop', index: blockIndex });
      openBlock = null;
    }
  };

  const ensureBlock = (type) => {
    if (openBlock === type) return;
    closeBlock();
    blockIndex += 1;
    openBlock = type;
    event(response, 'content_block_start', {
      type: 'content_block_start',
      index: blockIndex,
      content_block: type === 'thinking'
        ? { type: 'thinking', thinking: '', signature: '' }
        : { type: 'text', text: '' },
    });
  };

  const consume = (packet) => {
    if (packet.usage) usage = packet.usage;
    const choice = packet.choices?.[0];
    if (!choice) return;
    if (choice.finish_reason) finishReason = choice.finish_reason;
    const delta = choice.delta || {};
    if (delta.reasoning) {
      ensureBlock('thinking');
      event(response, 'content_block_delta', {
        type: 'content_block_delta',
        index: blockIndex,
        delta: { type: 'thinking_delta', thinking: delta.reasoning },
      });
    }
    if (delta.content) {
      ensureBlock('text');
      event(response, 'content_block_delta', {
        type: 'content_block_delta',
        index: blockIndex,
        delta: { type: 'text_delta', text: delta.content },
      });
    }
    for (const item of delta.tool_calls || []) {
      const key = Number.isInteger(item.index) ? item.index : toolCalls.size;
      const current = toolCalls.get(key) || { id: '', name: '', arguments: '' };
      if (item.id) current.id = item.id;
      if (item.function?.name) current.name += item.function.name;
      if (item.function?.arguments) current.arguments += item.function.arguments;
      toolCalls.set(key, current);
    }
  };

  const finish = () => {
    if (done) return;
    done = true;
    closeBlock();
    for (const [index, call] of [...toolCalls.entries()].sort(([a], [b]) => a - b)) {
      blockIndex += 1;
      event(response, 'content_block_start', {
        type: 'content_block_start',
        index: blockIndex,
        content_block: {
          type: 'tool_use',
          id: call.id || `call_${index}`,
          name: call.name || 'unknown_tool',
          input: {},
        },
      });
      if (call.arguments) {
        event(response, 'content_block_delta', {
          type: 'content_block_delta',
          index: blockIndex,
          delta: { type: 'input_json_delta', partial_json: call.arguments },
        });
      }
      event(response, 'content_block_stop', { type: 'content_block_stop', index: blockIndex });
    }
    const cached = usage.prompt_tokens_details?.cached_tokens || 0;
    event(response, 'message_delta', {
      type: 'message_delta',
      delta: { stop_reason: stopReason(finishReason, toolCalls.size > 0), stop_sequence: null },
      usage: {
        input_tokens: Math.max(0, (usage.prompt_tokens || 0) - cached),
        output_tokens: usage.completion_tokens || 0,
        cache_read_input_tokens: cached,
        cache_creation_input_tokens: 0,
      },
    });
    event(response, 'message_stop', { type: 'message_stop' });
    response.end();
  };
  return { consume, finish };
}

function sendUpstream(body, onResponse, onError) {
  const payload = Buffer.from(JSON.stringify(body));
  const request = http.request({
    host: upstreamHost,
    port: upstreamPort,
    method: 'POST',
    path: '/v1/chat/completions',
    headers: { 'content-type': 'application/json', 'content-length': String(payload.length) },
  }, onResponse);
  request.on('error', onError);
  request.end(payload);
  return request;
}

function handleMessages(clientRequest, clientResponse, request) {
  const streaming = request.stream === true;
  const converted = toOpenAI(request);
  let heartbeat = null;
  let upstreamRequest = null;
  let finished = false;
  const stopHeartbeat = () => {
    if (heartbeat !== null) clearInterval(heartbeat);
    heartbeat = null;
  };
  const fail = (message, status = 502) => {
    stopHeartbeat();
    if (streaming && clientResponse.headersSent) {
      event(clientResponse, 'error', { type: 'error', error: { type: 'api_error', message } });
      clientResponse.end();
    } else if (!clientResponse.headersSent) {
      clientResponse.writeHead(status, { 'content-type': 'application/json' });
      clientResponse.end(JSON.stringify({ type: 'error', error: { type: 'api_error', message } }));
    }
  };

  if (streaming) {
    clientResponse.writeHead(200, {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache',
      connection: 'keep-alive',
      'x-crouter-mlx-heartbeat': '1',
    });
    clientResponse.flushHeaders();
    clientResponse.write(': crouter-mlx-heartbeat\n\n');
    heartbeat = setInterval(() => {
      if (!clientResponse.destroyed) clientResponse.write(': crouter-mlx-heartbeat\n\n');
    }, heartbeatMs);
    heartbeat.unref();
  }

  upstreamRequest = sendUpstream(converted, (upstreamResponse) => {
    if ((upstreamResponse.statusCode || 500) >= 400) {
      const chunks = [];
      upstreamResponse.on('data', (chunk) => chunks.push(chunk));
      upstreamResponse.on('end', () => fail(`MLX returned HTTP ${upstreamResponse.statusCode}: ${Buffer.concat(chunks).toString('utf8')}`));
      return;
    }
    if (!streaming) {
      const chunks = [];
      upstreamResponse.on('data', (chunk) => chunks.push(chunk));
      upstreamResponse.on('end', () => {
        try {
          clientResponse.writeHead(200, { 'content-type': 'application/json' });
          clientResponse.end(JSON.stringify(toAnthropic(JSON.parse(Buffer.concat(chunks).toString('utf8')))));
          finished = true;
        } catch (error) {
          fail(`Invalid MLX response: ${error.message}`);
        }
      });
      return;
    }

    const output = anthropicStream(clientResponse, `msg_${Date.now()}`);
    let buffer = '';
    upstreamResponse.setEncoding('utf8');
    upstreamResponse.on('data', (chunk) => {
      buffer += chunk.replace(/\r\n/g, '\n');
      while (true) {
        const boundary = buffer.indexOf('\n\n');
        if (boundary < 0) break;
        const frame = buffer.slice(0, boundary);
        buffer = buffer.slice(boundary + 2);
        for (const line of frame.split('\n')) {
          if (!line.startsWith('data:')) continue;
          const data = line.slice(5).trim();
          if (!data || data === '[DONE]') continue;
          try { output.consume(JSON.parse(data)); }
          catch (error) { process.stderr.write(`invalid MLX stream packet: ${error.message}\n`); }
        }
      }
    });
    upstreamResponse.on('end', () => {
      finished = true;
      stopHeartbeat();
      output.finish();
    });
    upstreamResponse.on('error', (error) => fail(error.message));
  }, (error) => fail(error.message));

  clientResponse.on('close', () => {
    stopHeartbeat();
    if (!finished && upstreamRequest && !upstreamRequest.destroyed) upstreamRequest.destroy();
  });
}

const server = http.createServer((request, response) => {
  request.on('error', () => {});
  response.on('error', () => {});
  if (request.method === 'GET' && request.url === '/health') {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify({
      ok: true,
      service: 'crouter-mlx-anthropic-adapter',
      upstream: `${upstreamHost}:${upstreamPort}`,
      model,
      heartbeat_ms: heartbeatMs,
    }));
    return;
  }
  if (request.method !== 'POST' || !request.url?.startsWith('/v1/messages')) {
    response.writeHead(404, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ error: 'Not Found' }));
    return;
  }
  const chunks = [];
  request.on('data', (chunk) => chunks.push(chunk));
  request.on('end', () => {
    try {
      const parsed = JSON.parse(Buffer.concat(chunks).toString('utf8'));
      if (parsed.model !== model) {
        response.writeHead(400, { 'content-type': 'application/json' });
        response.end(JSON.stringify({ error: `MLX adapter only accepts model ${model}` }));
        return;
      }
      handleMessages(request, response, parsed);
    } catch (error) {
      response.writeHead(400, { 'content-type': 'application/json' });
      response.end(JSON.stringify({ error: `Invalid request: ${error.message}` }));
    }
  });
});

server.on('clientError', (_error, socket) => {
  if (socket.writable) socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n');
  else socket.destroy();
});
server.on('error', (error) => {
  process.stderr.write(`MLX adapter error: ${error.stack || error.message}\n`);
  process.exitCode = 1;
});
server.listen(listenPort, listenHost, () => {
  process.stdout.write(`MLX Anthropic adapter listening on http://${listenHost}:${listenPort}\n`);
});
for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
