# Provider MCP Assets & Tool Recipes

This guide outlines recipes for injecting vendor-provided MCP tools in `lib/provider-assets.js` and explains how session isolation is maintained.

> [!NOTE]
> **Terminology**: Some vendors brand their bundled multi-tool suite (e.g. a vendor search bundle) as a "Harness". Other vendors simply provide standalone MCP servers, plugins, or no companion tools at all. In `crouter`, this entire mechanism is called **Provider Assets**.

---

## 1. Do All Providers Need MCP Assets?

**No.** Providers fall into three categories:

1. **Vendors with multi-tool suites**: a few vendors ship an official multi-tool Harness.
2. **Vendors with Companion MCPs**: MiniMax (`minimax-coding-plan-mcp`), DashScope (`WebSearch`), Z.AI (`@z_ai/mcp-server`, web_search, zread), StepFun (`step_plan/v1/mcp/web_search`), Tencent (`CR_TENCENT_MCP_URL`), Qiniu (`CR_QINIU_MCP_URLS`).
3. **Pure Model Gateways**: Moonshot, Xiaomi, Huawei, DeepSeek, etc. do NOT ship companion MCP tools. Their `ASSET_PROFILE` is either `empty` or omitted, requiring zero MCP processes.

---

## 2. Zero-Collision Lifecycle Architecture

`crouter` guarantees that switching between different subscription plans (e.g. MiniMax -> DashScope -> Moonshot) will NEVER contaminate tools or retain residual configurations.

```
+-------------------------------------------------------------------+
| 1. User launches session: crouter minimax                        |
|                                                                   |
| 2. lib/assets.sh: prepare_provider_assets()                       |
|    - Runs: node lib/provider-assets.js render minimax <tmpfile>  |
|    - Outputs JSON with file permissions 0600                     |
|                                                                   |
| 3. bin/crouter -> lib/launch.sh:                                  |
|    - Passes --mcp-config <tmpfile> to Claude Code                |
|    - Claude Code exposes tools directly to the model              |
|                                                                   |
| 4. Session Terminated (Exit / Ctrl+C / Error):                    |
|    - lib/assets.sh: cleanup_provider_assets() (hooked in trap)    |
|    - Deletes <tmpfile> immediately                                |
|    - ~/.claude.json is untouched at all times                     |
+-------------------------------------------------------------------+
```

---

## 3. Common Transport Recipes

### A. Python UVX / Stdio Tools
Used when vendors publish Python packages (e.g. MiniMax Coding Plan, OpenViking):

```javascript
mcpServers['crouter-minimax-token-plan'] = {
  command: 'uvx',
  args: ['minimax-coding-plan-mcp==0.0.4', '-y'],
  env: {
    MINIMAX_API_KEY: planToken,
    MINIMAX_API_HOST: 'https://api.minimaxi.com',
  },
};
```

### B. Node NPX / Stdio Tools
Used when vendors distribute packages on NPM (e.g. `@z_ai/mcp-server`):

```javascript
mcpServers['crouter-zai-vision'] = {
  type: 'stdio',
  command: 'npx',
  args: ['-y', '@z_ai/mcp-server@0.1.4'],
  env: {
    Z_AI_API_KEY: activeToken,
    Z_AI_MODE: 'ZAI',
  },
};
```

### C. Streamable HTTP Tools
Used for direct HTTP endpoints (e.g. DashScope WebSearch, StepFun WebSearch):

```javascript
mcpServers['crouter-dashscope-web-search'] = {
  type: 'http',
  url: 'https://dashscope.aliyuncs.com/api/v1/mcps/WebSearch/mcp',
  headers: {Authorization: 'Bearer ' + apiToken},
};
```

### D. Server-Sent Events (SSE) Tools
Used for streaming MCP servers (e.g. Tencent Web Search):

```javascript
mcpServers['crouter-tencent-web-search'] = {
  type: 'sse',
  url: endpoint,
};
```

---

## 4. Invariants

1. **Prefixing**: Always name servers `crouter-<provider>-<tool>` to prevent tool name collision.
2. **Credential Gating**: Only register tools if credentials are valid (`if (planToken)` or `if (activeToken)`).
3. **Never touch user global config**: Only output to caller-supplied temporary files with mode `0600`.
