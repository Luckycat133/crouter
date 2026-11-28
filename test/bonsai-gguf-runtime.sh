#!/bin/sh
# Real dispatcher with mocked curl/lsof/nohup; never starts a model runtime.
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export FIXTURE_WRAPPER_PRESENT=1
for state in compatible absent; do
  FIXTURE_NATIVE_BACKEND=gguf FIXTURE_NATIVE_STATE="$state" \
    "${TEST_SHELL:-sh}" "$ROOT_DIR/test/bonsai-cli-startup.sh"
done
for identity in wrong-path wrong-alias; do
  FIXTURE_NATIVE_BACKEND=gguf FIXTURE_NATIVE_STATE=compatible FIXTURE_IDENTITY="$identity" \
    "${TEST_SHELL:-sh}" "$ROOT_DIR/test/bonsai-cli-startup.sh"
done
# Upgrading the launcher must not claim or replace a correct old MLX listener.
FIXTURE_NATIVE_BACKEND=mlx FIXTURE_NATIVE_STATE=compatible \
  "${TEST_SHELL:-sh}" "$ROOT_DIR/test/bonsai-cli-startup.sh"
printf 'ok    Bonsai GGUF identity, preferred native launcher and legacy MLX reuse\n'
