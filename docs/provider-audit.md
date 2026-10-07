# Provider audit

Primary-source audit date: 2026-08-08. Release documentation checked:
2026-08-09 for crouter 0.5.1.

This document records the primary sources used for crouter's provider
contracts. It is a configuration audit, not a promise that an account owns a
particular plan or model. Vendor catalogs can vary by region, plan tier, and
account entitlements.

The catalog contains 38 provider contracts, including 22 mainland-China
provider entries. Counts include separate products when their credentials or
endpoints cannot safely share a route, such as DashScope/Coding Plan,
Qianfan personal/team/legacy Coding Plan, and Tencent personal/Coding Plan.
The published README catalog table documents 37 of them; the local experimental
`bonsai` route is intentionally excluded from that table.

## Local Ollama reasoning-effort contract — 2026-10-06

Primary sources: the `qwen3.8-27b-heretic:q4` GGUF chat template as rendered by
Ollama 0.12.x, a live effort sweep against `http://127.0.0.1:11434/v1/messages`,
and the recorded Claude Code sessions under `~/.claude/projects/`.

- Ollama copies Anthropic `output_config.effort` into the model chat template
  almost verbatim, collapsing `xhigh` to `high`. The Qwen3.8 template raises
  `Unexpected reasoning effort <level>` for `high` and `max`; only `low`,
  `medium`, or an omitted field render. Measured mapping (live probe):
  `low`→low ok, `medium`→medium ok, `high`→high rejected, `xhigh`→high rejected,
  `max`→max rejected. Because the template default is `xhigh`, the effective
  level set for this model is `{low, medium, default}`.
- Ollama reports that rejection as HTTP 500 `chat template prompt error`. The
  body never contains the string `output_config`, which is the only signal
  Claude Code uses to auto-downgrade a rejected effort, so the client keeps
  resending the same rejected request with exponential backoff. Observed on
  2026-10-06 15:04:59–15:07:24 (+08:00): eight retries of a `qwen3.8-27b-heretic:q4`
  turn, ending in the "Waiting for API response · will retry in 29m" state.
- Fix: `providers/ollama.sh` declares `OLLAMA_EFFORT_MAX=medium` for the
  `qwen3.8*` selections (the highest level the template accepts, since an
  inbound `xhigh` would be collapsed and rejected). The heartbeat relay clamps
  every matching request down to that cap, records
  `{"type":"effort_clamp",...,"cap":"medium"}`, and reports the cap in `/health`
  so a session reuses a relay only when it clamps to the level the selected
  model needs. Levels at or below the cap, an omitted field, the DeepSeek V4
  pass-through contract, and relays started without a declared cap are all
  unchanged.
- Verified 2026-10-06: `crouter ollama qwen3.8-27b-heretic:q4 --effort {xhigh,max,high} -p ...`
  each returns `PONG` where the same three levels previously returned 500; the
  last template rejection in `~/.ollama/logs/server.log` predates the fix.

## OpenRouter free default recheck — 2026-10-06

Primary sources: `GET https://openrouter.ai/api/v1/models` and
`GET /api/v1/models/nvidia/nemotron-3-ultra-550b-a55b:free/endpoints`
(retrieved 2026-10-06), plus a live Anthropic Messages probe.

- The declared default `qwen/qwen3.8-27b:free` is **no longer served**.
  `/api/v1/messages` returns `404 not_found_error`: "This model is unavailable
  for free. The paid version is available now - use this slug instead:
  qwen/qwen3.8-27b". The default and the main tiers no longer depend on it; the
  remaining `qwen` shorthand and alias entries keep their previous values, so
  they still fail against the retired free slug until that surface is
  repointed by the owner.
- Default is pinned to `nvidia/nemotron-3-ultra-550b-a55b:free` (550B MoE /
  55B active, 1,000,000 context, 65,536 max output, tool calling). Every Claude
  Code tier keeps that model, and the session compacts at 786,432 so the
  summary and the next turn still fit inside the 1M window.
- Unrelated declarations are unchanged, with one cleanup on 2026-10-06: the
  unreferenced `google/gemma-4-26b-a4b-it:free=131072` context override was
  removed because no tier, alias, or self-route entry named that model, so it
  could never match. The surviving `google/gemma-4-31b-it:free` entry still
  declares 131,072 while the live catalog reports 262,144; that value is left
  for its owner to repoint.
- Anthropic `thinking: {"type":"enabled"}` is rejected by the Ultra upstream
  ("Upstream error from Nvidia: Internal server error"), while
  `{"type":"disabled"}` and an omitted field both succeed. Reasoning output is
  produced regardless. Claude Code does not negotiate a thinking budget for
  this unrecognized model ID, so `EFFORT=xhigh` remains usable.

## Comprehensive model generation upgrade — 2026-10-05

This upgrade synchronizes provider default models and aliases with the latest
vendor releases across the catalog:

- **DeepSeek:** Upgraded to `deepseek-flash[1m]` serving DeepSeek-V4.1-Flash (CED
  architecture, 1M context, native vision, and 786,432 auto-compaction).
- **Z.AI:** Adopted official Claude Code recommendations mapping default/Opus/Sonnet
  to `glm-5.3[1m]` and Haiku/Subagents to `glm-5.3-flash[1m]`.
- **DashScope Coding Plan:** Upgraded default to `qwen3.8-plus`, matching Alibaba's
  Qwen 3.8 series generation on the Coding Plan endpoint.
- **StepFun:** Upgraded flagship default to `step-5-preview` with 1,000,000 context
  and auto-compaction window, keeping `step-3.7-flash` as fast Haiku fallback.
- **SiliconFlow:** Replaced deprecated Kimi-K2.6 default with `Pro/moonshotai/Kimi-K2.7-Code`,
  Haiku with `deepseek-ai/DeepSeek-V4-Flash`, and updated aliases to include GLM-5.3.
- **Huawei Cloud MaaS:** Upgraded default to `glm-5.3` and Haiku to `deepseek-v4.1-flash`.
- **Qianfan Team Plan:** Upgraded default from legacy V3.2 to `deepseek-v4-flash`.
- **Antigravity:** Upgraded default Gemini model to `gemini-3.8-flash` (Google
  DeepMind September 2026 release) across default, Opus, Sonnet, Haiku, and subagent
  mappings, with `gemini-3.7-flash` retained in aliases.
- **Gateway Aliases:** Added `deepseek-v4.1-flash` and `glm-5.3` across Volcengine,
  Tencent, DashScope, and OpenRouter alias pools.

## Targeted documentation recheck — 2026-09-26

This recheck covers Kimi Code and Z.AI only; the full audit date above remains
unchanged. It verifies published contracts, not live account entitlements.

- Kimi's [model configuration](https://www.kimi.com/code/docs/en/kimi-code/models.html)
  and [overview](https://www.kimi.com/code/docs/en/) distinguish the China
  endpoint `https://api.kimi.com/coding/` from the overseas endpoint
  `https://api.kimi.ai/coding/`. The English Claude Code guide uses the overseas
  endpoint. Keep the current China endpoint; this is not evidence of retirement.
- Z.AI's [current Claude Code example](https://docs.z.ai/devpack/tool/claude)
  maps Opus/Sonnet to `glm-5.3[1m]` and Haiku to `glm-5.3-flash[1m]`, with the
  same endpoint, bearer authentication and 1,000,000 compact window. Its
  [model overview](https://docs.z.ai/guides/overview/overview) still lists GLM-5.2
  with 1M context and GLM-4.7. Existing model defaults are retained; adopting
  the newer recommendation is a separate model upgrade, not a confirmed fix.

## Provider defaults and credential isolation recheck — 2026-09-26

These changes use current vendor documentation and catalog entries. They do
not establish that a particular account owns the updated models or plans.

- [MiniMax's China Claude Code guide](https://platform.minimax.cn/docs/token-plan/claude-code)
  now uses `https://api.minimax.cn/anthropic`, `MiniMax-M3`, and a 1,000,000
  auto-compaction window. Its [text generation guide](https://platform.minimax.cn/docs/guides/text-generation)
  recommends the same Anthropic-compatible host for general API use. The
  [Token Plan MCP guide](https://platform.minimax.cn/docs/token-plan/mcp-guide)
  separately sets `MINIMAX_API_HOST=https://api.minimax.cn` for the session
  MCP. Keep plan and API credentials in separate pools.
- [Anthropic's current model overview](https://platform.claude.com/docs/en/models/overview)
  lists `claude-opus-5-5` and `claude-fable-5-1`; the direct API route now
  advertises these exact IDs. [Vercel's Opus 5.5 announcement](https://vercel.com/changelog/claude-opus-5-5-now-available-on-ai-gateway)
  gives `anthropic/claude-opus-5.5` for its Messages gateway. The
  [302.AI catalog](https://302.ai/search) lists `claude-opus-5-5` for its
  original-format API; its prior Fable 5 alias remains explicit.
- [Xiaomi's current Claude Code guide](https://mimo.mi.com/docs/zh-CN/tokenplan/integration/claudecode)
  now recommends `mimo-v2.6-pro` and documents `[1m]` on 1M-capable logical
  IDs. The logical default is `mimo-v2.6-pro[1m]` and each surface maps it to
  raw `mimo-v2.6-pro`; old raw V2.5 IDs remain available as migration aliases.
- [DeepSeek's Claude Code integration](https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code/)
  maps Haiku and subagents to `deepseek-flash`. The previous
  `deepseek-v4-flash` stays an explicit alias. The [Anthropic API guide](https://api-docs.deepseek.com/guides/anthropic_api/)
  still supports `x-api-key`, so the existing header remains valid.
- [Huawei's current Token Plan overview](https://support.huaweicloud.com/Token-Plan-maas/tokenplan-maas-0001.html)
  says `GLM-5` and `DeepSeek-V3.2` have been removed from the subscription.
  Those IDs no longer appear in the shared alias list; an API customer may
  still specify an account-specific model explicitly.
- [Volcengine Agent Plan](https://docs.volcengine.com/docs/ark/agent-plan-enterprise-other-tools?lang=zh)
  uses a dedicated `/api/plan` endpoint and plan-only API key, distinct from
  regular Ark API keys. Its [Coding Plan guide](https://docs.volcengine.com/docs/ark/coding-plan-enterprise-ai-opencode?lang=zh)
  uses `/api/coding` and a separate Coding Plan key. The Agent Plan reads only
  `VOLCENGINE_PLAN_KEY` or its `VOLCENGINE_AGENT_PLAN_KEY` alias and only its
  own Keychain services; Coding Plan reads only
  `VOLCENGINE_CODING_PLAN_KEY` and `volcengine-coding-plan`. The two plans do
  not borrow each other's keys or generic Ark API keys.

## Additional direct routes and native backend — 2026-09-26

This focused addition checks published endpoints, header shapes and model IDs.
It does not check account entitlements or make credentialed API calls.

- **Fireworks AI:** [Anthropic compatibility](https://docs.fireworks.ai/tools-sdks/anthropic-compatibility)
  gives `POST https://api.fireworks.ai/inference/v1/messages`, the base prefix
  `https://api.fireworks.ai/inference`, and `Authorization: Bearer` with
  `FIREWORKS_API_KEY`. Its [serverless quickstart](https://docs.fireworks.ai/getting-started/quickstart)
  uses `accounts/fireworks/models/glm-5p3-flash` with the Anthropic SDK and
  also demonstrates `accounts/fireworks/models/kimi-k3`. The [GLM model page](https://fireworks.ai/models/fireworks/glm-5p3-flash)
  lists serverless pay-per-token billing and a 1040k-token context. The
  provider leaves the global context unset because the selectable catalog is
  broader than that model. Fireworks [Nexus/FireConnect](https://docs.fireworks.ai/nexus/harnesses)
  is a distinct product with a custom-header route and is not part of this
  API-key preset.
- **Vercel AI Gateway:** Its [Messages API guide](https://vercel.com/docs/ai-gateway/sdks-and-apis/anthropic-messages-api)
  specifies `https://ai-gateway.vercel.sh` before `/v1/messages`, accepts the
  `AI_GATEWAY_API_KEY` as `Authorization: Bearer`, and shows Claude Code's
  `ANTHROPIC_AUTH_TOKEN` configuration. Vercel's published catalog and
  Opus 5.5 announcement verify
  `anthropic/claude-opus-5.5`, `anthropic/claude-sonnet-5`, and
  `anthropic/claude-haiku-4.5` on the Messages API: [Opus](https://vercel.com/changelog/claude-opus-5-5-now-available-on-ai-gateway),
  [Sonnet](https://vercel.com/ai-gateway/models/claude-sonnet-5), and
  [Haiku](https://vercel.com/ai-gateway/models/claude-haiku-4.5). The model
  tiers have different context limits, so no global limit is injected. Gateway
  API usage is [billed at API rates](https://vercel.com/docs/ai-gateway/pricing).
  Its separate [Claude Max gateway pass-through](https://vercel.com/docs/ai-gateway/coding-agents/claude-code)
  is not treated as a crouter API credential or placed in `crouter all`.
- **LongCat:** The [platform quickstart](https://longcat.chat/platform/docs/)
  gives `POST https://api.longcat.chat/anthropic/v1/messages`, Bearer API-key
  authentication, the exact `LongCat-2.5-Preview` and `LongCat-2.0` IDs, and
  1M context for each. Its [Claude Code guide](https://longcat.chat/platform/docs/ClaudeCode.html)
  maps all tiers to `LongCat-2.5-Preview`. The [FAQ](https://longcat.chat/platform/docs/FAQ.html)
  confirms one platform key works for the Anthropic route. Token Packs and
  pay-as-you-go are billing balances behind this same key and route; no
  second credential surface is invented. An older [Messages reference](https://longcat.ai/platform/docs/api/messages)
  still mentions only `LongCat-2.0`, so the current quickstart and Claude Code
  guide take precedence for the new default.
- **Microsoft Foundry:** [Claude Code's Foundry guide](https://code.claude.com/docs/en/microsoft-foundry)
  specifies `CLAUDE_CODE_USE_FOUNDRY=1`, either
  `ANTHROPIC_FOUNDRY_RESOURCE` or `ANTHROPIC_FOUNDRY_BASE_URL`, and
  `ANTHROPIC_FOUNDRY_AUTH_TOKEN` Bearer, `ANTHROPIC_FOUNDRY_API_KEY`, or the
  Azure SDK default credential chain. Azure CLI is only one chain member.
  Microsoft's [setup example](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/how-to/configure-claude-code?tabs=bash)
  shows explicit base URL without `/anthropic`, while Anthropic's example
  includes that suffix. crouter therefore recommends
  `ANTHROPIC_FOUNDRY_RESOURCE` and passes an explicit base URL unchanged.
  The tier IDs `claude-opus-4-6`, `claude-sonnet-4-6`, and
  `claude-haiku-4-5` are Microsoft example deployments, not portable defaults.
  crouter keeps `MODEL=sonnet` as a logical alias and forwards
  `ANTHROPIC_DEFAULT_*_MODEL` only when the user pins an actual deployment.
  This lets Claude Code use its documented main-model fallback when no Haiku
  deployment exists. The isolated launch passes declared
  [Azure SDK identity variables](https://learn.microsoft.com/en-us/javascript/api/overview/azure/identity-readme?view=azure-node-latest),
  `AZURE_CONFIG_DIR`, `CLAUDE_CONFIG_DIR`, and unexported `config.sh` values.
  `doctor foundry` reports an unobserved SDK chain or endpoint as `UNVERIFIED`:
  Claude settings may provide the endpoint, and offline checks cannot prove
  sign-in, resource access, or model entitlement.

Deferred candidates: [OpenCode Zen](https://opencode.ai/docs/zen) lists
`/zen/v1/messages` for Claude and some Qwen models, but its published Bearer
example is for `/zen/v1/systemone`; the Messages authentication contract is
not established clearly enough for an enabled preset. [Cloudflare Workers AI
REST](https://developers.cloudflare.com/ai-gateway/usage/rest-api/) requires
an account ID inside its URL and a Workers AI-scoped token; the current static
provider contract cannot require and validate that ID safely. Its separate
[AI Gateway Anthropic integration](https://developers.cloudflare.com/ai-gateway/integrations/coding-agents/claude-code/)
uses another path and header. Neither route is configured by guesswork.

## Additional Messages routes and native CLIs — 2026-09-26

These routes use published Claude Code/Messages contracts. The two native CLI
entries execute each client's own login and settings; no subscription token is
reused as a provider API key. A 2026-09-26 invalid-key probe reached each
configured `/v1/messages` endpoint's authentication rejection (Meta and
NagaAI 401, Requesty 403); this did not test model entitlement or inference.

- **Meta Model API:** Its [coding-agent guide](https://dev.meta.ai/docs/coding-agents)
  specifies `https://api.meta.ai` as the Claude Code base before `/v1/messages`,
  Bearer auth via `ANTHROPIC_AUTH_TOKEN` from `MODEL_API_KEY`, the exact
  `muse-spark-1.3` ID for all aliases and subagents, 1,048,576 context, and
  `ENABLE_TOOL_SEARCH=true` to retain Claude Code MCP tool search. This is
  separate from Meta's [Muse Code CLI](https://dev.meta.ai/docs/muse-code),
  which runs as `muse` with its own browser login or `META_API_KEY`.
  [Muse Code subscriptions](https://dev.meta.ai/docs/muse-code/subscriptions)
  apply only within that CLI; additional Model API keys use pay-as-you-go.
- **Requesty:** The [Claude Code integration](https://docs.requesty.ai/integrations/claude-code)
  gives `https://router.requesty.ai` as the Messages base and a Bearer
  Requesty API key. Its current model pages list exact IDs for
  [Sonnet 5](https://www.requesty.ai/models/anthropic/claude-sonnet-5),
  [Opus 5.5](https://www.requesty.ai/models/anthropic/claude-opus-5-5), and
  [Haiku 4.5](https://www.requesty.ai/models/anthropic/claude-haiku-4-5).
  Those model pages show an OpenAI-compatible `/v1` base, which is not used
  for Claude Code's Messages route. Requesty's generic quickstart also gives
  an Anthropic SDK path under `/anthropic/v1/messages`, but the Claude Code
  guide's root base reached Requesty auth at `/v1/messages` in the invalid-key
  probe; the other path returned 404. Their context sizes differ, so the
  provider does not inject one global limit.
- **NagaAI:** Its [Claude Code guide](https://docs.naga.ac/integrations/agents/claude-code)
  specifies `https://api.naga.ac`, Bearer auth and explicit empty
  `ANTHROPIC_API_KEY`, with `claude-opus-4.5`, `claude-sonnet-4.5` and
  `claude-haiku-4.5` tier IDs. The crouter-defined `NAGAAI_API_KEY` environment
  name reads a [standard inference key](https://docs.naga.ac/get-started/authentication),
  not an administrative provisioning key. No global context is injected.
- **Kilo Code CLI:** Its [official CLI guide](https://kilo.ai/docs/code-with-ai/platforms/cli)
  documents the `kilo` command and its own `/connect` flow. Its gateway is not
  listed as an Anthropic Messages provider here.

## Client protocol boundary — 2026-09-26

Native CLI selection runs each client with its own authentication. It does not
make an Anthropic Messages provider usable by a different protocol client.
[Codex custom model providers](https://learn.chatgpt.com/docs/config-file/config-reference)
currently support `responses` as their only `wire_api`; its
[ChatGPT login and API-key login](https://learn.chatgpt.com/docs/auth) have
different billing. [Gemini CLI configuration](https://geminicli.com/docs/reference/configuration/)
limits `GOOGLE_GEMINI_BASE_URL` to Gemini API requests with Gemini API-key
authentication. Neither client is assigned one of this catalog's Messages
URLs or another client's subscription credential. [OpenCode V2](https://opencode.ai/v2/docs/providers)
documents an `anthropic-compatible` package, while its [V1 provider format](https://opencode.ai/docs/providers)
differs; no implicit settings edit is safe without version-specific validation.
[Anthropic's gateway guidance](https://code.claude.com/docs/en/llm-gateway)
also states that routing Claude Code to non-Claude models is unsupported by
Anthropic, even when a third-party gateway offers an Anthropic-format API.

## Acceptance rules

A provider is included only when its vendor documents an Anthropic Messages
base URL that Claude Code can use, or Claude Code itself provides a native
backend. The base stored in `providers/*.sh` is the prefix before
`/v1/messages`; full endpoint paths are rejected by the offline matrix test.

The audit also applies these rules:

- Token Plan and pay-as-you-go credentials remain bound to their documented
  URL and auth header.
- Candidate failover treats 401/402/403/429 as authentication, entitlement, or
  quota rejection; Baidu Qianfan explicitly uses 403 for expired plans. A
  failed candidate is cooled down across requests, honoring a longer
  `Retry-After` value, before it is tried again.
- Model IDs preserve vendor case, punctuation, and Claude Code annotations.
- A context limit is configured only when a primary source states it.
- A vendor's recommended automatic compaction threshold is a separate field;
  it is never substituted for the model's maximum context.
- Product-specific MCPs are enabled only from vendor documentation. Packages
  downloaded at session start are pinned to a verified registry version.
- A provider's MCP/skill configuration is temporary and session-scoped; no
  vendor setup script is allowed to rewrite global Claude configuration.

## Audited contracts

### Anthropic and native cloud backends

- [Claude Code authentication](https://code.claude.com/docs/en/authentication)
  documents browser `/login`, stored macOS Keychain credentials, setup tokens,
  and Anthropic API-key authentication.
- [Claude Code environment variables](https://code.claude.com/docs/en/env-vars)
  states that `ANTHROPIC_API_KEY` is sent as `X-Api-Key` and overrides a Claude
  subscription login when present.
- [Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance)
  keeps Claude.ai subscription OAuth within Anthropic's own products and
  distinguishes third-party API integrations.
- [Claude Code model configuration](https://code.claude.com/docs/en/model-config)
  is the basis for the model aliases and context annotation behavior.
- [Claude model overview](https://platform.claude.com/docs/en/models/overview)
  lists the current Opus 5.5, Sonnet 5, Fable 5.1, and Haiku 4.5 model IDs and
  their different context limits.
- [Claude Code on Amazon Bedrock](https://code.claude.com/docs/en/amazon-bedrock)
  documents `CLAUDE_CODE_USE_BEDROCK=1` and the AWS credential chain.
- [Claude Code on Vertex AI](https://code.claude.com/docs/en/google-vertex-ai)
  documents `CLAUDE_CODE_USE_VERTEX=1`, project, region, and ADC variables.
- [Claude Code CLI reference](https://code.claude.com/docs/en/cli-usage) and
  [plugin reference](https://code.claude.com/docs/en/plugins-reference) define
  `--mcp-config`, `--strict-mcp-config`, and session `--plugin-dir` behavior.

Decision: `crouter claude` executes Claude Code without an isolated environment
or injected provider variables, so its stored `/login` session and optional
`CLAUDE_CODE_OAUTH_TOKEN` remain owned by Claude Code. `crouter anthropic` is a
separate Console API-key route using `x-api-key`; neither direct failover nor
`crouter all` proxies a personal subscription credential. The Anthropic route
does not inject one global context value because its configured catalog mixes
1M Opus/Sonnet/Fable with 200K Haiku.

Bedrock, Vertex, and Foundry use Claude Code's native signers. The previous localhost
proxy definitions and guessed future/date-suffixed model IDs were removed.
Native routes are not placed behind `crouter all`.

The [Bedrock guide](https://code.claude.com/docs/en/amazon-bedrock) documents
alternate `AWS_SHARED_CREDENTIALS_FILE` and `AWS_CONFIG_FILE` locations,
`ANTHROPIC_BEDROCK_BASE_URL`, AWS chain controls, explicit model pins, and
`$CLAUDE_CONFIG_DIR/settings.json`. The [Vertex guide](https://code.claude.com/docs/en/google-vertex-ai)
documents `ANTHROPIC_VERTEX_BASE_URL`, model-specific
`VERTEX_REGION_CLAUDE_*` values, explicit pins, and the same optional Claude
settings directory. Native launches allow only provider-declared credentials
and narrowly validated Vertex model-region variable names through `env -i`.
Unexported `config.sh` values are included. `doctor` treats credentials and
settings-held project/endpoint values it cannot inspect as `UNVERIFIED`, and
still fails for definite missing local tools or configured health failures.

### MiniMax

- [MiniMax M3](https://www.minimax.io/models/text/m3) gives the exact
  `MiniMax-M3` ID, the 1M API context, and states that Token Plan users
  automatically receive M3 capabilities.
- [Token Plan overview](https://platform.minimaxi.com/docs/token-plan/intro)
  states that Token Plan keys and pay-as-you-go API keys are not
  interchangeable.
- [MiniMax Token Plan MCP](https://platform.minimax.cn/docs/token-plan/mcp-guide)
  documents `uvx minimax-coding-plan-mcp -y`,
  `MINIMAX_API_HOST=https://api.minimax.cn`, and the
  Token Plan key environment variable.
- [MiniMax CLI](https://platform.minimaxi.com/docs/token-plan/minimax-cli)
  is exposed by the session skill through pinned `mmx-cli@1.0.19`.

Decision: both billing surfaces use the China Anthropic prefix but keep
independent credential pools. The MCP uses pinned PyPI release `0.0.4` and is
activated only when a plan credential is present. The active prefix is
`https://api.minimax.cn/anthropic`, and both maximum context and automatic
compaction are set to 1,000,000 tokens.

### Kimi Code

- [Kimi Code model configuration](https://www.kimi.com/code/docs/en/kimi-code/models.html)
  lists `k3`, `k3-256k`, `kimi-for-coding`, and
  `kimi-for-coding-highspeed`, including their plan restrictions.
- [Claude Code integration](https://www.kimi.com/code/docs/en/third-party-tools/claude-code.html)
  documents the `https://api.kimi.com/coding/` Anthropic prefix,
  `ANTHROPIC_API_KEY`, 262,144 for the recommended `k3-256k`, and the
  Claude-only `k3[1m]` annotation.
- [Kimi CLI MCP](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/mcp.html)
  and [skills](https://www.kimi.com/code/docs/en/kimi-code-cli/customization/skills.html)
  describe generic Kimi CLI extension mechanisms, not a Kimi-hosted MCP or
  plan-specific Claude Code plugin.

Decision: `moonshot` represents the Kimi Code membership surface only. The
Moonshot pay-as-you-go platform is not silently mixed in because its ordinary
API is a different product contract. No vendor asset is installed merely from
generic extension examples.

### Z.AI

- [Z.AI Claude Code integration](https://docs.z.ai/devpack/tool/claude)
  documents `https://api.z.ai/api/anthropic`, bearer auth, Opus/Sonnet
  `glm-5.3[1m]`, Haiku `glm-5.3-flash[1m]`, and the 1,000,000 compact window.
- [Z.AI model overview](https://docs.z.ai/guides/overview/overview) states that
  GLM-5.3 has a stable 1M context.
- Official MCP pages: [vision](https://docs.z.ai/devpack/mcp/vision-mcp-server),
  [search](https://docs.z.ai/devpack/mcp/search-mcp-server),
  [reader](https://docs.z.ai/devpack/mcp/reader-mcp-server), and
  [zread](https://docs.z.ai/devpack/mcp/zread-mcp-server).

Decision: the local vision package is pinned to
`@z_ai/mcp-server@0.1.4`; remote MCP endpoints use the active Z.AI credential.

### Alibaba Cloud Model Studio

- [Claude Code integration](https://help.aliyun.com/en/model-studio/claude-code)
  is the source for all three product contracts:
  - Token Plan: `https://token-plan.cn-beijing.maas.aliyuncs.com/apps/anthropic`,
    `qwen3.8-max`, `qwen3.6-flash`, `qwen3.7-max`, and 983,616. The former
    `qwen3.8-max-preview` ID now redirects to the stable ID and is no longer the
    configured default.
  - Coding Plan: `https://coding.dashscope.aliyuncs.com/apps/anthropic` and
    `qwen3.8-plus`.
  - Pay-as-you-go: `https://dashscope.aliyuncs.com/apps/anthropic`,
    `qwen3.7-max`, and `qwen3.6-flash`.
- [Anthropic-compatible Messages](https://help.aliyun.com/en/model-studio/anthropic-api-messages)
  confirms that the legacy pay-as-you-go domain remains functional and lists
  the recommended workspace-specific domains for each region.
- [Token Plan quick start](https://help.aliyun.com/en/model-studio/token-plan-personal-quick-start)
  documents that `sk-sp-` plan keys and `sk-` API keys are isolated.
- [Token Plan multimodal generation](https://help.aliyun.com/en/model-studio/token-plan-multimodal-gen)
  provides the official image, video, and speech endpoints, auth header, model
  defaults, and asynchronous video polling contract.

Decision: Token Plan and API candidates share `dashscope`; Coding Plan is a
separate `dashscope-coding` provider because it has its own URL and catalog.
The official WebSearch MCP is activated only with the API surface. The Token
Plan media contract is exposed as a session-only, namespaced skill rather than
a global setup script. Set `DASHSCOPE_API_URL` to use the recommended
workspace-specific prefix.

### DeepSeek

- [Models and pricing](https://api-docs.deepseek.com/quick_start/pricing)
  documents `deepseek-flash`, `deepseek-v4-pro`, the
  `https://api.deepseek.com/anthropic` prefix, and 1M context.
- [Anthropic API guide](https://api-docs.deepseek.com/guides/anthropic_api)
  documents `ANTHROPIC_API_KEY` and full `x-api-key` support.
- [Claude Code integration](https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code)
  recommends `deepseek-flash[1m]` for default, Opus, and Sonnet,
  `deepseek-flash` for Haiku and subagents, and maximum effort. It also
  sets the auto-compaction window to 786,432 and documents DeepSeek's
  server-side web-search tool.

Decision: DeepSeek is API-only and uses `x-api-key`, not Bearer. The public
default/Opus/Sonnet mapping carries Claude Code's `[1m]` annotation and is
stripped to raw `deepseek-flash` on the upstream request; Haiku and subagents
map to `deepseek-flash`. `deepseek-v4.1-flash`, `deepseek-v4.1`, `deepseek-v4-pro`,
and `deepseek-v4-flash` remain explicit migration aliases. Maximum context and
automatic compaction remain separate settings. Web search is model-native, not a
downloadable MCP package.

### SiliconFlow

- [Anthropic Messages API](https://docs.siliconflow.cn/cn/api-reference/chat-completions/messages)
  documents `https://api.siliconflow.cn/v1/messages`, Bearer authentication,
  and the dynamically managed model catalog.
- [Claude Code integration](https://docs.siliconflow.cn/cn/usercases/use-siliconcloud-in-ClaudeCode)
  documents the base prefix and ordinary SiliconFlow API key.
- [Current CC Switch preset](https://api-docs.siliconflow.cn/docs/usercases/use-siliconcloud-in-ccswitch)
  maps every Claude tier to `Pro/moonshotai/Kimi-K2.7-Code`.

Decision: SiliconFlow is API-only. The default follows its current Claude Code
preset; the context remains unset because the endpoint is a dynamic multi-model
catalog. Generic MCP presets shown in CC Switch are not SiliconFlow-billed or
provider-owned, so crouter does not install them.

### 302.AI

- [Current original-format Messages API](https://doc.302.ai/221170151e0)
  documents `https://api.302.ai/v1/messages` and `x-api-key`.
- [2026 product updates](https://help.302.ai/docs/geng-xin-ri-zhi-2026) record
  the July launches of `claude-sonnet-5` and `claude-opus-5`; the
  [Sonnet 5 product page](https://302.ai/product/detail/claude-sonnet-5)
  confirms native Messages support and its 1M context. The current
  [model catalog](https://302.ai/search) additionally lists
  `claude-opus-5-5`; the pricing catalog retains
  `claude-haiku-4-5-20251001` for the fast tier.
- [Claude Code dedicated route](https://302.ai/product/detail/anthropic-claude-opus-4-1-20250805-Code)
  documents a separate `/cc` prefix but also warns that it may substitute GLM
  or Kimi during Claude risk-control periods.

Decision: `302ai` uses the original Messages API so an explicitly selected
model remains an exact contract. It is API-only; Sonnet 5 is the balanced 1M
default, Opus 5.5 and Haiku 4.5 own their logical tiers, and Fable 5 remains an
explicit premium alias.

### AIHubMix

- [Native Claude Code gateway](https://docs.aihubmix.com/en/blogs/free-ai-models)
  documents `https://aihubmix.com`, Bearer configuration, and current free
  coding model IDs including `coding-glm-5.1-free`.
- [Official AIHubMix MCP](https://docs.aihubmix.com/en/clients/AHM-mcp)
  documents `https://aihubmix.com/mcp/` and Bearer authentication with the
  AIHubMix API key.

Decision: AIHubMix is an API-only dynamic catalog. crouter keeps context unset,
uses the documented free coding default, and activates its API MCP only inside
the AIHubMix session.

### InfiniAI GenStudio

- [Claude Code integration](https://docs.infini-ai.com/shared/gen-studio/coding-tools/gs-use-claude-code.html)
  documents `https://cloud.infini-ai.com/maas`, Bearer configuration, the
  `glm-5.1` tier example, and an account-dependent `/v1/models` catalog.
- [Coding Plan changelog](https://docs.infini-ai.com/gen-studio-coding-plan/changelog.html)
  states that Infini Coding Plan stopped service on 2026-06-26.

Decision: `infini` exposes only the current pay-as-you-go GenStudio API. The
retired Coding Plan is not accepted as a live surface; context and effort stay
unset because they vary by the selected Claude-compatible model.

### PPIO

- [Claude Code integration](https://ppio.com/docs/third-party/claude-code)
  documents `https://api.ppio.com/anthropic` and Bearer authentication.
- [MiniMax M3 model page](https://ppio.com/model/minimax/minimax-m3) confirms
  Anthropic API support, the exact `minimax/minimax-m3` ID, and a
  1,000,000-token context.
- [GLM-5.2 model page](https://ppio.com/model/zai-org/glm-5.2) confirms the
  optional `zai-org/glm-5.2` catalog ID and Anthropic API support.
- [PPIO MCP](https://ppio.com/docs/ai/mcp-server) documents the hosted
  `https://mcp.ppio.com/mcp` endpoint and its independent OAuth 2.1 flow.

Decision: PPIO is API-only, with current MiniMax M3 as the default and GLM-5.2
as an explicit catalog alias. Its account-management MCP is session-scoped but
does not receive the LLM API key; Claude Code performs the documented OAuth
authorization separately.

### StepFun

- [Claude Code integration](https://platform.stepfun.com/docs/zh/step-plan/integrations/claude-code)
  documents the `https://api.stepfun.com/step_plan` Messages prefix and bearer
  credential.
- [Step 5 Preview](https://platform.stepfun.com/docs/zh/guides/models/step-5-preview)
  documents the exact `step-5-preview` ID, 1M context, Messages support, and
  agentic reasoning. `step-3.7-flash` remains available for fast execution.
- [StepSearch](https://platform.stepfun.com/docs/zh/step-plan/integrations/search-mcp)
  documents its HTTP endpoint, Bearer header, `web_search`, and `web_fetch`.

Decision: Step Plan and the ordinary API are separate candidates. StepSearch
and its matching skill activate only for a plan session.

### Tencent Cloud

- [Personal Token Plan Claude Code integration](https://cloud.tencent.com/document/product/1823/130070)
  documents `https://api.lkeap.cloud.tencent.com/plan/anthropic`, bearer auth,
  `tc-code-latest`, and the current plan catalog.
- [TokenHub pay-as-you-go overview](https://cloud.tencent.com/document/product/1823/130079)
  documents `https://tokenhub.tencentmaas.com` and bearer auth.
- [Coding Plan integration](https://cloud.tencent.com/document/product/1823/130092)
  documents `https://api.lkeap.cloud.tencent.com/coding/anthropic`.
- [TokenHub Claude Code and WebSearch](https://cloud.tencent.com/document/product/1823/131903)
  documents the pay-as-you-go `hy3` example and console-issued WebSearch SSE
  URL.

Decision: personal Token Plan and TokenHub API are candidates under `tencent`;
Coding Plan is `tencent-coding`. WebSearch is optional because its URL includes
an account-specific identifier that crouter cannot infer.

### Baidu Qianfan

- [Personal Token Plan Claude Code](https://cloud.baidu.com/doc/qianfan/s/zmracpp70)
  documents the `https://qianfan.baidubce.com/anthropic/tokenplan/personal`
  prefix, a plan-only key, and `deepseek-v4-pro` for every Claude tier.
- [Team Token Plan Claude Code](https://cloud.baidu.com/doc/qianfan/s/Ymq98210m)
  documents the separate `https://qianfan.baidubce.com/anthropic/tokenplan/team`
  prefix, team key, and `deepseek-v4-flash` for every Claude tier (with `deepseek-v3.2` alias).
- [Anthropic compatibility](https://cloud.baidu.com/doc/qianfan-docs/s/6mh3e6gjp)
  documents the ordinary `https://qianfan.baidubce.com/anthropic` prefix and
  recommends `deepseek-v3.2` for Claude Code.
- [Coding Plan](https://cloud.baidu.com/doc/qianfan/s/imlg0beiu) documents the
  legacy `https://qianfan.baidubce.com/anthropic/coding` prefix,
  `qianfan-code-latest`, its exact selectable catalog, and a dedicated key.
- [Token Plan launch and Coding Plan retirement](https://cloud.baidu.com/doc/qianfan/s/Fmrexuejc)
  states that new Coding Plan sales stopped on 2026-07-13 while existing
  subscriptions continue only through their current service period.

Decision: `qianfan` binds the current personal Token Plan and ordinary API as
separate candidates; `qianfan-team` isolates the enterprise/team credential;
`qianfan-coding` preserves old subscriptions without treating the retired
product as current. Standard 262,144 context tokens are declared across the
Qianfan suite.

### Qiniu AI

- [Claude Code integration](https://developer.qiniu.com/aitokenapi/13416/tools-claude-code-configuration-instructions)
  documents `https://api.qnaigc.com`, Anthropic compatibility, and Bearer
  configuration through `ANTHROPIC_AUTH_TOKEN`.
- [Enterprise subscription](https://developer.qiniu.com/aitokenapi/13330/subscription-introduction)
  documents dedicated `sk-plan` subscription keys, ordinary pay-as-you-go
  fallback, and the current subscription catalog.
- [AI coding configuration](https://developer.qiniu.com/aitokenapi/13417/tools-AI-Coding-api)
  provides the exact `deepseek/deepseek-v3.2-251201` Claude Code model ID.
- [MCP access](https://developer.qiniu.com/aitokenapi/12984/mcp-user-manual)
  documents console-issued
  `https://api.qnaigc.com/v1/mcp/http-streamable/<id>` endpoints and Bearer
  authentication with the Qiniu AI key.
- [Compatibility FAQ](https://developer.qiniu.com/aitokenapi/kb/13462/aitoken-use-faq)
  confirms `/v1/messages` and that `xhigh` is unsupported, so crouter uses
  `high` effort.

Decision: subscription and API keys remain distinct candidates even though
they share a host. The catalog and context vary by entitlement, so only the
officially demonstrated default is mapped and no context is injected. Optional
MCP URLs are host/path validated and activated only in the Qiniu session.

### Huawei Cloud ModelArts MaaS

- [Token Plan guide (PDF)](https://support.huaweicloud.com/Token-plan-maas/MaaS%E6%A8%A1%E5%9E%8B%E5%8D%B3%E6%9C%8D%E5%8A%A1%20Token%20Plan-pdf.pdf)
  documents `https://api.modelarts-maas.com/plan/anthropic`, bearer auth, and
  supported IDs including GLM-5.1.
- [MaaS model call guide (PDF)](https://support.huaweicloud.com/intl/zh-cn/model-call-maas/MaaS%E6%A8%A1%E5%9E%8B%E5%8D%B3%E6%9C%8D%E5%8A%A1%20%E6%A8%A1%E5%9E%8B%E8%B0%83%E7%94%A8-pdf.pdf)
  documents the regional pay-as-you-go Anthropic prefix and
  `ANTHROPIC_AUTH_TOKEN`.

Decision: the China default prefixes are kept separate. Standard 262,144 context
tokens are declared for the default GLM-5.3 catalog.

### Xiaomi MiMo

- [Claude Code integration](https://mimo.mi.com/docs/zh-CN/tokenplan/integration/claudecode)
  documents the China Token Plan Anthropic prefix, bearer config, and
  `mimo-v2.6-pro`; it requires Claude Code's `[1m]` annotation when enabling
  the million-token window.
- [Token Plan quick access](https://mimo.mi.com/docs/en-US/tokenplan/Token%20Plan/quick-access)
  states that `tp-` plan keys and `sk-` API keys and their base URLs are
  independent.
- [MiMo V2.5 release](https://mimo.mi.com/docs/en-US/news/latest/v2.5-open-sourced)
  states that both V2.5 models support 1M context.

Decision: plan and API surfaces remain isolated even though they expose the
same upstream model. The public logical ID is `mimo-v2.6-pro[1m]`; crouter
removes the Claude Code annotation through the surface model map before the
upstream request. Raw V2.5 IDs remain as explicit migration aliases.

### Volcengine Ark

Volcano Engine offers two distinct subscription plan interfaces:
1. `volcengine` (Ark Agent Plan):
   - Gateway endpoint: `https://ark.cn-beijing.volces.com/api/plan` for Anthropic tools.
   - Empirically validated multi-vendor models: `doubao-seed-evolving` (default, 1M context),
     `deepseek-v4-pro` (1M), `glm-5.3` / `glm-latest` (1M), `kimi-k3` (1M / 256K), `minimax-m3` (1M),
     `glm-5.3-flash` (1M / 256K, multimodal), `deepseek-v4-flash` (1M / 256K), `kimi-k2.7-code` (256K),
     `kimi-k2.6` (256K), `minimax-m2.7` (256K), `doubao-seed-2.1-turbo` (256K), `doubao-seed-2.0-code` (256K),
     `doubao-seed-2.0-lite` (256K), `doubao-seed-2.0-mini` (256K), and `ark-code-latest`.
   - Defaults to `doubao-seed-evolving` with 1,000,000 tokens context. Haiku maps to
     `doubao-seed-2.1-turbo`. Context overrides apply to non-1M models (256K).
   - Uses `VOLCENGINE_PLAN_KEY` or its `VOLCENGINE_AGENT_PLAN_KEY` alias.
     `PLAN_KEYS` checks only `volcengine-agent-plan` and `volcengine-plan`.

2. `volcengine-coding` (Ark Coding Plan):
   - [Ark Coding Plan gateway](https://www.volcengine.com/article/37839)
     documents `https://ark.cn-beijing.volces.com/api/coding` for Anthropic tools.
   - [Ark Coding Plan catalog](https://www.volcengine.com/article/37570) lists
     `doubao-seed-evolving` (1M), Seed 2.1 variants (`doubao-seed-2.1-pro`,
     `doubao-seed-2.1-turbo`), Seed 2.0 variants, `ark-code-latest`, and DeepSeek variants.
   - Dedicated coding gateway using only `VOLCENGINE_CODING_PLAN_KEY` and
     the `volcengine-coding-plan` Keychain service.

   `volcengine` (Agent Plan) automatically injects the official Doubao Search MCP
   (`mcp-server-askecho-search-infinity`), DataPro professional datasets MCP, and
   OpenViking control-plane MCP alongside the public Ark documentation MCP.
   `volcengine-coding` (Coding Plan) provides the public documentation MCP.

## Exclusions and non-vendor routes

- OpenAI's official API exposes Responses and Chat Completions, not an
  Anthropic Messages base URL. A direct POST to `/v1/messages` returns 404, so
  the old `openai` provider and launcher were removed. `codex` remains a
  separately named local translation proxy for ChatGPT subscription access.
- Baichuan's published API is OpenAI-compatible; its old provider guessed an
  Anthropic URL and even included the full `/v1/messages` path. It was removed.
- [Ollama's Claude Code integration](https://docs.ollama.com/integrations/claude-code) supports
  the local Anthropic endpoint; the installed model catalog remains local.
- Local implementation (checked 2026-09-26): `ollama` defaults to
  `qwen3.8-27b` on the MLX adapter, unless an actual Ollama-provider launch has
  saved another model selection. `providers/ollama.sh` owns the current model
  IDs and caps: Qwen uses 262,144 tokens, and the explicit DeepSeek V4 Flash
  entries use the measured 373,760-token cap. Default Claude effort is `max`;
  the `qwen3.8*` selections instead declare `medium` and the relay clamps every
  request to that cap, because Ollama's chat template rejects higher levels with
  an HTTP 500 that Claude Code cannot downgrade from. See "Local Ollama
  reasoning-effort contract" above.
  Other selected models use the port-11435 Ollama relay, which sends SSE
  comments every 60 seconds. DeepSeek thinking fields are preserved; its
  unsupported image content blocks are replaced with a text fallback. Upstream
  response events are preserved, and each session stops only its own relay.
- [OpenRouter's Nemotron 3 Ultra free model page](https://openrouter.ai/nvidia/nemotron-3-ultra-550b-a55b%3Afree)
  documents the exact `nvidia/nemotron-3-ultra-550b-a55b:free` ID and a 1M
  context. crouter pins that model rather than using the dynamic free-model
  router, so its 1,000,000-token client limit is an exact-model contract.
  Live probe 2026-10-06: the catalog reports a single Nvidia endpoint with
  1,000,000 context and 65,536 max output, and `/api/v1/messages` returned
  `thinking` + `text` + `tool_use` at cost 0. The same upstream rejects
  Anthropic `thinking: {"type":"enabled"}` with an Nvidia 500, so the client
  must not negotiate an extended-thinking budget for this model.
- OpenRouter, Codex, and Antigravity keep their existing documented gateway or
  local-proxy contracts. Their catalogs are not presented as first-party model
  APIs.

## Re-audit checklist

When a vendor changes its plan:

1. Check the vendor's Claude Code or Anthropic Messages page.
2. Record the page update date and exact base prefix, auth variable, models,
   and stated context.
3. Update `test/provider-matrix.sh` first and confirm it fails.
4. Update the provider file and any model-map assertion.
5. Verify MCP package versions in their official npm/PyPI registry entries.
6. Run every offline test and a credentialed smoke test only when the account
   owner explicitly provides the required credentials.

## Reproducible local proof

The repository's offline suite verifies provider declarations, exact surface
binding, model rewriting, header isolation, cross-request cooldown, key-pool
registration, session asset selection/cleanup, native Claude login passthrough,
and unified route construction under both POSIX `sh` and `dash`.

```sh
crouter all --check
for test_file in test/*.sh; do sh "$test_file"; done
for test_file in test/*.sh; do dash "$test_file"; done
```

`all --check` is deliberately non-networked and redacted. These checks prove
that the implementation matches the recorded contracts; only a credentialed,
potentially billable request can prove that a particular account currently has
quota and entitlement to a vendor's live catalog. The check also does not start
or probe local proxy routes; those dependencies must be running before use.
