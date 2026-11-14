# crouter 开发入口

crouter 只服务 Claude Code：API、订阅、多 Key、本地模型和 App 反代是来源。主线是模型切换方便、凭证自动管理、日常操作交互完成，不发展成多客户端启动器。

## 当前进度入口

使用 [crouter-development](../.agents/skills/crouter-development/SKILL.md)。[基线与证据](../.agents/skills/crouter-development/references/baseline-and-sources.md) 保存审阅 SHA、CI 和用户本地报告；[路线图](../.agents/skills/crouter-development/references/roadmap.md) 是任务状态真源；[当前交接](../.agents/skills/crouter-development/references/implementation-handoff.md) 给出下一批切片。

2026-11-14 已确认 `528a2e1` 的现有 CI 离线门禁成功，DEV-15 已交付。原始 provider 刷新交接中的待测试项是历史快照，不再是当前全量阻塞；原生 Claude 菜单、完整首页体验和账户自动化仍按各任务验收。

```text
/crouter-development 先对照当前 HEAD、基线证据和路线图，保留已通过的 provider/统一路由回归；从当前交接选择一个切片，补真实入口反例后实现。分别报告本轮测试、复核的 CI、用户本地报告与未验证范围。
```

这是下一次开发的调用示例，不是本次技能维护自动执行所有功能的授权。`.claude/skills`、`.codex/skills` 仍指向同一技能；真实客户端是否加载需在对应客户端确认。

## 技能检查

```sh
node .agents/skills/crouter-development/scripts/validate.mjs
node .agents/skills/crouter-development/scripts/validate.test.mjs
TEST_SHELL=sh sh test/development-skill.sh
TEST_SHELL=dash dash test/development-skill.sh
```

技能结构、校验器反例、产品离线 suite、真实客户端、LLM 行为评测分开记录。当前证据的范围和未验证项以基线/验收矩阵为准，不从某一个绿灯推导全功能完成。
