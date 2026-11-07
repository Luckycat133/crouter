# Provider refresh — 2026-11-07

基线：`fdcaf9120b9b4d0bb6c811d0ce75f935435e754d`。检查全部 36 个 provider；更新 28 个远端声明，另外 8 个本地/原生声明保留实际部署身份，由 loader 补齐目录发现策略。不是“所有供应商已经实测可用”。

## 证据与范围

远端 ID 来自供应商文档或公开目录，计费面分别记录；未使用真实 Key、登录会话或付费推理。静态列表是经过核对的入口集合，不是数百模型聚合平台的完整实时清单，也不是账户权益。支持目录的来源可交互刷新；缺少凭证、目录失败或不支持目录时保留静态/最后有效目录。旧审计 `provider-audit.md` 保留历史上下文；与本次型号和地址冲突时，以本次有来源的决策及代码为准。

每行的一手来源、保留原因与验证级别也保存在 [机器可读记录](provider-review-2026-11-07.json)。原生/本地八项仅检查仓库契约，没有访问用户机器。

| Provider | 默认模型／别名 | 目录策略 | 本次依据与决策 |
| --- | --- | --- | --- |
| `302ai` | `claude-sonnet-5-5` | remote | [来源](https://302.ai/search)；Use exact 302 Claude IDs; do not infer upstream IDs for unrelated gateways. |
| `aihubmix` | `coding-glm-5.1-free` | remote | [来源](https://docs.aihubmix.com/en/blogs/free-ai-models)；Retain documented free default. Source page is dated May 2026, not proof of current account availability; use authenticated catalog refresh. |
| `anthropic` | `claude-sonnet-5-5` | remote | [来源](https://platform.claude.com/docs/en/models/overview)；Refresh current Claude family; leave native client context authority intact. |
| `antigravity` | `gemini-3.8-flash` | remote | [来源](https://github.com/Luckycat133/crouter/blob/fdcaf9120b9b4d0bb6c811d0ce75f935435e754d/providers/antigravity.sh)；保留 Gemini 3.8 本地映射与生命周期；目录从正在运行的反代读取，浏览不会启动反代。 |
| `antigravity-claude` | `claude-opus-4-6-thinking` | remote | [来源](https://github.com/Luckycat133/crouter/blob/fdcaf9120b9b4d0bb6c811d0ce75f935435e754d/providers/antigravity-claude.sh)；保留本地 Claude 4.6/GPT-OSS 映射；不能把官方 Claude 5.5 ID 硬塞进旧反代。 |
| `bedrock` | `sonnet` | native | [来源](https://code.claude.com/docs/en/amazon-bedrock)；保留原生 SDK 的 opus/sonnet/haiku 别名与 AWS 认证链；不猜账户/区域 deployment。 |
| `bonsai` | `ternary-bonsai-2-27b` | static | [来源](https://github.com/Luckycat133/crouter/blob/fdcaf9120b9b4d0bb6c811d0ce75f935435e754d/providers/bonsai.sh)；保留固定 Bonsai 适配器及静态目录；上游模型路径仍是机器特定配置，不能声称可移植。 |
| `codex` | `gpt-5.6-sol` | remote | [来源](https://github.com/Luckycat133/crouter/blob/fdcaf9120b9b4d0bb6c811d0ce75f935435e754d/providers/codex.sh)；保留本地反代的 gpt-5.6-sol/terra/luna 映射；目录来自该反代 /v1/models，不拿官方 API 型号冒充反代支持。 |
| `dashscope` | `qwen3.8-max` | static | [来源](https://help.aliyun.com/zh/model-studio/token-plan-personal-overview)；Keep explicit main model instead of switching user to auto routing. Remove unlisted qwen3.8-plus from Token Plan. API contract remains distinct. |
| `dashscope-coding` | `qwen3.7-plus` | static | [来源](https://help.aliyun.com/zh/model-studio/claude-code)；Current Coding Plan example uses qwen3.7-plus, not Token Plan qwen3.8-max. Do not inherit an unverified 983616 context for every model. |
| `deepseek` | `deepseek-flash[1m]` | remote | [来源](https://api-docs.deepseek.com/quick_start/pricing)；Use official Flash service alias; former V4 Flash routes now resolve to V4.1 Flash 1017. Remove unsupported guessed V4.1 IDs. |
| `fireworks` | `accounts/fireworks/models/glm-5p3-flash` | static | [来源](https://docs.fireworks.ai/getting-started/quickstart)；Retain current GLM 5.3 Flash quickstart default; serverless/deployment catalog is account-dependent. |
| `foundry` | `sonnet` | native | [来源](https://code.claude.com/docs/en/microsoft-foundry)；保留原生 SDK 别名和 Azure 认证链，部署名由用户实际资源决定。 |
| `huawei` | `glm-5.3` | static | [来源](https://support.huaweicloud.com/Token-Plan-maas/tokenplan-maas-0003.html)；Restrict plan seed list to current documented model names. Preserve conservative context cap; do not infer the API or regional entitlement from upstream maxima. |
| `infini` | `glm-5.1` | remote | [来源](https://docs.infini-ai.com/shared/gen-studio/coding-tools/gs-use-claude-code.html)；Keep documented glm-5.1 example; live catalog required for exact Claude-compatible account choices. Do not restore retired Coding Plan. |
| `longcat` | `LongCat-2.5` | remote | [来源](https://longcat.chat/platform/docs/ClaudeCode.html)；Replace preview/default and old 2.0 seed with current stable 2.5 model. |
| `meta` | `muse-spark-1.3` | static | [来源](https://dev.meta.ai/docs/models)；Add Wonder 1.0 as explicit premium/preview Opus choice; retain Spark main default to avoid an unrequested price/preview jump. No Muse Code subscription keys. |
| `minimax` | `MiniMax-M3.1-Flash` | static | [来源](https://platform.minimax.cn/docs/m-plan/claude-code)；Update M3.1 Flash and documented 512K compaction. Separate subscription and pay-as-you-go keys. |
| `moonshot` | `k3.1-pro` | remote | [来源](https://www.kimi.com/code/docs/en/kimi-code/models.html)；Use Kimi Code raw IDs, recommended 256K client budget; optional larger context must be deliberate and entitlement verified. |
| `nagaai` | `claude-sonnet-5` | remote | [来源](https://docs.naga.ac/integrations/agents/claude-code)；Use Naga dot-separated versions, not Anthropic spellings. Public metadata is not entitlement; newer IDs require live catalog. |
| `ollama` | `qwen3.8:27b-dflash` | remote | [来源](https://github.com/Luckycat133/crouter/blob/fdcaf9120b9b4d0bb6c811d0ce75f935435e754d/providers/ollama.sh)；保留已安装的 DFlash/MLX 路径；从本机 Ollama /v1/models 读取目录，不下载或替换模型。 |
| `openrouter` | `nvidia/nemotron-3.5-super-vl:free` | remote | [来源](https://openrouter.ai/api/v1/models)；Use current Super 3.5 VL free default; public dynamic catalog supplies the wider list. Refuse retired free Qwen -> paid substitution. |
| `ppio` | `minimax/minimax-m3.1-flash` | static | [来源](https://ppio.com/model/minimax/minimax-m3.1-flash)；Upgrade to documented M3.1 Flash Messages model; keep per-model metadata separate from other PPIO catalog entries. |
| `qianfan` | `deepseek-v4-pro` | static | [来源](https://cloud.baidu.com/doc/qianfan/s/Dmrabu8b6)；Current personal-plan catalog; 1017 may require points plan. Exclude soon-retiring dated IDs from recommended seeds; preserve API surface model separately. |
| `qianfan-coding` | `qianfan-code-latest` | static | [来源](https://cloud.baidu.com/doc/qianfan/s/imlg0beiu)；Legacy subscriptions only; current exact custom IDs documented are deepseek-v4-pro and glm-5.1. Keep control-panel router explicit. |
| `qianfan-team` | `deepseek-v4.1-flash` | static | [来源](https://cloud.baidu.com/doc/qianfan/s/ymq8wwch2)；Use current enterprise model-parameter table rather than stale tool example. Team credentials remain isolated from personal plan. |
| `qiniu` | `deepseek/deepseek-v4.1-flash` | static | [来源](https://developer.qiniu.com/aitokenapi/13330/subscription-introduction)；Refresh to current subscription list; per-tier entitlements still apply. Remove old V3.2 default not in current plan coverage. |
| `requesty` | `anthropic/claude-sonnet-5-5` | remote | [来源](https://www.requesty.ai/models/anthropic/claude-sonnet-5-5)；Exact Requesty deployment IDs; do not infer dot/dash naming from another gateway. |
| `siliconflow` | `Pro/moonshotai/Kimi-K2.7-Code` | remote | [来源](https://api-docs.siliconflow.cn/docs/usercases/use-siliconcloud-in-ccswitch)；Keep existing server-specific Pro model IDs; refresh account catalog instead of manufacturing new K3 IDs from upstream releases. |
| `stepfun` | `step-5-preview` | static | [来源](https://platform.stepfun.com/docs/zh/guides/developer/integrations/claude-code)；Current four documented Messages model IDs. Keep fast tier choice; no undocumented router alias. Same API key may be usable on both paths but user must explicitly assign each billing surface. |
| `tencent` | `tc-code-latest` | static | [来源](https://cloud.tencent.com/document/product/1823/130060)；Move only Token Plan to new TokenHub domain. Current plan seeds include Hy4; stop recommending MiniMax M2.7 scheduled for retirement 2026-11-17. Preserve explicit legacy aliases via manual entry, not silent rewriting. |
| `tencent-coding` | `tc-code-latest` | static | [来源](https://cloud.tencent.com/document/product/1823/130092)；Retain legacy Coding Plan endpoint and router; never migrate its credentials to TokenHub Token Plan automatically. |
| `vercel` | `anthropic/claude-sonnet-5.5` | remote | [来源](https://ai-gateway.vercel.sh/v1/models)；Use current public catalog exact IDs and per-model limits; exclude batch/media-only entries from picker. |
| `vertex` | `sonnet` | native | [来源](https://code.claude.com/docs/en/google-vertex-ai)；保留原生 SDK 别名、项目/区域与 ADC；不把公开 Anthropic ID 当作所有项目可用部署。 |
| `xiaomi` | `mimo-v2.6-pro[1m]` | static | [来源](https://mimo.mi.com/docs/zh-CN/quick-start/summary/model)；Remove V2.5 IDs retired on 2026-10-21. UltraSpeed is custom entitlement, not assumed available. Preserve [1m] logical-to-raw map. |
| `z-ai` | `glm-5.3[1m]` | static | [来源](https://docs.z.ai/devpack/tool/claude)；Retain current documented manual tier mapping; source summary and sample differ, so do not force all tiers to Flash. Remove API-to-plan credential inference. |

## 重要配置变更

- 套餐 Key 不再从普通 API Key 环境变量自动复制。原先依赖该行为的配置必须把真实套餐 Key 存入明确的套餐字段；不要通过重新添加隐式 fallback 来“修复”认证失败。
- Tencent Token Plan 使用 `https://tokenhub.tencentmaas.com/plan/anthropic`；旧 Coding Plan 仍保留原域名。DashScope Token Plan、Coding Plan 与 API 的型号/地址分别维护。
- MiniMax M3.1-Flash 推荐压缩窗口为 524288；Kimi K3.1 Pro 默认保留 256K 客户端预算，1M 依赖会员权益。窗口、压缩与输出上限不能互相代用。目录元数据并未自动变成所有客户端能力开关。
- MiMo V2.5 系列不再列为可用迁移别名；LongCat 采用稳定 2.5。OpenRouter 已退役的免费 Qwen ID 不自动映射到收费 ID，显式选择收费模型才允许使用。
- 公共目录不携带推理 Key；账户目录只使用其声明计费面的凭证。目录 URL 与认证 origin 绑定，不跟随重定向；保留 query，限制响应大小、请求时限、分页和重试。
- 本次给显式 `surfaces` 候选增加费用/模型边界：同时有套餐与 API 时，默认只保留套餐候选。启用 `CROUTER_ALLOW_PAID_FALLBACK=1` 后，若实际 model_map 不同，还需独立启用 `CROUTER_ALLOW_CROSS_MODEL_FALLBACK=1`。只有 API 配置时仍可正常使用 API。首页只提供同模型付费兜底开关，作用于从该首页启动的新会话。
- 这不是全局预算或完整调度器：旧自定义 dual-source/keypool 保持兼容；Keychain 拒绝/锁定与“未配置”区分仍需 AUTH-02 验收；上游自行计费/轮换不受本地候选列表完全控制。不要宣称具有账单硬限额。

## 不可假装已确认的部分

AIHubMix 的引用页面较旧；SiliconFlow 当前公开接入样例落后于仓库已用型号，因此保留原有默认，提供账户目录，而不凭上游厂商发布猜测平台支持。302.AI/Kimi 的常见模型目录路径仅作为可回退探测，未做认证 HTTP 验证。Huawei、Qianfan 等保留的 262144 是既有客户端预算，不是所有别名统一的最大能力证明。所有目录条目都标为 catalog-only。

本地 Bonsai 仍有机器特定路径；Ollama、Antigravity 的固定端口/共享进程边界和旧 gateway 的重试/断流状态机未在本次全面改写。用户另行保存的旧模型不会被升级过程静默改选；旧 ID 失效时应从菜单重新选择。

## 本次实现与交接

见 [测试交接](provider-refresh-handoff.md)。本次版本号不变，无自动发布、无反代安装、无用户凭证迁移。
