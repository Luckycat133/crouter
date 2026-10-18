---
name: crouter-runtime-diagnostics
description: Diagnose an existing crouter route, authentication surface, local translation proxy or model-tool response. Use for an apparently configured provider that fails in a real client; use provider-development skills when adding or redesigning a provider.
---

# crouter runtime diagnostics

Read `CLAUDE.md`, `docs/agent-architecture.md` and the affected provider/proxy source. Preserve the selected provider, model and billing surface while finding the failed boundary. A model alias in a file is not proof of remote model access.

## Narrow the boundary

1. Establish the actual launcher and checkout, installed version, provider selection, plan/API surface, upstream URL prefix and model mapping. Use `crouter provider show <provider>` and `crouter config show` for their redacted allowlisted views; do not dump configuration or Keychain secrets.
2. `crouter all --check` prints the configured route/candidate graph without network requests or a Claude launch. It proves configuration only. `crouter doctor <provider>` checks dependencies/credentials and may probe the health URL; it does not run startup hooks or prove account/model access for native cloud credential chains.
3. For a local proxy, establish the owning process, listen address, configured upstream and lifecycle owner. Fixing a stale local endpoint is different from invalid upstream credentials. Stop only a process owned by the selected session; do not kill unrelated model servers to clear a port.
4. If the task authorizes a real request, use the intended client/protocol and model. Record redacted request identity, HTTP/stream terminal status, returned model, text/tool result and usage. A model list or healthy local port does not prove a successful Anthropic Messages request.

## Match the symptom to existing tests

| Symptom | Focused evidence |
|---|---|
| Wrong plan/API credential or candidate | `test/surface-auth.sh`, `test/surface-candidates.sh`, `test/key-surfaces.sh` |
| Unified route graph or cleanup | `test/unified-routes.sh`, `test/unified-cleanup.sh` |
| Model/context state leaks between sessions | `test/model-state-isolation.sh`, `test/model-context-overrides.sh` |
| MLX upstream routing | `test/mlx-upstream-config.sh`, `test/mlx-anthropic-proxy.sh` |
| Qwen multimodal/native video path | `test/qwen-native-video.sh` |
| Redacted diagnostics and health checks | `test/diagnostics.sh` |

Inspect a test before running it; use its isolated fixtures and relevant `sh`/`dash` checks. Documentation-only diagnosis does not require reinstalling launchers or the full release suite.

For translation failures, trace request conversion, streamed tool-call fragments, terminal reasons and token accounting in the actual proxy. `lib/anthropic-openai-proxy.mjs` derives cache-read usage from upstream `prompt_tokens_details.cached_tokens`; that field is accounting evidence, not proof that a particular cache strategy or model capability worked. Confirm tools/images/video independently only when they belong to the requested use case.

Do not repair a subscription failure by silently switching to a payable API, replacing the model, rotating unrelated keys or enabling a fallback route. Preserve native Claude login outside provider proxies. Keep endpoint/auth/model facts distinct from billing or actual runtime success.
