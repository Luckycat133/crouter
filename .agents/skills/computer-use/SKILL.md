---
name: computer-use
description: Computer use capabilities for Claude Code. Use for desktop control, screen capture, mouse/keyboard automation, shell command execution, and desktop application interaction within safe boundaries.
---

# Computer Use Skill

Scope: desktop automation and computer control capabilities available to Claude Code (shell, file tools, browser automation, screen capture).

## Invariants

- **Minimal privilege**: Prefer read-only operations (read files, list directories, screenshot) over mutating operations (write files, click, type, execute commands) whenever the task allows.
- **Explicit user consent**: Destructive or state-changing actions (deleting files, installing software, modifying system settings, sending network requests that alter remote state) require clear user authorization before execution.
- **No hidden automation**: Do not run background loops, daemons, or unattended agents that continue operating without user awareness. All computer use should be bounded to the current task session.
- **Sandbox awareness**: Respect the sandboxed execution environment. Do not attempt to escape container boundaries, access unrelated user directories, or escalate privileges.
- **Evidence trail**: Log what was done (command run, file changed, URL visited) so the user can review and verify. Report outcomes faithfully — success, partial success, or failure.

## When to use

- Running shell commands via Bash to inspect or modify the local environment.
- Capturing screenshots or viewing screen content to understand UI state.
- Browser automation (Playwright) for web interactions.
- Reading/writing files to inspect or modify project state.
- Desktop application interaction when no API/CLI alternative exists.

## Verification

- Before mutating commands, preview the exact command and its expected effect.
- After file/system changes, verify the resulting state matches intent (e.g., `git diff`, file existence, command exit code).
- Report what succeeded, what failed, and any side effects observed.
