#!/usr/bin/env bash
# Перевірка підсумку успішного та невдалого запусків.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
output="$(SETUP_TEST_ONLY=test-no-clear SETUP_TEST_SLOW_THRESHOLD=0 bash "$ROOT_DIR/tests/run-tests.sh" 2>&1)"
[[ "$output" == *'=== Підсумок тестування ==='* ]]
[[ "$output" == *'FAIL: 0'* ]]
[[ "$output" == *'Повільні тести (від 0 с):'* ]]
[[ "$output" == *'test-no-clear — '* ]]
[[ "$output" =~ PASS:\ [0-9]+\ \|\ FAIL:\ 0\ \|\ SKIP:\ [0-9]+\ \|\ Час:\ [0-9]+\ с ]]
cat > "$tmp/timeout" <<'WRAPPER'
#!/usr/bin/env bash
exit 124
WRAPPER
chmod +x "$tmp/timeout"
if output="$(SETUP_TEST_TIMEOUT=60 SETUP_TEST_ONLY=test-no-clear PATH="$tmp:$PATH" bash "$ROOT_DIR/tests/run-tests.sh" 2>&1)"; then
    printf '[FAIL] Очікувався ненульовий код виходу\n' >&2
    exit 1
fi
[[ "$output" == *'перевищено ліміт 60 с'* ]]
[[ "$output" == *'FAIL: 1'* ]]
[[ "$output" == *'=== Підсумок тестування ==='* ]]
printf '[PASS] test-runner-summary-v1420\n'
