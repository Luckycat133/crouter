#!/bin/sh
# Provider: Gemini models through the local Antigravity compatibility proxy.
. "$ROOT_DIR/lib/antigravity-common.sh"

PROVIDER_NAME="antigravity"
PROVIDER_DESC="Gemini models via the local Antigravity proxy"

BASE_URL=$(antigravity_base_url)
# Only the live account directory supplies selectable model variants.
MODELS_ACCOUNT_LIVE="1"
MODEL="gemini-3.8-flash"
CONTEXT_TOKENS="1048576"

# Expose the canonical pricing ID to clients such as Vibe Usage. The local
# Antigravity proxy maps this public ID to the account's -tiered model ID.
MODEL_OPUS="gemini-3.8-flash"
MODEL_SONNET="gemini-3.8-flash"
MODEL_HAIKU="gemini-3.8-flash"
MODEL_SUBAGENT="gemini-3.8-flash"

# Known IDs for explicit configuration, not proof of account availability.
# Browsing and unified menus use only the live local account directory; these
# compatibility seeds never fill missing models or thinking levels.
MODEL_ALIASES="gemini-4-neon-low gemini-4-neon-medium gemini-4-neon-high gemini-4-neon-xhigh gemini-4-carbon-low gemini-4-carbon-medium gemini-4-carbon-high gemini-4-argon-low gemini-4-argon-medium gemini-4-argon-high gemini-4-hydrogen-low gemini-4-hydrogen-medium gemini-4-hydrogen-high gemini-4-hydrogen-xhigh gemini-3.8-flash-low gemini-3.8-flash-medium gemini-3.8-flash-high gemini-3.8-flash-tiered gemini-3.7-flash gemini-3.7-flash-tiered gemini-3.5-flash-medium gemini-3.1-pro-low"

# Explicit tier IDs match Antigravity's current standalone model catalog.
# Orchestrator is deliberately excluded: it is a multi-model agent mode, not
# an Anthropic Messages model that this proxy can faithfully provide.
MODEL_ID_ALIASES="gemini-4-neon=gemini-4-neon-high gemini-4-carbon=gemini-4-carbon-medium gemini-4-argon=gemini-4-argon-medium gemini-4-hydrogen=gemini-4-hydrogen-medium"
# Exact live-account metadata reviewed 2026-11-28 reports 1,048,576 for
# every Neon variant; do not retain the older 512K client ceiling.
MODEL_CONTEXT_OVERRIDES="gemini-4-neon-low=1048576 gemini-4-neon-medium=1048576 gemini-4-neon-high=1048576 gemini-4-neon-xhigh=1048576"
MODEL_SELF_ROUTE_MODELS="*"

# Gemini effort is handled internally by the Antigravity proxy, so leave
# Claude Code's --effort unset to avoid double control.
EFFORT=""

AUTH_MODE="static"
AUTH_REFERENCE="local-antigravity-proxy"

EXTRA_ENV="CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=0"

PRE_START="antigravity_ensure_gateway"
POST_STOP="antigravity_stop_gateway"
HEALTH_CHECK_URL="$BASE_URL/health"
