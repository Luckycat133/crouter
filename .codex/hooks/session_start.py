#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Read-only SessionStart context; malformed or out-of-scope input fails open."""
import json
import sys
from pathlib import Path

CONTEXT = '按 CLAUDE.md 与 .agents/SKILLS.md 路由；认证/路由/生命周期先读 docs/agent-architecture.md，供应商事实核对 docs/provider-audit.md 及官方资料。凭据与 endpoint/header/tier 绑定，保留 session 隔离，不读写用户凭据来做离线验证。路由或运行时代码变更后，跑受影响离线测试；现有 .githooks/pre-push 保持原样。配置保存、离线契约与真实端到端请求成功分别报告。'
ROOT = Path(__file__).resolve().parents[2]

def in_project(raw):
    if not isinstance(raw, str) or not raw or not Path(raw).is_absolute():
        return False
    current = Path(raw).resolve(strict=True)
    if not current.is_dir() or (current != ROOT and ROOT not in current.parents):
        return False
    # A nested repository or separately instructed project owns its context.
    while current != ROOT:
        if any((current / marker).exists() for marker in
               ('.git', 'AGENTS.md', 'AGENTS.override.md', '.codex/config.toml', '.codex/hooks.json')):
            return False
        current = current.parent
    return True

def main():
    result = {}
    try:
        raw = sys.stdin.buffer.read(65537)
        if len(raw) <= 65536:
            data = json.loads(raw)
            if (isinstance(data, dict) and data.get('hook_event_name') == 'SessionStart'
                    and data.get('source') in ('startup', 'resume', 'compact', 'clear')
                    and in_project(data.get('cwd')) and in_project(str(Path.cwd()))):
                result = {'hookSpecificOutput': {'hookEventName': 'SessionStart',
                                                'additionalContext': CONTEXT}}
    except (ValueError, TypeError, OSError, RuntimeError):
        pass
    print(json.dumps(result, ensure_ascii=False))

if __name__ == '__main__':
    main()
