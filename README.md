# crouter

[![CI](https://github.com/Luckycat133/crouter/actions/workflows/ci.yml/badge.svg)](https://github.com/Luckycat133/crouter/actions/workflows/ci.yml)
![Version](https://img.shields.io/badge/version-0.5.1-blue)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

`crouter` launches Claude Code against audited Anthropic-compatible providers
without copying provider credentials into this repository. It keeps Token Plan
keys, pay-as-you-go API keys, endpoints, auth headers, and model mappings as
separate routing surfaces. It fails over on HTTP 401/402/403/429 without
restarting Claude Code and temporarily cools down an exhausted candidate so
the next request does not immediately spend another retry on it.

The current provider values were checked against vendor documentation on
2026-08-08. See [docs/provider-audit.md](docs/provider-audit.md) for the source
matrix and decisions.

Release 0.5.1 is implementation-complete against the repository's offline
contract suite under POSIX `sh` and `dash`. Live catalog access, remaining
quota, and account entitlement still require the account owner's credentials
and may incur provider charges.

## Table of contents

- [Install](#install)
- [Usage](#usage)
- [Provider catalog](#provider-catalog)
- [Token Plan and API key isolation](#token-plan-and-api-key-isolation)
- [Provider MCPs and skills](#provider-mcps-and-skills)
- [Unified gateway](#unified-gateway)
- [Native Bedrock and Vertex](#native-bedrock-and-vertex)
- [Antigravity and local providers](#antigravity-and-local-providers)
- [Adding a provider](#adding-a-provider)
- [Security](#security)
- [Development](#development)
- [Maintenance and license](#maintenance-and-license)

## Install

```sh
./install.sh
crouter list
```

The installer creates `crouter` and one `claude-<provider>` compatibility
shortcut per file in `providers/`. Re-run it after moving the repository or
adding/removing providers.

Requirements:

- Claude Code
- Node.js (for the local keypool and unified gateway)
- macOS Keychain's `security` command when using Keychain credentials
- `uvx` only for the MiniMax Token Plan MCP

`config.sh` is optional and gitignored. Copy `config.example.sh` when local
overrides are needed.

## Usage

```sh
crouter list
crouter provider show dashscope
crouter doctor minimax

crouter claude                     # native Claude account login
crouter anthropic                  # Anthropic Console API key
crouter minimax
crouter dashscope qwen3.7-max
crouter deepseek --model 'deepseek-v4-pro[1m]'

crouter add minimax --surface plan
crouter add minimax --surface api
pass show minimax/plan | crouter add minimax --surface plan --stdin
crouter list keys minimax
crouter remove minimax --surface api --name minimax-api-2

crouter all --check               # redacted route proof, no launch/network
crouter all
```

The first bare argument before any flag is a primary-model override. Remaining
arguments are forwarded to Claude Code.

## Provider catalog

An empty context means crouter deliberately does not inject a client-side
limit; the selected vendor model or native backend remains authoritative.

| Provider | Billing surfaces | Default model | Context | Managed assets |
| --- | --- | --- | ---: | --- |
| `302ai` | API | `claude-sonnet-5` | 1,000,000 | — |
| `aihubmix` | API | `coding-glm-5.1-free` | — | API MCP |
| `anthropic` | Console API key | `claude-sonnet-5` | — | — |
| `antigravity` | local proxy | `gemini-3.7-flash-tiered` | 1,048,576 | — |
| `antigravity-claude` | local proxy | `claude-opus-4-6-thinking` | 200,000 | — |
| `bedrock` | native AWS credentials | `sonnet` alias | — | — |
| `codex` | local ChatGPT subscription proxy | `gpt-5.6-sol` | 1,050,000 | — |
| `dashscope` | Token Plan + API | `qwen3.8-max` | 983,616 | Plan media skill + API WebSearch MCP |
| `dashscope-coding` | Coding Plan | `qwen3.7-plus` | — | — |
| `deepseek` | API | `deepseek-v4-pro[1m]` | 1,000,000 | native web search |
| `huawei` | Token Plan + API | `glm-5.1` | — | — |
| `infini` | GenStudio API | `glm-5.1` | — | — |
| `minimax` | Token Plan + API | `MiniMax-M3` | 1,048,576 | Plan MCP + CLI skill |
| `moonshot` | Kimi Code membership | `k3-256k` | 262,144 | — |
| `ollama` | local | `glm-4.7-flash` | 65,536 | — |
| `openrouter` | API | `openrouter/free` | — | — |
| `ppio` | API | `minimax/minimax-m3` | 1,000,000 | cloud OAuth MCP |
| `qianfan` | personal Token Plan + API | `deepseek-v4-pro` | — | — |
| `qianfan-team` | team Token Plan | `deepseek-v3.2` | — | — |
| `qianfan-coding` | legacy Coding Plan | `qianfan-code-latest` | — | — |
| `qiniu` | enterprise subscription + API | `deepseek/deepseek-v3.2-251201` | — | optional managed MCPs |
| `siliconflow` | API | `Pro/moonshotai/Kimi-K2.6` | — | — |
| `stepfun` | Step Plan + API | `step-3.7-flash` | 262,144 | StepSearch MCP + skill |
| `tencent` | personal Token Plan + TokenHub API | `tc-code-latest` | — | optional WebSearch MCP |
| `tencent-coding` | Coding Plan | `tc-code-latest` | — | — |
| `vertex` | native Google ADC | `sonnet` alias | — | — |
| `volcengine` | Ark Coding Plan | `doubao-seed-2.0-code` | — | public docs MCP |
| `xiaomi` | Token Plan + API | `mimo-v2.5-pro[1m]` | 1,048,576 | — |
| `z-ai` | Coding Plan + API | `glm-5.2[1m]` | 1,000,000 | vision/search/reader/zread MCPs |

DeepSeek additionally follows its official 786,432-token automatic compaction
threshold; this is kept separate from its 1M maximum context.

OpenAI and Baichuan are intentionally absent. Their official APIs do not expose
an Anthropic Messages base URL that Claude Code can call directly. `codex`
continues to support a ChatGPT subscription through its explicitly documented
local translation proxy; crouter does not mislabel OpenAI's normal API as
Anthropic-compatible.

## Token Plan and API key isolation

Domestic providers use `AUTH_MODE="surfaces"`. Each candidate owns all of the
following together:

- its Token Plan or API key;
- its exact base URL;
- its auth header type (`bearer` or `x-api-key`);
- its per-tier upstream model map.

Keys are never multiplied across URLs. For example, DashScope's plan key stays
on the Token Plan endpoint and maps Opus/Sonnet/Haiku/Subagent to the plan's
Qwen catalog; an API key stays on the pay-as-you-go endpoint and maps the same
logical tiers to the API catalog. Explicit models outside that tier map pass
through unchanged.

Environment credentials take priority, followed by built-in Keychain services
and user-added services in the local key registry:

| Provider | Plan environment variable | API environment variable |
| --- | --- | --- |
| `302ai` | — | `AI302_API_KEY` |
| `aihubmix` | — | `AIHUBMIX_API_KEY` |
| `minimax` | `MINIMAX_TOKEN_PLAN_KEY` | `MINIMAX_API_KEY` |
| `moonshot` | `KIMI_CODE_KEY` | — |
| `z-ai` | `Z_AI_CODING_PLAN_KEY` | `Z_AI_API_KEY` |
| `dashscope` | `DASHSCOPE_TOKEN_PLAN_KEY` | `DASHSCOPE_API_KEY` |
| `dashscope-coding` | `DASHSCOPE_CODING_PLAN_KEY` | — |
| `deepseek` | — | `DEEPSEEK_API_KEY` |
| `stepfun` | `STEPFUN_PLAN_KEY` | `STEPFUN_API_KEY` |
| `volcengine` | `VOLCENGINE_CODING_PLAN_KEY` | — |
| `tencent` | `TENCENT_TOKEN_PLAN_KEY` | `TENCENT_API_KEY` |
| `tencent-coding` | `TENCENT_CODING_PLAN_KEY` | — |
| `qianfan` | `QIANFAN_TOKEN_PLAN_KEY` | `QIANFAN_API_KEY` |
| `qianfan-team` | `QIANFAN_TEAM_TOKEN_PLAN_KEY` | — |
| `qianfan-coding` | `QIANFAN_CODING_PLAN_KEY` | — |
| `qiniu` | `QINIU_SUBSCRIPTION_KEY` | `QINIU_API_KEY` |
| `siliconflow` | — | `SILICONFLOW_API_KEY` |
| `huawei` | `HUAWEI_TOKEN_PLAN_KEY` | `HUAWEI_API_KEY` |
| `infini` | — | `INFINI_API_KEY` |
| `ppio` | — | `PPIO_API_KEY` |
| `xiaomi` | `XIAOMI_TOKEN_PLAN_KEY` | `XIAOMI_API_KEY` |

Use `crouter provider show <name>` to inspect the URL, auth type, Keychain
service names, and tier maps without revealing secrets.

### Key management

`crouter add` stores only the secret in macOS Keychain. The first key fills the
provider's built-in service; subsequent keys get names such as
`minimax-plan-2` in a mode-600 registry under `.state/keypools/`. Provider files
are never edited, so an upgrade cannot overwrite the user's pool. Use `--name`
for a stable service name and `--stdin` with a password manager or CI; the key
never appears in process arguments.

For a provider with both surfaces, candidate order is plan environment key,
plan Keychain pool, API environment key, then API Keychain pool. `crouter list
keys <provider>` reports which references exist without printing their values.

### Failover behavior

Direct launches start a localhost-only proxy for surface providers. It tries
credentials in declaration order and advances on 401/402/403/429 or connection
failure. HTTP 403 is included because some plans report expired or missing
entitlements with that status. A rejected candidate is cooled down for five
minutes by default, or for the upstream `Retry-After` duration when longer.
Set `CROUTER_CANDIDATE_COOLDOWN_MS` to a non-negative millisecond value to
change the floor.
The proxy rewrites only known logical tier models for the active surface and
preserves other model IDs. It is stopped when Claude Code exits.

### Anthropic account and API access

`crouter claude` is a transparent native launch: it preserves Claude Code's
stored `/login` session, `CLAUDE_CODE_OAUTH_TOKEN`, `HOME`, and normal settings,
and injects no provider URL or API credential. `crouter anthropic` is separate
and uses only an Anthropic Console `ANTHROPIC_API_KEY` or the
`anthropic-api-key` Keychain item. Personal subscription OAuth credentials are
not sent through crouter's proxy or unified gateway. This keeps the official
Claude account flow inside Claude Code and prevents API billing from silently
overriding a subscription login.

The older `AUTH_MODE="keypool"` contract remains supported for custom provider
files. Its `PLUS_KEYS` are bound only to `PLUS_URL`; they are no longer combined
with every declared URL.

For DashScope pay-as-you-go, the legacy public domain remains supported. Alibaba
now recommends a workspace-specific prefix; set the complete value, such as
`https://<WorkspaceId>.cn-beijing.maas.aliyuncs.com/apps/anthropic`, in
`DASHSCOPE_API_URL`.

Baidu stopped new Coding Plan sales on 2026-07-13. New personal subscriptions
use `qianfan`; enterprise/team subscriptions use `qianfan-team`. The separate
`qianfan-coding` provider remains only for an existing Coding Plan subscription
until its service period ends, so its dedicated key never reaches a Token Plan
or pay-as-you-go endpoint.

Qiniu subscription keys (`sk-plan`) and ordinary API keys use the same host but
remain separate candidates and Keychain pools. To activate MCP services created
in the Qiniu console, set one or more official HTTP-Streamable addresses in
`QINIU_MCP_URLS`; crouter rejects other hosts and injects only the active Qiniu
credential into the temporary session profile.

InfiniAI's Coding Plan was shut down on 2026-06-26. The `infini` provider is
therefore API-only and does not accept obsolete `sk-cp-` plan credentials.

## Provider MCPs and skills

Managed assets are session-scoped. crouter renders a mode-600 temporary MCP
configuration, supplies it with `--mcp-config`, loads provider skills with
`--plugin-dir`, and deletes the temporary file at session exit. It never edits
`~/.claude.json`, runs `claude mcp add`, or globally installs a plugin.

By default, `--strict-mcp-config` suppresses user/project MCP definitions for a
managed provider session. This prevents an old provider's tools or credentials
from remaining active after switching plans. crouter-owned plugin names and
skills are namespaced, so provider skills do not collide. Set
`CROUTER_STRICT_PROVIDER_MCP=0` to merge existing MCPs, or
`CROUTER_PROVIDER_ASSETS=0` to disable all managed assets.

Current profiles:

- MiniMax plan: `minimax-coding-plan-mcp==0.0.4` through `uvx`, plus the
  session-only `minimax-cli` skill using `mmx-cli@1.0.19`.
- Z.AI: `@z_ai/mcp-server@0.1.4` vision plus the official remote web search,
  web reader, and zread MCP endpoints.
- DashScope Token Plan: a namespaced media skill for the official image,
  video, and speech endpoints. The plan credential is supplied only as a
  session environment variable and never placed in command arguments.
- DashScope API: official Model Studio WebSearch MCP. It is omitted when only a
  Token Plan credential is available because that MCP requires the API key.
- Step Plan: official StepSearch (`web_search` and `web_fetch`) and a matching
  session skill.
- Volcengine: public Ark documentation MCP.
- Tencent: optional console-issued WebSearch SSE URL. Set the complete
  `TENCENT_MCP_URL`; crouter refuses non-HTTPS or non-Tencent hosts.
- AIHubMix: official API MCP, authenticated with only the active AIHubMix API
  surface credential.
- PPIO: official cloud-management MCP. It uses its own OAuth 2.1 flow rather
  than copying the LLM API key into the MCP profile.

DeepSeek's documented web search is a server-side model tool rather than a
downloadable MCP. Kimi documents how users can add generic MCPs and skills to
Kimi CLI, but not a Kimi-owned Claude Code plan package. Those providers, and
every other vendor without a documented plan-specific asset, get an
intentionally empty strict profile. crouter does not invent or install
unofficial packages.

Local packages are pinned and downloaded on demand by their documented package
runner; remote MCPs use their official HTTPS endpoint. Disable all managed
assets with `CROUTER_PROVIDER_ASSETS=0`. To merge rather than replace existing
MCP configuration, explicitly set `CROUTER_STRICT_PROVIDER_MCP=0` and accept
the possibility of duplicate or conflicting tool names.

Switch providers by starting the matching direct session, for example
`crouter minimax` then later `crouter stepfun`. A running Claude Code process
cannot replace its plugin set dynamically.

## Unified gateway

```sh
crouter all --check
crouter all
/model 'deepseek/deepseek-v4-pro[1m]'
/model dashscope/qwen3.7-max
```

`crouter all` exposes a namespaced `/v1/models` catalog on
`127.0.0.1:${CROUTER_GATEWAY_PORT:-18799}` and uses the same bound candidates
and per-surface model maps. Its paid `/v1/messages` route requires a random
per-session local token. Native Bedrock/Vertex routes are excluded because their
SDK signers live inside Claude Code.

`crouter all --check` builds the same configured route graph, prints only redacted
URLs, candidate labels/auth shapes, model counts, and the chosen default, then
exits without starting the gateway or Claude Code. Anthropic becomes the
default only when an explicit Console API key is configured; otherwise a route
with discovered remote credentials is preferred over unprobed local proxies.
The check proves local structure and credential discovery; it cannot prove a
paid account's remaining quota or live model entitlement without making a
billable request.
It also does not run provider `PRE_START` hooks or health probes: configured
local routes such as Codex, Antigravity, and Ollama must already be running.

The unified gateway switches model traffic only. Provider MCPs and skills are
fixed when a Claude Code process starts. By default `all` supplies a strict,
empty MCP profile so stale plan tools and credentials cannot cross providers.
An explicit Claude `--mcp-config` flag wins; setting
`CROUTER_STRICT_PROVIDER_MCP=0` keeps the user's existing MCP configuration.
Use `crouter <provider>` when vendor assets, a stored Claude account login, or a
native cloud backend are needed.

## Native Bedrock and Vertex

`bedrock` and `vertex` use Claude Code's supported native integrations. crouter
does not start a third-party localhost proxy or guess date-suffixed cloud model
IDs.

```sh
AWS_PROFILE=my-profile AWS_REGION=us-east-1 crouter bedrock

ANTHROPIC_VERTEX_PROJECT_ID=my-project \
CLOUD_ML_REGION=us-east5 \
crouter vertex
```

Only provider-declared AWS/Google credential variables survive the launcher's
isolated `env -i` environment.

## Antigravity and local providers

Antigravity requires a checkout of
[`antigravity-claude-proxy`](https://github.com/badrisnarayanan/antigravity-claude-proxy).
Set `ANTIGRAVITY_PROXY_DIR` and optionally `ANTIGRAVITY_PORT` in `config.sh`.
crouter starts it only when needed and stops it only if that same session owns
the process; a proxy that was already running is left untouched.

Ollama exposes its native Anthropic compatibility endpoint at
`http://localhost:11434`. Pull the configured default or select an installed
model explicitly:

```sh
ollama pull glm-4.7-flash
crouter ollama
crouter ollama qwen3.5:2b
```

Codex requires `icebear0828/codex-proxy` on port 19000 and a completed ChatGPT
OAuth PKCE login. Its available catalog remains account-dependent.

## Adding a provider

For a provider with distinct billing surfaces:

```sh
PROVIDER_NAME="example"
PROVIDER_DESC="Example Token Plan and API"

BASE_URL="https://plan.example/anthropic"
MODEL="plan-main"
MODEL_OPUS="plan-opus"
MODEL_HAIKU="plan-fast"

AUTH_MODE="surfaces"

PLAN_URL="https://plan.example/anthropic"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="EXAMPLE_PLAN_KEY"
PLAN_KEYS="example-plan"
PLAN_MODEL="plan-main"
PLAN_MODEL_OPUS="plan-opus"
PLAN_MODEL_HAIKU="plan-fast"

API_URL="https://api.example/anthropic"
API_AUTH_TYPE="x-api-key"
API_KEY_ENV="EXAMPLE_API_KEY"
API_KEYS="example-api"
API_MODEL="api-main"
API_MODEL_OPUS="api-large"
API_MODEL_HAIKU="api-fast"
```

`BASE_URL` must be the prefix Claude Code can append `/v1/messages` to. Do not
put the full messages path in a provider definition. Leave uncertain context
limits empty instead of guessing. Add an offline contract assertion to
`test/provider-matrix.sh` and record primary sources in the audit document.

## Security

- Real `config.sh`, credentials, logs, and provider account data are ignored.
- Secrets are never printed by `list`, `doctor`, `provider show`, or key-list
  commands.
- `crouter add` reads a key from `/dev/tty` with echo disabled, or from stdin
  when explicitly requested, and stores it in macOS Keychain.
- User-added pool metadata is mode 600 and contains Keychain service names,
  never secret values; provider source files stay immutable.
- Local proxies bind only to `127.0.0.1` and are reaped with the session.
- Local proxies require random per-session client tokens, so a fixed gateway
  port does not expose loaded provider credentials to other local processes.
- `BYPASS_PERMISSIONS=1` is available but unsafe on untrusted repositories.

## Development

```sh
sh test/smoke.sh
for test_file in test/*.sh; do sh "$test_file"; done
sh -n bin/crouter lib/*.sh providers/*.sh test/*.sh
git diff --check
```

Version is read from `VERSION`. Bash and zsh completions are under
`completions/`.

## Maintenance and license

The project is maintained in
[`Luckycat133/crouter`](https://github.com/Luckycat133/crouter) and distributed
under the [MIT License](LICENSE).
