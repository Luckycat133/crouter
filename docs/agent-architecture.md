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

If the final allowed candidate returns HTTP 401/402/403/429, the unified gateway
forwards that response's status, body and headers (including `Retry-After`)
unchanged. Earlier rejected candidates still fail over before any response is
committed to the client. If the final attempt instead fails at the transport
layer without an HTTP response, a local 502 remains appropriate; earlier
discarded errors are not replayed. Existing gateway processes must be recreated
to load updated code.

The unified gateway forwards client cancellation to its upstream HTTP request and response and stops pending retry waits. A normal completed request body is not a cancellation. Once response headers are forwarded, an upstream body error or premature close terminates the client response without changing candidates or replaying the request. Cancellation is scoped to one request and preserves other concurrent requests.

## Model context metadata

`bin/gateway` annotates `GET /v1/models` rows with `context_length` and
`max_input_tokens` (an Anthropic-compatible alias of the same input-side
bound), plus `max_output_tokens`, only when the route's model metadata holds
a known, valid limit for that exact model — e.g. 1,048,576 or 262,144
tokens. Unknown limits are omitted rather than guessed. Metadata is scoped
per provider, endpoint, origin, surface and credential digest: a stale cache
or another account's directory can never leak into this route's models.

`lib/route-build.js` assembles the metadata from directory catalog metadata,
account-live catalog metadata, and declared limits
(`CONTEXT_TOKENS`, `MAX_OUTPUT_TOKENS`, `MODEL_CONTEXT_OVERRIDES`). For each
exact model the effective context/output bound is the smaller of the declared
limit and the catalog value — declaration and directory intersect at the
minimum, and neither side is treated as statically dominant. The primary
model's declared output cap is applied when set.
`lib/unified.sh` forwards those declared limits into unified gateway route
construction but still sets no global 1M window, so `crouter all` exposes
per-model metadata without forcing every model to a 1M context window.

Claude Code 2.1.316 gateway discovery reads only `id`, `display_name` and
`description`; the extra context fields do not change any model's window in
Claude Code. They are intended for HAPI and other integration consumers.
Per-provider `MAX_CONTEXT` environment variables continue to apply as before;
do not claim `crouter all` natively applies per-model windows.

## Ollama transport

Current model defaults, effort and per-model window caps are defined in `providers/ollama.sh`; read that file instead of copying a dated model catalog into instructions. The session-owned relay in `lib/ollama-heartbeat-proxy.mjs` listens on port 11435 and sends transport-only SSE comments every 60 seconds during upstream silence. Preserve upstream response events and session-owned cleanup.

DeepSeek request handling preserves the requested thinking/effort fields and reports effective local behavior without claiming unsupported budget control. Its text-only image fallback is deliberately model-scoped; other models retain their multimodal input. Changes here need focused offline coverage for model selection/caps, thinking pass-through, image scope, heartbeat interval, relay fidelity and cleanup.

The exact Ollama IDs `qwen3.8-abliterated:27b-dflash` (declared 262,144-token client window) and `qwen3.6-hauhau:35b-a3b-q4_k_p` (declared 262,144-token client window) are registered in `providers/ollama.sh` alongside the DFlash and `inkling` profiles; tiers pin to the selected ID through `MODEL_SELF_ROUTE_MODELS`, and native Ollama definitions keep sampler/cache/MTP defaults, so crouter injects no extra inference settings. Declared windows are scoped per exact ID in `MODEL_CONTEXT_OVERRIDES`; selections without a declared override keep the 65,536-token fallback.

Qwen3.8 reference-price naming is opt-in through
`OLLAMA_QWEN38_PRICING_ALIASES=1` in the local `config.sh`; the default keeps
legacy IDs unchanged. With the flag enabled, `MODEL_ID_ALIASES` resolves
`qwen3.8-abliterated:27b-dflash` to `abliterated-dflash/qwen3.8-27b` and
`qwen3.8:27b-dflash` to `dflash/qwen3.8-27b`. The two explicit new
namespace aliases normalize `:latest` to the untagged form even without the
opt-in, so choosing a native catalog entry preserves the same plan. Other
tags remain distinct. These are native Ollama copies
of the respective manifests, retaining their parameters and model identity.
Both aliases declare a 262,144-token window, self-route every tier and use
11435, never the bare `qwen3.8-27b` MLX route. The abliterated copy keeps
medium effort; the standard copy joins the relay's exact DFlash allowlist
and retains xhigh. The DFlash capability marker is
`qwen38-dflash-named-effort-v2`, so a running relay that cannot handle the
new standard alias is rejected for reuse without stopping its current work.
Vibe's current provider-prefix matcher associates the untagged alias names
with the standard `qwen3.8-27b` reference price. No Vibe CLI patch, raw
transcript rewrite or historical upload migration is involved. Native copy
creation and CLI `--plan` / `--apply-only` do not load models.

## Inkling native transport

`providers/mlx-vlm.sh` declares the independent `mlx-vlm` provider, default
`inkling-2-mini:latest`, with `inkling-2-mini` also accepted. It uses static
model discovery and `lib/inkling-runtime.sh`, adapter 11440 and native 8082;
no Ollama discovery, readiness or inference endpoint is involved. The old
Ollama Inkling route and `OLLAMA_INKLING_MLX_VLM` opt-in are removed; an
explicit old command is rejected and directs the caller to `crouter mlx-vlm`.
Other Ollama models retain their current behavior.
`MODEL_BLOCKED_IDS` excludes the old IDs from catalogs and compiled unified
routes. Route `blockedModels` also rejects an explicitly typed
`ollama/inkling-2-mini` or `ollama/inkling-2-mini:latest` request before any
upstream call. Other unlisted model requests keep existing gateway behavior.
`MODEL_BLOCKED_MESSAGE` is reset on provider load; providers without a custom
message retain the existing retired-model error.

The native directory is `INKLING_MLX_RUNTIME_DIR` or
`$HOME/.local/share/local-llm/inkling-mlx-vlm`. crouter invokes its existing
`start-server.sh` without inference arguments. Native sampling/APC/DSpark
settings stay in the backend, and `MLX_INHERIT_DEFAULTS=1` prevents adapter
sampler defaults from masking them while preserving explicit request fields.

Before reuse or adapter startup, native `/health` must be healthy and not
explicitly unready, and both `loaded_model` and a `/v1/models` ID must resolve
to native `model` by realpath. Adapter health must match the exact selected
ID, upstream, native model and inheritance mode. Conflicting or unverifiable
listeners are rejected without replacement. Only PIDs created by this
session are stopped; the native launcher's exec chain preserves that PID.
Planning and save-only use pure model selection and never start a service.
Both IDs keep the 1,048,576 client window and all tiers on the same ID.

The local launcher reuses Bonsai-demo’s existing `.venv-vlm`, upgraded in
place to official mlx-vlm 0.8.1; it has no separate Inkling venv. It uses
original weights and bundled DSpark, and retains BF16 KV because the
Inkling-specific Q8 path is incompatible. Offline fixtures verify transport
and lifecycle, not actual model inference or cache hit performance. This
startup path applies only to direct `crouter mlx-vlm` launches; `crouter all`
does not implement per-model native startup.

## Bonsai transport

`crouter bonsai` exposes local Ternary Bonsai models to Claude Code through the session-owned Anthropic-compatible adapter. The default `ternary-bonsai-2-27b` profile (alias `bonsai`) uses adapter port 11438 → native port 8000 against the legacy PrismML MLX runtime, which crouter keeps but neither starts nor stops; its declared client window is 262,144 tokens. `ternary-bonsai-2.5-27b` uses adapter port 11439 → native port 8081 with the same client window. Tiers pin to the selected model; native output, sampler, cache, KV and MTP settings remain owned by the backend, with `MLX_INHERIT_DEFAULTS=1` and no additional crouter inference defaults.

Only `PRE_START` performs native checks and startup. Under `$BONSAI_DEMO_DIR` (default sibling `Bonsai-demo`), an installed executable `scripts/start_bonsai25_agent_server.sh` is preferred when no compatible service exists. It is started without inference arguments; its no-model-load `--check` JSON declares the expected GGUF `model_path`. A GGUF listener must report `/health.status == "ok"`, `/props.model_path` with the same realpath, and `/v1/models` containing the exact `ternary-bonsai-2.5-27b` alias. The adapter forwards that friendly upstream ID.

The existing MLX identity remains valid even when the preferred wrapper is installed: `/health.status == "healthy"`, `/health.loaded_model` and a `/v1/models` ID must identify `models/Ternary-Bonsai-2.5-27B-mlx-2bit` by realpath. Checking a correct MLX listener does not invoke the new wrapper. Without an executable wrapper, absent-service startup retains `scripts/start_mlx_server.sh` with family `bonsai25`, size `27B` and port `8081`. Compatible listeners are reused without ownership, incompatible occupied ports are rejected, and `bonsai_stop` stops only session-started PIDs. `--plan` and `--apply-only` do not check or start native services. Launch with `crouter bonsai --model ternary-bonsai-2.5-27b`; `crouter all` does not yet perform per-model native startup.
