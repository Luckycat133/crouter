#!/bin/sh
# Provider: Gemini models through the local Antigravity compatibility proxy.
. "$ROOT_DIR/lib/antigravity-common.sh"

PROVIDER_NAME="antigravity"
PROVIDER_DESC="Gemini models via the local Antigravity proxy"

BASE_URL=$(antigravity_base_url)
MODEL="gemini-3.7-flash-tiered"
CONTEXT_TOKENS="1048576"

# Gemini 3.7 Flash; the account only exposes the -tiered variant, so all tiers
# map to gemini-3.7-flash-tiered (effort is handled internally by the proxy).
MODEL_OPUS="gemini-3.7-flash-tiered"
MODEL_SONNET="gemini-3.7-flash-tiered"
MODEL_HAIKU="gemini-3.7-flash-tiered"
MODEL_SUBAGENT="gemini-3.7-flash-tiered"

# Extra Antigravity Gemini models that aren't tier-mapped. Select explicitly
# with `crouter antigravity --model <name>` — Claude Code's --model flag picks
# them up directly. Discovered by `crouter provider show antigravity`.
MODEL_ALIASES="gemini-3.7-flash-tiered gemini-3.5-flash-medium gemini-3.1-pro-low"

# Gemini effort is encoded in the model name (gemini-3.7-flash-tiered),
# so we leave Claude Code's --effort unset here to avoid double control.
EFFORT=""

AUTH_MODE="static"
AUTH_REFERENCE="local-antigravity-proxy"

EXTRA_ENV="CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=0"

PRE_START="antigravity_ensure_gateway"
POST_STOP="antigravity_stop_gateway"
HEALTH_CHECK_URL="$BASE_URL/health"
