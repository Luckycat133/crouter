# Changelog

All notable changes to this local setup are documented in this file.

## [Unreleased]

## [0.5.3] - 2026-08-20

### Added

- Ollama direct sessions now use a dependency-free localhost SSE heartbeat
  relay. It sends one transport-only comment every 60 seconds while a streaming
  upstream response is silent, preventing Claude Code 2.1.237 from cancelling
  healthy multi-minute local tool-call generations. The relay exposes a typed
  health response, forwards request/model events unchanged, survives
  request-local cancellation, and is covered by an offline integration test.

### Changed

- The Ollama provider now defaults to the locally validated
  `deepseek-v4-flash:q8` model with `high` Claude Code effort. Its exact-model
  373,760-token override remains isolated from the 65,536-token fallback used
  by other explicitly selected Ollama models.
- Ollama's heartbeat interval is 60 seconds rather than the initial 15-second
  benchmark workaround, reducing keepalive traffic by 75% while retaining a
  wide margin below Claude Code's observed five-minute idle cancellation.

### Fixed

- The Ollama relay is launched through the repository-relative `ROOT_DIR`
  instead of a machine-specific absolute path. crouter now verifies the relay's
  service identity and stops it only when the current session started it.
- `crouter provider show ollama` now applies the exact-model override for the
  default model, so its displayed 373,760-token context matches real launches.
- README's version badge and `VERSION` metadata now agree on release 0.5.3.
- Provider-matrix and smoke expectations now agree with the already configured
  OpenRouter Nemotron 3 Ultra free default and Antigravity Gemini 3.7 tiered
  catalog; the README and provider audit no longer describe OpenRouter's older
  dynamic free-router contract.

## [0.5.2] - 2026-08-16

### Changed

- `antigravity` provider now defaults to `gemini-3.7-flash-tiered` (the only Gemini 3.7 variant exposed by the account) across all tiers; `gemini-3.7-flash-tiered`, `gemini-3.5-flash-medium`, and `gemini-3.1-pro-low` remain selectable via `--model`.
- README provider catalog updated to reflect the new Antigravity default.

## [0.5.1] - 2026-08-09

### Added

- The repository is now distributed under the MIT License.
- `crouter claude` preserves Claude Code's native `/login`, stored account, and
  OAuth environment resolution; `crouter anthropic` remains the separate
  Anthropic Console API-key route.
- `crouter all --check` prints a redacted, non-networked proof of every configured
  route, candidate surface, auth shape, model-map count, and chosen default.
- User-added Keychain pool entries now live in a mode-600 local registry rather
  than modifying provider source. `crouter add --stdin` supports password
  managers and CI; Keychain input uses Apple's trailing `security -w` prompt
  form so the secret is absent from both crouter and child process arguments.
  Registry metadata changes only after Keychain confirms an add or delete.
- Alibaba Model Studio Token Plan sessions include a namespaced skill for the
  vendor-documented image, video, and speech APIs.

### Changed

- CI now runs on mainline and `codex/**` release branches and checks the
  extensionless shell entry points, all Node entry points, release metadata,
  and every offline test under both `sh` and `dash`.
- The Codex provider documentation now matches its port-19000 health gate and
  current Sol/Terra/Luna tier mapping instead of retaining the obsolete port
  8080 implementation plan.
- Direct and unified proxies cool down candidates after 401/402/403/429 or
  connection failure, honor longer `Retry-After` values, and share one auth,
  header-sanitization, retry, and health implementation.
- Unified default selection prefers an explicit Anthropic API route, then a
  credentialed remote route, before unprobed local static/no-auth proxies.
- DeepSeek now follows its current Claude Code guide: V4 Pro 1M for the default,
  Opus, and Sonnet tiers; V4 Flash for Haiku and subagents; and a 786,432-token
  automatic compaction window distinct from the 1M model context.
- Anthropic subscription OAuth is no longer proxied or included in unified
  routing. The API provider uses `x-api-key`, and its mixed-context catalog no
  longer receives an inaccurate global context override.
- Provider-managed MCPs/plugins remain session-scoped and strict by default;
  `crouter all` uses a strict empty profile to block stale provider tools, and
  the redundant global MiniMax auto-setup script was removed.

### Fixed

- Direct launches now accept an environment-only credential or either one of
  the Plan/API surfaces without requiring every declared Keychain item to
  exist.
- Provider assets are included in clean checkouts and release archives, and a
  failed asset preparation step tears down any proxy started during prelaunch.
- Unified route construction propagates ambiguous or invalid provider errors
  instead of silently omitting the route.
- Local gateway credentials accept both Claude Code authentication headers but
  strip them before forwarding, and launch signal handoff cleans up the Claude
  child, proxy, hooks, and temporary assets exactly once.

## [0.5.0] - 2026-08-08

### Added

- Explicit Token Plan/API key surfaces with per-credential URL, auth header,
  key pool, and tier-model maps; direct and unified routes fail over on
  401/402/403/429 without cross-combining credentials and endpoints.
- Audited domestic providers for Alibaba Model Studio (including Coding Plan),
  Tencent Cloud (including Coding Plan), Baidu Qianfan (personal/team Token
  Plans plus legacy Coding Plan), Huawei ModelArts MaaS, Xiaomi MiMo,
  SiliconFlow, Qiniu AI (enterprise subscription plus API), 302.AI, AIHubMix,
  InfiniAI GenStudio, and PPIO.
- Session-scoped provider MCP/skill profiles for MiniMax, Z.AI, DashScope,
  StepFun, Volcengine, optional Tencent WebSearch, and console-issued Qiniu
  MCP services, plus the official AIHubMix API and PPIO OAuth MCPs. Managed
  profiles use strict MCP isolation and never mutate global Claude
  configuration.
- Offline provider-matrix, surface routing, model-map, native backend, asset,
  lifecycle, and ownership regression tests plus a dated primary-source audit.

### Changed

- MiniMax, Kimi Code, Z.AI, DashScope, DeepSeek, StepFun, and Volcengine now use
  current vendor endpoints/models and the surface contract. MiniMax defaults to
  M3, Kimi to K3 256K, Z.AI to GLM-5.2 1M, DashScope to stable Qwen 3.8 Max,
  and StepFun to Step 3.7 Flash.
- Qianfan now defaults to the current personal Token Plan, isolates the team
  Token Plan as `qianfan-team`, and retains the retired Coding Plan only as
  `qianfan-coding` for existing subscriptions.
- Bedrock and Vertex use Claude Code's native cloud backends instead of local
  third-party proxies and guessed model IDs.
- Anthropic's default Sonnet context is configured at 1,048,576 tokens.
- Antigravity cleanup stops only a gateway started by the current session.
- Local gateway and keypool requests use random per-session client tokens; retry
  budgets reset per request, while HTTP 402 quota exhaustion and HTTP 403
  entitlement rejection trigger failover.
- `crouter all` consumes explicit surface candidates and skips native backends;
  provider MCPs/skills remain a direct-session feature.

### Removed

- Invalid OpenAI and Baichuan providers and the stale `claude-openai` launcher;
  neither vendor documents a directly usable Anthropic Messages base URL.

## [0.4.17] - 2026-08-08

Antigravity lineup refresh + key-mgmt rework + several smaller cleanups
that were sitting in the working tree.

### Added
- **`MODEL_ALIASES` provider contract.** Providers can declare a
  space-separated list of extra model names that are not tier-mapped (no
  opus/sonnet/haiku/subagent slot), but should still surface in
  `crouter provider show <provider>` under an `extras:` line. Selected
  explicitly via `crouter <provider> --model <name>`. Providers that don't
  set `MODEL_ALIASES` are unaffected. Currently used by:
  - `antigravity`: `gemini-3.5-flash-medium gemini-3.1-pro-low`
  - `antigravity-claude`: `gpt-oss-120b-medium`
- **`bin/antigravity-proxy-patch`.** Idempotent sed-based patcher for the
  local `antigravity-claude-proxy` checkout. Adds the `gpt-oss` family
  branch to `getModelFamily()` and extends `isSupportedModel()` so the
  proxy stops rejecting names like `gpt-oss-120b-medium` with
  `Invalid model`. Without this patch the proxy's request validation
  (`server.js`) refuses any non-Claude/Gemini model name even when the
  upstream Cloud Code API serves it.
  Modes: default = apply (no-op if already applied); `--status` reports;
  `--revert` undoes the patch; `--proxy-dir <path>` overrides the
  auto-detected `$ROOT_DIR/antigravity-claude-proxy`.
- **`install.sh` auto-runs the proxy patcher** when the proxy checkout
  exists next to the install, so a fresh `./install.sh` configures GPT-OSS
  support end-to-end. Safe to re-run.
- **`BYPASS_PERMISSIONS` config flag** (`config.example.sh` + `lib/launch.sh`).
  When set to `1`, every `crouter <provider>` launch injects
  `--dangerously-skip-permissions` unless the caller already passed it.
  Default off; documented with a SECURITY warning in config.example.sh.

### Changed
- **Antigravity provider model lineup updated** to match the upstream UI
  (2026-08-08):
  - `antigravity`: `gemini-2.5-flash-*` → `gemini-3.6-flash-{low,medium,high}`
  - `antigravity-claude`: `claude-sonnet-5` / `claude-opus-5-thinking` →
    `claude-sonnet-4-6` / `claude-opus-4-6-thinking`
- **`openrouter` provider** default updated to
  `nvidia/nemotron-3-ultra-550b-a55b:free` (1M context reasoning model);
  `EFFORT=high` since OpenRouter's `reasoning_effort` shares only
  `low|medium|high` with Claude Code's `--effort`.
- **`cmd_provider_show` (bin/crouter)** now prints an `extras:` line under
  the existing aliases block when the provider declares `MODEL_ALIASES`.
- **`README.md`** documents the `MODEL_ALIASES` opt-in, how to invoke the
  extra models via `--model`, and the new `antigravity-proxy-patch` script.

### Fixed
- **`lib/key-mgmt.sh` rewrite** (`_require_keypool` → `_single_key_service`).
  `crouter add` and `crouter remove` now also work for single-key providers
  (`AUTH_MODE=keychain` / `env` with keychain fallback / dual-source
  `API_KEY_REF`). Keypool-mode behaviour is unchanged. Mode-specific error
  copy replaces the old generic "is not in keypool mode" message.
- **`cmd_list_keys` accepts an optional provider arg.** `crouter list
  <provider>` is now shorthand for `crouter list keys <provider>`; with
  no provider it walks every known provider and prints key status,
  including the new dual-source layout (default account via env + api key
  via env/keychain).
- **`crouter run` no longer honours `ANTHROPIC_MODEL` from the shell.**
  The shell export was misleading — `launch.sh`'s `env -i` keeps it out
  of the Claude child anyway, so honouring it only in `cmd_run` produced
  a model the child couldn't introspect. The provider's `MODEL` field is
  now the authoritative default; `--model` is the documented override.

### Upstream
- **PR submitted to `badrisnarayanan/antigravity-claude-proxy`**:
  [pull/362](https://github.com/badrisnarayanan/antigravity-claude-proxy/pull/362).
  Adds the `gpt-oss` family to `getModelFamily()` and `isSupportedModel()`
  upstream. Until it merges, `bin/antigravity-proxy-patch` is the
  supported local fallback.

## [0.4.16] - 2026-08-06

Housekeeping release: no intended change to how any provider launches. The
routes JSON produced by `crouter all` and the environment injected into Claude
Code were diffed before/after and are byte-identical, except for the two
`openrouter` fixes noted below.

### Fixed
- **`crouter uninstall` left dangling symlinks.** The target list was hardcoded
  and missed `claude-anthropic`, `claude-codex`, `claude-ollama`,
  `claude-openai` and `claude-openrouter`. It is now derived from
  `providers/*.sh` exactly as `install.sh` does, so the two stay in sync as
  providers are added.
- **`crouter provider show <name>` failed** with "unknown provider 'show'" — the
  documented three-word form was never handled by the dispatcher. Both
  `crouter provider <name>` and `crouter provider show <name>` now work.
- **`openrouter` context window** was 200,000; the default model's real
  `context_length` is 1,000,000. `CLAUDE_CODE_MAX_CONTEXT_TOKENS` was cutting
  the usable window to a fifth.
- **`:free` billing claim corrected** in the README and the 0.4.15 entry. A
  `:free` model is free only within OpenRouter's daily allowance; beyond it,
  requests keep the `:free` suffix and bill at the underlying paid rate. The
  only hard zero-spend guarantee is a `$0` credit limit on the key
  (openrouter.ai/settings/keys — account-side, not something crouter can set).

### Changed
- **Route/candidate JSON extracted to `lib/route-build.js`.** Four inline
  `node -e '...'` blobs in `bin/crouter` and `lib/auth.sh` collapsed into one
  readable file with subcommands `candidates`, `dual-candidates`, `combine` and
  `default-model`, driven by a documented `CR_*` env contract. The shell still
  owns credential discovery; the JS only owns the JSON shapes.
- **`kc_get()` added to `lib/auth.sh`.** Every Keychain read now goes through
  one helper instead of six copies of
  `security find-generic-password -a "$USER" -s ... -w`.
- **`providers/lib/antigravity-common.sh` moved to `lib/antigravity-common.sh`.**
  It is a shared library, not a provider; `lib/` is where the other shared
  modules live. Both antigravity providers now source it via `$ROOT_DIR/lib/`.
- **`openrouter` no longer pretends to be dual-source.** It declared
  `API_URL`/`API_AUTH_TYPE`/`API_KEY_ENV`/`API_KEY_REF`, which made
  `is_dual_source()` route it through the two-account failover path only for it
  to degrade back to a direct launch. It is now a single surface —
  `AUTH_MODE="env"` resolving `$OPENROUTER_API_KEY` first and the
  `openrouter-api-key` Keychain item second (same order, same Bearer header,
  both paths verified). `crouter list` shows `env` instead of `apikey`.
- **Redundant tier aliases dropped** from `openrouter.sh` and `ollama.sh`, which
  set all four `MODEL_*` aliases to the same value as `MODEL`. `lib/provider.sh`
  already falls back to `MODEL`; the fallback is now documented there.
- **`_AUTH_SCHEME` is reset in `load_provider()`.** It was the one contract
  variable the reset block missed, so it could leak between providers when
  several are loaded in one shell (`crouter doctor`, `crouter all`).
- **New `AUTH_KEYCHAIN_FALLBACK` field for `AUTH_MODE=env`.** Lets a provider
  accept both "export the key" and "store it in the Keychain" without inventing
  a second AUTH_MODE or embedding shell in the provider file. `openrouter`
  migrated from `AUTH_MODE=command` (eval string) to `AUTH_MODE=env` +
  `AUTH_KEYCHAIN_FALLBACK="openrouter-api-key"`.
- **`CONTEXT_TOKENS` documented** in README and CLAUDE.md: it maps to
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS`; if omitted the variable is not injected
  and Claude Code uses its own default.

### Removed
- **Dead `run_post_stop()`** in `bin/crouter` — never called from anywhere;
  `lib/launch.sh` evaluates `POST_STOP` directly from its exit trap.

## [0.4.15] - 2026-08-05

### Fixed
- **`openrouter` provider double-`/v1` 404 (was causing Claude Code's
  "model may not exist" error).** `BASE_URL`/`API_URL` were
  `https://openrouter.ai/api/v1`; Claude Code appends its own `/v1/messages`,
  producing `.../api/v1/v1/messages` → 404, and model validation against
  `.../api/v1/v1/models` returned an HTML error page → "model may not exist /
  run /model". Now `https://openrouter.ai/api` (no trailing `/v1`), matching
  the README and `anthropic.sh`'s pattern. Verified by a mock-Claude run:
  injected `ANTHROPIC_BASE_URL=https://openrouter.ai/api`,
  `ANTHROPIC_AUTH_TOKEN` (Bearer) set, `ANTHROPIC_API_KEY` empty.

### Changed
- **`openrouter` default model locked to the free tier.** All four tiers
  (`MODEL` + `MODEL_OPUS/SONNET/HAIKU/SUBAGENT`) set to
  `nvidia/nemotron-3-ultra-550b-a55b:free`. ~~Free `:free` models never consume
  account credit; daily free-quota exhaustion returns a 429 rate-limit, not a
  deduction.~~ **Corrected in 0.4.16** — `:free` is only free inside the daily
  allowance; past it, requests bill at the underlying paid rate. Credit-limit =
  0 is an OpenRouter *account* backend setting — set it at
  openrouter.ai/settings, crouter can't toggle it.

## [0.4.14] - 2026-08-04

### Fixed
- **`openai` provider header shape (silent `crouter all` 401 + direct-launch
  both-headers bug).** Added `_AUTH_SCHEME="bearer"` in `providers/openai.sh`
  so `lib/launch.sh:70-78` takes the bearer-only branch (was falling into
  the `*)` both-headers branch and emitting both `Authorization: Bearer` and
  `x-api-key:`). OpenAI's compat Messages API rejects `x-api-key:`. Caught
  by an ultracode audit pass on the 0.4.13 changes.
- **`codex` `CONTEXT_TOKENS` was an order of magnitude low.** Was 272000
  (Codex CLI's per-run cap), should be 1050000 — GPT-5.6 family ships with
  a 1.05M-token context window per icebear's own `src/ollama/bridge.ts`
  context table.
- **`codex` `HEALTH_CHECK_URL`** pointed at `/`; now points at
  `http://localhost:8080/health` (the endpoint icebear actually exposes
  for probes — `src/routes/admin/health.ts`).
- **`test/smoke.sh`** section heading updated — "Dual-source providers"
  no longer lists `openai` (which is single-surface keychain now).

### Added
- **`test/header-shape.sh`** — non-hermetic integration test for providers
  with non-Anthropic auth headers. Captures the headers `crouter openai`
  sends to `api.openai.com` and asserts `Authorization: Bearer` is present
  while `x-api-key:` is absent (OpenAI's compat Messages API rejects
  x-api-key). Skips cleanly when prerequisites are missing (no keychain
  entry, no `nc`, no `python3`). Run locally after editing
  `providers/openai.sh` or `lib/launch.sh`; not part of the default
  `./test/smoke.sh` CI gate.

## [0.4.13] - 2026-08-04

### Added
- **`codex` provider (ChatGPT/Codex 订阅 via icebear0828/codex-proxy).**
  `providers/codex.sh` — backend is `icebear0828/codex-proxy` on
  `http://localhost:8080` (single-process Anthropic↔Codex translation layer,
  OAuth PKCE login). `BASE_URL` per icebear's default port; `AUTH_MODE=none`
  + `EXTRA_ENV` injecting the `pwd` placeholder (Claude Code requires a
  non-empty credential; matches icebear's auto-generated `proxy_api_key` from
  `config-loader.ts`). Models are **not pinned**: only `MODEL="gpt-5.6-terra"`
  as the default, four tier aliases left unset (fallback to `MODEL`, default
  is balanced so no flagship-quota waste), per the 2026-08-04 user
  requirement. The runtime catalog (5.6-sol/terra/luna + 5.5/5.4/5.4-mini +
  5.3-codex-spark + `-high/-low/-fast` suffix variants) is dynamic — verify
  with `GET /v1/models/catalog`. Overrides: `crouter codex <model>`,
  in-session `/model`, or `ANTHROPIC_DEFAULT_*_MODEL` env vars.
  `PRE_START` probes `:8080` and dies with a launch hint when icebear is not
  running (only runs in direct launch; `crouter all` does not execute
  PRE_START — icebear must be kept alive via launchd / `.dmg` for the
  unified gateway).
- **Compatibility launcher `claude-codex`** (installed by `./install.sh`).
- **Planning document `TASKS-chatgpt-provider.md`:** documents the
  evaluation of 8 backend repositories, the rationale for picking icebear
  over the alternatives, the in-flight verification needed to ship
  `codex.sh`, and a 22-entry corrections log from the `/code-review max`
  pass + 8-repository cross-verification.

### Changed
- **`openai` provider reworked to official-API-only.** `providers/openai.sh`
  now targets OpenAI's official Anthropic-compatible Messages API
  (`https://api.openai.com/v1/messages`) as a single credential surface — the
  optional `OPENAI_DEFAULT_URL` org-gateway surface is removed. Models
  updated to the current GPT-5.6 catalog per OpenAI's API docs:
  `gpt-5.6-sol` / `gpt-5.6-terra` (default) / `gpt-5.6-luna` (all 1.05M ctx
  / 128K max out); auth via Keychain service `openai-api-key` (matches the
  `deepseek` house pattern); `EFFORT="high"`.
- **README** documents the new `crouter codex` provider + `claude-codex`
  shortcut, and notes that `openai` is now single-surface keychain-only
  (no longer dual-source).
- **CLAUDE.md** updates the providers list and the dual-source
  enumeration (`anthropic` / `openrouter` only; `openai` is keychain-only).
- **`test/smoke.sh`** asserts `codex` is listed with `none` auth and `openai`
  with `keychain` auth; the dual-source list is narrowed to `anthropic` /
  `openrouter`.

### Fixed
- **`antigravity-claude-proxy` model-cache corruption (local patch, not
  upstream).** `src/cloudcode/model-api.js` had three related bugs that
  caused intermittent `400 Invalid model: claude. Use /v1/models to see
  available models.` errors even when the user's Antigravity account had
  Claude quota fully available (100% unused per the official UI):
  1. `populateModelCache()` would silently overwrite `validModels` with an
     empty Set when `fetchAvailableModels()` returned a partial response
     lacking `claude-*` ids (possible on quota-exhausted endpoints or
     during backend endpoint fallbacks).
  2. On fetch failure, the stale cache was kept intact, so the next request
     would trust a list of ids that the backend may have since disabled.
  3. `isValidModel()` rejected any id absent from cache without fail-open,
     so a single bad fetch poisoned every subsequent Claude request until
     the 24h cache TTL expired.
  Patch (local only — proxy is in `antigravity-claude-proxy/`, which is
  gitignored): keep the existing cache when a fetch returns zero supported
  models; clear the cache on fetch failure so the next call retries; make
  `isValidModel()` fail-open when an id is not in cache (let the upstream
  API validate). Verified end-to-end: `POST /v1/messages` with
  `model: claude-sonnet-4-6` returns a real Claude response (`stop_reason:
  end_turn`, model echoed back as `claude-sonnet-4-6`), and the proxy log
  shows the cache populated with 19 models including `claude-sonnet-4-6`.

## [0.4.12] - 2026-08-04

### Changed
- **`openai` provider reworked to official-API-only.** `providers/openai.sh` now
  targets OpenAI's official Anthropic-compatible Messages API
  (`https://api.openai.com/v1/messages`) as a single credential surface — the
  optional `OPENAI_DEFAULT_URL` org-gateway surface is removed. Models updated to
  the current GPT-5.6 catalog per OpenAI's API docs: `gpt-5.6-sol` /
  `gpt-5.6-terra` (default) / `gpt-5.6-luna` (all 1.05M ctx / 128K max out);
  auth via Keychain
  service `openai-api-key` (matches the `deepseek` house pattern); `EFFORT="high"`.

## [0.4.11] - 2026-08-03

### Added
- **MiniMax auto-MCP wiring.** `crouter minimax` auto-registers the two official MiniMax MCP servers (`minimax-coding` = `web_search` + `understand_image`, `minimax-gen` = `text_to_image` / `generate_video` / `music_generation` / `voice_clone` / `voice_design`) using the official `uvx` method, and installs the `minimax-multimodal-toolkit` skill via the official **Claude Code plugin method** (`claude plugin marketplace add https://github.com/MiniMax-AI/skills` + `claude plugin install minimax-skills`) — but only when a Token Plan key (`codex-minimax-token-plan` in Keychain) is present. All three are registered **globally** (`claude mcp add -s user`, `~/.claude` plugins), never project-scoped. Idempotent; already-registered servers / installed skills are skipped. Gated by `MINIMAX_AUTO_MCP` (default 1) and `MINIMAX_AUTO_SKILL` (default 1) in `config.sh`; set to `0` to disable. Wiring is driven by `providers/minimax.sh`'s `PRE_START` hook → `bin/minimax-mcp-autosetup`. Missing dependencies are auto-installed using the official methods: `uvx` (astral.sh installer) and `mmx-cli` (`npm install -g`), and `mmx auth login` runs automatically with the Token Plan key so the skill is usable immediately. Note: the `mcp==1.9.4` pin on both MCP `uvx` commands is a compatibility workaround (MiniMax's packages import the removed `mcp.server.fastmcp` path under mcp 2.x); it can be dropped once MiniMax pins its SDK dependency.

### Removed
- `bin/minimax-mcp-bridge` (obsoleted by the official-`uvx` auto-wiring above).

## [0.4.10] - 2026-08-03

### Added
- **MiniMax auto-MCP wiring.** `crouter minimax` auto-registers the two official MiniMax MCP servers (`minimax-coding` = `web_search` + `understand_image`, `minimax-gen` = `text_to_image` / `generate_video` / `music_generation` / `voice_clone` / `voice_design`) and installs the `minimax-multimodal-toolkit` skill via the official `uvx` method — but only when a Token Plan key (`codex-minimax-token-plan` in Keychain) is present. Idempotent; already-registered servers / installed skills are skipped. Gated by `MINIMAX_AUTO_MCP` (default 1) and `MINIMAX_AUTO_SKILL` (default 1) in `config.sh`; set to `0` to disable. Wiring is driven by `providers/minimax.sh`'s `PRE_START` hook → `bin/minimax-mcp-autosetup`.

## [0.4.9] - 2026-08-02

### Added
- Three new providers: **`anthropic`** (Anthropic Claude, `https://api.anthropic.com`, default `claude-sonnet-4`), **`openai`** (GPT via OpenAI's Anthropic-compatible `https://api.openai.com/v1/messages`, default `gpt-4o`), and **`openrouter`** (`https://openrouter.ai/api/v1`, default `anthropic/claude-sonnet-4`, with the mandatory empty `ANTHROPIC_API_KEY` in `EXTRA_ENV`).
- **Dual-source auth: default account first, API key as fallback.** `anthropic` and `openai` declare two credential surfaces instead of a single `AUTH_MODE` — `DEFAULT_URL`/`DEFAULT_AUTH_TYPE`/`DEFAULT_TOKEN_ENV`(`_FALLBACK`) for the preferred account and `API_URL`/`API_AUTH_TYPE`/`API_KEY_ENV`/`API_KEY_REF` for the metered key. crouter always spends the default account's included quota first and rotates to the API key on **401/429**. For `anthropic` the default account is the Claude subscription OAuth token (`claude setup-token` → `CLAUDE_CODE_OAUTH_TOKEN`, or `ANTHROPIC_AUTH_TOKEN`); for `openai` it is an optional self-configured gateway (`OPENAI_DEFAULT_URL` / `OPENAI_DEFAULT_TOKEN`).
- Rotation works in **both** launch paths, not just at start-up: `crouter <provider>` fronts the two surfaces with `bin/keypool-proxy` in the new **candidate mode** (`KEYPOOL_CANDIDATES` JSON, per-candidate URL + header shape), and `crouter all` makes each surface a candidate on the provider's route. With only one surface configured, the direct connection is used and no proxy is started.
- `crouter list` reports `dual` / `apikey` for these providers; `crouter doctor` reports which credentials are actually live (`auth:ok(default+api)`); `crouter provider <name>` prints the full surface layout (URLs, header types, env/keychain names) with no secrets.

### Changed
- `bin/gateway` routes now hold an ordered `candidates[]` array (each with its own `url`, `auth{type,token}` and `extra_env`) instead of a single `auth` object. Failing over on 401/429 is now one mechanism shared by keypool key rotation and dual-source fallback; keypool routes simply list every key as its own candidate.
- `install.sh` derives the `claude-<provider>` compatibility shortcuts from the contents of `providers/`, so adding a provider no longer requires editing the install script. Repo-local `bin/claude-*` symlinks added for `ollama`, `anthropic`, `openai`, `openrouter`.
- Shell completions now offer provider names (and `all`) at the first argument position, not only the subcommand verbs.

### Fixed
- **Auth header shape is no longer guessed.** `lib/launch.sh` used to export *both* `ANTHROPIC_API_KEY` and `ANTHROPIC_AUTH_TOKEN` with the same value. An Anthropic subscription OAuth token is only valid as `Authorization: Bearer`, so sending it as `x-api-key` gets it rejected. Dual-source providers now set `_AUTH_SCHEME` during resolution and only the matching env var is injected; legacy providers keep the previous both-headers behavior.
- `load_provider()` did not reset `AUTH_KEYS`, `PLUS_URL`, `PLUS_KEYS`, `EFFORT` or any of the new dual-source variables, so values leaked between providers when several were loaded in one shell (`crouter doctor`, `crouter all`). All optional contract fields are now cleared before sourcing.
- `check_auth()` returned "ok" for dual-source providers with no credentials at all (they default to `AUTH_MODE=none`). It now requires at least one usable surface.
- `bin/keypool-proxy` / `bin/gateway` no longer send an empty credential header when a `none`-auth route has no dummy token.

### Verified
- `test/smoke.sh` extended to 29 checks, including a real end-to-end failover run against a mock upstream: the proxy sends `Authorization: Bearer` first, receives 429, then retries with `x-api-key` only and gets HTTP 200 — asserting the exact header sequence `bearer,x-api-key` (never both on one request). The same failover was verified through `bin/gateway`, and all four direct-launch permutations (both surfaces / default only / API key only / none) were checked against a stub `claude` binary.

## [0.4.8] - 2026-08-02

### Fixed
- `crouter all` (unified gateway) was broken for `none`-auth providers (ollama): `build_all_routes` split `EXTRA_ENV` on `;` only, but ollama's `EXTRA_ENV` is newline-separated, so the dummy token came out as `"ollama\nANTHROPIC_API_KEY=ollama"`. The gateway injected that as an invalid multi-line `x-api-key` header and the backend connection returned an empty reply. Now split on both newline and `;`, and forward the full `EXTRA_ENV` set as headers (mirroring `launch.sh`). The ollama catalog is also enriched from `ollama list` so `/model` can list locally-pulled models. Verified end-to-end against real ollama (`qwen3.5:2b`, HTTP 200) and real DeepSeek (`deepseek-v4-flash` via keypool, HTTP 200).

## [0.4.7] - 2026-08-02

### Added
- `crouter all`: a unified gateway that fuses every provider behind one fixed `ANTHROPIC_BASE_URL`. It starts a local Anthropic-protocol router (`bin/gateway`, dependency-free Node) and launches Claude Code against it, so providers can be switched live from inside Claude Code via `/model <provider>/<model>` (e.g. `/model ollama/qwen3.5:2b`). The router serves `GET /v1/models` (combined, namespaced catalog) and `POST /v1/messages` (route by model prefix to the right backend with that backend's own auth; keypool providers still rotate keys on 429). The gateway listens on `127.0.0.1:${CROUTER_GATEWAY_PORT:-18799}` and is reaped when Claude Code exits. The individual per-provider commands remain untouched.

## [0.4.6] - 2026-08-02

### Added
- Added an `ollama` provider (`providers/ollama.sh`) that runs Claude Code against local or cloud open-weight models through Ollama's native Anthropic-compatible Messages API (Ollama v0.14.0+). No translation proxy and no API key are needed — `BASE_URL` points at `http://localhost:11434` and `AUTH_MODE="none"` injects the dummy `ANTHROPIC_AUTH_TOKEN=ollama` (Ollama ignores it) via `EXTRA_ENV`. `PRE_START` verifies the Ollama service is up; `HEALTH_CHECK_URL` enables `doctor` checks. `install.sh` now also links `claude-ollama`. Verified end-to-end with `qwen3.5:2b` on 2026-08-02 (no proxy, no key).

### Changed
- `crouter <provider> <model>` is now shorthand for `--model <model>`: the first bare positional argument before any flag is treated as the model and is stripped from the args forwarded to Claude Code (so `crouter ollama qwen3.5:2b -p "hi"` works, and a flag's value such as `-p "x"` is never misread as the model). Explicit `--model` still wins. Applies to every provider through the shared `cmd_run` dispatch.

## [0.4.5] - 2026-08-02

### Changed
- Deduplicated the four compatibility launchers (`bin/claude-minimax`, `claude-antigravity`, `claude-deepseek`, `claude-antigravity-claude`) into a single shared `bin/crouter-compat` that derives the provider from the invoked name (strips the `claude-` prefix). The four launchers are now symlinks to it, eliminating ~45 lines of duplicated symlink-resolution boilerplate. `install.sh` links each shortcut to `crouter-compat`.

### Internal
- Extracted the cross-provider helper logic out of the ~900-line `bin/crouter` into sourced `lib/` modules with no behavior change: `lib/provider.sh` (provider lookup/load with contract reset), `lib/auth.sh` (keychain state, keypool start/check, health), `lib/key-mgmt.sh` (key add/remove/list + keychain I/O), and `lib/launch.sh` (the `env -i` isolated Claude Code launch, incl. keypool vs direct-auth branches, effort injection, and `EXTRA_ENV`). `bin/crouter` now sources these four modules and drops from ~906 to ~405 lines. Verified equivalent via `test/smoke.sh` and a dedicated launch-env harness (alias/model vars, `EXTRA_ENV`, minimal terminal env, and keypool `keypool-local` creds all match the previous inline code).

## [0.4.4] - 2026-08-02

### Changed
- Renamed the second surface (MiniMax Coding Plan) variables `CODING_BASE_URL` / `CODING_KEYS` to `PLUS_URL` / `PLUS_KEYS`, and the `--surface` value `coding` to `plus`, across the launcher, `providers/minimax.sh`, README, and CLAUDE.md.
- The keypool proxy now orders the plus surface **first** (plus keys + plus URL ahead of the main Token Plan), spending the plus plan's quota before falling back.
- Single-key keypool providers (exactly one `AUTH_KEYS` entry and no `PLUS_KEYS`) auto-degrade: the gateway bypasses the Node keypool proxy and uses the single key directly via keychain auth, avoiding an unnecessary proxy process.

## [0.4.3] - 2026-08-02

### Removed
- Dropped the `start` / `stop` / `forget` / `rotate` subcommands and the per-provider "last used model" memory (`.state/last-model/<provider>`). Model selection now resolves purely from `--model` > `ANTHROPIC_MODEL` env > provider `MODEL`.

## [0.4.2] - 2026-08-02

### Added
- Management subcommands: `provider show`, `config show` / `config path`, `logs list` / `logs tail`, and `uninstall`.

## [0.4.1] - 2026-08-02

### Changed
- Renamed the launcher and its messages from `claude-gateway` to `crouter`. The binary file `bin/claude-gateway` was renamed to `bin/crouter` in a follow-up fix commit that completed the rename (the initial 0.4.1 commit only rewrote the string references).

## [0.4.0] - 2026-08-02

### Added
- Key-management subcommands for keypool providers: `add`, `rotate`, `remove`, `list keys` (Keychain-backed, TTY-entered secrets).

### Fixed
- `crouter <provider> --version` (and `--help`) no longer spins up the Node keypool proxy — auth/proxy startup is bypassed for help/version queries and torn down cleanly.

## [0.3.4] - 2026-08-01

### Changed
- Raised `EFFORT` to `max` (highest reasoning strength) for `deepseek` and `minimax`, matching what each API's `/anthropic` endpoint supports. DeepSeek thinking is ON by default at effort `high` and `max` is its ceiling; MiniMax-M3 supports the `thinking` block (`adaptive`) and `max` drives the deepest budget. Override per session with `claude-<provider> --effort <level>`. Verified `--effort max` injection for both with a mock Claude binary.

## [0.3.3] - 2026-08-01

### Added
- Reasoning effort control: a provider can set `EFFORT` (`low`|`medium`|`high`|`xhigh`|`max`), which the gateway passes to Claude Code as `--effort`. Override per session with `claude-<provider> --effort <level>`; invalid values are ignored with a warning. Defaults: `medium` for `antigravity-claude`/`deepseek`/`minimax`; unset for `antigravity` (Gemini effort is encoded in the model name, e.g. `gemini-3.6-flash-high`).

## [0.3.2] - 2026-08-01

### Added
- Remember last-used model per provider: the gateway stores the primary model chosen via `--model` or `ANTHROPIC_MODEL` in `.state/last-model/<provider>` and replays it on the next launch (precedence: `--model` > `ANTHROPIC_MODEL` env > remembered > provider `MODEL`). Reset with `claude-gateway forget <provider>`. Only the primary model is tracked; in-session `/model` switches inside Claude Code are not persisted.

## [0.3.1] - 2026-07-31

### Added
- Key pool & automatic failover: `AUTH_MODE="keypool"` + `AUTH_KEYS` starts a tiny dependency-free local proxy (`bin/keypool-proxy`) that rotates across multiple API keys on HTTP 429 (quota/rate-limit) or 401 (auth). Switching is transparent mid-session — no Claude Code restart required.
- `providers/minimax.sh` now ships in keypool mode: the Keychain item `codex-minimax-token-plan` is the first pool entry; add more keys via `AUTH_KEYS`, or a separate Coding Plan surface via optional `CODING_BASE_URL`/`CODING_KEYS`.
- Provider-agnostic: any provider can opt into keypool by setting `AUTH_MODE="keypool"` + `AUTH_KEYS`.

### Changed
- In keypool mode, `bin/claude-gateway` launches Claude Code as a child process (instead of `exec`) so the local proxy is torn down cleanly on session exit.

## [0.3.0] - 2026-07-31

### Added
- `deepseek` provider: DeepSeek V4 (Flash/Pro) via the official Anthropic-compatible endpoint `https://api.deepseek.com/anthropic`. No translation proxy required.
- `claude-deepseek` compatibility launcher (joins `claude-minimax`, `claude-antigravity`, `claude-antigravity-claude`).

### Changed
- Renamed the Gemini provider `antigravity-gemini` → `antigravity` so `claude-antigravity` maps 1:1 to the provider (antigravity = Gemini, `antigravity-claude` = Claude).
- Gemini model mapping now uses only `gemini-3.6-flash` with low/medium/high tiers: opus→high, sonnet→medium, haiku→low, subagents→medium.

## [0.2.0] - 2026-07-30

### Added
- bash/zsh shell autocompletion (`completions/crouter.bash` and `.zsh`).
- Offline smoke test (`test/smoke.sh`).
- GitHub Actions CI running `shellcheck` + smoke test on push/PR.

### Changed
- `auth` env mode now reads the token via `printenv` instead of `eval` (no code-injection surface).
- Gateway `stop` uses `SIGTERM` → wait → `SIGKILL` fallback, with an `lsof` availability guard.
- Keychain lookups are cached to avoid repeated `security` calls.
- `cmd_doctor` uses explicit `if/else`; all sourced scripts gained `#!/bin/sh` shebangs.

## [0.1.0] - 2026-07-30

Initial release of the claude-gateway adapter framework.

### Changed

- Replaced the per-provider launcher scripts (`claude-minimax`, `claude-antigravity`, `claude-antigravity-claude`, `start/stop/status-antigravity`) with a single adapter framework: `bin/claude-gateway` + declarative `providers/*.sh`.
- Providers now declare only connection facts (endpoint, models, context, auth mode, hooks); the entry point owns secure key resolution, clean `env -i` launch, and lifecycle subcommands (`list`, `status`, `doctor`, `start`, `stop`).
- All absolute paths removed; the entry point locates the repository through symlink-safe self-resolution. Local overrides live in gitignored `config.sh` (see `config.example.sh`).
- Antigravity providers auto-start the local gateway via a `PRE_START` hook and wait for `/health`.

### Added

- A single directory for the Antigravity proxy, MiniMax launcher, gateway-control scripts, and usage documentation.
- Background start, stop, and health-check commands for the Antigravity gateway.
- A dedicated Antigravity Claude launcher with Claude-specific model aliases and a 200K context window.

### Fixed

- Antigravity start command now runs `npm start` from the proxy source directory.
- Antigravity stop command now targets only the Node process listening on port 18080.
- Antigravity Claude Code sessions now use Gemini's 1,048,576-token context window instead of the gateway fallback of 200,000 tokens.
- MiniMax Claude Code sessions now use MiniMax M3's 1,048,576-token context window instead of the gateway fallback of 200,000 tokens.
- Gemini launcher no longer exposes raw gateway model discovery, preventing Claude models from inheriting Gemini's 1M context configuration.
