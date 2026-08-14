#!/bin/sh
# A legacy dual-source provider may declare only the compatibility token name.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PROVIDER_NAME=demo
AUTH_MODE=none
BASE_URL=https://default.example
DEFAULT_URL=https://default.example
DEFAULT_AUTH_TYPE=bearer
DEFAULT_TOKEN_ENV=
DEFAULT_TOKEN_ENV_FALLBACK=DEMO_COMPAT_TOKEN
API_KEY_ENV=
API_KEY_REF=
API_URL=
API_AUTH_TYPE=
USER=${USER:-test}

die() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
kc_get() { return 1; }

. "$ROOT_DIR/lib/provider.sh"
. "$ROOT_DIR/lib/auth.sh"

export DEMO_COMPAT_TOKEN=compat-token

is_dual_source || {
  printf 'FAIL  fallback-only token declaration was not recognized\n' >&2
  exit 1
}

resolve_dual_source
[ "$AUTH_TOKEN" = compat-token ] && [ "$_DUAL_COUNT" -eq 1 ] || {
  printf 'FAIL  fallback-only token was not resolved\n' >&2
  exit 1
}

[ "$(dual_source_state)" = default ] || {
  printf 'FAIL  fallback-only token was not reported as available\n' >&2
  exit 1
}

printf 'ok    fallback-only dual-source token is supported\n'
