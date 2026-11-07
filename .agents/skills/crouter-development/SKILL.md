---
name: crouter-development
description: Develop and validate crouter, an interactive model and account router exclusively for Claude Code. Use for provider catalog refresh, TUI simplification, model switching, multi-key and subscription automation, App reverse-proxy sources, session isolation, regression repair and acceptance. 中文触发：开发 crouter、更新模型、交互改造、管理订阅和 Key、接入反代、按 skill 跑测试。Not a multi-client launcher skill.
---

# crouter 项目开发

## 产品边界

使用端只有 Claude Code。API、订阅、多 Key、本地推理与 App 反代是来源，不是其他客户端。日常操作以裸 `crouter` 交互为主，脚本保留 `run` 等接口。不要另造多客户端平台、强制 Profile 或大型 Web 控制台；现有 app 只保留兼容。只安装 crouter，不复活已退役的连字符快捷入口，也不覆盖用户的 claude。

## 当前接续

本轮用户授权全 provider 更新与继续开发，并指定拉取后由本地 agent 按 skill 跑测试。**先读 [本轮交接](references/implementation-handoff.md)，核对实际 HEAD 与工作树，然后验证已落地切片；不要重新按旧“只有文档、没有首页”的假设开发。** 全量集成、真实客户端与账户验收仍未完成，不因代码提交而标 DONE。

基线/任务状态分别只在参考中维护，主文件不复制不断变化的模型清单。最新源记录在 `docs/provider-review-2026-11-07.json`；每个更新必须有准确日期、来源与验证等级。模型 ID、价格、订阅额度不从记忆补全。

## 工作流程

1. 读 AGENTS.md、CLAUDE.md 和 .agents/SKILLS.md；记录 HEAD、工作树、环境和当前授权。保留用户修改。旧交付报告只证明其当时范围，不代表当前集成。
2. 根据任务只加载下表相关参考。供应商变更另用 crouter-provider-dev；认证/生命周期先读 docs/agent-architecture.md。发现旧参考与已更新来源冲突时记录差异，不复制旧 Key fallback 模板。
3. 定义用户流程、输入输出、取消/失败恢复、禁止副作用和验收 ID。先读对应代码和测试，复现缺陷再做最小修复。
4. 当前测试任务先跑本轮新增用例和 provider 矩阵，再跑旧集成；严格区分缺依赖的 fixture、过时型号预期与真正实现回归。不得用自动重建 golden、删除负例、跳过失败或降低 CI 级别来消红。
5. 缺真实凭证时完成隔离 mock/PTY 部分，报告未验证项目。没有新必要信息不反复问是否继续，不自动读取 Keychain、登录、安装反代或付费验证。

## 按需加载

| 本次任务 | 参考 |
| --- | --- |
| 本次提交后的验证、回归与剩余开发 | [本轮交接](references/implementation-handoff.md) |
| 首页、模型选择、账户向导、终端体验 | [产品与交互](references/product-and-ux.md) |
| 解析、状态、凭证、调度与并发 | [运行时契约](references/runtime-contracts.md) |
| App 反代与 Claude 原生菜单 | [适配器与 Claude](references/adapters-and-claude.md) |
| 任务顺序与状态 | [路线图](references/roadmap.md) |
| 测试层级、反例与完成定义 | [验收矩阵](references/acceptance.md) |
| 历史基线、当前代码定位和一手资料 | [基线与来源](references/baseline-and-sources.md) |
| 技能行为评测 | [案例](evals/cases.json) |
| 技能包结构检查 | [校验器](scripts/validate.mjs) |

## 不可破坏的契约

- 选择与纯解析先于启动。目录读取可以按需取专用凭证；浏览、取消、save-only 不运行 PRE_START、推理代理或 MCP。既有 hook 中的模型归一化要提取或测试，不能机械移动导致选错本地后端。
- TUI/CLI 复用应用操作。shell/Node 间用明确 argv、结构化数据和退出码；不 eval 用户输入，不解析菜单文字。模型 ID 不拼进源码或文件路径。
- 凭证引用、计费面、endpoint、认证头、model_map 绑定；普通 API key 不自动升级成套餐 key。来源等价、费用授权与跨模型授权是独立约束。
- 当前实现仅对显式 surfaces 加入初步付费/跨模型候选门禁，不能宣称旧 dual-source、Keychain 锁定语义或上游自身计费已经全部受控。
- 模型窗口、输出、压缩、effort 和模态按实际能力及来源解析；未知不等于免费或支持。不得通过伪造 Claude 身份来宣称兼容。
- 每个会话/请求使用稳定路由；默认选择改变不广播给活动会话。流式提交后不换候选拼接或重放工具调用。只停止本会话仍拥有的进程。
- 保留 POSIX sh/dash、符号链接定位、隔离 env -i、原生 Claude 登录、临时 MCP/插件隔离；其他 App 自己拥有登录边界。
- 不把秘密放入源码、argv、日志、截图、fixture、报告；离线测试必须使用临时 HOME/XDG、stub 凭证与 loopback，不 source 用户 config.sh。
- 技能不是无限授权。按当前任务提交；不自动发布、升级 VERSION 或扩大付费/安装/账户操作范围。

## 验证与交付

技能包：`node .agents/skills/crouter-development/scripts/validate.mjs`、`node .agents/skills/crouter-development/scripts/validate.test.mjs`，再在 sh/dash 下运行 `test/development-skill.sh`。这不是 LLM 行为评测。

运行时：先读本轮交接中的实际通过/未执行清单，再跑受影响用例及当前 CI 完整门禁。使用 `TEST_SHELL="$shell" "$shell" "$file"`，syntax 逐个文件检查，覆盖 bin/crouter-models、bin/openrouter-models 与所有新增 lib/*.js。没有 ShellCheck/真实平台就准确记录缺失。

交付分别报告已改、实际运行的命令/环境/结果、失败与 skipped、真实客户端/账号未验证、commit 和剩余任务。只在声明范围证据完整时更新 DONE；不得把生成文件、HTTP 目录可读或 CI 排队当成端到端成功。
