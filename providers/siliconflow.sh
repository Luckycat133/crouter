#!/bin/sh
# SiliconFlow exposes a pay-as-you-go Anthropic Messages endpoint.
PROVIDER_NAME="siliconflow"
PROVIDER_DESC="SiliconFlow multi-model API"

BASE_URL="https://api.siliconflow.cn"
MODEL="Pro/moonshotai/Kimi-K2.7-Code"
CONTEXT_TOKENS=""
MODEL_OPUS="Pro/moonshotai/Kimi-K2.7-Code"
MODEL_SONNET="Pro/moonshotai/Kimi-K2.7-Code"
MODEL_HAIKU="deepseek-ai/DeepSeek-V4-Flash"
MODEL_SUBAGENT="Pro/moonshotai/Kimi-K2.7-Code"
MODEL_ALIASES="zai-org/GLM-5.3 Pro/zai-org/GLM-5.3 deepseek-ai/DeepSeek-V4-Flash Pro/moonshotai/Kimi-K2.6"
EFFORT="high"

AUTH_MODE="surfaces"
API_URL="https://api.siliconflow.cn"
API_AUTH_TYPE="bearer"
API_KEY_ENV="SILICONFLOW_API_KEY"
API_KEYS="siliconflow-api-key"
API_MODEL="Pro/moonshotai/Kimi-K2.7-Code"

EXTRA_ENV="CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1"
PRE_START=""
POST_STOP=""
HEALTH_CHECK_URL=""
