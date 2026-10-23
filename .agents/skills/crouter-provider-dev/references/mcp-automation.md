# Automated Zero-Collision MCP Configuration Reference

This reference documents the implementation of companion Model Context Protocol (MCP) tooling and automated switching in `crouter`.

---

## 1. Zero-Collision Architecture

`crouter` guarantees that switching between different providers (e.g. MiniMax -> DashScope -> DeepSeek) completely replaces active tools with **zero tool collision** and **zero persistent state**.

```
+---------------------------------------------------------------------------------+
| 1. User launches session: crouter <provider>                                    |
|                                                                                 |
| 2. lib/assets.sh: prepare_provider_assets()                                     |
|    - Creates isolated temporary file: mktemp -t crouter-mcp.XXXXXX (mode 0600)  |
|    - Runs: node lib/provider-assets.js render <profile> <tmpfile>               |
|                                                                                 |
| 3. lib/launch.sh:                                                               |
|    - Passes --mcp-config <tmpfile> (and --strict-mcp-config) to Claude Code     |
|    - Tools are mounted exclusively in the active session                        |
|                                                                                 |
| 4. Session Exit / Interruption (Ctrl+C, termination, normal exit):              |
|    - cleanup_provider_assets() triggered via POSIX trap                         |
|    - Deletes <tmpfile> immediately                                              |
|    - ~/.claude.json is NEVER touched                                            |
+---------------------------------------------------------------------------------+
```

---

## 2. Invariants for `lib/provider-assets.js`

When adding or updating a profile branch in `lib/provider-assets.js`:

1. **Mandatory Prefix**: Every MCP server key must start with `crouter-<provider>-` (e.g. `crouter-minimax-token-plan`, `crouter-dashscope-web-search`).
2. **Credential Gating**: Always wrap tools requiring authentication in `if (planToken)` or `if (activeToken)`. Never register a tool with missing credentials that will fail at runtime.
3. **Never Hardcode Secrets**: Secrets arrive solely through environment variables (`CR_PLAN_TOKEN`, `CR_API_TOKEN`) and are injected only into the temporary file.
4. **Strict URL Validation**: If an MCP endpoint is read from an environment variable (e.g. `CR_TENCENT_MCP_URL`, `CR_QINIU_MCP_URLS`), validate the protocol and domain using `new URL()` to prevent SSRF or unauthorized domains.
5. **No Forced Tools**: Pure model gateways (Moonshot, DeepSeek, Xiaomi, Huawei, etc.) must map to `profile === 'empty'` or omit `ASSET_PROFILE`.

---

## 3. Transport Implementation Recipes

### A. Python UVX (`stdio`)
Used when vendors distribute tools via PyPI (e.g. MiniMax Coding Plan, OpenViking):

```javascript
} else if (profile === 'myprovider') {
  if (planToken) {
    mcpServers['crouter-myprovider-tools'] = {
      command: 'uvx',
      args: ['myprovider-mcp==1.2.0', '-y'],
      env: {
        MYPROVIDER_API_KEY: planToken,
        MYPROVIDER_HOST: 'https://api.myprovider.com',
      },
    };
  }
}
```

### B. Node NPX (`stdio`)
Used when tools are distributed via npm (e.g. `@z_ai/mcp-server`):

```javascript
} else if (profile === 'myprovider') {
  if (activeToken) {
    mcpServers['crouter-myprovider-cli'] = {
      type: 'stdio',
      command: 'npx',
      args: ['-y', '@myprovider/mcp-server@0.2.1'],
      env: {
        MYPROVIDER_API_KEY: activeToken,
      },
    };
  }
}
```

### C. Streamable HTTP (`http`)
Used for direct vendor-hosted HTTP MCP endpoints (e.g. DashScope WebSearch, StepFun WebSearch):

```javascript
} else if (profile === 'myprovider') {
  if (activeToken) {
    mcpServers['crouter-myprovider-search'] = {
      type: 'http',
      url: 'https://api.myprovider.com/v1/mcp/search',
      headers: {
        Authorization: 'Bearer ' + activeToken,
        Accept: 'application/json',
      },
    };
  }
}
```

### D. Server-Sent Events (`sse`)
Used for streaming MCP servers (e.g. Tencent Web Search):

```javascript
} else if (profile === 'myprovider') {
  const endpoint = process.env.CR_MYPROVIDER_MCP_URL || '';
  if (endpoint) {
    let parsed;
    try {
      parsed = new URL(endpoint);
    } catch (e) {
      fail('MYPROVIDER_MCP_URL is not a valid URL');
    }
    if (parsed.protocol !== 'https:' || parsed.hostname !== 'mcp.myprovider.com') {
      fail('MYPROVIDER_MCP_URL must use https://mcp.myprovider.com');
    }
    mcpServers['crouter-myprovider-search'] = {type: 'sse', url: endpoint};
  }
}
```

### E. Public Documentation / Zero-Auth Tools
For documentation lookup endpoints that require no user credential:

```javascript
} else if (profile === 'myprovider') {
  mcpServers['crouter-myprovider-docs'] = {
    type: 'http',
    url: 'https://docs.myprovider.com/mcp',
  };
}
```

---

## 4. Session Plugins & Environment Activation (`lib/assets.sh`)

If the provider includes custom session-scoped skills (located under `assets/plugins/<plugin>/skills/`):

1. Declare `ASSET_PLUGIN_DIRS` or `ASSET_PLAN_PLUGIN_DIRS` in `providers/<provider>.sh`:
   ```sh
   ASSET_PLAN_PLUGIN_DIRS="$ROOT_DIR/assets/plugins/myprovider-plan"
   ```
2. If the provider tools require specific environment variables in the Claude Code session, set `PROVIDER_ASSET_ENV` in `lib/assets.sh`:
   ```sh
   case $_asset_profile in
     myprovider)
       if [ -n "${_PLAN_FIRST_TOKEN:-}" ]; then
         PROVIDER_ASSET_ENV="MYPROVIDER_API_KEY=$_PLAN_FIRST_TOKEN
   MYPROVIDER_REGION=cn"
       fi
       ;;
   esac
   ```
