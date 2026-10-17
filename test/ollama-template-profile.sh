#!/bin/sh
# Entirely offline provider-hook checks. All networking and process lifecycle
# operations are stubbed; only Node's JSON parser runs as a real child process.
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_TMP=$(mktemp -d 2>/dev/null || mktemp -d -t crouter-template-profile)
trap 'rm -rf "$TEST_TMP"' EXIT INT TERM

fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }
load_last_selected_model() { printf '%s' 'qwen3.8-27b-heretic:q4'; }
die() { printf 'provider refused: %s\n' "$*" >&2; exit 77; }

curl() {
  _stub_url=
  for _stub_arg do
    case $_stub_arg in http://*) _stub_url=$_stub_arg ;; esac
  done
  case $_stub_url in
    http://127.0.0.1:11434)
      printf 'Ollama is running\n'
      ;;
    http://127.0.0.1:11434/api/show)
      printf 'show\n' >>"$TEST_TMP/calls"
      printf '%s' "$SHOW_JSON"
      return "$SHOW_STATUS"
      ;;
    http://127.0.0.1:11435/health)
      printf 'health\n' >>"$TEST_TMP/calls"
      printf '%s' "$HEALTH_JSON"
      ;;
    *)
      printf 'unexpected-curl\n' >>"$TEST_TMP/lifecycle"
      return 99
      ;;
  esac
}
kill() { printf 'kill %s\n' "$*" >>"$TEST_TMP/lifecycle"; return 99; }
nohup() { printf 'nohup %s\n' "$*" >>"$TEST_TMP/lifecycle"; return 99; }
lsof() { printf 'lsof\n' >>"$TEST_TMP/lifecycle"; printf '987654321\n'; }
sleep() { printf 'sleep\n' >>"$TEST_TMP/lifecycle"; }

PATCHED='{"template":"{#CROUTER_QWEN_SYSTEM_ORDER_V1 padding#}{{ template_body }}"}'
UNPATCHED='{"template":"{{ original_template }}"}'
LEGACY_HEALTH='{"service":"crouter-ollama-heartbeat","effort_cap":"medium"}'
PATCHED_HEALTH='{"service":"crouter-ollama-heartbeat","effort_cap":"medium","system_order_models":"qwen3.8-27b-heretic:q4"}'

run_case() {
  _case_name=$1 SHOW_JSON=$2 SHOW_STATUS=$3 HEALTH_JSON=$4 _expected=$5
  : >"$TEST_TMP/lifecycle"
  : >"$TEST_TMP/calls"
  if (
    . "$ROOT_DIR/providers/ollama.sh"
    _main_model=qwen3.8-27b-heretic:q4
    eval "$PRE_START"
  ) >"$TEST_TMP/output" 2>&1; then
    _actual=0
  else
    _actual=$?
  fi
  if [ "$_actual" != "$_expected" ]; then
    cat "$TEST_TMP/output" >&2
    fail "$_case_name: expected exit $_expected, got $_actual"
  fi
  if [ -s "$TEST_TMP/lifecycle" ]; then
    cat "$TEST_TMP/lifecycle" >&2
    fail "$_case_name touched process lifecycle"
  fi
  grep -q '^show$' "$TEST_TMP/calls" || fail "$_case_name skipped template verification"
  if [ "$_expected" = 0 ]; then
    grep -q '^health$' "$TEST_TMP/calls" || fail "$_case_name skipped relay verification"
  fi
  printf 'ok    %s\n' "$_case_name"
}

run_case 'patched template reuses matching relay' "$PATCHED" 0 "$PATCHED_HEALTH" 0
run_case 'unpatched template reuses legacy relay' "$UNPATCHED" 0 "$LEGACY_HEALTH" 0
run_case 'system-field marker cannot enable preservation' \
  '{"template":"original","system":"{#CROUTER_QWEN_SYSTEM_ORDER_V1 padding#}"}' 0 "$LEGACY_HEALTH" 0
run_case 'modelfile-field marker cannot enable preservation' \
  '{"template":"original","modelfile":"{#CROUTER_QWEN_SYSTEM_ORDER_V1 padding#}"}' 0 "$LEGACY_HEALTH" 0
run_case 'non-prefix template marker cannot enable preservation' \
  '{"template":"original {#CROUTER_QWEN_SYSTEM_ORDER_V1 padding#}"}' 0 "$LEGACY_HEALTH" 0
run_case 'malformed JSON is rejected' '{' 0 "$LEGACY_HEALTH" 77
run_case 'missing template is rejected' '{"system":"anything"}' 0 "$LEGACY_HEALTH" 77
run_case 'non-string template is rejected' '{"template":null}' 0 "$LEGACY_HEALTH" 77
run_case 'API error is rejected even with valid marker in its body' "$PATCHED" 22 "$PATCHED_HEALTH" 77
run_case 'patched template refuses legacy relay without killing it' "$PATCHED" 0 "$LEGACY_HEALTH" 77
run_case 'unpatched template refuses preserving relay without killing it' "$UNPATCHED" 0 "$PATCHED_HEALTH" 77
