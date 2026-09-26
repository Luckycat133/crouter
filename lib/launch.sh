#!/bin/sh
# Claude Code launch with isolated env. Sourced by bin/crouter.
# launch_claude <main_model> <bypass_auth> [claude args...]
#   Builds a minimal, terminal-safe "env -i" environment and launches Claude Code
#   as a child process (so POST_STOP / any local proxy is reaped on exit).
# Reads these globals at call time: CLAUDE_BIN, EFFORT, EXTRA_ENV, MODEL_*,
# CONTEXT_TOKENS, AUTO_COMPACT_TOKENS, AUTH_MODE, AUTH_TOKEN, KEYPOOL_URL,
# BASE_URL, POST_STOP,
# and the standard shell vars (LANG, TERM, SHELL, PATH, USER, HOME, COLORTERM).

# Claude Code's Vertex region overrides are version-specific. Admit only the
# documented Claude family/version forms, not arbitrary VERTEX_REGION_* names.
_vertex_region_name_ok() {
  case $1 in
    VERTEX_REGION_CLAUDE_*) _vr_suffix=${1#VERTEX_REGION_CLAUDE_} ;;
    *) return 1 ;;
  esac
  case $_vr_suffix in
    OPUS_*|SONNET_*|HAIKU_*|FABLE_*) _vr_version=${_vr_suffix#*_} ;;
    *_OPUS|*_SONNET|*_HAIKU|*_FABLE) _vr_version=${_vr_suffix%_*} ;;
    *) return 1 ;;
  esac
  case $_vr_version in
    ''|_*|*_|*__*|*[!0-9_]*) return 1 ;;
    [0-9]*) return 0 ;;
    *) return 1 ;;
  esac
}

launch_claude() {
  _main_model=$1; _bypass=$2; shift 2

  [ -n "$CLAUDE_BIN" ] || die "claude binary not found; set CLAUDE_BIN in config.sh"
  [ -x "$CLAUDE_BIN" ] || die "claude binary is not executable: $CLAUDE_BIN"

  # Build "env -i KEY=VAL ... claude args..." via positional parameters so
  # values with spaces survive. Everything is prepended in front of "$@".
  set -- "$CLAUDE_BIN" "$@"

  # A managed profile is session-scoped. Strict MCP mode deliberately ignores
  # user/project/global MCP definitions for this session, preventing duplicate
  # tool names or provider credentials from crossing between Token Plans. An
  # explicit caller-supplied MCP flag wins and disables automatic injection.
  if [ -n "${PROVIDER_MCP_CONFIG:-}" ]; then
    _has_mcp_override=0
    for _arg in "$@"; do
      case $_arg in --mcp-config|--mcp-config=*|--strict-mcp-config) _has_mcp_override=1; break ;; esac
    done
    if [ "$_has_mcp_override" -eq 0 ]; then
      _claude_bin=$1; shift
      if [ "${CROUTER_STRICT_PROVIDER_MCP:-1}" = 1 ]; then
        set -- "$_claude_bin" "--strict-mcp-config" "--mcp-config" "$PROVIDER_MCP_CONFIG" "$@"
      else
        set -- "$_claude_bin" "--mcp-config" "$PROVIDER_MCP_CONFIG" "$@"
      fi
    else
      info "warn: explicit Claude MCP flags override crouter profile '$PROVIDER_MCP_CONFIG'"
    fi
  fi

  if [ -n "${PROVIDER_PLUGIN_DIRS:-}" ]; then
    _old_ifs=$IFS
    IFS='
'
    for _plugin_dir in $PROVIDER_PLUGIN_DIRS; do
      _claude_bin=$1; shift
      set -- "$_claude_bin" "--plugin-dir" "$_plugin_dir" "$@"
    done
    IFS=$_old_ifs
  fi

  # Bypass permissions mode. Enable via BYPASS_PERMISSIONS=1 in config.sh (default
  # off). When on, inject --dangerously-skip-permissions unless the caller already
  # passed --dangerously-skip-permissions or --permission-mode (avoid duplicates /
  # conflicts). SECURITY: this disables all permission prompts for the session.
  if [ "${BYPASS_PERMISSIONS:-0}" = "1" ]; then
    _has_bypass=0
    for _arg in "$@"; do
      case "$_arg" in
        --dangerously-skip-permissions|--permission-mode|--permission-mode=*) _has_bypass=1; break ;;
      esac
    done
    if [ "$_has_bypass" -eq 0 ]; then
      _claude_bin="$1"; shift
      set -- "$_claude_bin" "--dangerously-skip-permissions" "$@"
    fi
  fi

  # Reasoning effort (Claude Code --effort). Inject the provider default unless
  # the user already passed --effort. Valid levels: low|medium|high|xhigh|max.
  case "${EFFORT:-}" in
    ""|low|medium|high|xhigh|max) ;;
    *) info "warn: EFFORT='$EFFORT' is not a valid Claude Code effort level (low|medium|high|xhigh|max); ignoring"; EFFORT="" ;;
  esac
  if [ -n "${EFFORT:-}" ]; then
    _has_effort=0
    for _arg in "$@"; do
      case "$_arg" in --effort|--effort=*) _has_effort=1; break ;; esac
    done
    if [ "$_has_effort" -eq 0 ]; then
      _claude_bin="$1"; shift
      set -- "$_claude_bin" "--effort" "$EFFORT" "$@"
    fi
  fi

  if [ -n "$EXTRA_ENV" ]; then
    _old_ifs=$IFS
    IFS='
'
    for _pair in $EXTRA_ENV; do
      [ -n "$_pair" ] && set -- "$_pair" "$@"
    done
    IFS=$_old_ifs
  fi
  if [ -n "${PROVIDER_ASSET_ENV:-}" ]; then
    _old_ifs=$IFS
    IFS='
'
    for _pair in $PROVIDER_ASSET_ENV; do
      [ -n "$_pair" ] && set -- "$_pair" "$@"
    done
    IFS=$_old_ifs
  fi

  # Native cloud backends authenticate through their SDK credential chains.
  # Export only provider-declared names in this launcher process so unexported
  # config.sh assignments also reach the isolated child; env -i still drops
  # every other variable. No indirect eval is needed.
  _native_pass_names=${PASSTHROUGH_ENV:-}
  if [ "${NATIVE_BACKEND:-}" = vertex ]; then
    # POSIX sh has no variable-name iteration. `set` exposes shell variable
    # names (including unexported config.sh values); only tightly validated
    # Claude model region names may join the explicit provider allowlist.
    _vertex_region_names=$(set | LC_ALL=C sed -n 's/^\(VERTEX_REGION_CLAUDE_[A-Z0-9_]*\)=.*/\1/p')
    for _vertex_name in $_vertex_region_names; do
      if _vertex_region_name_ok "$_vertex_name"; then
        _native_pass_names="${_native_pass_names:+$_native_pass_names }$_vertex_name"
      fi
    done
  fi
  for _pass_name in $_native_pass_names; do
    case $_pass_name in
      ''|[0-9]*|*[!A-Za-z0-9_]*) continue ;;
    esac
    export "${_pass_name?}" 2>/dev/null || continue
    _pass_value=$(printenv "$_pass_name" 2>/dev/null || true)
    [ -n "$_pass_value" ] && set -- "$_pass_name=$_pass_value" "$@"
  done

  # Native cloud backends own their built-in alias resolver. Passing literal
  # aliases or example deployment IDs as pins can target an unavailable model.
  # Only explicit user pins were forwarded by the native allowlist above.
  case ${NATIVE_BACKEND:-} in
    bedrock|vertex|foundry) ;;
    *)
      set -- "CLAUDE_CODE_SUBAGENT_MODEL=$MODEL_SUBAGENT" "$@"
      set -- "ANTHROPIC_DEFAULT_HAIKU_MODEL=$MODEL_HAIKU" "$@"
      set -- "ANTHROPIC_DEFAULT_SONNET_MODEL=$MODEL_SONNET" "$@"
      set -- "ANTHROPIC_DEFAULT_OPUS_MODEL=$MODEL_OPUS" "$@"
      ;;
  esac
  set -- "ANTHROPIC_MODEL=$_main_model" "$@"
  [ -n "$CONTEXT_TOKENS" ] && set -- "CLAUDE_CODE_MAX_CONTEXT_TOKENS=$CONTEXT_TOKENS" "$@"
  [ -n "${AUTO_COMPACT_TOKENS:-}" ] &&
    set -- "CLAUDE_CODE_AUTO_COMPACT_WINDOW=$AUTO_COMPACT_TOKENS" "$@"

  # A local proxy (surface/keypool rotation or legacy dual-source failover) owns auth: Claude
  # Code just talks to it with a placeholder credential.
  if [ -n "${NATIVE_BACKEND:-}" ]; then
    : # Claude Code's native Bedrock/Vertex integration owns endpoint and auth.
  elif [ -n "${KEYPOOL_URL:-}" ] && [ "$_bypass" -eq 0 ]; then
    set -- "ANTHROPIC_BASE_URL=$KEYPOOL_URL" "$@"
    set -- "ANTHROPIC_API_KEY=${KEYPOOL_AUTH_TOKEN:-keypool-local}" "$@"
    set -- "ANTHROPIC_AUTH_TOKEN=${KEYPOOL_AUTH_TOKEN:-keypool-local}" "$@"
  elif [ "${AUTH_MODE:-}" = "keypool" ] && [ "$_bypass" -eq 0 ]; then
    die "keypool proxy not started"
  elif [ -n "$AUTH_TOKEN" ]; then
    # Header shape matters. `_AUTH_SCHEME` is resolved from the provider:
    #   bearer     -> Authorization: Bearer. Sending such a token as x-api-key
    #                 gets it rejected upstream.
    #   x-api-key  -> x-api-key              (Anthropic Console API key)
    # Legacy providers leave it unset: keep the historical both-headers behavior.
    case "${_AUTH_SCHEME:-both}" in
      bearer)
        set -- "ANTHROPIC_AUTH_TOKEN=$AUTH_TOKEN" "$@" ;;
      x-api-key)
        set -- "ANTHROPIC_API_KEY=$AUTH_TOKEN" "$@" ;;
      *)
        set -- "ANTHROPIC_API_KEY=$AUTH_TOKEN" "$@"
        set -- "ANTHROPIC_AUTH_TOKEN=$AUTH_TOKEN" "$@" ;;
    esac
  fi
  if [ -z "${NATIVE_BACKEND:-}" ]; then
    set -- "ANTHROPIC_BASE_URL=${KEYPOOL_URL:-$BASE_URL}" "$@"
  fi

  # Minimal, terminal-safe environment. No shell leftovers (NO_COLOR etc.).
  set -- "LANG=${LANG:-en_US.UTF-8}" "$@"
  set -- "COLORTERM=${COLORTERM:-truecolor}" "$@"
  set -- "TERM=${TERM:-xterm-256color}" "$@"
  set -- "SHELL=${SHELL:-/bin/zsh}" "$@"
  set -- "PATH=$PATH" "$@"
  set -- "USER=$USER" "$@"
  set -- "HOME=$HOME" "$@"

  # Run as a child (not exec) so POST_STOP and any local auth proxy are cleaned
  # up. Cleanup is idempotent: the signal/EXIT traps and the normal path may all
  # reach it, but the provider hook runs exactly once and cannot change Claude's
  # exit status merely because a best-effort kill found an already-dead process.
  _crouter_cleanup_done=0
  _crouter_pending_signal=0
  _cg_pid=""
  _crouter_launch_cleanup() {
    [ "${_crouter_cleanup_done:-0}" -eq 0 ] || return 0
    _crouter_cleanup_done=1
    [ -n "${POST_STOP:-}" ] && eval "$POST_STOP" || true
    [ -n "${KEYPOOL_PID:-}" ] && kill "$KEYPOOL_PID" 2>/dev/null || true
    if command -v cleanup_provider_assets >/dev/null 2>&1; then
      cleanup_provider_assets || true
    fi
    kill "${_cg_pid:-}" 2>/dev/null || true
    return 0
  }

  _crouter_launch_signal() {
    _crouter_pending_signal=$1
    # If the signal lands while the child is being created, defer the exit
    # until $! has been captured so the child can still be reaped.
    [ -n "${_cg_pid:-}" ] || return 0
    _crouter_launch_cleanup
    exit "$_crouter_pending_signal"
  }

  trap '_crouter_launch_cleanup' EXIT
  trap '_crouter_launch_signal 130' INT
  trap '_crouter_launch_signal 143' TERM

  [ "$_crouter_pending_signal" -eq 0 ] || exit "$_crouter_pending_signal"
  if [ "${PROVIDER_NAME:-}" = ollama ] && [ "$_bypass" -eq 0 ]; then
    remember_last_selected_model ollama "$_main_model"
  fi
  # Save stdin before the asynchronous command: dash may replace fd 0 with
  # /dev/null before applying the child's explicit redirections.
  exec 3<&0
  env -i "$@" <&3 3<&- &
  _cg_pid=$!
  exec 3<&-
  if [ "$_crouter_pending_signal" -ne 0 ]; then
    _pending_signal=$_crouter_pending_signal
    _crouter_launch_cleanup
    exit "$_pending_signal"
  fi
  wait "$_cg_pid"
  _rc=$?
  trap - EXIT INT TERM
  _crouter_launch_cleanup
  exit "${_rc:-0}"
}
