---
name: crouter-provider-plan
description: Standardize, configure, audit, and test AI provider subscription plans (Coding Plan, Agent Plan, Token Plan) and companion MCP assets in crouter. Use when integrating new vendor subscription plans, updating dual-surface auth (PLAN_URL / API_URL), configuring session-isolated zero-collision MCP injection (lib/provider-assets.js), adding vendor-bundled companion MCPs (MiniMax MCP, DashScope search, Volcengine tools), tuning context token thresholds, or writing test assertions in test/provider-matrix.sh and test/provider-assets.sh.
---

# crouter Provider Plan & Companion Asset Integration

Standardized workflow for configuring, auditing, and maintaining AI vendor subscription plans (Coding Plan, Agent Plan, Token Plan) and their associated MCP tooling in `crouter`.

## Architecture & Core Invariants

All vendor plans must adhere to the standard established for **Volcengine Ark** and **MiniMax**:

1. **Dual-Surface Authentication (`AUTH_MODE="surfaces"`)**:
   - Separate subscription plans from pay-as-you-go APIs.
   - Plan configuration: `PLAN_URL`, `PLAN_AUTH_TYPE="bearer"`, `PLAN_KEY_ENV`, `PLAN_KEYS`, `PLAN_MODEL*`.
   - API configuration: `API_URL`, `API_AUTH_TYPE="bearer"`, `API_KEY_ENV`, `API_KEYS`, `API_MODEL*`.
   - Dedicated provider files when gateway endpoints or model families diverge (e.g. `volcengine` for Agent Plan vs `volcengine-coding` for Coding Plan; `dashscope` vs `dashscope-coding`; `qianfan` vs `qianfan-coding` vs `qianfan-team`).

2. **Provider Assets & Companion Tools by Vendor Type**:
   - **Multi-Tool Suites (e.g. Volcengine Ark)**: Multi-tool suites (e.g. search, data plane, control plane, docs).
   - **Vendors with Companion MCPs**: MiniMax (`minimax-coding-plan-mcp`), DashScope (`WebSearch`), Z.AI (`@z_ai/mcp-server`, web_search, zread), StepFun (`web_search`), Tencent (`TENCENT_MCP_URL`), Qiniu (`QINIU_MCP_URLS`).
   - **Pure Model Gateways**: Moonshot, Xiaomi, Huawei, DeepSeek do NOT ship companion MCPs. They use `ASSET_PROFILE="empty"` or no asset profile. Do not force MCP injection on vendors that do not offer one.

3. **Session-Scoped Zero-Collision MCP Assets**:
   - All MCP servers and plugins are generated dynamically by `lib/provider-assets.js` into an isolated temporary file (`mktemp -t crouter-mcp.XXXXXX`) with mode `0600`.
   - Passed to Claude Code via `--mcp-config <tmpfile>`.
   - The temporary file is deleted immediately upon session exit via trap in `cleanup_provider_assets()` (`lib/assets.sh`).
   - **`~/.claude.json` is NEVER modified or contaminated.** Switching between different provider plans (e.g. Volcengine -> MiniMax -> DashScope -> Moonshot) completely replaces active tools with zero possibility of collision or leftover state.

4. **Autonomous Tool Invocation**:
   - Companion MCP tools mounted via `--mcp-config` are registered as first-class model tools.
   - Models invoke them autonomously via tool-calling whenever relevant (e.g., search queries, technical documentation lookup, domain datasets). Users can also invoke them explicitly by name.

5. **Quota and Billing Guardrails**:
   - Plan calls consume subscription quotas (AFP / token packages) without incurring cash charges.
   - Cash billing / overage must not be triggered silently.

---

## Step-by-Step Implementation Workflow

### Step 1: Provider Plan Definition (`providers/<provider>.sh`)

Define or update the provider configuration script:

```sh
#!/bin/sh
PROVIDER_NAME="provider-name"
PROVIDER_DESC="Provider Display Name (Subscription Plan)"

# Fallback resolution for user env vars
if [ -z "${PROVIDER_PLAN_KEY:-}" ]; then
  if [ -n "${PROVIDER_API_KEY:-}" ]; then
    export PROVIDER_PLAN_KEY="$PROVIDER_API_KEY"
  fi
fi

BASE_URL="https://api.vendor.com/plan/v1"
MODEL="vendor-flagship-model"
CONTEXT_TOKENS="1000000"
AUTO_COMPACT_TOKENS="1000000"
MODEL_OPUS="vendor-flagship-model"
MODEL_SONNET="vendor-flagship-model"
MODEL_HAIKU="vendor-fast-model"
MODEL_SUBAGENT="vendor-flagship-model"
MODEL_ALIASES="vendor-fast-model vendor-pro-model"
EFFORT="high"

AUTH_MODE="surfaces"
PLAN_URL="https://api.vendor.com/plan/v1"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="PROVIDER_PLAN_KEY"
PLAN_KEYS="provider-plan-key-name"
PLAN_MODEL="vendor-flagship-model"
PLAN_MODEL_OPUS="vendor-flagship-model"
PLAN_MODEL_SONNET="vendor-flagship-model"
PLAN_MODEL_HAIKU="vendor-fast-model"
PLAN_MODEL_SUBAGENT="vendor-flagship-model"

ASSET_PROFILE="provider-name" # or "empty" if vendor has no companion tools
EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
```

### Step 2: Session Asset & MCP Injection (`lib/provider-assets.js`)

In `lib/provider-assets.js`, add or update the `profile` branch (only if vendor has companion MCPs):

```javascript
} else if (profile === 'provider-name') {
  // 1. Optional public docs or zero-auth tools
  mcpServers['crouter-provider-docs'] = {
    type: 'http',
    url: 'https://docs.vendor.com/mcp',
  };

  // 2. Credential-gated companion tools (stdio uvx/npx or streamable http/sse)
  if (planToken) {
    mcpServers['crouter-provider-search'] = {
      command: 'uvx',
      args: ['vendor-search-mcp>=1.0.0', 'vendor-search-mcp'],
      env: {
        VENDOR_API_KEY: planToken,
      },
    };
  }
}
```

Rules:
- Prefix all tool names with `crouter-<provider>-<tool>`.
- Always gate credentialed tools behind `if (planToken)` or `if (activeToken)`.
- Never hardcode user secrets.
- Verify that URL endpoints match official vendor hosts.

### Step 3: Test Matrix Verification (`test/provider-matrix.sh`)

Add verification assertions in `test/provider-matrix.sh` for the provider:
- Verify `AUTH_MODE="surfaces"` and `PLAN_URL`.
- Verify key fallback resolution.
- Verify model aliases and context overrides.

Run the test suite:
```sh
sh test/provider-matrix.sh
dash test/provider-matrix.sh
```

### Step 4: Asset Rendering Verification (`test/provider-assets.sh`)

Add test cases in `test/provider-assets.sh`:
- Verify output file permissions are `0600`.
- Verify tools are injected when token is present.
- Verify tools are omitted when token is empty.
- Verify cleanup removes the temporary file.

Run the asset test suite:
```sh
sh test/provider-assets.sh
dash test/provider-assets.sh
```

### Step 5: Portability & Quality Checks

Run repository standard checks:
```sh
# 1. Shell syntax
sh -n providers/<provider>.sh
dash -n providers/<provider>.sh

# 2. Before release or for cross-cutting provider changes, run all tests
for test_file in test/*.sh; do sh "$test_file" || exit; done
for test_file in test/*.sh; do dash "$test_file" || exit; done

# 3. Check git diff for trailing whitespace or unintended edits
git diff --check
```

---

## Detailed References

- [Vendor Plan Matrix](references/vendor-plan-matrix.md): Complete list of vendor endpoints, tokens, models, and companion tools.
- [Provider MCP Recipes](references/companion-mcp-recipes.md): Code recipes for uvx, npx, streamable HTTP, and SSE transports.
