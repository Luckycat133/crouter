#!/bin/sh
# crouter local configuration.
#
# Copy this file to config.sh and adjust. config.sh is gitignored and must
# never contain API keys - keys belong in Keychain / env vars / a command
# (see AUTH_MODE in providers/*.sh).
#
# This file is sourced by bin/crouter after ROOT_DIR is set, so you
# may reference $ROOT_DIR and $HOME.

# Path to the Claude Code binary. Default: `command -v claude`.
#CLAUDE_BIN="$HOME/.local/bin/claude"

# Where runtime logs are written. Default: $ROOT_DIR/logs
#LOG_DIR="$ROOT_DIR/logs"

# Antigravity proxy checkout and listen port.
# Defaults: $ROOT_DIR/antigravity-claude-proxy and 18080.
#ANTIGRAVITY_PROXY_DIR="$ROOT_DIR/antigravity-claude-proxy"
#ANTIGRAVITY_PORT=18080

# The default qwen3.8-27b profile expects an OpenAI-compatible MLX server.
# Existing default: 10.211.55.2:18080. Override both values for your machine;
# a locally running MLX server can use 127.0.0.1. Other selected Ollama models
# use Ollama at 127.0.0.1:11434 and do not need these settings.
#MLX_UPSTREAM_HOST=127.0.0.1
#MLX_UPSTREAM_PORT=18080

# Provider-owned MCPs and skills are activated only for the current crouter
# session; crouter never edits ~/.claude.json or globally installs a plugin.
# Disable all managed assets with 0. Default: 1.
#CROUTER_PROVIDER_ASSETS=1

# Ignore user/project MCP definitions while a provider profile is active. This
# prevents duplicate tool names and credentials crossing between Token Plans;
# `crouter all` uses a strict empty profile because it cannot hot-swap plugins.
# Set to 0 to merge the provider profile with existing MCP configuration.
#CROUTER_STRICT_PROVIDER_MCP=1

# Tencent's WebSearch MCP URL contains a console-issued identifier and cannot
# be inferred. Copy the full official URL shown by Tencent Cloud when needed.
#TENCENT_MCP_URL="https://mcp-api.tencent-cloud.com/sse/REPLACE_ME"

# Qiniu generates one HTTP-Streamable URL per configured MCP service. Put one
# or more full official URLs here, separated by spaces or newlines.
#QINIU_MCP_URLS="https://api.qnaigc.com/v1/mcp/http-streamable/REPLACE_ME"

# Alibaba recommends a workspace-specific pay-as-you-go Anthropic prefix. The
# supported legacy domain is used when this is unset.
#DASHSCOPE_API_URL="https://WORKSPACE_ID.cn-beijing.maas.aliyuncs.com/apps/anthropic"

# Unified gateway port. Native Bedrock/Vertex routes and provider MCP/skills are
# intentionally excluded from `crouter all`; use a direct provider session for
# those features. Default: 18799.
#CROUTER_GATEWAY_PORT=18799

# After a candidate returns 401/402/403/429 or cannot connect, direct and
# unified proxies avoid it for at least this many milliseconds. A longer
# upstream Retry-After value wins. Default: 300000 (five minutes).
#CROUTER_CANDIDATE_COOLDOWN_MS=300000

# Bypass permissions mode. When 1, every `crouter <provider>` launch injects
# `--dangerously-skip-permissions` so Claude Code skips all permission prompts.
# Default: 0 (off). Set to 1 to enable by default. SECURITY: grants Claude Code
# unrestricted command execution for the session; only on trusted projects.
#BYPASS_PERMISSIONS=0
