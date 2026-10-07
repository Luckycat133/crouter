# Project: crouter Comprehensive Audit & Auto-Correction

## Architecture
- **Provider Layer (`providers/*.sh`)**: 38 shell scripts exporting model tiers (`MODEL_OPUS`, `MODEL_SONNET`, `MODEL_HAIKU`, `MODEL_SUBAGENT`), API/Plan surface tiers (`API_MODEL_*`, `PLAN_MODEL_*`), context windows (`CONTEXT_TOKENS`), context overrides (`MODEL_CONTEXT_OVERRIDES`), effort, and aliases (`MODEL_ALIASES`).
- **Core Runtime & Dispatcher (`bin/crouter`, `lib/provider.sh`, `lib/route-build.js`)**: Resolves active provider, evaluates surface candidates, builds candidate mapping tables (`model_map`), and sets up client runtime environment.
- **Proxy Layer (`antigravity-claude-proxy/`, `bin/keypool-proxy`, `bin/gateway`, `lib/anthropic-openai-proxy.mjs`)**: Translates client requests to upstream endpoints, handles model rewriting, authentication token generation, key rotation, and health checks.
- **Contract & Test Suite (`test/*.sh`, `.githooks/pre-push`)**: 38 hermetic offline contract tests asserting provider variables, routing behavior, lifecycle, and POSIX sh / dash compliance.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | OpenRouter Active Default Model | Eliminate deprecated `qwen/qwen3.8-27b:free` slug that returns HTTP 404, pointing to active `qwen/qwen3.8-27b` | M1 | Survey 1 |
| 2 | SiliconFlow API Haiku Alignment | Declare `API_MODEL_HAIKU="deepseek-ai/DeepSeek-V4-Flash"` to prevent collapsing Haiku queries into flagship on API surface | M1 | Survey 1 |
| 3 | StepFun API Haiku & Subagent Alignment | Declare `API_MODEL_HAIKU="step-3.7-flash"` and `API_MODEL_SUBAGENT="step-3.7-flash"` on API surface | M1 | Survey 1 |
| 4 | Huawei API Haiku Alignment | Declare `API_MODEL_HAIKU="deepseek-v4.1-flash"` on API surface | M1 | Survey 1 |
| 5 | Moonshot 1M Context Window Override | Add `MODEL_CONTEXT_OVERRIDES="k3[1m]=1000000"` in `providers/moonshot.sh` to allow full 1M context token window | M1 | Survey 1 |
| 6 | Antigravity Tiered Model Aliases | Add `gemini-3.8-flash-tiered` and `gemini-3.7-flash-tiered` to `MODEL_ALIASES` in `providers/antigravity.sh` | M1 | Survey 1 & 2 |
| 7 | Antigravity Claude Proxy Fallback Map | Add `gemini-3.8-flash`, `gemini-3.8-flash-tiered`, `gemini-3.7-flash-tiered` to `MODEL_FALLBACK_MAP` in `src/constants.js` | M2 | Survey 1 & 2 |
| 8 | Proxy Example Config Completeness | Include `modelMapping` block in `antigravity-claude-proxy/config.example.json` | M2 | Survey 2 |
| 9 | GPT-OSS Patch Verification on Launch | Ensure `lib/antigravity-common.sh` checks and runs `bin/antigravity-proxy-patch` if needed | M2 | Survey 2 |
| 10 | Keypool & Gateway HTTP 400 Prevention | Verify candidate mapping in `bin/keypool-proxy` and `bin/gateway` prevents unmapped model 400 errors | M2 | Survey 2 |
| 11 | README Documentation Reconcile | Fix context token column in `README.md` table for 7 mainland providers (`983,616` and `262,144` instead of `—`) | M3 | Survey 1 |
| 12 | Provider Audit Documentation Reconcile | Update stale descriptions in `docs/provider-audit.md` (Qianfan Team defaults, context injection) | M3 | Survey 1 |
| 13 | Test Suite Matrix Verification | Update `test/provider-matrix.sh` and related tests to assert corrected models and aliases under `sh` and `dash` | M3 | Survey 3 |
| 14 | Pre-push and Syntax Verification | Validate `sh .githooks/pre-push` and `node --check` across all proxy scripts | M3 | Survey 3 |
| 15 | Adversarial Verification & Forensic Audit | Run Reviewers, Challengers, and Forensic Auditor for final acceptance gate | M4 | Survey 1, 2, 3 |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Provider Configurations Audit & Auto-Correction | Correct models and aliases in `providers/openrouter.sh`, `siliconflow.sh`, `stepfun.sh`, `huawei.sh`, `moonshot.sh`, `antigravity.sh` | None | IN_PROGRESS |
| M2 | Proxy Routing Contract Validation & Auto-Correction | Update `antigravity-claude-proxy` fallback map, example config, patch hooks | M1 | IN_PROGRESS |
| M3 | Test Suite & Documentation Verification | Update `test/provider-matrix.sh`, `README.md`, `docs/provider-audit.md`, verify tests under sh/dash | M1, M2 | IN_PROGRESS |
| M4 | Final Acceptance Gate & Forensic Audit | Reviewers, Challengers, Forensic Auditor verification of all acceptance criteria | M1, M2, M3 | PLANNED |

## Interface Contracts
### Provider Script Contract (`providers/<name>.sh`)
- Must define: `MODEL`, `DEFAULT_MODEL_OPUS`, `DEFAULT_MODEL_SONNET`, `DEFAULT_MODEL_HAIKU`, `DEFAULT_MODEL_SUBAGENT` (or fall back to `MODEL`).
- If dual-surface (API + Plan), must define: `API_MODEL_*` and `PLAN_MODEL_*` for every tier where distinct models are intended.
- If context window overrides exist, must define: `MODEL_CONTEXT_OVERRIDES="alias=tokens..."`.
- Must pass `sh -n` and `dash -n` without syntax errors.

### Antigravity Claude Proxy Contract (`antigravity-claude-proxy/`)
- `config.modelMapping`: Translates `gemini-3.8-flash -> gemini-3.8-flash-tiered`, `gemini-3.7-flash -> gemini-3.7-flash-tiered`.
- `constants.MODEL_FALLBACK_MAP`: Fallback targets for tiered models under quota exhaustion.
- Must not throw `invalid_request_error: Invalid model: ...` for valid declared models.

## Code Layout
- `providers/*.sh`: Provider configuration files. Owned by Worker.
- `antigravity-claude-proxy/`: Local proxy configuration and runtime. Owned by Worker.
- `lib/antigravity-common.sh`: Common startup hooks for antigravity. Owned by Worker.
- `test/*.sh`: Test suites. Owned by Worker.
- `README.md`, `docs/provider-audit.md`: Documentation. Owned by Worker.
