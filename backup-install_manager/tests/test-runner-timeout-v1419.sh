#!/usr/bin/env bash
# Перевірка типового та явно заданого тайм-ауту без затримки тестів.
set -Eeuo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cat > "$tmp/timeout" <<'WRAPPER'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SETUP_TIMEOUT_TRACE"
exit 124
WRAPPER
chmod +x "$tmp/timeout"
export SETUP_TIMEOUT_TRACE="$tmp/trace"
output=''
if output="$(env -u SETUP_TEST_TIMEOUT PATH="$tmp:$PATH" SETUP_TEST_ONLY=test-no-clear bash "$PROJECT_DIR/tests/run-tests.sh" 2>&1)"; then
    printf '[FAIL] Ліміт часу не завершив підтест\n' >&2
    exit 1
fi
[[ "$output" == *'перевищено ліміт 60 с'* ]] || exit 1
grep -F -- '60s bash' "$SETUP_TIMEOUT_TRACE" >/dev/null || exit 1
: > "$SETUP_TIMEOUT_TRACE"
if output="$(SETUP_TEST_TIMEOUT=17 PATH="$tmp:$PATH" SETUP_TEST_ONLY=test-no-clear bash "$PROJECT_DIR/tests/run-tests.sh" 2>&1)"; then
    printf '[FAIL] Користувацький ліміт часу не застосовано\n' >&2
    exit 1
fi
[[ "$output" == *'перевищено ліміт 17 с'* ]] || exit 1
grep -F -- '17s bash' "$SETUP_TIMEOUT_TRACE" >/dev/null || exit 1
printf '[PASS] test-runner-timeout-v1419\n'
