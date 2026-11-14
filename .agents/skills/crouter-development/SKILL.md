---
name: crouter-development
description: Develop, review and validate crouter, the interactive model and account router exclusively for Claude Code. Use for roadmap and acceptance updates, provider catalogs, TUI, model switching, multi-key and subscription automation, App reverse-proxy sources and regression repair. 中文触发：开发 crouter、审查代码、更新 skill 和 roadmap、模型切换、订阅与 Key、按 skill 验收。Not a multi-client launcher skill.
---

# crouter 项目开发

## 产品边界

使用端只有 Claude Code。API、订阅、多 Key、本地推理与 App 反代是模型来源，不是其他客户端。日常操作以裸 `crouter` 交互为主，脚本保留 `run` 等入口。不另造多客户端平台、强制 Profile 或大型 Web 控制台；现有 app 冻结兼容。只安装 crouter，不恢复退役快捷入口、不覆盖原生 claude。

## 开始任务

1. 读 `AGENTS.md`、`CLAUDE.md`、`.agents/SKILLS.md`，记录 HEAD、工作树、工具环境和本次授权。审查/更新技能不等于授权修改运行时、模型配置或账户。
2. 读 [当前基线](references/baseline-and-sources.md) 与 [路线图](references/roadmap.md)，比较记录 SHA 和实际 HEAD。以源码、断言、对应 SHA 的 CI job/日志核实状态；不照搬旧聊天、提交标题或旧交接中的“待测试”。
3. 区分用户本地报告、已读取的 CI 结果、本轮实际执行、静态代码观察和待验证假设。不把用户报告写成自己的执行，不把 CI 全绿写成真实供应商/Claude UI 全部可用。
4. 按 [接续交接](references/implementation-handoff.md) 选择一个用户可见切片，定义成功、取消/失败、禁止副作用和验收 ID。保留已通过的修复；基线已绿时不反复从修 CI 开始，也不为完成表格先造大框架。
5. 跟踪真实调用链：入口→解析→目录/状态→候选→上游。helper 单测通过不能替代调用者验收；确认 scope、模型身份、费用授权在每一跳都被消费。先补能失败的回归，再实现最小修复。
6. 按风险测试并更新证据。只改技能运行包校验和校验器反例；运行时改动跑受影响用例，广泛改动/发布按现有全量门禁。提交前复核远端 HEAD，保留并发修改，不 force push。

## 按需加载

| 任务 | 参考 |
| --- | --- |
| 接续实现、测试范围和剩余工作 | [接续交接](references/implementation-handoff.md) |
| 首页、模型选择、账户向导、终端体验 | [产品与交互](references/product-and-ux.md) |
| 解析、状态、凭证、调度与并发 | [运行时契约](references/runtime-contracts.md) |
| App 反代、Claude 原生菜单与兼容性 | [适配器与 Claude](references/adapters-and-claude.md) |
| 任务状态、依赖和交付证据 | [路线图](references/roadmap.md) |
| 验收要求及已覆盖/未覆盖子项 | [验收矩阵](references/acceptance.md) |
| 审阅 SHA、CI、本地报告、代码缺口、一手来源 | [基线与来源](references/baseline-and-sources.md) |
| 技能行为评测，不是已执行结果 | [案例](evals/cases.json) |
| 技能结构与校验器回归 | [校验器](scripts/validate.mjs)、[反例测试](scripts/validate.test.mjs) |

provider 更新另读 `crouter-provider-dev`；认证/路由/生命周期另读 `docs/agent-architecture.md`。供应商事实保留各自核查日期，不因测试矩阵通过就更新型号审计日期。旧刷新交接是历史快照，当前基线和路线图才是接续入口。

## 不可破坏的契约

- 先选模型、规范化别名、解析完整配置，再启动 hooks/代理/MCP。保存和启动的 model/context/effort/tier 语义一致；无副作用不等于允许保存无法启动的模型。
- TUI/CLI 共用应用操作；跨语言用明确 argv、结构化结果和退出码。不 eval 用户输入，不拼源码/路径，不解析菜单文本。模型 ID 与人类别名分层校验。
- scope 不只是缓存生产端的字段：主页、网关、状态读取也要验证来源/endpoint/计费面/账户归属与时效。目录可见、凭证存在、模型权限和实际推理成功是不同状态。
- 凭证、计费面、endpoint、认证头、model_map 绑定；不将 API key 推断为套餐 key。同模型换 key、跨来源、按量兜底、跨模型分别授权。Keychain 拒绝不等于未配置，更不能因此默认转付费。
- 模型窗口、输出、压缩、effort、模态使用真实能力和证据；未知不等于免费或支持，不冒充 Claude 身份。保留明确的辅助模型分工。
- 请求采用稳定快照；改默认不广播活动会话。响应提交后不拼接其他候选、不重放工具调用。取消要终止上游和 timer，不能仅关闭 UI。只清理仍属于本会话的资源。
- 保留 POSIX sh/dash、符号链接定位、env -i、原生 Claude 登录、临时 MCP/插件隔离。其他 App 拥有自己的登录边界。
- 离线测试使用临时 HOME/XDG、假凭证和 loopback，不读真实 Keychain/config。秘密不进入源码、argv、日志、截图、fixture 或报告。缺账号仍完成离线部分并报告未验证范围。

## 验证与交付

```sh
node .agents/skills/crouter-development/scripts/validate.mjs
node .agents/skills/crouter-development/scripts/validate.test.mjs
TEST_SHELL=sh sh test/development-skill.sh
TEST_SHELL=dash dash test/development-skill.sh
git diff --check
```

以上只验证技能包和校验器，不是 LLM 行为评测。运行时使用 `TEST_SHELL="$shell" "$shell" "$file"`，syntax 逐文件执行。保留固定 fixture、认证/费用负例；不得从实际输出生成期望值来消红。测试日志中的“Live Gateway”可能只是本地 mock，必须检查 fixture。

交付分别列出改动、本轮执行、复核他人的证据、失败/未执行、剩余风险与 commit/PR。DONE 只表示任务声明范围完成，不能从 CI 绿灯推导整个路线图完成；新发现回归记录到相应任务，不抹去历史通过证据。常规细节采用已有保守默认值，不反复询问已确认的产品方向。
