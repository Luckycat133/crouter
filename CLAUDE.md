# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

- **Run Smoke Tests**: `./test/smoke.sh`
- **Install Local Binary & Compatibility Launchers**: `./install.sh`
- **Lint Shell Scripts**: `shellcheck bin/crouter bin/crouter-compat install.sh test/smoke.sh providers/*.sh lib/*.sh`
- **Run Framework Entry Point**: `./bin/crouter list` (or `doctor`, `add <provider>`, `remove <provider> --name <service>`, `list keys <provider>`, `all`)

## Architecture & Code Structure

`crouter` is a POSIX `/bin/sh` adapter framework that provides a single, portable entry point to launch Claude Code against multiple Anthropic-compatible LLM providers.

### Execution Flow

1. **Self-Location**: `bin/crouter` dynamically resolves its absolute path following symlinks using `readlink` with `CDPATH=` to ensure safety across environments.
2. **Configuration & Provider Contracts**: Sourcing `config.sh` (gitignored local overrides) followed by `providers/<name>.sh`. Providers set declarative variables:
   - `BASE_URL`, `MODEL`, `CONTEXT_TOKENS`, `EFFORT` (reasoning effort: `low`|`medium`|`high`|`xhigh`|`max`, passed to Claude Code as `--effort`)
   - `CONTEXT_TOKENS`: upstream model's default context window in tokens. Sets `CLAUDE_CODE_MAX_CONTEXT_TOKENS` at launch. If omitted, the variable is not injected and Claude Code uses its own default.
   - `MODEL_CONTEXT_OVERRIDES`: optional whitespace-separated exact-model overrides in `model=context` form, applied after `--model` / positional model resolution.
   - Model aliases: `MODEL_OPUS`, `MODEL_SONNET`, `MODEL_HAIKU`, `MODEL_SUBAGENT`
   - `AUTH_MODE`: `keychain`, `env`, `command`, `static`, `none`, or `keypool`
   - `AUTH_REFERENCE`: Keychain service name, environment variable name, or command
   - `AUTH_KEYCHAIN_FALLBACK`: optional Keychain service name used when `AUTH_MODE=env` and the env var is unset (lets a provider accept both "export the key" and "store it in the Keychain" without a second AUTH_MODE).
   - Dual-source (`anthropic`/`openrouter`, replaces `AUTH_MODE`): `DEFAULT_URL`, `DEFAULT_AUTH_TYPE`, `DEFAULT_TOKEN_ENV`, `DEFAULT_TOKEN_ENV_FALLBACK` for the preferred account; `API_URL`, `API_AUTH_TYPE`, `API_KEY_ENV`, `API_KEY_REF` for the fallback key. `is_dual_source()` detects them; `load_provider()` must reset every one of these or values leak across providers.
   - Lifecycle hooks: `PRE_START`, `POST_STOP`, `HEALTH_CHECK_URL`
3. **Lifecycle Hooks**: `PRE_START` hook runs prior to launch (e.g. `antigravity_ensure_gateway` auto-starts the local proxy and polls `/health`).
4. **Credential Resolution**: `AUTH_TOKEN` is resolved at launch time without exposing secrets in process environments or disk storage. Dual-source providers go through `resolve_dual_source()`, which discovers *both* surfaces, picks the default account as the active one, and sets `_AUTH_SCHEME` (`bearer` / `x-api-key`). `lib/launch.sh` injects only the matching header env (`ANTHROPIC_AUTH_TOKEN` vs `ANTHROPIC_API_KEY`) — sending an Anthropic OAuth token as `x-api-key` would be rejected. Legacy providers leave `_AUTH_SCHEME` unset and keep the historical both-headers behavior.
   When both surfaces exist, `start_dual_failover()` fronts them with `bin/keypool-proxy` in candidate mode so 401/429 rotation happens mid-session; `launch.sh` treats any non-empty `KEYPOOL_URL` as "a local proxy owns auth".
5. **Isolated Execution**: Launches Claude Code via `env -i` with a clean, terminal-safe minimal environment (`HOME`, `PATH`, `TERM`, `LANG`, etc.) and injected `ANTHROPIC_*` environment variables.

### Subcommands

Subcommands are flat: `crouter <verb> [args]`. Verbs: `<provider> [<model>]` (default — launch; a bare positional before any flag selects the model), `list [keys [provider]]`, `doctor [provider]`, `add <provider> [--surface main|plus] [--name <service>]`, `remove <provider> --name <service> [--surface main|plus] [-y]`, `all` (unified gateway). The three key-management verbs (`add` / `remove` / `list keys`) operate on a keypool provider's `AUTH_KEYS` / `PLUS_KEYS` list and the matching macOS Keychain entries; `add` reads the secret from `/dev/tty` so it never appears in argv or shell history. `all` starts a local Anthropic-protocol gateway (`bin/gateway`, dependency-free Node) that fronts every provider behind one `ANTHROPIC_BASE_URL`; Claude Code switches providers live via `/model <provider>/<model>` (routed by prefix, with per-provider auth and keypool key rotation).

### File Layout

- `bin/crouter`: Core entry point owning launcher execution, auth lookup, key-management commands, environment isolation, and the `all` unified-gateway command.
- `bin/gateway`: Dependency-free Node Anthropic-protocol router used by `crouter all`. Reads a routes JSON (one entry per provider: `prefix`, `base_url`, `candidates[]`, `models`), serves `GET /v1/models` (combined namespaced catalog) and `POST /v1/messages` (route by the *first* `<provider>/` model segment to the right backend). Each candidate is a full auth surface (`url` + `auth{type,token}` + `extra_env`); the gateway tries them in order and fails over on 401/429 — this is the single mechanism behind both keypool key rotation and dual-source default→API fallback.
- `bin/keypool-proxy`: Local failover proxy. Legacy mode = `KEYPOOL_KEYS` x `KEYPOOL_TARGETS` (all keys sent as both `x-api-key` and Bearer). Candidate mode = `KEYPOOL_CANDIDATES` JSON (`[{url,type,token,label}]`) with per-candidate header shape; used by dual-source direct launches.
- `bin/claude-*`: Compatibility launchers — symlinks to `bin/crouter-compat` that delegate to specific provider commands (the provider is derived from the invoked name). `install.sh` generates one per file in `providers/`, so adding a provider needs no edit there.
- `providers/`: Provider definitions (`anthropic.sh`, `openai.sh`, `openrouter.sh`, `codex.sh` for ChatGPT/Codex 订阅 via icebear0828/codex-proxy, `minimax.sh`, `antigravity.sh` for Gemini, `antigravity-claude.sh` for Claude, `deepseek.sh`, `ollama.sh` for local/cloud Ollama models via its native Anthropic API).
- `lib/`: Shared shell modules sourced by `bin/crouter` (`provider.sh`, `auth.sh`, `key-mgmt.sh`, `launch.sh`) plus `antigravity-common.sh` (proxy management, sourced by the two antigravity providers) and `route-build.js` (dependency-free Node; builds the gateway routes JSON and the keypool-proxy candidate array — subcommands `candidates`, `dual-candidates`, `combine`, `default-model`. The shell owns credential discovery; this file owns the JSON shapes).
- `install.sh`: Creates executable symlinks in `$INSTALL_DIR` (`~/.local/bin`) and copies `config.example.sh` to `config.sh`.
- `test/smoke.sh`: Hermetic offline smoke test suite (with stubs for `security(1)` / `node(1)` so key-management paths run without a real Keychain or Node).
