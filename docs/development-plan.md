# crouter 开发入口

crouter 只服务 Claude Code：API、订阅、多 Key、本地推理和 App 反代是模型来源。交互优先，不发展成多客户端启动器。

## 从当前状态继续

使用 [crouter-development](../.agents/skills/crouter-development/SKILL.md)，先读 [当前基线](../.agents/skills/crouter-development/references/baseline-and-sources.md) 与 [路线图](../.agents/skills/crouter-development/references/roadmap.md)。事实和任务状态分别维护，不在本页复制整个完成清单。

```text
/crouter-development 对照当前 HEAD 复核基线和 CI，按路线图优先级完成下一个可验收切片；保留已交付修复，报告实际测试与未验证项。
```

`.agents/SKILLS.md` 和 `CLAUDE.md` 提供路由，`.claude/skills`、`.codex/skills` 指向同一技能真源。符号链接存在不等于目标客户端已实际加载。

## 本轮校准

2026-11-07 对照 `554fd5c5e4a0b6cc8b198565de8c2b4a3495a558` 更新：保留 DEV-01 的历史交付，增加 DEV-15 处理当前集成/CI 阻塞，再继续解析和交互工作。不再写“所有任务 TODO”，也不再把已经修复的 q 搜索、基础目录探测和取消行为当作待开发。

当前安装契约仅创建 crouter；旧连字符快捷入口已退役。裸命令交互首页仍是目标，不应与现有选择器混为一谈。具体兼容性和未验证项见基线与 [验收矩阵](../.agents/skills/crouter-development/references/acceptance.md)。

只更新技能的任务不代表修复了 CI、上线了新交互或完成了账户实测。本轮不改变运行时、凭证、反代安装、版本号或用户设置。

## 技能检查

```sh
node .agents/skills/crouter-development/scripts/validate.mjs
node .agents/skills/crouter-development/scripts/validate.test.mjs
TEST_SHELL=sh sh test/development-skill.sh
TEST_SHELL=dash dash test/development-skill.sh
```

结构校验和反例测试验证技能材料的完整性，不执行产品功能或 LLM 行为评测。现有 CI 的 test/*.sh 循环会包含技能检查，但只有实际运行且成功才可报告通过。
