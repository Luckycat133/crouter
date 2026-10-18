---
name: crouter-maintenance
description: Maintain, test, review, or release the crouter POSIX shell provider-routing framework. Use for providers, authentication surfaces, key pools, lifecycle hooks, gateway routes, session assets, portability, credentials, or release synchronization.
---

# crouter Maintenance

Read `CLAUDE.md` for the full architecture and commands.

## Invariants

- Keep scripts portable under POSIX `/bin/sh`; run syntax checks and tests with both `sh` and `dash` when relevant.
- Keep plan and API credentials bound to their own URL, auth header, key list, and model map.
- Resolve secrets at launch time without printing them. Preserve mode-600 temporary MCP configuration and cleanup.
- Lifecycle cleanup may stop only processes started by the current session.
- Keep maximum context and auto-compaction thresholds separate.
- Preserve direct native Claude login; never route it through an inferred proxy.
- `VERSION` is the runtime release source. Keep it synchronized with the README badge and changelog release entry.

Run focused shell tests first. Before release, run all `test/*.sh` under `sh` and `dash`, syntax checks, ShellCheck when installed, `git diff --check`, and release-version consistency checks.
