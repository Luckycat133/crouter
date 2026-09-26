#!/bin/sh
# Exact model caps must not leak to IDs that merely share their prefix.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
. "$ROOT_DIR/lib/provider.sh"
MODEL_CONTEXT_OVERRIDES='qwen3.8-27b=262144 foo:=8192'
fail=0
check() {
  CONTEXT_TOKENS=65536
  apply_model_context_override "$1"
  if [ "$CONTEXT_TOKENS" != "$2" ]; then
    printf 'FAIL  %s got context %s, expected %s\n' "$1" "$CONTEXT_TOKENS" "$2"
    fail=1
  fi
}
check qwen3.8-27b 262144
check qwen3.8-27b-suffix 65536
check qwen3.8-27b:custom 65536
check foo:tag 8192
check foo-other:tag 65536
check foo 65536
[ "$fail" -eq 0 ] || exit 1
printf 'ok    exact model caps and explicit tag-family caps stay scoped\n'
