# Provider audit

Primary-source audit date: 2026-08-08. Release documentation checked:
2026-08-09 for crouter 0.5.1.

This document records the primary sources used for crouter's provider
contracts. It is a configuration audit, not a promise that an account owns a
particular plan or model. Vendor catalogs can vary by region, plan tier, and
account entitlements.

The release contains 29 provider contracts, including 21 mainland-China
provider entries. Counts include separate products when their credentials or
endpoints cannot safely share a route, such as DashScope/Coding Plan,
Qianfan personal/team/legacy Coding Plan, and Tencent personal/Coding Plan.

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
- [Claude model overview](https://platform.claude.com/docs/en/about-claude/models/overview)
  lists the current Opus 5, Sonnet 5, Fable 5, and Haiku 4.5 model IDs and
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

Bedrock and Vertex use Claude Code's native signers. The previous localhost
proxy definitions and guessed future/date-suffixed model IDs were removed.
Native routes are not placed behind `crouter all`.

### MiniMax

- [MiniMax M3](https://www.minimax.io/models/text/m3) gives the exact
  `MiniMax-M3` ID, the 1M API context, and states that Token Plan users
  automatically receive M3 capabilities.
- [Token Plan overview](https://platform.minimaxi.com/docs/token-plan/intro)
  states that Token Plan keys and pay-as-you-go API keys are not
  interchangeable.
- [MiniMax Token Plan MCP](https://platform.minimaxi.com/docs/token-plan/mcp-guide)
  documents `uvx minimax-coding-plan-mcp -y`, the China API host, and the
  Token Plan key environment variable.
- [MiniMax CLI](https://platform.minimaxi.com/docs/token-plan/minimax-cli)
  is exposed by the session skill through pinned `mmx-cli@1.0.19`.

Decision: both billing surfaces use the China Anthropic prefix but keep
independent credential pools. The MCP uses pinned PyPI release `0.0.4` and is
activated only when a plan credential is present.

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
  `glm-5.2[1m]`, Haiku `glm-4.7`, and the 1,000,000 compact window.
- [Z.AI model overview](https://docs.z.ai/guides/overview/overview) states that
  GLM-5.2 has a stable 1M context.
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
    `qwen3.7-plus`.
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
  documents `deepseek-v4-flash`, `deepseek-v4-pro`, the
  `https://api.deepseek.com/anthropic` prefix, and 1M context.
- [Anthropic API guide](https://api-docs.deepseek.com/guides/anthropic_api)
  documents `ANTHROPIC_API_KEY` and full `x-api-key` support.
- [Claude Code integration](https://api-docs.deepseek.com/quick_start/agent_integrations/claude_code)
  recommends `deepseek-v4-pro[1m]` for default, Opus, and Sonnet,
  `deepseek-v4-flash` for Haiku and subagents, and maximum effort. It also
  sets the auto-compaction window to 786,432 and documents DeepSeek's
  server-side web-search tool.

Decision: DeepSeek is API-only and uses `x-api-key`, not Bearer. The public
default/Opus/Sonnet mapping carries Claude Code's `[1m]` annotation and is
stripped to raw `deepseek-v4-pro` on the upstream request; Haiku and subagents
map to V4 Flash. Maximum context and automatic compaction remain separate
settings. Web search is model-native, not a downloadable MCP package.

### SiliconFlow

- [Anthropic Messages API](https://docs.siliconflow.cn/cn/api-reference/chat-completions/messages)
  documents `https://api.siliconflow.cn/v1/messages`, Bearer authentication,
  and the dynamically managed model catalog.
- [Claude Code integration](https://docs.siliconflow.cn/cn/usercases/use-siliconcloud-in-ClaudeCode)
  documents the base prefix and ordinary SiliconFlow API key.
- [Current CC Switch preset](https://api-docs.siliconflow.cn/docs/usercases/use-siliconcloud-in-ccswitch)
  maps every Claude tier to `Pro/moonshotai/Kimi-K2.6`.

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
  confirms native Messages support and its 1M context. The current pricing
  catalog retains `claude-haiku-4-5-20251001` for the fast tier.
- [Claude Code dedicated route](https://302.ai/product/detail/anthropic-claude-opus-4-1-20250805-Code)
  documents a separate `/cc` prefix but also warns that it may substitute GLM
  or Kimi during Claude risk-control periods.

Decision: `302ai` uses the original Messages API so an explicitly selected
model remains an exact contract. It is API-only; Sonnet 5 is the balanced 1M
default, Opus 5 and Haiku 4.5 own their logical tiers, and Fable 5 remains an
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
- [Step 3.7 Flash](https://platform.stepfun.com/docs/zh/guides/models/step-3.7-flash)
  documents the exact ID, 256K context, Messages support, and low/medium/high
  effort levels.
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
  prefix, team key, and `deepseek-v3.2` for every Claude tier.
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
product as current. No context is injected because the official integration
pages do not state a single authoritative context limit for these routed
catalogs.

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

Decision: the China default prefixes are kept separate. Context is left unset
because it depends on the selected MaaS model.

### Xiaomi MiMo

- [Claude Code integration](https://mimo.mi.com/docs/zh-CN/tokenplan/integration/claudecode)
  documents the China Token Plan Anthropic prefix, bearer config, and
  `mimo-v2.5-pro`; it requires Claude Code's `[1m]` annotation when enabling
  the million-token window.
- [Token Plan quick access](https://mimo.mi.com/docs/en-US/tokenplan/Token%20Plan/quick-access)
  states that `tp-` plan keys and `sk-` API keys and their base URLs are
  independent.
- [MiMo V2.5 release](https://mimo.mi.com/docs/en-US/news/latest/v2.5-open-sourced)
  states that both V2.5 models support 1M context.

Decision: plan and API surfaces remain isolated even though they expose the
same upstream model. The public logical ID is `mimo-v2.5-pro[1m]`; crouter
removes the Claude Code annotation through the surface model map before the
upstream request.

### Volcengine Ark

- [Ark Coding Plan gateway](https://www.volcengine.com/article/37839)
  documents `https://ark.cn-beijing.volces.com/api/coding` for Anthropic tools.
- [Ark Coding Plan catalog](https://www.volcengine.com/article/37570) lists
  `doubao-seed-2.0-code`, Pro/Lite variants, and `ark-code-latest`.

Decision: model punctuation uses the documented dots. Context is left unset
because the available primary material does not state a single limit for the
multi-model plan. The public documentation MCP has no credential.

## Exclusions and non-vendor routes

- OpenAI's official API exposes Responses and Chat Completions, not an
  Anthropic Messages base URL. A direct POST to `/v1/messages` returns 404, so
  the old `openai` provider and launcher were removed. `codex` remains a
  separately named local translation proxy for ChatGPT subscription access.
- Baichuan's published API is OpenAI-compatible; its old provider guessed an
  Anthropic URL and even included the full `/v1/messages` path. It was removed.
- [Ollama's Claude Code integration](https://docs.ollama.com/integrations/claude-code) supports
  the local Anthropic endpoint; the installed model catalog remains local.
- Local implementation decision: `deepseek-v4-flash:q8` is this machine's
  crouter default, with `high` effort and a measured 373,760-token client cap.
  Direct sessions pass through a localhost-only port-11435 relay that emits an
  SSE comment every 60 seconds during otherwise silent multi-minute generation.
  The comment is transport metadata, not a model event; request bytes and
  upstream response events are forwarded unchanged. A session stops only the
  relay process it started itself.
- [OpenRouter's Nemotron 3 Ultra free model page](https://openrouter.ai/nvidia/nemotron-3-ultra-550b-a55b%3Afree)
  documents the exact `nvidia/nemotron-3-ultra-550b-a55b:free` ID and a 1M
  context. crouter pins that model rather than using the dynamic free-model
  router, so its 1,000,000-token client limit is an exact-model contract.
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
