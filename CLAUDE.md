# crouter contributor context

POSIX `/bin/sh` launcher for Anthropic-compatible providers, with dependency-free Node proxies. `bin/crouter` owns dispatch; `providers/` declares provider contracts; `lib/` handles auth, assets and isolated launches. `install.sh` generates compatibility launchers from provider files.

## Boundaries

- Preserve POSIX portability, symlink-safe self-location and the allowlisted `env -i` launch environment.
- Keep each credential bound to its endpoint, auth header and tier model map. Resolve secrets at launch; never log them or store user keys in provider source.
- `crouter claude` retains native account/login behavior; subscription credentials must not enter provider proxies or the unified gateway.
- Managed MCP files are temporary, mode `0600`, and deleted at exit. Skills/assets are session-scoped and namespaced. Cleanup stops only processes started by that session.
- For auth, routing, lifecycle or provider changes, read [provider and proxy contracts](docs/agent-architecture.md). Provider facts and source provenance live in [provider-audit.md](docs/provider-audit.md); recheck primary sources before changing an audit date.
- The nested `antigravity-claude-proxy/` has its own `CLAUDE.md` and commands.

## Commands and release

Use focused offline tests for the affected behavior. Before release, run every `test/*.sh` under both `sh` and `dash`; the legacy smoke test alone is insufficient.

```sh
for test_file in test/*.sh; do sh "$test_file"; done
for test_file in test/*.sh; do dash "$test_file"; done
sh -n bin/crouter bin/crouter-compat install.sh lib/*.sh providers/*.sh test/*.sh
shellcheck --severity=warning --exclude=SC1007,SC1090,SC1091,SC2034,SC2120 \
  .githooks/pre-push bin/crouter bin/crouter-compat completions/crouter.bash \
  config.example.sh install.sh lib/*.sh providers/*.sh test/*.sh
for file in bin/gateway bin/keypool-proxy lib/*.js lib/*.mjs; do node --check "$file"; done
./bin/crouter --version
git diff --check
```

`VERSION` is the only runtime version source. Keep the README badge and newest CHANGELOG release aligned; retain `Unreleased` for pending changes and order published releases newest first. Install with `./install.sh`; command usage belongs in [README.md](README.md).

<!-- agent-workflow:v1:start -->
## 通用执行约定（2026-09-13）

- 将行动请求执行到可验证结果；用上下文补齐常规细节，只有答案会实质改变结果时才澄清。新消息用于调整当前目标，不因阶段完成而反复询问是否继续。
- 系统/开发者限制优先；用户明确授权高于通用 Skill 默认流程。本块统一通用工作流，保留本项目的产品基线、兼容性、发布、凭据和计费专用门禁。缺少必要授权时先完成可审查的前置工作；已有同范围授权不重复索取。
- 只加载当前任务相关的入口、技能和必要片段；历史日志不是当前状态。规则导致暂停或偏离时，给出准确文件、条款和原因，不把自己的推断说成硬门。
- 默认用简洁段落报告结果和必要证据。独立子任务在工具与权限允许、且能明显节省时间时并行，先分配文件所有权；小任务不强行委派，不默默创建用户侧边栏任务。
- 验证覆盖实际改动和风险；小型文档或可逆改动不自动触发全产品测试。协议、发布、数据迁移等仍执行项目相应门禁。通过后停止重复检查；失败、新改动或未解决风险才扩大测试。
- 分开报告已改、已验证、未执行与阻塞；操作发起不等于结果完成。保留用户工作，未经当前任务授权不提交、推送、发布或改变模型/账户配置。

维护：只同步此标记块；各工具专用正文保留，不强求整份入口相同。项目若明确规定完整镜像，仍保持完整镜像。仅在规则更新或交付涉及规则时检查入口/副本一致性。
<!-- agent-workflow:v1:end -->
