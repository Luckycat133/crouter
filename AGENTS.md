# crouter contributor context

POSIX `/bin/sh` launcher for Anthropic-compatible providers, with dependency-free Node proxies. `bin/crouter` owns dispatch; `providers/` declares provider contracts; `lib/` handles auth, assets and isolated launches. `install.sh` installs only `crouter`; the retired `claude-<provider>` launchers are not generated.

## 产品主线

crouter 只服务 Claude Code：API、订阅、多 Key、本地推理和 App 反代是模型来源，不是要启动的其他客户端。下一版交互优先，让用户从 `crouter` 完成模型选择与账户管理；现有 `app` 入口仅保留兼容，不继续扩展。开发该主线时先加载 [.agents/skills/crouter-development/SKILL.md](.agents/skills/crouter-development/SKILL.md)，按需读取参考与验收；人类开发入口见 [docs/development-plan.md](docs/development-plan.md)。计划中的行为不等于当前版本已实现。

## Boundaries

- Preserve POSIX portability, symlink-safe self-location and the allowlisted `env -i` launch environment.
- Keep each credential bound to its endpoint, auth header and tier model map. Resolve secrets at launch; never log them or store user keys in provider source.
- `crouter claude` retains native account/login behavior; native Claude account subscription credentials must not enter provider proxies or the unified gateway. Explicitly authorized App reverse-proxy sources keep their own authentication boundary.
- Managed MCP files are temporary, mode `0600`, and deleted at exit. Skills/assets are session-scoped and namespaced. Cleanup stops only processes started by that session.
- For auth, routing, lifecycle or provider changes, read [provider and proxy contracts](docs/agent-architecture.md). Provider facts and source provenance live in [provider-audit.md](docs/provider-audit.md); recheck primary sources before changing an audit date.
- The nested `antigravity-claude-proxy/` has its own `CLAUDE.md` and commands.

## Commands and release

Use focused offline tests for the affected behavior. Before release, run every `test/*.sh` under both `sh` and `dash`; the legacy smoke test alone is insufficient. Run from an isolated checkout, propagate TEST_SHELL and retain failures. Syntax checks must visit each file, not pass later filenames as shell positional arguments.

```sh
failed=0
for shell in sh dash; do
  for test_file in test/*.sh; do
    TEST_SHELL="$shell" "$shell" "$test_file" || failed=1
  done
  for file in bin/crouter install.sh lib/*.sh providers/*.sh test/*.sh; do
    "$shell" -n "$file" || failed=1
  done
done
test "$failed" -eq 0 || exit 1
shellcheck --severity=warning --exclude=SC1007,SC1090,SC1091,SC2034,SC2120 \
  .githooks/pre-push bin/crouter completions/crouter.bash \
  config.example.sh install.sh lib/*.sh providers/*.sh test/*.sh || exit 1
for file in bin/gateway bin/keypool-proxy bin/crouter-models bin/openrouter-models lib/*.js lib/*.mjs; do
  node --check "$file" || exit 1
done
./bin/crouter --version || exit 1
git diff --check
```

`VERSION` is the only runtime version source. Keep the README badge and newest CHANGELOG release aligned; retain `Unreleased` for pending changes and order published releases newest first. Install with `./install.sh`; command usage belongs in [README.md](README.md).

## 项目技能入口

按当前任务从 `.agents/SKILLS.md` 选择技能；`.claude/skills` 仅提供发现入口，正文维护在项目现有真源。不要一次加载全部技能。

## 当前任务接续提醒（2026-10-06）

按 `AGENTS.md` 与 `.agents/SKILLS.md` 路由；认证/路由/生命周期先读 docs/agent-architecture.md，供应商事实核对 docs/provider-audit.md 及官方资料。凭据与 endpoint/header/tier 绑定，保留 session 隔离，不读写用户凭据来做离线验证。路由或运行时代码变更后，跑受影响离线测试；现有 .githooks/pre-push 保持原样。配置保存、离线契约与真实端到端请求成功分别报告。

此处承载静态上下文；不另设只重复文本的 Claude SessionStart 钩子。

## 项目接续钩子（2026-10-03）

本项目 Codex 配置仅用于 SessionStart 的短提示；行为、边界和客户端信任说明见 [.codex/hooks/README.md](.codex/hooks/README.md)。配置自检不等于原生客户端已加载，也不替代当前任务验证。
