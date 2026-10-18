# Curated Project Skill Routing

This repository keeps task-specific Skills in .agents/skills. Codex and Claude entry directories point to the same project-owned copies where links are present.

This table records the Skills reviewed or added by the 2026-09-11 audit; it does not remove or replace other project-owned Skills already present in the repository.

Load only the Skill whose trigger matches the current task. A Skill may be reused by several projects, and this project may use several Skills. Existing repository instructions and the user's current request take priority over a Skill.

| Skill | Use here for |
|---|---|
| [crouter-runtime-diagnostics](skills/crouter-runtime-diagnostics/SKILL.md) | Existing provider/client failures, redacted route evidence, streaming/tool and local-proxy diagnosis |
| `crouter-maintenance` | Provider contracts, auth isolation, lifecycle, gateway, portability, and releases |
| `crouter-provider-dev` | Universal provider development across all 5 archetypes, using the relevant contract stages (docs audit, parameters, session MCP assets, routing, and verification) |
| `crouter-provider-plan` | Provider subscription plans (Coding/Agent/Token Plan), dual-surface auth, session MCP assets, and matrix tests |
| `github-actions` | Shell-project CI workflow design and debugging |

## Maintenance rules

- Keep domain and implementation Skills in the project instead of the global Codex Skill directory.
- Preserve project-specific Skills as the source of truth; do not replace them with an archived global copy.
- Prefer links for IDE-specific discovery so Codex and Claude read the same maintained content.
- Add or expand a Skill only when it captures repeatable project knowledge that is not already clear from code or repository documentation.
- For small changes, run focused checks first and expand testing only when failures, risk, or new scope justify it.
