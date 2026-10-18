# Provider Audit & Acceptance Guide

This guide establishes the mandatory primary-source auditing workflow before any provider configuration is written in `crouter`.

## 1. Acceptance Criteria & Hard Invariants

Before writing a single line of shell script, every provider candidate must pass these acceptance gates:

### Gate 1: Official Anthropic Messages Base URL
- **Prefix Only**: The configured URL (`BASE_URL`, `PLAN_URL`, `API_URL`) must be the URL prefix **before** `/v1/messages`.
  - ✅ Correct: `https://api.deepseek.com`
  - ✅ Correct: `https://api.minimaxi.com/anthropic`
  - ❌ **Forbidden**: `https://api.deepseek.com/v1/messages` (Rejected by `test/provider-matrix.sh`)
- **Native Anthropic Compatibility**: The vendor gateway must natively accept Anthropic Messages requests (streaming, tool calling, JSON schema).
- **OpenAI-Only Gateways Excluded**: Direct OpenAI API and vendors without an official Anthropic compatibility layer (e.g. Baichuan) cannot be added as direct crouter providers. They require an audited translation proxy (such as `icebear0828/codex-proxy` on port 19000).

### Gate 2: Exact Model Identity & Casing
- Model IDs must preserve the exact casing, punctuation, and suffixes documented by the vendor (e.g. `MiniMax-M3`, `glm-4-plus`, `deepseek-v4-flash:q8`, `qwen3.8-27b`).
- Never invent date suffixes or guess unreleased model versions.
- Tiers must map logically:
  - `MODEL`: Default flagship model for general coding tasks.
  - `MODEL_OPUS`: Highest capability tier (or flagship).
  - `MODEL_SONNET`: High capability and fast reasoning.
  - `MODEL_HAIKU`: Fast, lightweight model for small edits or tool triage.
  - `MODEL_SUBAGENT`: Recommended model for subagent invocations.

### Gate 3: Context Limit vs. Auto Compaction Separation
- `CONTEXT_TOKENS`: Upstream model's maximum context window in tokens. Injects `CLAUDE_CODE_MAX_CONTEXT_TOKENS`.
  - Only configure when documented by vendor primary source.
  - If omitted, Claude Code retains its own default.
- `AUTO_COMPACT_TOKENS`: Vendor-recommended context auto-compaction window. Injects `CLAUDE_CODE_AUTO_COMPACT_WINDOW`.
  - **Rule**: Never substitute auto-compaction threshold for the maximum context window.

### Gate 4: Financial Safety & Billing Surface Separation
- Subscription plans (Coding Plan, Agent Plan, Token Plan) and pay-as-you-go API keys are separate billing surfaces.
- Plan routes must default to consuming prepaid quota/AFP packages and must not trigger unconfirmed cash charges.
- Use `AUTH_MODE="surfaces"` when a vendor provides both plan and API access under different endpoints or keys.

### Gate 5: Companion Tooling Verification
- Only inject companion MCP servers that are officially published or documented by the vendor.
- Check package distribution: PyPI (`uvx`), npm (`npx`), Streamable HTTP, or SSE.
- Never force MCP injection onto pure model gateways. Vendors without companion tools must use `ASSET_PROFILE="empty"` or omit `ASSET_PROFILE`.

---

## 2. Auditing Checklist (Step-by-Step)

1. **Locate Vendor Documentation**:
   - Anthropic compatibility / Claude Code setup guide
   - API endpoints & base URL specification
   - Authentication scheme (`Bearer <token>` vs `x-api-key: <token>`)
   - Model pricing, token limits, and quota guidelines
2. **Extract Parameters**:
   - Base URL (strip `/v1/messages`)
   - Auth mode: `surfaces`, `env`, `keychain`, `none`, or `native`
   - Key environment variable names (e.g. `PROVIDER_PLAN_KEY`, `PROVIDER_API_KEY`)
   - Context tokens & compaction tokens
   - Reasoning effort capability (`low`, `medium`, `high`, `xhigh`, `max`)
   - Companion MCP package name, transport type, and required environment variables
3. **Record in `docs/provider-audit.md`**:
   - Add entry under `### <Provider Name>`
   - Link all primary sources
   - Record exact model IDs and context parameters
   - Document any architectural decisions (e.g. key fallback, proxy requirement, timeout adjustments)
