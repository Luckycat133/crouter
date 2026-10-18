---
trigger: always_on
---

# 项目接续要点

按 CLAUDE.md 与 .agents/SKILLS.md 路由；认证/路由/生命周期先读 docs/agent-architecture.md，供应商事实核对 docs/provider-audit.md 及官方资料。凭据与 endpoint/header/tier 绑定，保留 session 隔离，不读写用户凭据来做离线验证。路由或运行时代码变更后，跑受影响离线测试；现有 .githooks/pre-push 保持原样。配置保存、离线契约与真实端到端请求成功分别报告。

<!-- Static counterpart of .codex/hooks/session_start.py CONTEXT; maintain together with CLAUDE.md project context. No runtime hook required. -->
