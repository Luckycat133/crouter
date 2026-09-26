#!/bin/sh
# Bedrock, Vertex and Foundry must use Claude Code's native signers, never invented
# model IDs or unowned localhost proxy processes.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-native)
trap 'rm -rf "$TMP_DIR"' EXIT INT TERM
# Keep deployment-name assertions independent of the caller's Azure setup.
unset ANTHROPIC_FOUNDRY_RESOURCE ANTHROPIC_FOUNDRY_BASE_URL ANTHROPIC_FOUNDRY_API_KEY AZURE_CONFIG_DIR
unset ANTHROPIC_FOUNDRY_AUTH_TOKEN AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_CLIENT_SECRET
unset CLAUDE_CONFIG_DIR
unset ANTHROPIC_DEFAULT_OPUS_MODEL ANTHROPIC_DEFAULT_SONNET_MODEL ANTHROPIC_DEFAULT_HAIKU_MODEL
unset CLAUDE_CODE_SUBAGENT_MODEL AWS_SHARED_CREDENTIALS_FILE AWS_CONFIG_FILE
unset ANTHROPIC_BEDROCK_BASE_URL ANTHROPIC_BEDROCK_REGION_PREFIX ANTHROPIC_BEDROCK_SERVICE_TIER
unset CLAUDE_CODE_SKIP_AWS_CRED_CACHE CLAUDE_CODE_AWS_CHAIN_RESOLVE_TIMEOUT_MS
unset ANTHROPIC_VERTEX_BASE_URL VERTEX_REGION_CLAUDE_HAIKU_4_5 VERTEX_REGION_CLAUDE_4_6_SONNET
unset VERTEX_REGION_CLAUDE_SECRET_1 VERTEX_REGION_CLAUDE_HAIKU_4_5_EXTRA

# Control Azure CLI discovery without depending on the host's installed tools.
NO_AZ_PATH="$TMP_DIR/no-az"
WITH_AZ_PATH="$TMP_DIR/with-az"
mkdir -p "$NO_AZ_PATH" "$WITH_AZ_PATH"
for _tool in cat curl dirname; do
  _tool_path=$(command -v "$_tool")
  ln -s "$_tool_path" "$NO_AZ_PATH/$_tool"
  ln -s "$_tool_path" "$WITH_AZ_PATH/$_tool"
done
cat > "$WITH_AZ_PATH/az" <<'AZ'
#!/bin/sh
exit 0
AZ
chmod +x "$WITH_AZ_PATH/az"

cat > "$TMP_DIR/claude" <<'MOCK'
#!/bin/sh
_capture_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if [ "${CLAUDE_CODE_USE_BEDROCK:-}" = 1 ]; then
  _capture_file="$_capture_dir/bedrock"
elif [ "${CLAUDE_CODE_USE_FOUNDRY:-}" = 1 ]; then
  _capture_file="$_capture_dir/foundry"
else
  _capture_file="$_capture_dir/vertex"
fi
{
  printf 'bedrock=%s\n' "${CLAUDE_CODE_USE_BEDROCK:-}"
  printf 'vertex=%s\n' "${CLAUDE_CODE_USE_VERTEX:-}"
  printf 'foundry=%s\n' "${CLAUDE_CODE_USE_FOUNDRY:-}"
  printf 'aws_profile=%s\n' "${AWS_PROFILE:-}"
  printf 'aws_credentials_file=%s\n' "${AWS_SHARED_CREDENTIALS_FILE:-}"
  printf 'aws_config_file=%s\n' "${AWS_CONFIG_FILE:-}"
  printf 'bedrock_url=%s\n' "${ANTHROPIC_BEDROCK_BASE_URL:-}"
  printf 'bedrock_prefix=%s\n' "${ANTHROPIC_BEDROCK_REGION_PREFIX:-}"
  printf 'bedrock_tier=%s\n' "${ANTHROPIC_BEDROCK_SERVICE_TIER:-}"
  printf 'aws_cache_skip=%s\n' "${CLAUDE_CODE_SKIP_AWS_CRED_CACHE:-}"
  printf 'aws_chain_timeout=%s\n' "${CLAUDE_CODE_AWS_CHAIN_RESOLVE_TIMEOUT_MS:-}"
  printf 'vertex_project=%s\n' "${ANTHROPIC_VERTEX_PROJECT_ID:-}"
  printf 'vertex_url=%s\n' "${ANTHROPIC_VERTEX_BASE_URL:-}"
  printf 'vertex_haiku_region=%s\n' "${VERTEX_REGION_CLAUDE_HAIKU_4_5:-}"
  printf 'vertex_sonnet_region=%s\n' "${VERTEX_REGION_CLAUDE_4_6_SONNET:-}"
  printf 'vertex_invalid_region_present=%s\n' "${VERTEX_REGION_CLAUDE_SECRET_1+x}"
  printf 'vertex_extra_region_present=%s\n' "${VERTEX_REGION_CLAUDE_HAIKU_4_5_EXTRA+x}"
  printf 'foundry_resource=%s\n' "${ANTHROPIC_FOUNDRY_RESOURCE:-}"
  printf 'foundry_url=%s\n' "${ANTHROPIC_FOUNDRY_BASE_URL:-}"
  printf 'foundry_key=%s\n' "${ANTHROPIC_FOUNDRY_API_KEY:-}"
  printf 'foundry_token=%s\n' "${ANTHROPIC_FOUNDRY_AUTH_TOKEN:-}"
  printf 'azure_client_id=%s\n' "${AZURE_CLIENT_ID:-}"
  printf 'azure_tenant_id=%s\n' "${AZURE_TENANT_ID:-}"
  printf 'azure_client_secret=%s\n' "${AZURE_CLIENT_SECRET:-}"
  printf 'azure_config_dir=%s\n' "${AZURE_CONFIG_DIR:-}"
  printf 'claude_config_dir=%s\n' "${CLAUDE_CONFIG_DIR:-}"
  printf 'main_model=%s\n' "${ANTHROPIC_MODEL:-}"
  printf 'opus_deployment=%s\n' "${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
  printf 'sonnet_deployment=%s\n' "${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
  printf 'haiku_deployment=%s\n' "${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
  printf 'opus_pin_present=%s\n' "${ANTHROPIC_DEFAULT_OPUS_MODEL+x}"
  printf 'sonnet_pin_present=%s\n' "${ANTHROPIC_DEFAULT_SONNET_MODEL+x}"
  printf 'haiku_pin_present=%s\n' "${ANTHROPIC_DEFAULT_HAIKU_MODEL+x}"
  printf 'subagent_pin_present=%s\n' "${CLAUDE_CODE_SUBAGENT_MODEL+x}"
  printf 'base=%s\n' "${ANTHROPIC_BASE_URL:-}"
  printf 'api_key=%s\n' "${ANTHROPIC_API_KEY:-}"
  printf 'auth_token=%s\n' "${ANTHROPIC_AUTH_TOKEN:-}"
} > "$_capture_file"
MOCK
chmod +x "$TMP_DIR/claude"

CLAUDE_BIN="$TMP_DIR/claude" AWS_PROFILE=audit-profile \
  AWS_SHARED_CREDENTIALS_FILE="$TMP_DIR/aws credentials" \
  AWS_CONFIG_FILE="$TMP_DIR/aws config" \
  ANTHROPIC_BEDROCK_BASE_URL=https://bedrock-runtime.example.test \
  ANTHROPIC_BEDROCK_REGION_PREFIX=eu \
  ANTHROPIC_BEDROCK_SERVICE_TIER=priority \
  CLAUDE_CODE_SKIP_AWS_CRED_CACHE=1 \
  CLAUDE_CODE_AWS_CHAIN_RESOLVE_TIMEOUT_MS=90000 \
  "$ROOT_DIR/bin/crouter" bedrock --version
grep -q '^bedrock=1$' "$TMP_DIR/bedrock"
grep -q '^aws_profile=audit-profile$' "$TMP_DIR/bedrock"
grep -Fxq "aws_credentials_file=$TMP_DIR/aws credentials" "$TMP_DIR/bedrock"
grep -Fxq "aws_config_file=$TMP_DIR/aws config" "$TMP_DIR/bedrock"
grep -q '^bedrock_url=https://bedrock-runtime.example.test$' "$TMP_DIR/bedrock"
grep -q '^bedrock_prefix=eu$' "$TMP_DIR/bedrock"
grep -q '^bedrock_tier=priority$' "$TMP_DIR/bedrock"
grep -q '^aws_cache_skip=1$' "$TMP_DIR/bedrock"
grep -q '^aws_chain_timeout=90000$' "$TMP_DIR/bedrock"
grep -q '^opus_pin_present=$' "$TMP_DIR/bedrock"
grep -q '^sonnet_pin_present=$' "$TMP_DIR/bedrock"
grep -q '^haiku_pin_present=$' "$TMP_DIR/bedrock"
grep -q '^subagent_pin_present=$' "$TMP_DIR/bedrock"
grep -q '^base=$' "$TMP_DIR/bedrock"
grep -q '^api_key=$' "$TMP_DIR/bedrock"
grep -q '^auth_token=$' "$TMP_DIR/bedrock"

CLAUDE_BIN="$TMP_DIR/claude" \
  ANTHROPIC_DEFAULT_OPUS_MODEL=us.anthropic.claude-opus-5-5 \
  ANTHROPIC_DEFAULT_SONNET_MODEL=us.anthropic.claude-sonnet-4-6 \
  ANTHROPIC_DEFAULT_HAIKU_MODEL=us.anthropic.claude-haiku-4-5 \
  CLAUDE_CODE_SUBAGENT_MODEL=us.anthropic.claude-sonnet-4-6 \
  "$ROOT_DIR/bin/crouter" bedrock --version
grep -q '^opus_deployment=us.anthropic.claude-opus-5-5$' "$TMP_DIR/bedrock"
grep -q '^sonnet_deployment=us.anthropic.claude-sonnet-4-6$' "$TMP_DIR/bedrock"
grep -q '^haiku_deployment=us.anthropic.claude-haiku-4-5$' "$TMP_DIR/bedrock"
grep -q '^subagent_pin_present=x$' "$TMP_DIR/bedrock"

CLAUDE_BIN="$TMP_DIR/claude" ANTHROPIC_VERTEX_PROJECT_ID=audit-project \
  ANTHROPIC_VERTEX_BASE_URL=https://aiplatform.example.test \
  VERTEX_REGION_CLAUDE_HAIKU_4_5=us-east5 \
  VERTEX_REGION_CLAUDE_4_6_SONNET=europe-west1 \
  VERTEX_REGION_CLAUDE_SECRET_1=must-not-pass \
  VERTEX_REGION_CLAUDE_HAIKU_4_5_EXTRA=must-not-pass \
  "$ROOT_DIR/bin/crouter" vertex --version
grep -q '^vertex=1$' "$TMP_DIR/vertex"
grep -q '^vertex_project=audit-project$' "$TMP_DIR/vertex"
grep -q '^vertex_url=https://aiplatform.example.test$' "$TMP_DIR/vertex"
grep -q '^vertex_haiku_region=us-east5$' "$TMP_DIR/vertex"
grep -q '^vertex_sonnet_region=europe-west1$' "$TMP_DIR/vertex"
grep -q '^vertex_invalid_region_present=$' "$TMP_DIR/vertex"
grep -q '^vertex_extra_region_present=$' "$TMP_DIR/vertex"
grep -q '^opus_pin_present=$' "$TMP_DIR/vertex"
grep -q '^sonnet_pin_present=$' "$TMP_DIR/vertex"
grep -q '^haiku_pin_present=$' "$TMP_DIR/vertex"
grep -q '^subagent_pin_present=$' "$TMP_DIR/vertex"
grep -q '^base=$' "$TMP_DIR/vertex"

CLAUDE_BIN="$TMP_DIR/claude" \
  ANTHROPIC_VERTEX_PROJECT_ID=audit-project \
  ANTHROPIC_DEFAULT_OPUS_MODEL=claude-opus-5-5 \
  ANTHROPIC_DEFAULT_SONNET_MODEL=claude-sonnet-5 \
  ANTHROPIC_DEFAULT_HAIKU_MODEL=claude-haiku-4-5 \
  "$ROOT_DIR/bin/crouter" vertex --version
grep -q '^opus_deployment=claude-opus-5-5$' "$TMP_DIR/vertex"
grep -q '^sonnet_deployment=claude-sonnet-5$' "$TMP_DIR/vertex"
grep -q '^haiku_deployment=claude-haiku-4-5$' "$TMP_DIR/vertex"

CLAUDE_BIN="$TMP_DIR/claude" ANTHROPIC_FOUNDRY_RESOURCE=audit-resource \
  ANTHROPIC_FOUNDRY_API_KEY=audit-key \
  ANTHROPIC_DEFAULT_SONNET_MODEL=custom-sonnet-deployment \
  ANTHROPIC_BASE_URL=https://wrong.example \
  ANTHROPIC_API_KEY=wrong-key \
  "$ROOT_DIR/bin/crouter" foundry --version
grep -q '^foundry=1$' "$TMP_DIR/foundry"
grep -q '^foundry_resource=audit-resource$' "$TMP_DIR/foundry"
grep -q '^foundry_key=audit-key$' "$TMP_DIR/foundry"
grep -q '^sonnet_deployment=custom-sonnet-deployment$' "$TMP_DIR/foundry"
grep -q '^base=$' "$TMP_DIR/foundry"
grep -q '^api_key=$' "$TMP_DIR/foundry"
grep -q '^auth_token=$' "$TMP_DIR/foundry"

CLAUDE_BIN="$TMP_DIR/claude" ANTHROPIC_FOUNDRY_RESOURCE=audit-resource \
  ANTHROPIC_FOUNDRY_AUTH_TOKEN=audit-entra-token \
  "$ROOT_DIR/bin/crouter" foundry --version
grep -q '^foundry_token=audit-entra-token$' "$TMP_DIR/foundry"
grep -q '^foundry_key=$' "$TMP_DIR/foundry"

CLAUDE_BIN="$TMP_DIR/claude" \
  ANTHROPIC_FOUNDRY_BASE_URL=https://audit-resource.services.ai.azure.com \
  "$ROOT_DIR/bin/crouter" foundry --version
grep -q '^foundry_url=https://audit-resource.services.ai.azure.com$' "$TMP_DIR/foundry"
grep -q '^foundry_resource=$' "$TMP_DIR/foundry"
grep -q '^main_model=sonnet$' "$TMP_DIR/foundry"
grep -q '^opus_pin_present=$' "$TMP_DIR/foundry"
grep -q '^sonnet_pin_present=$' "$TMP_DIR/foundry"
grep -q '^haiku_pin_present=$' "$TMP_DIR/foundry"
grep -q '^subagent_pin_present=$' "$TMP_DIR/foundry"

(
  unset ANTHROPIC_FOUNDRY_RESOURCE ANTHROPIC_FOUNDRY_BASE_URL
  CLAUDE_BIN="$TMP_DIR/claude" PATH="$WITH_AZ_PATH" \
    "$ROOT_DIR/bin/crouter" doctor foundry
) > "$TMP_DIR/doctor-missing" 2>&1
grep -q 'foundry .*auth:UNVERIFIED' "$TMP_DIR/doctor-missing"
grep -q '^note  Foundry endpoint not visible to crouter; check ANTHROPIC_FOUNDRY_RESOURCE or ANTHROPIC_FOUNDRY_BASE_URL in the shell, config.sh, or Claude settings$' "$TMP_DIR/doctor-missing"

(
  unset ANTHROPIC_FOUNDRY_API_KEY
  CLAUDE_BIN="$TMP_DIR/claude" PATH="$WITH_AZ_PATH" \
    ANTHROPIC_FOUNDRY_RESOURCE=audit-resource \
    ANTHROPIC_FOUNDRY_BASE_URL= "$ROOT_DIR/bin/crouter" doctor foundry
) > "$TMP_DIR/doctor-resource" 2>&1
if grep -q 'Foundry endpoint missing' "$TMP_DIR/doctor-resource"; then
  printf 'FAIL  doctor rejected Foundry with a resource name\n' >&2
  exit 1
fi

(
  unset ANTHROPIC_FOUNDRY_API_KEY
  CLAUDE_BIN="$TMP_DIR/claude" PATH="$WITH_AZ_PATH" \
    ANTHROPIC_FOUNDRY_RESOURCE= \
    ANTHROPIC_FOUNDRY_BASE_URL=https://audit-resource.services.ai.azure.com \
    "$ROOT_DIR/bin/crouter" doctor foundry
) > "$TMP_DIR/doctor-url" 2>&1
if grep -q 'Foundry endpoint missing' "$TMP_DIR/doctor-url"; then
  printf 'FAIL  doctor rejected Foundry with a base URL\n' >&2
  exit 1
fi
grep -q 'foundry .*auth:UNVERIFIED' "$TMP_DIR/doctor-url"
grep -q '^note  Azure credential chain is unverified; doctor cannot check Foundry account or model access$' "$TMP_DIR/doctor-url"

CLAUDE_BIN="$TMP_DIR/claude" PATH="$NO_AZ_PATH" \
  ANTHROPIC_FOUNDRY_RESOURCE=audit-resource \
  "$ROOT_DIR/bin/crouter" doctor foundry > "$TMP_DIR/doctor-no-auth" 2>&1
grep -q 'foundry .*auth:UNVERIFIED' "$TMP_DIR/doctor-no-auth"
grep -q '^note  Azure credential chain is unverified; doctor cannot check Foundry account or model access$' "$TMP_DIR/doctor-no-auth"

CLAUDE_BIN="$TMP_DIR/claude" PATH="$NO_AZ_PATH" \
  ANTHROPIC_FOUNDRY_RESOURCE=audit-resource \
  ANTHROPIC_FOUNDRY_API_KEY=audit-key \
  "$ROOT_DIR/bin/crouter" doctor foundry > "$TMP_DIR/doctor-key" 2>&1
grep -q 'foundry .*auth:ok' "$TMP_DIR/doctor-key"

CLAUDE_BIN="$TMP_DIR/claude" PATH="$NO_AZ_PATH" \
  ANTHROPIC_FOUNDRY_RESOURCE=audit-resource \
  ANTHROPIC_FOUNDRY_AUTH_TOKEN=audit-entra-token \
  "$ROOT_DIR/bin/crouter" doctor foundry > "$TMP_DIR/doctor-token" 2>&1
grep -q 'foundry .*auth:ok' "$TMP_DIR/doctor-token"

CLAUDE_BIN="$TMP_DIR/claude" "$ROOT_DIR/bin/crouter" doctor bedrock > "$TMP_DIR/doctor-bedrock" 2>&1
grep -q 'bedrock .*auth:UNVERIFIED' "$TMP_DIR/doctor-bedrock"
grep -q '^note  AWS credential chain is unverified; doctor cannot check Bedrock account or model access$' "$TMP_DIR/doctor-bedrock"

CLAUDE_BIN="$TMP_DIR/claude" ANTHROPIC_VERTEX_PROJECT_ID= \
  "$ROOT_DIR/bin/crouter" doctor vertex > "$TMP_DIR/doctor-vertex-missing" 2>&1
grep -q 'vertex .*auth:UNVERIFIED' "$TMP_DIR/doctor-vertex-missing"
grep -q '^note  Vertex project not visible to crouter; check ANTHROPIC_VERTEX_PROJECT_ID in the shell, config.sh, or Claude settings$' "$TMP_DIR/doctor-vertex-missing"
CLAUDE_BIN="$TMP_DIR/claude" ANTHROPIC_VERTEX_PROJECT_ID=audit-project \
  "$ROOT_DIR/bin/crouter" doctor vertex > "$TMP_DIR/doctor-vertex" 2>&1
grep -q 'vertex .*auth:UNVERIFIED' "$TMP_DIR/doctor-vertex"
grep -q '^note  Google ADC is unverified; doctor cannot check Vertex project or model access$' "$TMP_DIR/doctor-vertex"

# An unexported config.sh assignment must reach the same child that doctor checks.
CONFIG_ROOT="$TMP_DIR/config-root"
mkdir -p "$CONFIG_ROOT/bin"
cp "$ROOT_DIR/bin/crouter" "$CONFIG_ROOT/bin/crouter"
ln -s "$ROOT_DIR/lib" "$CONFIG_ROOT/lib"
ln -s "$ROOT_DIR/providers" "$CONFIG_ROOT/providers"
ln -s "$ROOT_DIR/VERSION" "$CONFIG_ROOT/VERSION"
cat > "$CONFIG_ROOT/config.sh" <<CONFIG
ANTHROPIC_FOUNDRY_RESOURCE=config-resource
ANTHROPIC_FOUNDRY_API_KEY=config-key
ANTHROPIC_DEFAULT_SONNET_MODEL=config-sonnet-deployment
AZURE_CONFIG_DIR="$TMP_DIR/azure-config"
CLAUDE_CONFIG_DIR="$TMP_DIR/claude-config"
CONFIG

CLAUDE_BIN="$TMP_DIR/claude" "$CONFIG_ROOT/bin/crouter" foundry --version
grep -q '^foundry_resource=config-resource$' "$TMP_DIR/foundry"
grep -q '^foundry_key=config-key$' "$TMP_DIR/foundry"
grep -q '^sonnet_deployment=config-sonnet-deployment$' "$TMP_DIR/foundry"
grep -Fxq "azure_config_dir=$TMP_DIR/azure-config" "$TMP_DIR/foundry"
grep -Fxq "claude_config_dir=$TMP_DIR/claude-config" "$TMP_DIR/foundry"
CLAUDE_BIN="$TMP_DIR/claude" PATH="$NO_AZ_PATH" \
  "$CONFIG_ROOT/bin/crouter" doctor foundry > "$TMP_DIR/doctor-config" 2>&1
grep -q 'foundry .*auth:ok' "$TMP_DIR/doctor-config"

# Each native backend receives only its declared unexported config.sh values.
cat > "$CONFIG_ROOT/config.sh" <<CONFIG
AWS_SHARED_CREDENTIALS_FILE="$TMP_DIR/config aws credentials"
AWS_CONFIG_FILE="$TMP_DIR/config aws config"
ANTHROPIC_BEDROCK_BASE_URL=https://config-bedrock.example.test
ANTHROPIC_DEFAULT_HAIKU_MODEL=us.anthropic.config-haiku
CLAUDE_CONFIG_DIR="$TMP_DIR/claude-config"
CONFIG
CLAUDE_BIN="$TMP_DIR/claude" "$CONFIG_ROOT/bin/crouter" bedrock --version
grep -Fxq "aws_credentials_file=$TMP_DIR/config aws credentials" "$TMP_DIR/bedrock"
grep -Fxq "aws_config_file=$TMP_DIR/config aws config" "$TMP_DIR/bedrock"
grep -q '^bedrock_url=https://config-bedrock.example.test$' "$TMP_DIR/bedrock"
grep -q '^haiku_deployment=us.anthropic.config-haiku$' "$TMP_DIR/bedrock"
grep -Fxq "claude_config_dir=$TMP_DIR/claude-config" "$TMP_DIR/bedrock"

cat > "$CONFIG_ROOT/config.sh" <<CONFIG
ANTHROPIC_VERTEX_PROJECT_ID=config-project
ANTHROPIC_VERTEX_BASE_URL=https://config-vertex.example.test
VERTEX_REGION_CLAUDE_HAIKU_4_5=asia-southeast1
VERTEX_REGION_CLAUDE_SECRET_1=must-not-pass
ANTHROPIC_DEFAULT_SONNET_MODEL=config-vertex-sonnet
CLAUDE_CONFIG_DIR="$TMP_DIR/claude-config"
CONFIG
CLAUDE_BIN="$TMP_DIR/claude" "$CONFIG_ROOT/bin/crouter" vertex --version
grep -q '^vertex_project=config-project$' "$TMP_DIR/vertex"
grep -q '^vertex_url=https://config-vertex.example.test$' "$TMP_DIR/vertex"
grep -q '^vertex_haiku_region=asia-southeast1$' "$TMP_DIR/vertex"
grep -q '^vertex_invalid_region_present=$' "$TMP_DIR/vertex"
grep -q '^sonnet_deployment=config-vertex-sonnet$' "$TMP_DIR/vertex"
grep -Fxq "claude_config_dir=$TMP_DIR/claude-config" "$TMP_DIR/vertex"

cat > "$CONFIG_ROOT/config.sh" <<CONFIG
ANTHROPIC_FOUNDRY_RESOURCE=config-resource
ANTHROPIC_FOUNDRY_AUTH_TOKEN=config-bearer
AZURE_CLIENT_ID=config-client
AZURE_TENANT_ID=config-tenant
AZURE_CLIENT_SECRET=config-secret
CLAUDE_CONFIG_DIR="$TMP_DIR/claude-config"
CONFIG
CLAUDE_BIN="$TMP_DIR/claude" "$CONFIG_ROOT/bin/crouter" foundry --version
grep -q '^foundry_token=config-bearer$' "$TMP_DIR/foundry"
grep -q '^azure_client_id=config-client$' "$TMP_DIR/foundry"
grep -q '^azure_tenant_id=config-tenant$' "$TMP_DIR/foundry"
grep -q '^azure_client_secret=config-secret$' "$TMP_DIR/foundry"
grep -Fxq "claude_config_dir=$TMP_DIR/claude-config" "$TMP_DIR/foundry"

# The custom Claude settings directory is limited to native cloud backends.
CLAUDE_BIN="$TMP_DIR/claude" ANTHROPIC_API_KEY=audit-anthropic \
  "$CONFIG_ROOT/bin/crouter" anthropic --version
grep -q '^claude_config_dir=$' "$TMP_DIR/vertex"
grep -q '^foundry_token=$' "$TMP_DIR/vertex"

printf 'ok    Bedrock, Vertex and Foundry launch through native Claude Code backends\n'
