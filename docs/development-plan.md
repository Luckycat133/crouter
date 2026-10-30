# crouter 开发入口

产品定位：**让用户在 Claude Code 中方便地选择模型，由 crouter 管理 API、订阅、多 Key、本地模型和 App 反代来源。** 不发展成多客户端启动器。下一版先完成交互闭环，再完善原生模型菜单、账户调度与反代管理。

## 给开发 agent

使用 [crouter-development](../.agents/skills/crouter-development/SKILL.md)。Claude Code 项目技能入口支持显式调用：

```text
/crouter-development 按路线图从最早未完成的 P0 任务开始；先检查当前代码和回归测试，再实现交互闭环，报告实际验证结果。
```

也可自然语言要求 agent 按该技能继续开发。项目 `.agents/SKILLS.md` 和 `CLAUDE.md` 已提供路由；`.claude/skills`、`.codex/skills` 指向同一真源。实际客户端加载仍需在对应客户端确认。

## 任务与验收

[路线图](../.agents/skills/crouter-development/references/roadmap.md) 是 DEV-01～DEV-14 的状态真源；[验收矩阵](../.agents/skills/crouter-development/references/acceptance.md) 定义用户流程和失败路径。旧 `PROJECT.md` 保留历史审计，不能当作这轮产品主线的完成记录。

默认策略：仅在启用来源内同模型切换；未授权不转按量付费、不跨模型；常用操作交互完成，不强制创建 Profile。其他 App 反代优先级未指定，不阻塞通用 endpoint 与现有 Antigravity 的开发。

## 本次交付状态

已添加开发技能、分模块参考、任务与验收、技能评测案例、发现链接和静态校验。**未因这些文件的提交而实现新 TUI 或修改运行时；产品任务仍从 TODO 开始。** 不包含真实账号验证、凭证读取、反代安装或版本发布。

静态检查：

```sh
node .agents/skills/crouter-development/scripts/validate.mjs
sh test/development-skill.sh
dash test/development-skill.sh
```

现有 CI 的 `test/*.sh` 循环会包含该检查。它校验包结构与链接，不会运行案例中的 LLM 行为评测，也不能替代产品回归或真实 Claude Code 验证。
