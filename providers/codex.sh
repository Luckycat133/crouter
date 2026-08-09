#!/bin/sh
# Provider: Codex via icebear0828/codex-proxy (ChatGPT/Codex subscription).
# icebear proxy exposes /v1/messages on :19000 with Anthropic-compatible API.
# Subscription auth handled by icebear OAuth PKCE; crouter injects dummy token.
PROVIDER_NAME="codex"
PROVIDER_DESC="ChatGPT/Codex subscription via icebear0828/codex-proxy"

BASE_URL="http://localhost:8080"
MODEL="gpt-5.6-terra"
CONTEXT_TOKENS="1050000"

# Model aliases intentionally left unset — let the dynamic catalog from icebear
# drive tier selection via ANTHROPIC_DEFAULT_*_MODEL or /model in-session.
# The default gpt-5.6-terra is balanced so no flagship-quota waste.

EFFORT=""

# icebear auto-generates proxy_api_key=pwd on first run; inject matching
# dummy token so Claude Code sees non-empty credentials.
AUTH_MODE="none"
EXTRA_ENV="ANTHROPIC_AUTH_TOKEN=pwd
ANTHROPIC_API_KEY=pwd"

PRE_START='curl -fsS --max-time 3 http://localhost:8080/health >/dev/null 2>&1 || die "icebear0828/codex-proxy not running at http://localhost:8080/health — start with docker compose up -d (--port 8080) or run .dmg and complete ChatGPT login"'
POST_STOP=""
HEALTH_CHECK_URL="http://localhost:8080/health"