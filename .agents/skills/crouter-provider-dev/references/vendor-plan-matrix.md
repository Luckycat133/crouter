# AI Vendor Subscription Plan Matrix

This reference documents the configuration parameters, endpoint URLs, auth headers, and companion MCP suites for all AI vendor subscription plans supported in `crouter`.

## 1. Provider Plan Matrix

| Provider | Surface Name | Plan Gateway URL | Default Plan Key Env | Context Limit | Companion MCP Tools / Assets |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **minimax** | Token Plan | `https://api.minimaxi.com/anthropic` | `MINIMAX_TOKEN_PLAN_KEY` | 1,048,576 | MiniMax Token Plan MCP (`uvx minimax-coding-plan-mcp`), media plugin |
| **dashscope** | Token Plan | `https://token-plan.cn-beijing.maas.aliyuncs.com/apps/anthropic` | `DASHSCOPE_TOKEN_PLAN_KEY` | 983,616 | DashScope WebSearch (`http`), DashScope media plugin |
| **dashscope-coding**| Coding Plan | `https://coding.dashscope.aliyuncs.com/apps/anthropic` | `DASHSCOPE_CODING_PLAN_KEY` | 983,616 | DashScope WebSearch (`http`, isolated profile) |
| **tencent** | Token Plan | `https://api.lkeap.cloud.tencent.com/plan/anthropic` | `TENCENT_TOKEN_PLAN_KEY` | 262,144 | Tencent Web Search (`sse`, via `CR_TENCENT_MCP_URL`) |
| **tencent-coding** | Coding Plan | `https://api.lkeap.cloud.tencent.com/coding/anthropic` | `TENCENT_CODING_PLAN_KEY` | 262,144 | Tencent Web Search (`sse`, via `CR_TENCENT_MCP_URL`) |
| **qianfan** | Token Plan | `https://qianfan.baidubce.com/anthropic/tokenplan/personal` | `QIANFAN_TOKEN_PLAN_KEY` | 262,144 | Pure model gateway (`empty`) |
| **qianfan-coding** | Coding Plan | `https://qianfan.baidubce.com/anthropic/coding` | `QIANFAN_CODING_PLAN_KEY` | 262,144 | Pure model gateway (`empty`) |
| **qianfan-team** | Team Plan | `https://qianfan.baidubce.com/anthropic/tokenplan/team` | `QIANFAN_TEAM_PLAN_KEY` | 262,144 | Pure model gateway (`empty`) |
| **stepfun** | Step Plan | `https://api.stepfun.com/step_plan` | `STEPFUN_PLAN_KEY` | 262,144 | StepFun WebSearch (`http`), stepfun-plan plugin |
| **z-ai** | Coding Plan | `https://api.z.ai/api/anthropic` | `Z_AI_CODING_PLAN_KEY` | 1,000,000 | Z.AI Vision (`npx`), Web Search (`http`), Web Reader (`http`), ZRead (`http`) |
| **moonshot** | Kimi Code | `https://api.kimi.com/coding/` | `KIMI_CODE_KEY` | 262,144 | Pure model gateway (`empty`) |
| **xiaomi** | MiMo Token Plan | `https://token-plan-cn.xiaomimimo.com/anthropic` | `XIAOMI_TOKEN_PLAN_KEY` | 1,048,576 | Pure model gateway (`empty`) |
| **huawei** | MaaS Token Plan | `https://api.modelarts-maas.com/plan/anthropic` | `HUAWEI_TOKEN_PLAN_KEY` | 262,144 | Pure model gateway (`empty`) |
| **qiniu** | Qnaigc Subscription| `https://api.qnaigc.com` | `QINIU_SUBSCRIPTION_KEY` | 262,144 | Qiniu Streamable HTTP MCPs (`CR_QINIU_MCP_URLS`) |

## 2. Dual-Surface Invariants

1. **Surface Separation**:
   - Plans and pay-as-you-go APIs are independent surfaces.
   - Plans always use `PLAN_URL`, `PLAN_AUTH_TYPE="bearer"`, `PLAN_KEY_ENV`, `PLAN_KEYS`, and `PLAN_MODEL*`.
   - Pay-as-you-go keys use `API_URL`, `API_AUTH_TYPE="bearer"`, `API_KEY_ENV`, `API_KEYS`, and `API_MODEL*`.
   - `AUTH_MODE="surfaces"` instructs `crouter`'s credential resolver to check plan keys first, falling back to API keys only if the plan key is unset.

2. **Deduction and Financial Safety**:
   - By default, requests routed through a plan endpoint consume monthly subscription quotas (AFP / token quotas).
   - Never inject credentials that trigger unconfirmed cash billing unless explicit user approval is granted.
