#!/usr/bin/env node
// Render provider-owned MCP profiles into a caller-supplied temporary file.
// Secrets arrive only through the process environment and are never printed.

'use strict';

const fs = require('fs');

function fail(message) {
  process.stderr.write('provider-assets: ' + message + '\n');
  process.exit(2);
}

const [command, profile, outputPath] = process.argv.slice(2);
if (command !== 'render' || !profile || !outputPath) {
  fail('usage: provider-assets.js render <profile> <output-file>');
}

const planToken = process.env.CR_PLAN_TOKEN || '';
const apiToken = process.env.CR_API_TOKEN || '';
const activeToken = planToken || apiToken;
const mcpServers = {};

if (profile === 'minimax') {
  if (planToken) {
    mcpServers['crouter-minimax-token-plan'] = {
      command: 'uvx',
      args: ['minimax-coding-plan-mcp==0.0.4', '-y'],
      env: {
        MINIMAX_API_KEY: planToken,
        MINIMAX_API_HOST: 'https://api.minimax.cn',
      },
    };
  }
} else if (profile === 'zai') {
  if (activeToken) {
    const bearerHeaders = {Authorization: 'Bearer ' + activeToken};
    mcpServers['crouter-zai-vision'] = {
      type: 'stdio',
      command: 'npx',
      args: ['-y', '@z_ai/mcp-server@0.1.4'],
      env: {Z_AI_API_KEY: activeToken, Z_AI_MODE: 'ZAI'},
    };
    mcpServers['crouter-zai-web-search'] = {
      type: 'http',
      url: 'https://api.z.ai/api/mcp/web_search_prime/mcp',
      headers: bearerHeaders,
    };
    mcpServers['crouter-zai-web-reader'] = {
      type: 'http',
      url: 'https://api.z.ai/api/mcp/web_reader/mcp',
      headers: bearerHeaders,
    };
    mcpServers['crouter-zai-zread'] = {
      type: 'http',
      url: 'https://api.z.ai/api/mcp/zread/mcp',
      headers: bearerHeaders,
    };
  }
} else if (profile === 'dashscope') {
  if (apiToken) {
    mcpServers['crouter-dashscope-web-search'] = {
      type: 'http',
      url: 'https://dashscope.aliyuncs.com/api/v1/mcps/WebSearch/mcp',
      headers: {Authorization: 'Bearer ' + apiToken},
    };
  }
} else if (profile === 'dashscope-coding') {
  if (planToken) {
    mcpServers['crouter-dashscope-web-search'] = {
      type: 'http',
      url: 'https://dashscope.aliyuncs.com/api/v1/mcps/WebSearch/mcp',
      headers: {Authorization: 'Bearer ' + planToken},
    };
  }
} else if (profile === 'volcengine') {
  mcpServers['crouter-volcengine-docs'] = {
    type: 'http',
    url: 'https://sd6j8o9hu8aldae0o6es0.apigateway-cn-beijing.volceapi.com/mcp',
  };
  if (planToken) {
    mcpServers['crouter-volcengine-doubao-search'] = {
      command: 'uvx',
      args: ['--from', 'mcp-server-askecho-search-infinity>=0.2.0', 'mcp-server-askecho-search-infinity'],
      env: {
        ASK_ECHO_SEARCH_INFINITY_API_KEY: planToken,
      },
    };
    mcpServers['crouter-volcengine-datapro'] = {
      type: 'http',
      url: 'https://datapro.hqd.cn-beijing.volces.com/mcp',
      headers: {
        'X-Agent-Plan-Key': planToken,
        Accept: 'application/json',
      },
    };
    mcpServers['crouter-volcengine-openviking'] = {
      command: 'uvx',
      args: [
        '--from',
        'git+https://github.com/volcengine/mcp-server#subdirectory=server/mcp_server_openviking_controlplane',
        'mcp-server-openviking-controlplane',
      ],
      env: {
        AGENTPLAN_API_KEY: planToken,
      },
    };
  }
} else if (profile === 'volcengine-coding') {
  mcpServers['crouter-volcengine-docs'] = {
    type: 'http',
    url: 'https://sd6j8o9hu8aldae0o6es0.apigateway-cn-beijing.volceapi.com/mcp',
  };
} else if (profile === 'stepfun') {
  if (planToken) {
    mcpServers['crouter-stepfun-web-search'] = {
      type: 'http',
      url: 'https://api.stepfun.com/step_plan/v1/mcp/web_search/mcp',
      headers: {Authorization: 'Bearer ' + planToken},
    };
  }
} else if (profile === 'aihubmix') {
  if (activeToken) {
    mcpServers['crouter-aihubmix-api'] = {
      type: 'http',
      url: 'https://aihubmix.com/mcp/',
      headers: {Authorization: 'Bearer ' + activeToken},
    };
  }
} else if (profile === 'ppio') {
  mcpServers['crouter-ppio-cloud'] = {
    type: 'http',
    url: 'https://mcp.ppio.com/mcp',
  };
} else if (profile === 'tencent' || profile === 'tencent-coding') {
  const endpoint = process.env.CR_TENCENT_MCP_URL || '';
  if (endpoint) {
    let parsed;
    try {
      parsed = new URL(endpoint);
    } catch (error) {
      fail('TENCENT_MCP_URL is not a valid URL');
    }
    if (
      parsed.protocol !== 'https:' ||
      parsed.hostname !== 'mcp-api.tencent-cloud.com' ||
      parsed.port ||
      parsed.username ||
      parsed.password
    ) {
      fail('TENCENT_MCP_URL must use https://mcp-api.tencent-cloud.com');
    }
    mcpServers['crouter-tencent-web-search'] = {type: 'sse', url: endpoint};
  }
} else if (profile === 'qiniu') {
  const endpoints = [...new Set((process.env.CR_QINIU_MCP_URLS || '').split(/\s+/).filter(Boolean))];
  endpoints.forEach((endpoint, index) => {
    let parsed;
    try {
      parsed = new URL(endpoint);
    } catch (error) {
      fail('QINIU_MCP_URLS contains an invalid URL');
    }
    if (
      parsed.protocol !== 'https:' ||
      parsed.hostname !== 'api.qnaigc.com' ||
      parsed.port ||
      parsed.username ||
      parsed.password ||
      parsed.search ||
      parsed.hash ||
      !/^\/v1\/mcp\/http-streamable\/[^/]+\/?$/.test(parsed.pathname)
    ) {
      fail('QINIU_MCP_URLS must contain only official https://api.qnaigc.com/v1/mcp/http-streamable/<id> URLs');
    }
    if (!activeToken) fail('Qiniu MCP requires an active Qiniu credential');
    mcpServers['crouter-qiniu-managed-' + (index + 1)] = {
      type: 'http',
      url: endpoint,
      headers: {Authorization: 'Bearer ' + activeToken},
    };
  });
} else if (profile === 'empty') {
  // An intentionally empty managed profile still lets --strict-mcp-config
  // suppress stale MCPs from another provider session.
} else {
  fail('unknown profile ' + JSON.stringify(profile));
}

fs.writeFileSync(outputPath, JSON.stringify({mcpServers}, null, 2) + '\n', {mode: 0o600});
