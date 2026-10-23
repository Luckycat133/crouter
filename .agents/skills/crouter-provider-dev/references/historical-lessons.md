# Hard-Won Lessons & Historical Pitfalls Reference

This document compiles the real-world engineering lessons, historical bug fixes, and architectural decisions accumulated across `crouter` releases (v0.1 to v0.5.3+).

---

## 1. Gateway & URL Pitfalls

### Pitfall 1: Appending `/v1/messages` to `BASE_URL`
- **History**: Early provider definitions accidentally copied full URLs like `https://api.vendor.com/v1/messages`.
- **Consequence**: `crouter` automatically appends `/v1/messages` at runtime, resulting in double-path requests (`/v1/messages/v1/messages`) and 404 errors.
- **Rule**: `BASE_URL`, `PLAN_URL`, and `API_URL` MUST be the prefix **before** `/v1/messages`. `test/provider-matrix.sh` explicitly fails if `/v1/messages` is present.

### Pitfall 2: Attempting to Add OpenAI-Only Gateways
- **History**: Providers for `openai.sh` and `baichuan.sh` were previously attempted and subsequently deleted with regression guards in `test/provider-matrix.sh`.
- **Reason**: Claude Code requires the native Anthropic Messages schema (streaming events, system prompts, tool schemas, thinking blocks). Plain OpenAI-compatible gateways cannot be used directly without an explicit translation proxy.
- **Rule**: Never create direct provider scripts for vendors without official Anthropic compatibility.

---

## 2. Context Window vs. Auto-Compaction Conflation

### Lesson from DeepSeek & MiniMax Audits
- **History**: In early versions, DeepSeek's 786,432-token automatic compaction recommendation was mistakenly configured as `CONTEXT_TOKENS="786432"`.
- **Consequence**: Claude Code prematurely restricted its maximum conversation horizon, preventing users from utilizing DeepSeek's full 1,000,000-token capacity.
- **Correction**:
  - `CONTEXT_TOKENS="1000000"` (sets `CLAUDE_CODE_MAX_CONTEXT_TOKENS`)
  - `AUTO_COMPACT_TOKENS="786432"` (sets `CLAUDE_CODE_AUTO_COMPACT_WINDOW`)
- **Rule**: Never conflate maximum context capacity with recommended compaction windows.

### Lesson from Ollama Exact-Model Overrides
- **History**: Ollama runs many models locally. Setting a global 373,760 context for Ollama broke smaller models like Llama 3 (8k/128k) or Qwen (32k).
- **Solution**: `MODEL_CONTEXT_OVERRIDES="deepseek-v4-flash:q8=373760 deepseek-v4-flash=373760 qwen3.8-27b=262144"`. The default fallback `CONTEXT_TOKENS="65536"` applies to any unspecified model.

---

## 3. Local Proxy & Port Collision Hardening

### Lesson from Codex Port Collision (8080 -> 19000)
- **History**: The Codex local proxy (`icebear0828/codex-proxy`) initially targeted port 8080.
- **Issue**: Port 8080 is ubiquitously used by local development servers (Java, Spring, Tomcat, Vite, Webpack), causing constant port conflicts and false positive health checks.
- **Solution**: Standardized on port 19000 for Codex proxy (`http://127.0.0.1:19000/health`).
- **Rule**: Local proxy backends must use high, non-standard port numbers (e.g. 19000 for Codex, 11435 for Ollama heartbeat) and always implement a strict `PRE_START` health check.

### Lesson from Ollama Idle Cancellation (SSE Heartbeat Proxy)
- **History**: When running local Ollama models on complex coding tasks, reasoning or tool-call generation frequently experienced 1-3 minute pauses. Claude Code 2.1.237 cancelled these requests as idle timeouts.
- **Solution**: Created a lightweight localhost SSE relay on port 11435 (`lib/ollama-heartbeat-proxy.mjs`). It emits a transport-level SSE comment (`: keepalive`) every 60 seconds during silent generation, keeping the HTTP connection active without polluting Claude's message history.
- **Lifecycle Invariant**: The proxy is started in `PRE_START` and stopped in `POST_STOP` **only if the current session started it**. Never terminate pre-existing user daemons.

---

## 4. MCP Zero-Collision & Clean State Architecture

### Why `~/.claude.json` Must Never Be Modified
- **History**: Early provider tooling registered MCP servers directly in `~/.claude.json`.
- **Catastrophic Failure**:
  - Uninstalling a provider left dangling MCP configurations.
  - Concurrent Claude Code sessions collided and overwrote each other's configuration.
- **Solution**: Completely moved to dynamic session rendering:
  1. `lib/assets.sh` creates a mode-600 temporary file: `mktemp -t crouter-mcp.XXXXXX`.
  2. `lib/provider-assets.js` writes the active provider's MCP JSON into this file.
  3. Passed to Claude Code via `--mcp-config <tmpfile>` and `--strict-mcp-config`.
  4. Cleanup hook (`trap cleanup_provider_assets EXIT INT TERM`) removes the file on exit.
- **Rule**: `~/.claude.json` is sacred. All provider tooling must be session-scoped and self-cleaning.

---

## 5. Security & SSRF Defense in Asset Injection

### Lesson from Tencent & Qiniu Dynamic Endpoints
- **History**: Tencent and Qiniu MCP servers allowed users to provide custom URLs via `TENCENT_MCP_URL` and `QINIU_MCP_URLS`.
- **Vulnerability**: A malicious environment variable could point the MCP client to an internal IP (e.g. `http://169.254.169.254` AWS metadata or local intranet services), leading to SSRF.
- **Hardening**:
  - Implemented strict URL parsing with `new URL()`.
  - Protocol whitelist: `https:` only.
  - Hostname whitelist: `mcp-api.tencent-cloud.com` (Tencent) and `api.qnaigc.com` (Qiniu).
  - Path regex validation: `/^\/v1\/mcp\/http-streamable\/[^/]+\/?$/`.
- **Rule**: Any dynamic endpoint accepted from user environment variables must be strictly validated against vendor-owned hostnames.

---

## 6. Dual-Surface Plan/API Splitting Experience

### Lesson from DashScope and Qianfan
- **History**: Initially, single provider files tried to handle both subscription plans (Coding Plan / Token Plan) and pay-as-you-go API keys.
- **Failure**: Different models and different rate limits exist between personal Coding Plans, enterprise Agent Plans, and direct APIs. For example, a coding-only plan exposes just `/api/coding` with coding models, while a general plan exposes `/api/plan` with multi-vendor models (DeepSeek, GLM, Kimi).
- **Solution**:
  - Dedicated provider files when gateway URLs or model tiers diverge: `dashscope` vs `dashscope-coding`; `qianfan` vs `qianfan-coding` vs `qianfan-team`.
  - Dual-surface declarations (`AUTH_MODE="surfaces"`) when sharing a script: `PLAN_URL` / `API_URL`, `PLAN_KEY_ENV` / `API_KEY_ENV`.
  - Fallback logic: if plan key is unset, fall back to API key to prevent onboarding friction.
