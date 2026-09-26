#!/bin/sh
# Provider-specific MCP and skill activation. Profiles are rendered into a
# mode-600 temporary file and passed with Claude Code's session-only flags.

prepare_provider_assets() {
  PROVIDER_MCP_CONFIG=""
  PROVIDER_PLUGIN_DIRS=""
  PROVIDER_ASSET_ENV=""

  [ "${CROUTER_PROVIDER_ASSETS:-1}" != 0 ] || return 0

  _asset_plugins=${ASSET_PLUGIN_DIRS:-}
  if [ -n "${_PLAN_FIRST_TOKEN:-}" ] && [ -n "${ASSET_PLAN_PLUGIN_DIRS:-}" ]; then
    _asset_plugins="${_asset_plugins}${_asset_plugins:+
}$ASSET_PLAN_PLUGIN_DIRS"
  fi
  if [ -n "${_API_FIRST_TOKEN:-}" ] && [ -n "${ASSET_API_PLUGIN_DIRS:-}" ]; then
    _asset_plugins="${_asset_plugins}${_asset_plugins:+
}$ASSET_API_PLUGIN_DIRS"
  fi

  if [ -n "$_asset_plugins" ]; then
    _old_ifs=$IFS
    IFS='
'
    for _plugin_dir in $_asset_plugins; do
      [ -d "$_plugin_dir" ] || die "provider asset plugin not found: $_plugin_dir"
    done
    IFS=$_old_ifs
    PROVIDER_PLUGIN_DIRS=$_asset_plugins
  fi

  _asset_profile=${ASSET_PROFILE:-}
  if [ -z "$_asset_profile" ] && [ "${AUTH_MODE:-}" = surfaces ]; then
    _asset_profile=empty
  fi
  [ -n "$_asset_profile" ] || return 0
  [ -n "${NODE_BIN:-}" ] || die "node not found; cannot render provider MCP profile '$_asset_profile'"

  _asset_config=$(mktemp "${TMPDIR:-/tmp}/crouter-mcp.XXXXXX") || \
    die "failed to create provider MCP profile '$_asset_profile'"
  # Own the file before Node renders into it, so a signal during rendering
  # lets the caller's prelaunch trap remove even a partial credentialed file.
  PROVIDER_MCP_CONFIG=$_asset_config
  CR_PLAN_TOKEN="${_PLAN_FIRST_TOKEN:-}" CR_API_TOKEN="${_API_FIRST_TOKEN:-}" \
  CR_TENCENT_MCP_URL="${TENCENT_MCP_URL:-}" \
  CR_QINIU_MCP_URLS="${QINIU_MCP_URLS:-}" \
    "$NODE_BIN" "$LIB_DIR/provider-assets.js" render "$_asset_profile" "$_asset_config" || {
      rm -f "$_asset_config"
      die "failed to render provider MCP profile '$_asset_profile'"
    }
  chmod 600 "$_asset_config"

  case $_asset_profile in
    minimax)
      if [ -n "${_PLAN_FIRST_TOKEN:-}" ]; then
        PROVIDER_ASSET_ENV="MINIMAX_API_KEY=$_PLAN_FIRST_TOKEN
MINIMAX_REGION=cn"
      fi
      ;;
    dashscope)
      if [ -n "${_PLAN_FIRST_TOKEN:-}" ]; then
        PROVIDER_ASSET_ENV="CROUTER_DASHSCOPE_TOKEN_PLAN_KEY=$_PLAN_FIRST_TOKEN"
      fi
      ;;
  esac
}

cleanup_provider_assets() {
  if [ -n "${PROVIDER_MCP_CONFIG:-}" ]; then
    rm -f "$PROVIDER_MCP_CONFIG"
    PROVIDER_MCP_CONFIG=""
  fi
}
