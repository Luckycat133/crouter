#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CROUTER="$ROOT_DIR/bin/crouter"

_show=$($CROUTER provider show dashscope)
printf '%s\n' "$_show" | grep -q '^auth:        Token Plan / API key surfaces$'
printf '%s\n' "$_show" | grep -q '^  plan URL:  https://token-plan.cn-beijing.maas.aliyuncs.com/apps/anthropic$'
printf '%s\n' "$_show" | grep -q '^    key env: DASHSCOPE_TOKEN_PLAN_KEY$'
printf '%s\n' "$_show" | grep -q '^  API URL:   https://dashscope.aliyuncs.com/apps/anthropic$'
printf '%s\n' "$_show" | grep -q '^    model:   qwen3.7-max$'
printf '%s\n' "$_show" | grep -q '^assets:      MCP profile dashscope'

_native=$($CROUTER provider show bedrock)
printf '%s\n' "$_native" | grep -q '^auth:        native$'
printf '%s\n' "$_native" | grep -q '^  backend:   bedrock$'

_deepseek=$($CROUTER provider show deepseek)
printf '%s\n' "$_deepseek" | grep -q '^auto compact: 786432$'

printf 'ok    provider show exposes surfaces, model mappings, assets, and native backends\n'
