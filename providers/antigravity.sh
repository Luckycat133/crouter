#!/bin/sh
# Provider: Gemini models through the local Antigravity compatibility proxy.
. "$ROOT_DIR/lib/antigravity-common.sh"

PROVIDER_NAME="antigravity"
PROVIDER_DESC="Gemini models via the local Antigravity proxy"

BASE_URL=$(antigravity_base_url)
MODEL="gemini-3.7-flash"
CONTEXT_TOKENS="1048576"

# Expose the canonical pricing ID to clients such as Vibe Usage. The local
# Antigravity proxy maps this public ID to the account's -tiered model ID.
MODEL_OPUS="gemini-3.7-flash"
MODEL_SONNET="gemini-3.7-flash"
MODEL_HAIKU="gemini-3.7-flash"
MODEL_SUBAGENT="gemini-3.7-flash"

# Extra Antigravity Gemini models that aren't tier-mapped. Select explicitly
# with `crouter antigravity --model <name>` — Claude Code's --model flag picks
# them up directly. Discovered by `crouter provider show antigravity`.
MODEL_ALIASES="gemini-3.5-flash-medium gemini-3.1-pro-low"

# Gemini effort is handled internally by the Antigravity proxy, so leave
# Claude Code's --effort unset to avoid double control.
EFFORT=""

AUTH_MODE="static"
AUTH_REFERENCE="local-antigravity-proxy"

EXTRA_ENV="CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=0"

PRE_START="antigravity_ensure_gateway"
POST_STOP="antigravity_stop_gateway"
HEALTH_CHECK_URL="$BASE_URL/health"
