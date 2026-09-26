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
