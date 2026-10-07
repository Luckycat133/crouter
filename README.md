# crouter

[![CI](https://github.com/Luckycat133/crouter/actions/workflows/ci.yml/badge.svg)](https://github.com/Luckycat133/crouter/actions/workflows/ci.yml)
![Version](https://img.shields.io/badge/version-0.5.3-blue)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

`crouter` launches Claude Code against audited Anthropic-compatible providers
without copying provider credentials into this repository. It keeps Token Plan
keys, pay-as-you-go API keys, endpoints, auth headers, and model mappings as
separate routing surfaces. It fails over on HTTP 401/402/403/429 without
restarting Claude Code and temporarily cools down an exhausted candidate so
the next request does not immediately spend another retry on it.

The original catalog was checked against vendor documentation on 2026-08-08;
new routes and selected existing contracts were rechecked on 2026-09-26. See
[docs/provider-audit.md](docs/provider-audit.md) for the source matrix and
decisions.

`VERSION` remains 0.5.3; subsequent changes on `main` are recorded under
`Unreleased` in [CHANGELOG.md](CHANGELOG.md). The current checkout passes the
offline contract suite under POSIX `sh` and `dash`. Live catalog access,
remaining quota, and account entitlement still require the account owner's
credentials and may incur provider charges.

## Table of contents

- [Install](#install)
- [Usage](#usage)
- [Native coding-agent CLIs](#native-coding-agent-clis)
- [Provider catalog](#provider-catalog)
- [Token Plan and API key isolation](#token-plan-and-api-key-isolation)
- [Provider MCPs and skills](#provider-mcps-and-skills)
- [Unified gateway](#unified-gateway)
- [Native Bedrock, Vertex, and Foundry](#native-bedrock-vertex-and-foundry)
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
adding/removing providers. Reinstall prunes retired shortcuts only when they
point to this checkout. `crouter uninstall -y` removes all shortcuts owned by
this checkout, including retired ones, and preserves other files and links.

Requirements:

- [Claude Code v2.1.280+](https://code.claude.com/docs/en/model-config) for the
  Opus 5.5 preset
- Node.js (for the local keypool and unified gateway)
- macOS Keychain's `security` command when using Keychain credentials
- `uvx` only for the MiniMax Token Plan MCP

`config.sh` is optional and gitignored. Copy `config.example.sh` when local
overrides are needed.

## Diagnostics

`crouter doctor <provider>` exits nonzero when a required credential is known
to be missing, a configured health endpoint is down, or a required local tool
is unavailable. It prints the next configuration or connectivity check to make.
Required Node executables are checked for pooled routing, managed MCP profiles,
and local Node providers. Native Bedrock, Vertex, and Foundry SDK credentials
may be supplied through Claude settings or an external credential chain; doctor
reports `UNVERIFIED` when it cannot establish their status offline. It checks
credential discovery and configured health URLs, not live model entitlement,
and does not start local services. `crouter doctor` alone prints an
`Environment` block and a `Providers` block whose header counts the problems
(`38 total — 26 without a credential, 4 with a failing health check`), listing
affected providers first. Nothing is hidden and a missing optional credential
never fails the overview, so there is no `--all` counterpart here.
Keychain availability is checked fresh for each invocation, so adding or
removing an item outside crouter is reflected on the next diagnostic run.

Every command answers `-h` / `--help` with its own usage, and a help request
never launches a provider, starts a local service, or runs a diagnostic.
Arguments a command does not understand are rejected rather than ignored, so a
mistyped subcommand cannot silently do something else.

`crouter config show` lists normalized effective switches and whether known path
and binary settings are configured, without printing their values. It does not
print `config.sh` source, unknown variables, or credentials, even if a secret was
assigned to a path setting. Use `crouter config path` to locate the file for local
editing and `crouter --version` to check the installed version.

## Usage

```sh
crouter list                       # providers that can run on this machine
crouter list --all                 # the whole catalog, including no-key routes
crouter provider show dashscope
crouter doctor minimax

crouter claude                     # native Claude account login
crouter app list                   # installed coding-agent CLIs
crouter app codex --help           # run Codex with its own login and flags
crouter app muse                   # run Muse Code with its own login
crouter use app/codex              # select Codex for future launches
crouter                            # launch the selected target
crouter run --help                 # forward arguments to the selected target
crouter use                       # show the selected target
crouter use minimax               # select a Claude Code provider instead
crouter use --clear               # remove the selection
crouter anthropic                  # Anthropic Console API key
crouter minimax
crouter meta                       # Meta Model API key, billed as API usage
crouter requesty                   # Requesty API key
crouter nagaai                     # NagaAI inference API key
crouter dashscope qwen3.7-max
crouter deepseek --model 'deepseek-v4-pro[1m]'

crouter add                         # pick a provider from a menu
crouter add minimax --surface plan
crouter add minimax --surface api
pass show minimax/plan | crouter add minimax --surface plan --stdin
crouter list keys minimax
crouter remove minimax --surface api --name minimax-api-2

crouter all --check               # redacted route proof, no launch/network
crouter all
```

`crouter list` prints only the providers that can run right now, with a `ready`,
`local`, or `native` status, and ends by counting the ones that still need a
credential. `crouter list --all` prints the full catalog, marking those rows
`no-key`. `crouter add` with no argument offers the unconfigured providers as a
numbered menu; `crouter add --all` widens that menu to every provider, for
adding or rotating a key.

For provider launches, the first bare argument before any flag is a
primary-model override. Remaining arguments are forwarded to Claude Code.

`crouter use <provider>` selects a provider from `crouter list --all`, while
`crouter use app/<name>` selects a native CLI from `crouter app list`. The
selection affects future bare `crouter` and `crouter run [args...]` launches;
it does not change an already running client. Direct `crouter <provider>` and
`crouter app <name>` launches remain available and do not change the selection.
For example, `crouter use minimax` followed by `crouter run -p 'hello'` uses
the MiniMax provider through Claude Code, while `crouter use app/gemini`
followed by `crouter run --help` invokes Gemini with its own account.

The selected target is stored as a single mode-600 file at
`${XDG_STATE_HOME:-$HOME/.local/state}/crouter/selection`. If it is missing,
invalid, or points to a removed target, select another target with
`crouter use <provider>` or `crouter use app/<name>`; `crouter use --clear`
removes it.
Selection never edits Claude, Codex, Gemini, or other client settings. Native
app launches use each CLI's own authentication and skip `config.sh` and
provider setup.

## Native coding-agent CLIs

`crouter app list` shows which officially documented coding-agent commands are
installed. `crouter app <name> [args...]` executes the selected CLI with its
own authentication and forwards the arguments unchanged. This path skips
`config.sh` and provider setup entirely, so it does not create a proxy, inject
a model, or copy provider credentials into a different service. External
`claude`, `codex`, and IDE settings are not rewritten.

| App name | Executed command | Official CLI documentation |
| --- | --- | --- |
| `claude` | `claude` | [Claude Code](https://code.claude.com/docs/en/cli-usage) |
| `codex` | `codex` | [OpenAI Codex](https://developers.openai.com/codex/cli) |
| `gemini` | `gemini` | [Gemini CLI](https://github.com/google-gemini/gemini-cli) |
| `opencode` | `opencode` | [OpenCode](https://opencode.ai/docs/cli) |
| `copilot` | `copilot` | [GitHub Copilot CLI](https://docs.github.com/en/copilot/get-started/cli-quickstart) |
| `cursor` | `agent` (`cursor-agent` fallback) | [Cursor CLI](https://cursor.com/docs/cli/overview) |
| `kiro` | `kiro-cli` | [Kiro CLI](https://kiro.dev/docs/cli/) |
| `qoder` | `qoder` | [Qoder CLI](https://docs.qoder.com/cli/cli-reference) |
| `kimi` | `kimi` | [Kimi Code CLI](https://github.com/MoonshotAI/kimi-code/blob/main/docs/en/reference/kimi-command.md) |
| `qwen` | `qwen` | [Qwen Code](https://github.com/QwenLM/qwen-code) |
| `amp` | `amp` | [Amp CLI](https://ampcode.com/docs/cli) |
| `vibe` | `vibe` | [Mistral Vibe CLI](https://docs.mistral.ai/getting-started/quickstarts/vibe-code/install-cli) |
| `muse` | `muse` | [Meta Muse Code](https://dev.meta.ai/docs/muse-code) |
| `kilo` | `kilo` | [Kilo Code CLI](https://kilo.ai/docs/code-with-ai/platforms/cli) |

For Claude Code, `crouter claude` remains the existing native-login shortcut.
`crouter app claude` accepts an inherited `CLAUDE_BIN` environment variable;
`CLAUDE_BIN` set only inside `config.sh` applies to `crouter claude`.
`crouter app muse` keeps Muse Code's browser login or `META_API_KEY` in that
client. `crouter meta` instead uses a separately created `MODEL_API_KEY` for
Meta Model API; [Muse Code subscriptions](https://dev.meta.ai/docs/muse-code/subscriptions)
do not cover additional Model API keys.

Provider routing and client selection are separate: `crouter <provider>` uses
that provider's Anthropic Messages contract with Claude Code, while
`crouter app codex` and `crouter app gemini` use those clients' own login and
settings. Codex custom providers currently require the [Responses API](https://learn.chatgpt.com/docs/config-file/config-reference);
Gemini's [custom base URL](https://geminicli.com/docs/reference/configuration/)
still sends Gemini API requests. An Anthropic Messages URL cannot be inserted
into either client as a working provider without a validated protocol adapter.
OpenCode [V2](https://opencode.ai/v2/docs/providers) documents an
Anthropic-compatible adapter, but its configuration differs from V1, so crouter
does not rewrite either version's settings automatically.

## Provider catalog

An empty context means crouter deliberately does not inject a client-side
limit; the selected vendor model or native backend remains authoritative.

| Provider | Billing surfaces | Default model | Context | Managed assets |
| --- | --- | --- | ---: | --- |
| `302ai` | API | `claude-sonnet-5` | 1,000,000 | — |
| `aihubmix` | API | `coding-glm-5.1-free` | — | API MCP |
| `anthropic` | Console API key | `claude-sonnet-5` | — | — |
| `antigravity` | local proxy | `gemini-3.8-flash` | 1,048,576 | — |
| `antigravity-claude` | local proxy | `claude-opus-4-6-thinking` | 200,000 | — |
| `bedrock` | native AWS credentials | `sonnet` alias | — | — |
| `codex` | local ChatGPT subscription proxy | `gpt-5.6-sol` | 1,050,000 | — |
| `dashscope` | Token Plan + API | `qwen3.8-max` | 983,616 | Plan media skill + API WebSearch MCP |
| `dashscope-coding` | Coding Plan | `qwen3.8-plus` | 983,616 | — |
| `deepseek` | API | `deepseek-flash[1m]` | 1,000,000 | native web search |
| `fireworks` | API | `accounts/fireworks/models/glm-5p3-flash` | — | — |
| `foundry` | native Azure credentials, Bearer token, or Foundry API key | `sonnet` alias | — | — |
| `huawei` | Token Plan + API | `glm-5.3` | 262,144 | — |
| `infini` | GenStudio API | `glm-5.1` | — | — |
| `longcat` | Token Pack + pay-as-you-go on one API key | `LongCat-2.5-Preview` | 1,000,000 | — |
| `meta` | Model API key | `muse-spark-1.3` | 1,048,576 | — |
| `minimax` | Token Plan + API | `MiniMax-M3` | 1,000,000 | Plan MCP + CLI skill |
| `moonshot` | Kimi Code membership | `k3-256k` | 262,144 | — |
| `nagaai` | API | `claude-sonnet-4.5` | — | — |
| `ollama` | local MLX/Ollama | `qwen3.8-27b` | 262,144 for Qwen; 373,760 for DeepSeek V4 Flash | 60s SSE heartbeat |
| `openrouter` | API | `nvidia/nemotron-3-ultra-550b-a55b:free` | 1,000,000 | — |
| `ppio` | API | `minimax/minimax-m3` | 1,000,000 | cloud OAuth MCP |
| `qianfan` | personal Token Plan + API | `deepseek-v4-pro` | 262,144 | — |
| `qianfan-team` | team Token Plan | `deepseek-v4-flash` | 262,144 | — |
| `qianfan-coding` | legacy Coding Plan | `qianfan-code-latest` | 262,144 | — |
| `qiniu` | enterprise subscription + API | `deepseek/deepseek-v3.2-251201` | — | optional managed MCPs |
| `requesty` | API | `anthropic/claude-sonnet-5` | — | — |
| `siliconflow` | API | `Pro/moonshotai/Kimi-K2.7-Code` | — | — |
| `stepfun` | Step Plan + API | `step-5-preview` | 1,000,000 | StepSearch MCP + skill |
| `tencent` | personal Token Plan + TokenHub API | `tc-code-latest` | 262,144 | optional WebSearch MCP |
| `tencent-coding` | Coding Plan | `tc-code-latest` | 262,144 | — |
| `vercel` | AI Gateway API key | `anthropic/claude-sonnet-5` | — | — |
| `vertex` | native Google ADC | `sonnet` alias | — | — |
| `volcengine` | Ark Agent Plan | `doubao-seed-evolving` | 1,000,000 | Ark Docs + Doubao Search + DataPro + OpenViking MCPs |
| `volcengine-coding` | Ark Coding Plan | `doubao-seed-evolving` | 1,000,000 | Ark Docs MCP |
| `xiaomi` | Token Plan + API | `mimo-v2.6-pro[1m]` | 1,048,576 | — |
| `z-ai` | Coding Plan + API | `glm-5.3[1m]` | 1,000,000 | vision/search/reader/zread MCPs |

DeepSeek additionally follows its official 786,432-token automatic compaction
threshold; this is kept separate from its 1M maximum context.

OpenAI and Baichuan are intentionally absent. Their official APIs do not expose
an Anthropic Messages base URL that Claude Code can call directly. `codex`
continues to support a ChatGPT subscription through its explicitly documented
local translation proxy; crouter does not mislabel OpenAI's normal API as
Anthropic-compatible.

OpenCode Zen and Cloudflare AI Gateway are documented as deferred candidates in
the [provider audit](docs/provider-audit.md): Zen's Messages authentication
header is not specified clearly enough for an enabled preset, and Cloudflare's
route requires an account-specific URL. The `app` command can still run an
installed OpenCode CLI using its own login.

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
| `volcengine` | `VOLCENGINE_PLAN_KEY` | — |
| `volcengine-coding` | `VOLCENGINE_CODING_PLAN_KEY` | — |
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

`VOLCENGINE_AGENT_PLAN_KEY` is an alias for `VOLCENGINE_PLAN_KEY`. Agent Plan
and Coding Plan keys are accepted only by their respective endpoints; generic
Ark API keys are not used as subscription fallbacks.

Use `crouter provider show <name>` to inspect the URL, auth type, Keychain
service names, and tier maps without revealing secrets.

### Key management

`crouter add` stores only the secret in macOS Keychain. The first key fills the
provider's built-in service; subsequent keys get names such as
`minimax-plan-2` in a mode-600 registry under `.state/keypools/`. Provider files
are never edited, so an upgrade cannot overwrite the user's pool. Use `--name`
for a stable service name and `--stdin` with a password manager or CI.

Interactive `crouter add` asks once for the provider API key with terminal echo
disabled. With no provider argument it first shows the providers whose
credential is still missing and takes a number or a name; a provider with both
surfaces asks which surface to configure before the key prompt. `crouter add
--all` opens the same menu over the whole catalog, so a key can be added or
rotated for an already-configured provider. crouter stores the secret without
invoking the additional generic password and confirmation prompts from a bare
`security -w`. The value is not written
to shell history, repository files, or logs; it is supplied directly to the
short-lived macOS Keychain command.

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
- Volcengine: public Ark documentation MCP. When authenticated with an Ark Agent
  Plan credential, crouter automatically injects the official Doubao Search MCP
  (`mcp-server-askecho-search-infinity`), DataPro professional datasets MCP, and
  OpenViking control-plane MCP. Ark Coding Plan retains the public documentation MCP.
- Tencent: optional console-issued WebSearch SSE URL. Set the complete
  `TENCENT_MCP_URL`; crouter refuses non-HTTPS or non-Tencent hosts.
- AIHubMix: official API MCP, authenticated with only the active AIHubMix API
  surface credential.
- PPIO: official cloud-management MCP. It uses its own OAuth 2.1 flow rather
  than copying the LLM API key into the MCP profile.

DeepSeek's documented web search is a server-side model tool rather than a
downloadable MCP. Kimi documents how users can add generic MCPs and skills to
Kimi Code CLI, but not a Kimi-owned Claude Code plan package. Those providers, and
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
per-session local token. Native Bedrock/Vertex/Foundry routes are excluded because their
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

## Native Bedrock, Vertex, and Foundry

`bedrock`, `vertex`, and `foundry` use Claude Code's supported native integrations. crouter
does not start a third-party localhost proxy or guess date-suffixed cloud model
IDs.

```sh
AWS_PROFILE=my-profile AWS_REGION=us-east-1 crouter bedrock

ANTHROPIC_VERTEX_PROJECT_ID=my-project \
CLOUD_ML_REGION=us-east5 \
crouter vertex

ANTHROPIC_FOUNDRY_RESOURCE=my-resource crouter foundry
```

Only provider-declared AWS/Google/Microsoft credential and endpoint variables
survive the launcher's isolated `env -i` environment. This includes alternate
AWS credential/config file paths, Google ADC and version-specific Vertex model
regions, and Foundry API keys or `ANTHROPIC_FOUNDRY_AUTH_TOKEN` Bearer tokens.
`CLAUDE_CONFIG_DIR` reaches native backends so their setup wizards can read
settings saved outside `~/.claude`. These values can also be assigned in
`config.sh` without `export`.

Claude Code resolves cloud model aliases itself. crouter passes a deployment or
model pin only when you explicitly set `ANTHROPIC_DEFAULT_*_MODEL` (or
`CLAUDE_CODE_SUBAGENT_MODEL`). In Foundry, set
`ANTHROPIC_FOUNDRY_RESOURCE` for the simplest endpoint setup; its deployment
names are account-specific. `crouter doctor` reports native credentials as
`UNVERIFIED` when SDK or Claude settings cannot be checked offline.

## Antigravity and local providers

Antigravity requires a checkout of
[`antigravity-claude-proxy`](https://github.com/badrisnarayanan/antigravity-claude-proxy).
Set `ANTIGRAVITY_PROXY_DIR` and optionally `ANTIGRAVITY_PORT` in `config.sh`.
crouter starts it only when needed and stops it only if that same session owns
the process; a proxy that was already running is left untouched.

Ollama exposes its native Anthropic compatibility endpoint at
`http://127.0.0.1:11434`. The local crouter profile defaults to
`qwen3.8-27b` through the MLX adapter at port 11436 with `max` effort and a
262,144-token client cap. That Qwen preset expects an OpenAI-compatible MLX
server at `10.211.55.2:18080` by default (the existing local VM setup). Set
`MLX_UPSTREAM_HOST` and `MLX_UPSTREAM_PORT` in `config.sh` or your environment
to point it at another server, for example `127.0.0.1:18080`. crouter probes
the selected MLX endpoint before launch and passes that same address to the
adapter. An already running adapter must use the selected upstream; if it
does not, stop it before relaunching.

For a model installed in Ollama, select its exact installed ID explicitly. This
uses Ollama at `127.0.0.1:11434` and does not require the MLX server:

```sh
ollama pull deepseek-v4-flash:q8
crouter ollama deepseek-v4-flash:q8
crouter ollama <other-installed-model>
```

Direct Ollama sessions use a localhost-only transport proxy at
`http://127.0.0.1:11435`. While Ollama is generating a streaming Messages
response, the proxy emits one standards-compliant SSE comment every 60 seconds
so Claude Code does not mistake a healthy multi-minute tool-call generation for
an idle connection. For DeepSeek V4 requests, it preserves Claude Code's
Anthropic thinking request and logs the requested/effective mode, model, and
output ceiling without logging prompt content. Current Ollama releases reduce
this Anthropic path to their unbounded local thinking toggle; they do not yet
provide a token-bounded equivalent of cloud `max`. crouter therefore labels
the effective mode accurately and does not rewrite it into a misleading
2^31-1-token budget. Because this DeepSeek GGUF is text-only, the relay also turns image
blocks produced by Claude Code's `Read` tool into a text fallback notice. This
prevents Ollama's missing-`mmproj` HTTP 500 from terminating the agent and lets
it continue with DOM, console, Canvas, or pixel-statistics inspection. This
fallback is scoped to DeepSeek V4 model IDs; image blocks for other Ollama
models remain unchanged. A proxy started by the current session is stopped
when Claude Code exits; a healthy pre-existing proxy is reused and left
running.

The 373,760-token cap applies only to the exact `deepseek-v4-flash:q8` and
`deepseek-v4-flash` model IDs validated locally. Other explicitly selected
Ollama models retain the conservative 65,536-token fallback unless another
exact override is added to `MODEL_CONTEXT_OVERRIDES`.

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
for shell in sh dash; do
  for test_file in test/*.sh; do "$shell" "$test_file"; done
done
sh -n bin/crouter bin/crouter-compat install.sh lib/*.sh providers/*.sh test/*.sh
shellcheck --severity=warning --exclude=SC1007,SC1090,SC1091,SC2034,SC2120 \
  .githooks/pre-push bin/crouter bin/crouter-compat completions/crouter.bash \
  config.example.sh install.sh lib/*.sh providers/*.sh test/*.sh
for file in bin/gateway bin/keypool-proxy lib/*.js lib/*.mjs; do node --check "$file"; done
test "$(./bin/crouter --version)" = "crouter $(cat VERSION)"
git diff --check
```

Version is read from `VERSION`. Bash and zsh completions are under
`completions/`; they complete management subcommands at the correct argument
depth without loading `config.sh` or provider declarations.

### Push gate

`.githooks/pre-push` runs every offline test under `sh` and checks Node syntax
before a push. CI also runs the tests under `dash`, ShellCheck, and release
metadata checks. Run the full local validation above before publishing changes.
Enable it once per clone:

```sh
git config core.hooksPath .githooks
```

The suite is offline and hermetic: no credentials, no Keychain entry, and no
network access. Bypass a known-bad push with `git push --no-verify`; CI still
checks the push, so prefer fixing the failures.

### Daily sync

The maintainer's local Codex automation is scheduled for 23:00 Asia/Shanghai.
It checks the current branch and remote, stages only reviewed public source,
tests, and documentation, runs the repository checks, then commits and pushes
to the same remote branch with a normal fast-forward push. It leaves local
credentials, logs, state, ignored files, and unfinished changes alone. The
schedule lives in the local Codex app, so cloning this repository does not
install or enable it.

## Maintenance and license

The project is maintained in
[`Luckycat133/crouter`](https://github.com/Luckycat133/crouter) and distributed
under the [MIT License](LICENSE).
