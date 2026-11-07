---
name: crouter-development
description: Develop and review crouter, the interactive model and account router for Claude Code. Use for roadmap implementation or updates, TUI simplification, model switching, subscription and multi-key automation, App reverse-proxy sources, and acceptance planning. 中文触发：开发 crouter、更新开发 skill、交互改造、切换模型、管理订阅和 Key、接入 App 反代。Not a multi-client launcher skill.
---

# crouter 项目开发

## 产品边界

使用端只有 **Claude Code**。官方 API、订阅、多 Key、本地推理和 App 反代都是模型来源。目标是用户方便选模型，程序处理接入、凭证和授权范围内的切换，不是启动不同 App 客户端。

目标主入口是裸 `crouter` 的交互首页，不是再加 `--interactive` 或逐项包装 flags。不强制 Profile、不扩展大型 Web 控制台。现有 `app` 入口冻结为兼容功能。保留当前有效 CLI 契约，但不要恢复已经主动移除的 `claude-<provider>` 或 `bin/crouter-compat`。

这里的目标契约不等于已实现功能。当前事实和证据放在基线参考，任务状态只在路线图维护；不要把易变状态复制到所有入口。

## 工作流程

1. 先读 `AGENTS.md`、`CLAUDE.md` 和 `.agents/SKILLS.md`。记录 HEAD、工作树和本次授权范围，保留用户改动。只更新 skill 时，不顺手修运行时、CI 或发布版本。
2. 读 [基线与来源](references/baseline-and-sources.md) 和 [路线图](references/roadmap.md)。比较审阅基线与当前 HEAD，再查看受影响源码、测试及对应 SHA 的 CI。旧提交的绿灯、提交标题、历史交付记录都不能替代当前验证。
3. 选一个有依赖依据的纵向切片，不机械选择最小任务编号。基线阻塞先按路线图处理；已修复行为保留为回归，不重复开发。CI 失败、代码缺口和待复现风险分别记录，后续步骤 skipped 不算通过。
4. 把切片写成用户动作、可见结果、失败恢复、副作用边界和验收 ID。先建立或复用失败回归，再实现最小闭环。纯技能维护只检查技能相关结构和行为，不启动全套产品改造。
5. 按风险运行纯逻辑、mock HTTP、PTY、离线整合或真实客户端验证。测试使用隔离 HOME/XDG/STATE 和假凭证；有 shell 矩阵时设置 `TEST_SHELL`，不把 `sh -n a b` 当作检查两个文件。
6. 更新相应证据和任务状态。提交前重查远端 HEAD，合并并发改动后再验证；不 force push、不覆盖别人的工作。未指定的一般细节沿用保守默认值，不反复要求确认；缺账号仍继续完成可验证的离线部分。

## 按需加载

| 本次任务 | 参考 |
| --- | --- |
| 首页、模型列表、账户向导、TTY 行为 | [产品与交互](references/product-and-ux.md) |
| 计划解析、状态、凭证、调度、流式与会话 | [运行时契约](references/runtime-contracts.md) |
| App 反代和 Claude 原生模型菜单 | [适配器与 Claude Code](references/adapters-and-claude.md) |
| 优先级、依赖、任务状态与历史交付 | [路线图](references/roadmap.md) |
| 用户流程、CLI 兼容、测试分层与完成定义 | [验收矩阵](references/acceptance.md) |
| 已落地行为、剩余缺口、当前 CI、官方来源 | [基线与来源](references/baseline-and-sources.md) |
| 技能触发、边界和过时状态处理 | [行为评测案例](evals/cases.json) |
| 技能结构及校验器自身回归 | [校验器](scripts/validate.mjs)、[校验器测试](scripts/validate.test.mjs) |

认证/路由/生命周期改动另读 `docs/agent-architecture.md`；provider、故障诊断或单独 CI 修复按任务复用现有专项技能，不一次加载全部内容。

## 不可破坏的契约

- **先选模型并解析完整配置，再启动。** 取消不启动 Claude 只是其中一层，还要验证 hooks、认证代理、MCP/插件和推理请求均无副作用。目录读取是独立、可取消的操作。
- TUI/CLI 复用应用操作；跨语言用结构化输入输出，不拼 shell、不解析菜单文本。先保留 shell 外壳和 Node 核心，禁止为重构重写全部 provider。
- 每个候选绑定来源、账户、额度池、CredentialRef、计费面、endpoint、认证头和 model map；不交叉组合、不把 API key 自动当订阅 key。
- 同模型换凭证、跨来源、按量兜底、跨模型是不同授权。未授权的后两项默认关闭；新增来源和迁移不扩大旧授权。
- 请求采用不可变快照；默认选择不广播到活动会话。严格处理冷却、总重试预算、客户端取消；响应提交后不拼接另一候选、不重放工具调用。
- context、output、compact、effort 和 tier 必须绑定真实模型。删除旧状态文件不等于清空已加载的内存值。未知不是免费或支持，不能伪装 Claude 身份来解锁能力。
- 保留 POSIX sh/dash、符号链接定位、隔离的 env、原生 Claude 登录、临时 MCP 和进程归属。可选 `claude` 包装入口必须识别真正的 Claude 可执行文件，不能递归调用自身或覆盖用户原生 CLI。
- 不把秘密放到源码、argv、日志、截图、测试产物或评测提示词；离线验证不读真实凭证。技能本身不授予 push、安装、登录、付费验证或发布权限。

## 验证与交付

```sh
node .agents/skills/crouter-development/scripts/validate.mjs
node .agents/skills/crouter-development/scripts/validate.test.mjs
TEST_SHELL=sh sh test/development-skill.sh
TEST_SHELL=dash dash test/development-skill.sh
git diff --check
```

以上是技能结构与校验器回归，不是 LLM 行为评测、产品回归或真实 Claude 验证。行为评测用 `evals/cases.json`，检查实际读取、计划、工具调用及结果，不只看关键词。未运行的层级写未执行。

交付分开报告改动、实际通过、失败/未执行、剩余风险，附文件与 commit/PR。任务 DONE 必须有该范围的证据；历史 DONE 可以保留，但不能据此宣称新 HEAD 全绿。到达授权范围内的可验证结果即停止。
