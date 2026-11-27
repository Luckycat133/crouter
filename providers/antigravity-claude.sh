#!/bin/sh
# Provider: Claude models through the local Antigravity compatibility proxy.
. "$ROOT_DIR/lib/antigravity-common.sh"

PROVIDER_NAME="antigravity-claude"
PROVIDER_DESC="Claude models via the local Antigravity proxy"

BASE_URL=$(antigravity_base_url)
# Only the live account directory supplies selectable model variants.
MODELS_ACCOUNT_LIVE="1"
MODEL="claude-opus-5-5-medium"
# Claude 5.5 account metadata reviewed 2026-11-28 reports a 1M window.
CONTEXT_TOKENS="1000000"

MODEL_OPUS="claude-opus-5-5-medium"
MODEL_SONNET="claude-sonnet-5-5-medium"
MODEL_HAIKU="claude-sonnet-5-5-medium"
MODEL_SUBAGENT="claude-sonnet-5-5-medium"

# Known compatibility IDs do not imply account access; menus require live IDs.
MODEL_ALIASES="claude-opus-5-5-low claude-opus-5-5-high claude-opus-5-5-max claude-sonnet-5-5-low claude-sonnet-5-5-high claude-sonnet-5-5-max claude-opus-4-6-thinking claude-sonnet-4-6"
# Resolve bare aliases to an explicit tier before forwarding, preserving
# the requested model family/version across proxy releases.
MODEL_ID_ALIASES="claude-opus-5-5=claude-opus-5-5-medium claude-sonnet-5-5=claude-sonnet-5-5-medium"
MODEL_SELF_ROUTE_MODELS="claude-opus-5-5-low claude-opus-5-5-high claude-opus-5-5-max claude-sonnet-5-5-low claude-sonnet-5-5-medium claude-sonnet-5-5-high claude-sonnet-5-5-max"
MODEL_EFFORT_OVERRIDES="claude-opus-5-5-low=low claude-opus-5-5-medium=medium claude-opus-5-5-high=high claude-opus-5-5-max=max claude-sonnet-5-5-low=low claude-sonnet-5-5-medium=medium claude-sonnet-5-5-high=high claude-sonnet-5-5-max=max"

EFFORT="medium"

AUTH_MODE="static"
AUTH_REFERENCE="local-antigravity-proxy"

EXTRA_ENV="CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY=0"

PRE_START="antigravity_ensure_gateway"
POST_STOP="antigravity_stop_gateway"
HEALTH_CHECK_URL="$BASE_URL/health"
