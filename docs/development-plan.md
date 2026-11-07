# crouter 开发入口

只服务 Claude Code；API、订阅、多 Key、本地与 App 反代都是来源。交互优先，不发展成多客户端启动器。

使用 [crouter-development](../.agents/skills/crouter-development/SKILL.md)。本轮已写入 provider 更新、目录和状态模块、基础交互首页及初步费用边界。请先读 [本轮测试交接](provider-refresh-handoff.md) 和 [全 provider 审计](provider-refresh-2026-11-07.md)，不要再按“只有技能、没有实现”的旧状态接手。

```text
/crouter-development 先阅读本轮 implementation-handoff 与 docs/provider-refresh-handoff.md，核对当前 HEAD，在隔离环境执行新增回归、全 provider 矩阵、旧集成和完整 sh/dash/ShellCheck。修复真实失败并补回归，不弱化断言；报告实际结果和未验证项，再按路线图继续剩余交互。
```

[路线图](../.agents/skills/crouter-development/references/roadmap.md) 是状态真源；[验收矩阵](../.agents/skills/crouter-development/references/acceptance.md) 定义门禁。当前多个任务是 IN_PROGRESS，不是完整完成；真实 Claude 菜单、完整账户/额度池、批量 Key、通用 endpoint、托管反代和可靠流式调度仍需继续。

已有发现符号链接继续指向同一真源。请在实际客户端确认技能加载。技能结构校验不证明产品成功；真实凭证、付费请求、登录和安装需要各自授权。版本号未升级，没有创建 release。
