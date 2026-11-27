# Provider and proxy contracts

Read when changing provider declarations, credential resolution, launch isolation or proxy behavior. User-facing commands and provider catalogs live in [README.md](../README.md); audited vendor claims live in [provider-audit.md](provider-audit.md).

## Provider declarations

`bin/crouter` locates the repository through symlinks with `CDPATH=` cleared, then loads local `config.sh` and `providers/<name>.sh`. Preserve declarative provider configuration:

- `BASE_URL`, `MODEL`, `MODEL_OPUS`, `MODEL_SONNET`, `MODEL_HAIKU`, `MODEL_SUBAGENT` define endpoints and model aliases. `EFFORT` passes through as Claude Code `--effort`.
- `MODEL_ID_ALIASES` accepts space-separated `alias=id` entries. Put aliases containing spaces in `MODEL_LABEL_ALIASES`, one exact `label=id` entry per line. The launcher validates the resolved ID and rejects `MODEL_BLOCKED_IDS` before writing state or running startup hooks.
- `MODEL_EFFORT_OVERRIDES` lists exact `id=effort` entries that apply when saving or launching a model. `MODEL_SELF_ROUTE_MODELS` maps every tier to the selected ID for the listed models, or for every model when the field is exactly `*`.
- `CONTEXT_TOKENS`, `MAX_OUTPUT_TOKENS` and `AUTO_COMPACT_TOKENS` separately set the Claude Code context, output and compaction limits. Omit unknown limits. Keep declared limits scoped to their model.
- `AUTH_MODE` supports `keychain`, `env`, `command`, `static`, `none`, `keypool`, `surfaces`, and `native`. `AUTH_REFERENCE` identifies a Keychain service, environment variable or command. `AUTH_KEYCHAIN_FALLBACK` is used only if an `env` credential is unset.
- Explicit `surfaces` bind `PLAN_URL`, `PLAN_AUTH_TYPE`, `PLAN_KEY_ENV`, `PLAN_KEYS`, `PLAN_MODEL*` and their `API_*` counterparts. Prefer plan candidates before API candidates; never cross-multiply keys and URLs.
- Legacy/custom dual-source fields remain compatible: `DEFAULT_URL`, `DEFAULT_AUTH_TYPE`, `DEFAULT_TOKEN_ENV`, `DEFAULT_TOKEN_ENV_FALLBACK`, plus `API_URL`, `API_AUTH_TYPE`, `API_KEY_ENV`, `API_KEY_REF`. Legacy key management also retains `AUTH_KEYS` / `PLUS_KEYS`.
- Native backends use `NATIVE_BACKEND`, `EXTRA_ENV` and an explicit `PASSTHROUGH_ENV` allowlist. Session assets use `ASSET_PROFILE` and plan/API-specific plugin directories. Lifecycle fields are `PRE_START`, `POST_STOP` and `HEALTH_CHECK_URL`.

## Credential and session ownership

`lib/auth.sh` and `lib/key-mgmt.sh` resolve credentials without printing secrets. User-added Keychain service references belong in mode-600 `.state/keypools/<provider>.tsv`, not provider source. `lib/launch.sh` injects only the matching auth shape into the isolated environment. Any nonempty `KEYPOOL_URL` means the local proxy owns upstream auth.

`lib/assets.sh` renders a mode-600 temporary MCP config and activates only the matching namespaced session assets. Cleanup removes the temporary file. Preserve the strict-profile default and existing explicit user overrides; do not install these assets globally.

`MODEL_SETUP` resolves model-specific service, endpoint, effort, and asset choices without I/O. `bin/crouter` seals model identity, tiers, limits and asset requirements before obtaining credentials. `--plan` prints a redacted view of the same launch configuration.

`PRE_START` may start and health-check the planned service. A compatible relay can be reused. An incompatible Ollama relay produces a diagnostic and stays running. `POST_STOP` stops only resources owned by the session.

## Directory scope

Directory snapshots bind a provider, canonical directory URLs, the inference endpoint and the billing surface to the credential digest for account-only catalogs. Model picking, launch limits, home inventory and unified model listings use the shared validator in `lib/catalog.js`. The home and plan can verify public or environment-bound snapshots without decrypting Keychain. The gateway compares authenticated directory scopes to its resolved candidates and advertises entries only when all candidates match. A stale same-scope snapshot remains available for offline browsing with a stale label. Declared model limits and the selected model are saved independently of catalog freshness.

## Proxies and routing

`bin/keypool-proxy` accepts candidate records `{url,type,token,model_map,label}`. Managed instances require a random session token. Candidates rotate on 401/402/403/429 or connection failure, with cross-request cooldown honoring longer `Retry-After` values. Preserve endpoint/header/model ownership through failover.

`bin/gateway` serves `/v1/models` and routes authenticated `/v1/messages` by the first `<provider>/` model segment. Routes contain `prefix`, `auth_mode`, `candidates[]` and `models`. Default selection prefers configured Anthropic API, then credentialed remote routes, then unprobed local routes. `lib/proxy-common.js`, `route-build.js` and `provider-assets.js` hold shared primitives and JSON construction.

`crouter all` switches model traffic only and defaults to a strict empty MCP profile. Native Claude login, Bedrock/Vertex/Foundry and provider session assets require direct launches. `all --check` checks configured structure and credential discovery; it neither proves live entitlement nor starts local providers.

The unified gateway forwards client cancellation to its upstream HTTP request and response and stops pending retry waits. A normal completed request body is not a cancellation. Once response headers are forwarded, an upstream body error or premature close terminates the client response without changing candidates or replaying the request. Cancellation is scoped to one request and preserves other concurrent requests.

## Ollama transport

Current model defaults, effort and per-model window caps are defined in `providers/ollama.sh`; read that file instead of copying a dated model catalog into instructions. The session-owned relay in `lib/ollama-heartbeat-proxy.mjs` listens on port 11435 and sends transport-only SSE comments every 60 seconds during upstream silence. Preserve upstream response events and session-owned cleanup.

DeepSeek request handling preserves the requested thinking/effort fields and reports effective local behavior without claiming unsupported budget control. Its text-only image fallback is deliberately model-scoped; other models retain their multimodal input. Changes here need focused offline coverage for model selection/caps, thinking pass-through, image scope, heartbeat interval, relay fidelity and cleanup.
