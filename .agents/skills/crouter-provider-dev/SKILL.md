---
name: crouter-provider-dev
description: Audit, update and integrate crouter model sources for Claude Code: subscription/API surfaces, exact model IDs, authenticated catalogs, local App proxies, native cloud backends and session tools. Use for provider model/configuration updates and contract regressions. Never infer subscription credentials from generic API keys.
---

# crouter Provider Development

Read CLAUDE.md and the affected runtime contracts. crouter has one client: Claude Code. A model source may be an official Messages API, aggregator, local protocol adapter or native cloud backend. It is not another CLI to launch.

## Evidence first

Inventory every providers/*.sh when asked for an all-provider refresh. Check vendor primary documentation/catalog, exact date, billing product, region and protocol. Keep spelling, case and gateway-specific model IDs; an upstream release does not prove an aggregator or local proxy supports that ID. Native SDK aliases and installed local models must not be replaced by guessed deployments.

Record source URL, date, decision and verification level. The latest dated review is `docs/provider-refresh-2026-11-07.md` with machine-readable provenance. Older provider-audit.md and reference examples are historical, not an authority over newer evidence. A public catalog, an authenticated catalog and an actual tool-enabled inference are different evidence levels.

## Declaration contract

Use current providers and lib/provider.sh, not stale archetype labels, to determine AUTH_MODE. Single API providers may use surfaces; local proxies may use none or static; native backends use native. Keep BASE_URL/PLAN_URL/API_URL as prefixes before /v1/messages. Non-Messages sources require an explicitly tested adapter.

Bind each credential to its surface, endpoint, header and tier map. **Never copy API_KEY into PLAN_KEY, infer subscription rights from a variable name, or silently substitute a charged model for a retired free alias.** Replacing a key is an explicit user operation. Cross-origin catalog redirects never receive credentials.

MODEL / MODEL_OPUS / MODEL_SONNET / MODEL_HAIKU / MODEL_SUBAGENT describe logical tiers. PLAN_MODEL* and API_MODEL* describe actual upstream mappings; fill distinct tiers explicitly to avoid collapsing cheap/fast tiers into a different default. Model equivalence is not display-name equality.

Directory fields are MODELS_DISCOVERY (static/remote/auto/native), MODELS_API_URL, MODELS_API_AUTH (none/bearer/x-api-key/both), MODELS_API_SURFACE (public/api/plan/auth), PLAN_MODELS and API_MODELS. These lists are reviewed seeds, not proof of entitlement. Prefer documented endpoints; unverified probes need a static fallback and an honest note. Public lists get no inference token. Loader resets every optional field between providers.

Keep context, maximum output, compaction and effort separate. Leave unknown limits unset; model-specific audited caps must not be expanded by a generic directory value. Window annotations are client syntax, not permission to guess upstream IDs. Respect local model adapter settings and explicit auxiliary-tier choices.

## Runtime and tools

Select/normalize the model before PRE_START and account/proxy/assets startup. Catalog reads and save-only do not start inference services. Only owned processes may be stopped; shared ports are not ownership proof. Preserve env -i, POSIX sh/dash and native Claude login.

Explicit surfaces now require opt-in to API fallback when plan candidates exist; different model maps require separate cross-model permission. This preliminary gate does not constitute global budgeting, shared quota management or complete Keychain refusal handling. Test both permitted and forbidden routes. Don't weaken the gate to make old tests pass.

Companion MCP/plugins remain temporary, 0600, session-scoped, namespaced and bound to the correct credential. A provider update does not authorize changing global Claude settings or downloading unpinned tools. Unified sessions do not hot-swap MCP assets merely because the model changed.

## Verification and delivery

Before changing code, identify regression inputs and exact observable endpoint/header/model. Use loopback, fake secrets, temporary HOME/XDG and stubs, never real credentials. Update the committed provider fixture only from reviewed evidence; do not generate expected values from the program during tests.

Run affected provider matrix, catalog, model planning, auth/surface/assets and lifecycle tests with `TEST_SHELL=sh` and `TEST_SHELL=dash`. Run ShellCheck and all Node entry syntax checks. Broad refreshes require full existing test/*.sh before declaring the integrated build passed; missing tools/platform/live tests remain explicit unverified items. Only crouter is installed; do not recreate retired compatibility launchers.

Report changed vs retained providers, exact verification level, migration impact, tests actually run, unrun gates and commit. User-authorized repository writes do not automatically authorize real login, installation, paid inference or releases.

## Focused references

Load only the affected material and recheck dated examples against code and evidence:

- [Audit and acceptance](references/audit-and-acceptance.md)
- [Archetypes and templates](references/archetypes-and-templates.md)
- [MCP automation](references/mcp-automation.md)
- [Historical lessons](references/historical-lessons.md)
- [Testing and verification](references/testing-verification.md)
