# Provider Testing & Verification Reference

This reference documents the test suites and commands required to verify provider contracts, session assets, and unified routing in `crouter`.

---

## 1. Five-Layer Verification Checklist

Every provider modification must be verified against all five layers:

```
[Layer 1: POSIX Syntax] -> [Layer 2: Matrix Contract] -> [Layer 3: Asset Isolation] -> [Layer 4: Gateway Route] -> [Layer 5: Full Regression]
```

---

## 2. Layer 1: POSIX Shell Syntax & Portability

`crouter` runs under standard POSIX `/bin/sh` across macOS, Debian/Ubuntu (`dash`), and BSD.

Run syntax checks with both `sh` and `dash`:
```sh
sh -n providers/<provider>.sh
dash -n providers/<provider>.sh
```

Common pitfalls to avoid:
- ❌ Do NOT use `[[ ... ]]`; use `[ ... ]`.
- ❌ Do NOT use `function name()`; use `name()`.
- ❌ Do NOT use `local var`; use global or prefixed variables (e.g. `_var`).
- ❌ Do NOT use bash arrays `arr=(...)` or `${arr[@]}`.

---

## 3. Layer 2: Provider Contract Matrix (`test/provider-matrix.sh`)

Add assertions in `test/provider-matrix.sh` for the provider:

```sh
load myprovider
assert_eq myprovider.base "https://api.myprovider.com/plan" "$BASE_URL"
assert_eq myprovider.auth surfaces "$AUTH_MODE"
assert_eq myprovider.model myprovider-flagship-coding "$MODEL"
assert_eq myprovider.context 1000000 "$CONTEXT_TOKENS"
assert_eq myprovider.effort high "$EFFORT"
```

For dual-surface providers, also assert plan and API fields:
```sh
assert_eq myprovider.plan-url "https://api.myprovider.com/plan" "$PLAN_URL"
assert_eq myprovider.api-url "https://api.myprovider.com/v1" "$API_URL"
```

Run the matrix test suite:
```sh
sh test/provider-matrix.sh
dash test/provider-matrix.sh
```

---

## 4. Layer 3: Provider Asset & MCP Isolation (`test/provider-assets.sh`)

If the provider configures companion tools in `lib/provider-assets.js`, add test cases in `test/provider-assets.sh`:

```sh
# 1. Verify rendering when token is provided
rendered=$(CR_PLAN_TOKEN="test-plan-token" "$NODE_BIN" "$LIB_DIR/provider-assets.js" render myprovider "$tmp_config" && cat "$tmp_config")
echo "$rendered" | grep -q 'crouter-myprovider-search' || die "myprovider MCP not rendered with token"

# 2. Verify suppression when token is absent
empty_rendered=$(CR_PLAN_TOKEN="" "$NODE_BIN" "$LIB_DIR/provider-assets.js" render myprovider "$tmp_config" && cat "$tmp_config")
echo "$empty_rendered" | grep -q 'crouter-myprovider-search' && die "myprovider MCP should be omitted without token"
```

Run the asset isolation test suite:
```sh
sh test/provider-assets.sh
dash test/provider-assets.sh
```

---

## 5. Layer 4: Unified Gateway Route Check (`crouter all --check`)

Validate that `crouter all` correctly discovers and parses the provider without performing network calls:

```sh
./bin/crouter all --check
```

Confirm:
- The provider appears under remote or local routes.
- Sensitive API keys or plan keys are redacted (`[present]`).
- Model routes map to `<provider>/<model>` correctly.

---

## 6. Layer 5: Launcher Installation & Full Regression

### 1. Update compatibility launcher symlinks
`install.sh` scans `providers/` and creates a `bin/claude-<provider>` symlink for each provider script:
```sh
./install.sh
test -L "bin/claude-<provider>" || die "Symlink bin/claude-<provider> missing"
```

### 2. Run all repository test suites
```sh
for test_file in test/*.sh; do sh "$test_file" || exit 1; done
for test_file in test/*.sh; do dash "$test_file" || exit 1; done
```

### 3. Check git diff for unintended changes
```sh
git diff --check
```
