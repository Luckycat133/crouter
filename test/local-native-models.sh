#!/bin/sh
# Offline provider contracts; never contact or start installed model runtimes.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fail() { printf 'FAIL %s\n' "$*" >&2; exit 1; }
die() { fail "$*"; }
. "$ROOT_DIR/lib/provider.sh"
load_last_selected_model() { :; }
OLLAMA_QWEN38_PRICING_ALIASES=0
. "$ROOT_DIR/providers/ollama.sh"
for pair in qwen3.6-hauhau:35b-a3b-q4_k_p=262144 qwen3.8:27b-dflash=262144 dflash/qwen3.8-27b=262144 qwen3.8-abliterated:27b-dflash=262144 abliterated-dflash/qwen3.8-27b=262144; do
  id=${pair%=*}; CONTEXT_TOKENS=
  apply_model_context_override "$id"
  [ "$CONTEXT_TOKENS" = "${pair#*=}" ] || fail "$id context"
  apply_model_self_route "$id"
  for tier in "$MODEL_OPUS" "$MODEL_SONNET" "$MODEL_HAIKU" "$MODEL_SUBAGENT"; do
    [ "$tier" = "$id" ] || fail "$id self route"
  done
  case " $MODEL_ALIASES " in *" $id "*) : ;; *) fail "$id static catalog" ;; esac
done
[ "$(resolve_model_id qwen3.8-abliterated:27b-dflash)" = qwen3.8-abliterated:27b-dflash ] || fail 'default abliterated ID changed without opt-in'
[ "$(resolve_model_id qwen3.8:27b-dflash)" = qwen3.8:27b-dflash ] || fail 'default DFlash ID changed without opt-in'
assert_pricing_copy_tags() {
  for copy in abliterated-dflash/qwen3.8-27b dflash/qwen3.8-27b; do
    [ "$(resolve_model_id "$copy:latest")" = "$copy" ] || fail 'catalog latest tag was not normalized'
    [ "$(resolve_model_id "$copy:other")" = "$copy:other" ] || fail 'an unrelated tag was normalized'
  done
}
assert_pricing_copy_tags
OLLAMA_QWEN38_PRICING_ALIASES=1
. "$ROOT_DIR/providers/ollama.sh"
assert_pricing_copy_tags
[ "$(resolve_model_id qwen3.8-abliterated:27b-dflash)" = abliterated-dflash/qwen3.8-27b ] || fail 'abliterated compatibility alias'
[ "$(resolve_model_id qwen3.8:27b-dflash)" = dflash/qwen3.8-27b ] || fail 'DFlash compatibility alias'
[ "$(resolve_model_id qwen3.8-27b)" = qwen3.8-27b ] || fail 'exact MLX model ID changed'
. "$ROOT_DIR/providers/mlx-vlm.sh"
for id in inkling-2-mini inkling-2-mini:latest; do
  apply_model_context_override "$id"
  apply_model_self_route "$id"
  [ "$CONTEXT_TOKENS" = 1048576 ] || fail 'native MLX-VLM Inkling context'
  for tier in "$MODEL_OPUS" "$MODEL_SONNET" "$MODEL_HAIKU" "$MODEL_SUBAGENT"; do
    [ "$tier" = "$id" ] || fail 'native MLX-VLM Inkling self route'
  done
done
. "$ROOT_DIR/providers/bonsai.sh"
apply_model_context_override ternary-bonsai-2.5-27b
apply_model_self_route ternary-bonsai-2.5-27b
[ "$CONTEXT_TOKENS" = 262144 ] || fail 'Bonsai25 context'
[ "$MODEL_HAIKU" = ternary-bonsai-2.5-27b ] || fail 'Bonsai25 tier'
case " $MODEL_ALIASES " in *' ternary-bonsai-2.5-27b '*) : ;; *) fail 'Bonsai25 static catalog' ;; esac
_bonsai_upstream_port=
bonsai_model_plan ternary-bonsai-2.5-27b
[ "$BASE_URL" = http://127.0.0.1:11439 ] || fail 'Bonsai25 planned adapter port'
[ "$_bonsai_upstream_port" = 8081 ] || fail 'Bonsai25 native port'
bonsai_model_plan ternary-bonsai-2-27b
[ "$BASE_URL" = http://127.0.0.1:11438 ] || fail 'legacy planned adapter port'
[ "$_bonsai_upstream_port" = 8000 ] || fail 'legacy native port'
printf 'ok    local exact IDs, contexts, self tiers and Bonsai native plans\n'
TMP_DIR=$(mktemp -d)
trap 'bonsai_stop; rm -rf "$TMP_DIR"' 0
mkdir -p "$TMP_DIR/demo/models" "$TMP_DIR/demo/scripts" "$TMP_DIR/pack"
ln -s "$TMP_DIR/pack" "$TMP_DIR/demo/models/Ternary-Bonsai-2.5-27B-mlx-2bit"
: > "$TMP_DIR/demo/scripts/start_mlx_server.sh"
chmod +x "$TMP_DIR/demo/scripts/start_mlx_server.sh"
BONSAI_DEMO_DIR=$TMP_DIR/demo
_main_model=ternary-bonsai-2.5-27b
bonsai_model_plan "$_main_model"
_test_listener=compatible
curl() {
  _url=
  for _arg do case $_arg in http://*) _url=$_arg ;; esac; done
  case $_url in
    http://127.0.0.1:8081/health)
      [ "$_test_listener" != absent ] || [ -f "$TMP_DIR/native-start" ] || return 1
      if [ "$_test_listener" = incompatible ]; then
        printf '{"status":"healthy","loaded_model":"%s"}' "$TMP_DIR/demo"
      else
        printf '{"status":"healthy","loaded_model":"%s"}' "$TMP_DIR/pack"
      fi ;;
    http://127.0.0.1:8081/v1/models)
      printf '{"data":[{"id":"%s"}]}' "$TMP_DIR/demo/models/Ternary-Bonsai-2.5-27B-mlx-2bit" ;;
    http://127.0.0.1:11439/health)
      [ -f "$TMP_DIR/adapter-start" ] || return 1
      printf '{"service":"crouter-mlx-anthropic-adapter","model":"ternary-bonsai-2.5-27b","upstream":"127.0.0.1:8081"}' ;;
    *) fail "unexpected network call $_url" ;;
  esac
}
lsof() {
  case " $* " in *' -iTCP:8081 '*) [ "$_test_listener" != absent ] ;; *) return 1 ;; esac
}
nohup() {
  if [ "$1" = node ]; then
    [ "$MLX_INHERIT_DEFAULTS" = 1 ] || exit 91
    [ "$MLX_MODEL" = ternary-bonsai-2.5-27b ] || exit 92
    [ "$MLX_UPSTREAM_MODEL" = "$TMP_DIR/demo/models/Ternary-Bonsai-2.5-27B-mlx-2bit" ] || exit 93
    [ "$#" = 2 ] || exit 94
    : > "$TMP_DIR/adapter-start"
  else
    [ "$BONSAI_FAMILY:$BONSAI_MODEL:$PORT" = bonsai25:27B:8081 ] || exit 95
    [ "$#" = 1 ] || exit 96
    : > "$TMP_DIR/native-start"
  fi
  exec sleep 30
}
# Reuse verified service, start only an owned adapter; realpath alias is accepted.
bonsai_start
[ -z "$_BONSAI_NATIVE_PID" ] || fail 'reused native service became owned'
_owned_adapter=$_BONSAI_PROXY_PID
bonsai_stop
! kill -0 "$_owned_adapter" 2>/dev/null || fail 'owned adapter survived cleanup'
[ ! -f "$TMP_DIR/native-start" ] || fail 'reused service was restarted'
rm "$TMP_DIR/adapter-start"
_test_listener=incompatible
if (die() { exit 37; }; bonsai_start); then fail 'wrong native model was reused';
else [ "$?" = 37 ] || fail 'wrong native model rejection'; fi
[ ! -f "$TMP_DIR/adapter-start" ] || fail 'adapter started against wrong model'
_test_listener=absent
bonsai_start
[ -n "$_BONSAI_NATIVE_PID" ] || fail 'fresh native service not owned'
_owned_native=$_BONSAI_NATIVE_PID
_owned_adapter=$_BONSAI_PROXY_PID
bonsai_stop
! kill -0 "$_owned_native" 2>/dev/null || fail 'owned native process survived cleanup'
! kill -0 "$_owned_adapter" 2>/dev/null || fail 'owned adapter survived cleanup'
printf 'ok    Bonsai native identity, compatible reuse, refusal, startup and owner-only cleanup\n'
