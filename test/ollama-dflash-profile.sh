#!/bin/sh
# Offline contract checks: no user state, upstream service, or real processes.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT_DIR/lib/provider.sh"
load_last_selected_model() { :; }
. "$ROOT_DIR/providers/ollama.sh"
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
die() { fail "$*"; }
assert_no_output_cap() {
  case $EXTRA_ENV in
    *CLAUDE_CODE_MAX_OUTPUT_TOKENS=*) fail 'profiles must not inject an output cap' ;;
  esac
}
assert_no_output_cap
_base_extra_env=$EXTRA_ENV
[ "$MODEL" = qwen3.8:27b-dflash ] || fail 'default must select DFlash2'
[ "$EFFORT" = xhigh ] || fail 'default must request Qwen maximum xhigh'
apply_model_context_override "$MODEL"
apply_model_self_route "$MODEL"
[ "$CONTEXT_TOKENS" = 262144 ] || fail 'DFlash2 client window must match Ollama allocation'
for _tier in "$MODEL_OPUS" "$MODEL_SONNET" "$MODEL_HAIKU" "$MODEL_SUBAGENT"; do
  [ "$_tier" = "$MODEL" ] || fail 'all model tiers must use the selected DFlash2 model'
done

curl() {
  _stub_url=
  for _stub_arg do
    case $_stub_arg in http://*) _stub_url=$_stub_arg ;; esac
  done
  case $_stub_url in
    http://127.0.0.1:11434) printf 'Ollama running\n' ;;
    http://127.0.0.1:11435/health)
      printf '{"service":"crouter-ollama-heartbeat","effort_cap":"%s","dflash_effort_rewrite":"%s"}' "$CROUTER_TEST_EFFORT_CAP" "${CROUTER_TEST_DFLASH_VERSION-qwen38-dflash-named-effort-v1}"
      ;;
    http://10.211.55.2:18080/v1/models) printf '{}\n' ;;
    http://127.0.0.1:11436/health)
      printf '{"service":"crouter-mlx-anthropic-adapter","upstream":"10.211.55.2:18080"}'
      ;;
    *) fail "unexpected network endpoint: $_stub_url" ;;
  esac
}
kill() { fail 'must reuse the matching relay without killing a process'; }
nohup() { fail 'must not spawn a real process'; }
lsof() { fail 'must not inspect real listeners'; }
sleep() { fail 'must not wait on a real process'; }
MLX_UPSTREAM_HOST=10.211.55.2 MLX_UPSTREAM_PORT=18080

_main_model=qwen3.8:27b-dflash
CROUTER_TEST_EFFORT_CAP=xhigh
EFFORT=max
eval "$PRE_START"
[ "$EFFORT" = xhigh ] || fail 'DFlash2 hook must select xhigh'
[ "$BASE_URL" = http://127.0.0.1:11435 ] || fail 'DFlash2 must use the Ollama relay'
assert_no_output_cap

_relay_side_effects=$(mktemp)
trap 'rm -f "$_relay_side_effects"' 0
for _incompatible_relay in effort version; do
  if _rejection_output=$({
    die() { printf '%s\n' "$*" >&2; exit 37; }
    lsof() { printf 'lsof\n' >>"$_relay_side_effects"; exit 88; }
    kill() { printf 'kill\n' >>"$_relay_side_effects"; exit 88; }
    CROUTER_TEST_EFFORT_CAP=xhigh
    CROUTER_TEST_DFLASH_VERSION=qwen38-dflash-named-effort-v1
    if [ "$_incompatible_relay" = effort ]; then
      CROUTER_TEST_EFFORT_CAP=medium
    else
      CROUTER_TEST_DFLASH_VERSION=old-version
    fi
    eval "$PRE_START"
  } 2>&1); then
    fail 'DFlash2 must reject an incompatible existing relay'
  else
    [ "$?" = 37 ] || fail 'incompatible relay must stop via the profile diagnostic'
  fi
  [ ! -s "$_relay_side_effects" ] || fail 'DFlash2 must not inspect or kill an existing incompatible relay'
  case $_rejection_output in
    *'wait for its current task to finish, then restart the relay'*) : ;;
    *) fail 'relay rejection must explain when to restart' ;;
  esac
done

_main_model=qwen3.8:older-profile
EXTRA_ENV=$_base_extra_env
CROUTER_TEST_EFFORT_CAP=medium
eval "$PRE_START"
[ "$EFFORT" = medium ] || fail 'legacy Qwen effort cap must remain medium'
assert_no_output_cap

_main_model=deepseek-v4-flash:q8
EXTRA_ENV=$_base_extra_env
CROUTER_TEST_EFFORT_CAP=
eval "$PRE_START"
[ "$EFFORT" = max ] || fail 'DeepSeek effort default must remain max'
assert_no_output_cap

_main_model=qwen3.8-27b
EXTRA_ENV=$_base_extra_env
eval "$PRE_START"
[ "$EFFORT" = max ] || fail 'explicit legacy MLX selection must retain max'
[ "$BASE_URL" = http://127.0.0.1:11436 ] || fail 'legacy MLX endpoint must remain unchanged'
assert_no_output_cap
printf 'ok    DFlash2 uses one model, native 256K, xhigh and no injected output cap; other profiles stay isolated\n'
