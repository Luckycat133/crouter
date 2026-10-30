---
name: crouter-development
description: Develop crouter as an interactive model and account router exclusively for Claude Code. Use for crouter roadmap implementation, TUI or CLI simplification, model switching, multi-key and subscription automation, App reverse-proxy sources, session isolation, or end-to-end acceptance. 中文触发：开发 crouter、交互改造、切换模型、管理订阅和 Key、接入 App 反代。Not a multi-client launcher skill.
---

# crouter 项目开发

## 产品边界

crouter 的使用端只有 **Claude Code**。官方 API、订阅账户、多个 Key、本地推理、App 反代都是模型来源，不是要启动的新客户端。主线是让用户在 Claude Code 里方便地选择模型，由程序管理接入、凭证与允许范围内的自动切换。

默认交互入口是 `crouter`，不是再增加一个 `--interactive`。保留脚本接口和旧命令的兼容性，但不要把 CLI 参数逐个包装成菜单。不要扩展多客户端启动器、强制 Profile 系统或另起大型 Web 控制台。现有 `app` 兼容入口暂不扩展，也不在无迁移方案时删除。

本技能描述的是**开发目标与工作方法**，不是已实现功能清单。提交技能不等于交互改造、账户调度或真实上游验证已经完成。

## 开始一个任务

1. 阅读 `AGENTS.md`、`CLAUDE.md`、`.agents/SKILLS.md`；记录 HEAD 和工作树状态，保留用户未提交修改。不要把旧聊天、README 或 `PROJECT.md` 的历史审计当作当前实现。
2. 按下面的路由表只加载本次需要的参考文件。涉及认证、路由或生命周期时，另读 `docs/agent-architecture.md`，按需复用现有维护、provider、诊断技能；不要一次加载全部技能。
3. 把任务写成一条可观察的用户流程，明确输入、可见结果、失败恢复和不应产生的副作用。读取对应代码与测试，再确认缺口。
4. 从路线图选择最早未完成且可执行的增量。先建立受影响行为的回归测试，再实现最小闭环；不要先造通用框架或批量增加 provider。
5. 对未明确的常规细节采用文档中的保守默认值并记录。没有新的必要信息，不反复询问“是否继续”；缺少真实账号时继续完成 mock、离线契约和接入界面，不伪造 live 结果。

## 按需加载

| 本次任务 | 参考 |
| --- | --- |
| 产品决策、首页、模型列表、账号向导、TTY 体验 | [产品与交互](references/product-and-ux.md) |
| 解析顺序、状态、凭证、调度、重试、并发会话 | [运行时契约](references/runtime-contracts.md) |
| App 反代、协议适配、Claude Code 原生菜单 | [适配器与 Claude Code](references/adapters-and-claude.md) |
| 任务拆分、依赖、实施顺序、迁移和交付 | [开发路线图](references/roadmap.md) |
| 回归场景、测试层级、完成定义 | [验收矩阵](references/acceptance.md) |
| 当前代码定位、待复现问题、官方来源 | [基线与来源](references/baseline-and-sources.md) |
| 验证本技能是否能正确引导 agent | [技能评测案例](evals/cases.json) |
| 检查技能包、链接与发现入口 | [静态校验脚本](scripts/validate.mjs) |

## 实施时不可破坏的契约

- **先选模型并解析完整配置，再执行启动副作用。** 浏览、取消、保存配置不启动推理代理、不发起付费推理。目录刷新是独立、可取消的只读操作，不混入纯解析。
- TUI 与 CLI 调用相同应用操作；跨语言边界使用有版本的结构化输入输出，不拼 shell 命令、不解析人类可读输出。
- 一个候选绑定来源、账户、额度池、凭证引用、计费面、endpoint、认证头、上游 model map。不得交叉组合，不凭变量名推断套餐权益。
- 同模型换凭证、换来源、转按量付费、换模型是不同策略。未授权的付费兜底和跨模型 fallback 默认关闭；显式选择按量来源不等于授权其他来源的付费兜底。
- 每个请求使用不可变路由快照；凭证健康可按额度池共享，当前模型和在途响应不可跨会话串扰。流式输出开始后不得拼接另一候选的回答或重放已输出的工具调用。
- 模型能力、context、压缩阈值、effort 必须按实际模型和适配器解析；未知不是零、不代表免费、不代表支持。不得冒充 Claude 模型来解锁未验证能力。
- 保留 POSIX `sh`/`dash`、符号链接启动定位、隔离的 `env -i`、原生 `crouter claude` 登录、临时 MCP/插件隔离和进程所有权。开发工具可有多个，产品客户端仍只有 Claude Code。
- 默认不读取真实凭证来验证代码；不把 key/token/cookie 放进源码、argv、日志、截图、测试产物或评测提示词。不采集无关 App 凭证，不绕过授权。
- 不全量重写，不顺手修复无关问题，不把一次提交扩大成发布或账号操作。当前任务授权提交时可以提交；技能本身不授予 push、付费请求、安装或登录权限。

## 验证与交付

先跑受影响的纯逻辑、mock HTTP 和伪终端测试；参照验收矩阵补齐反例。涉及运行时的验收还需遵守现有项目测试门禁。版本相关能力用官方文档加真实版本验证，不只看生成的 JSON。

修改本技能时，在仓库根目录执行：

```sh
node .agents/skills/crouter-development/scripts/validate.mjs
sh test/development-skill.sh
dash test/development-skill.sh
git diff --check
```

这只验证技能包结构，不证明产品功能正确，也不是实际 agent 行为评测。用 `evals/cases.json` 独立检查 agent 的计划和执行证据；未运行的案例标为未运行。

交付报告必须分开写：实现了什么、实际运行并通过的检查、未运行/失败的检查、尚未完成的验收。给出文件和 commit/PR。只在相应测试通过后更新路线图状态；不要把建议、生成文件、启动进程或 CI 排队写成成功。到达用户授权范围内的可验证结果后停止，不擅自扩大范围。
