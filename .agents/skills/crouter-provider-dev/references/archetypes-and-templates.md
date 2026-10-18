# Provider Archetypes & Template Reference

Every provider in `crouter` is declared as a POSIX `/bin/sh` script in `providers/<provider>.sh`. Select the appropriate archetype template based on the vendor's authentication and deployment model.

---

## Template 1: Dual-Surface Subscription Plan (`AUTH_MODE="surfaces"`)

Use when a vendor offers both a subscription plan (Coding Plan, Agent Plan, Token Plan) and a standard pay-as-you-go API key under distinct endpoints or credentials.

```sh
#!/bin/sh
PROVIDER_NAME="myprovider"
PROVIDER_DESC="MyProvider (Token Plan)"

# Fallback resolution: plan key preferred, fallback to API key if unset
if [ -z "${MYPROVIDER_PLAN_KEY:-}" ]; then
  if [ -n "${MYPROVIDER_API_KEY:-}" ]; then
    export MYPROVIDER_PLAN_KEY="$MYPROVIDER_API_KEY"
  fi
fi

# Default fallback values for backward-compatibility / generic queries
BASE_URL="https://api.myprovider.com/plan"
MODEL="myprovider-flagship-coding"
CONTEXT_TOKENS="1000000"
AUTO_COMPACT_TOKENS="900000"
MODEL_OPUS="myprovider-flagship-coding"
MODEL_SONNET="myprovider-flagship-coding"
MODEL_HAIKU="myprovider-fast"
MODEL_SUBAGENT="myprovider-flagship-coding"
MODEL_ALIASES="myprovider-fast myprovider-pro"
EFFORT="high"

# Dual-surface declaration
AUTH_MODE="surfaces"
PLAN_URL="https://api.myprovider.com/plan"
PLAN_AUTH_TYPE="bearer"
PLAN_KEY_ENV="MYPROVIDER_PLAN_KEY"
PLAN_KEYS="myprovider-plan-key"
PLAN_MODEL="myprovider-flagship-coding"
PLAN_MODEL_OPUS="myprovider-flagship-coding"
PLAN_MODEL_SONNET="myprovider-flagship-coding"
PLAN_MODEL_HAIKU="myprovider-fast"
PLAN_MODEL_SUBAGENT="myprovider-flagship-coding"

API_URL="https://api.myprovider.com/v1"
API_AUTH_TYPE="bearer"
API_KEY_ENV="MYPROVIDER_API_KEY"
API_KEYS="myprovider-api-key"
API_MODEL="myprovider-flagship"
API_MODEL_OPUS="myprovider-flagship"
API_MODEL_SONNET="myprovider-flagship"
API_MODEL_HAIKU="myprovider-fast"
API_MODEL_SUBAGENT="myprovider-flagship"

# Companion tools profile (or "empty" if vendor has no tools)
ASSET_PROFILE="myprovider"
EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
```

---

## Template 2: Single-Surface API Key / Pure Gateway (`AUTH_MODE="env"`)

Use for vendors offering a single pay-as-you-go API key with an Anthropic-compatible base URL (e.g. DeepSeek, Moonshot, Xiaomi, Huawei).

```sh
#!/bin/sh
PROVIDER_NAME="mygateway"
PROVIDER_DESC="MyGateway Direct API"

BASE_URL="https://api.mygateway.com"
MODEL="mygateway-v3"
CONTEXT_TOKENS="128000"
MODEL_OPUS="mygateway-v3"
MODEL_SONNET="mygateway-v3"
MODEL_HAIKU="mygateway-v3-flash"
MODEL_SUBAGENT="mygateway-v3-flash"
MODEL_ALIASES="mygateway-v3-flash"
EFFORT="high"

AUTH_MODE="env"
AUTH_REFERENCE="MYGATEWAY_API_KEY"
AUTH_KEYCHAIN_FALLBACK="mygateway-api-key"

# Pure model gateways do not force MCP tooling
ASSET_PROFILE="empty"
EXTRA_ENV=""
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
```

---

## Template 3: Third-Party Aggregator (`AUTH_MODE="env"`)

Use for multi-model routing hubs (OpenRouter, SiliconFlow, 302.ai, AIHubMix, Infini, PPIO).

```sh
#!/bin/sh
PROVIDER_NAME="myhub"
PROVIDER_DESC="MyHub Multi-Model Aggregator"

BASE_URL="https://api.myhub.com/anthropic"
MODEL="vendor/flagship-model:free"
CONTEXT_TOKENS="200000"
MODEL_OPUS="vendor/flagship-model"
MODEL_SONNET="vendor/flagship-model"
MODEL_HAIKU="vendor/lightweight-model"
MODEL_SUBAGENT="vendor/lightweight-model"
EFFORT="high"

AUTH_MODE="env"
AUTH_REFERENCE="MYHUB_API_KEY"
AUTH_KEYCHAIN_FALLBACK="myhub-api-key"
ASSET_PROFILE="empty"
EXTRA_ENV=""
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
```

---

## Template 4: Local Proxy / Bridge Backend (`AUTH_MODE="none"`)

Use when Claude Code connects to a local daemon that translates Anthropic requests to an upstream protocol (e.g. `codex` via `codex-proxy` on port 19000, `ollama` on port 11435, or `antigravity`).

```sh
#!/bin/sh
PROVIDER_NAME="mybridge"
PROVIDER_DESC="MyBridge Local Translation Proxy"

BASE_URL="http://127.0.0.1:19000"
HEALTH_CHECK_URL="http://127.0.0.1:19000/health"
MODEL="proxy-model-default"
CONTEXT_TOKENS="1050000"
MODEL_OPUS="proxy-model-flagship"
MODEL_SONNET="proxy-model-sonnet"
MODEL_HAIKU="proxy-model-haiku"
MODEL_SUBAGENT="proxy-model-haiku"
EFFORT="high"

# Local proxy owns authentication internally
AUTH_MODE="none"
AUTH_REFERENCE="none"

PRE_START='
  if ! curl -fsS "$HEALTH_CHECK_URL" >/dev/null 2>&1; then
    printf "Error: %s is not running.\n" "$PROVIDER_NAME" >&2
    printf "Please start the proxy daemon and ensure %s responds.\n" "$HEALTH_CHECK_URL" >&2
    return 1
  fi
'
POST_STOP=""
ASSET_PROFILE="empty"
EXTRA_ENV=""
```

---

## Template 5: Native Cloud Backend (`AUTH_MODE="native"`)

Use when relying on Claude Code's native cloud provider signers (Amazon Bedrock, Google Vertex AI).

```sh
#!/bin/sh
PROVIDER_NAME="mycloud"
PROVIDER_DESC="MyCloud Native Backend"

BASE_URL="native://mycloud-endpoint"
MODEL="mycloud.claude-3-7-sonnet"
MODEL_OPUS="mycloud.claude-3-7-sonnet"
MODEL_SONNET="mycloud.claude-3-7-sonnet"
MODEL_HAIKU="mycloud.claude-3-5-haiku"
MODEL_SUBAGENT="mycloud.claude-3-5-haiku"

AUTH_MODE="native"
AUTH_REFERENCE=""
ASSET_PROFILE="empty"
EXTRA_ENV="CLAUDE_CODE_USE_MYCLOUD=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
```

---

## Variable Reference Glossary

| Variable | Description |
| :--- | :--- |
| `PROVIDER_NAME` | Identifier matching filename `providers/<name>.sh`. |
| `PROVIDER_DESC` | Human-readable name shown in `crouter list`. |
| `BASE_URL` | Base Anthropic Messages URL (prefix before `/v1/messages`). |
| `MODEL` | Default model launched when user runs `crouter <provider>`. |
| `CONTEXT_TOKENS` | Maximum context limit. Injected as `CLAUDE_CODE_MAX_CONTEXT_TOKENS`. |
| `AUTO_COMPACT_TOKENS` | Optional recommended compaction threshold. Injected as `CLAUDE_CODE_AUTO_COMPACT_WINDOW`. |
| `MODEL_OPUS` / `SONNET` / `HAIKU` / `SUBAGENT` | Per-tier model routing. |
| `MODEL_ALIASES` | Space-separated alternate model IDs accepted by CLI. |
| `AUTH_MODE` | `surfaces`, `env`, `keychain`, `none`, or `native`. |
| `ASSET_PROFILE` | Named profile rendered by `lib/provider-assets.js` or `"empty"`. |
| `PRE_START` / `POST_STOP` | Shell code hooks executed before launch and after exit. |
| `HEALTH_CHECK_URL` | Polled by `crouter doctor <provider>`. |
