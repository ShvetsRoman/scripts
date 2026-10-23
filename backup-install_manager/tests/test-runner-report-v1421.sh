#!/usr/bin/env bash
# Регресійна перевірка фінального звіту й упорядкування тривалостей.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT

# При рівних тривалостях сортуємо назви для відтворюваності.
# Не успадковуємо тайм-аут зовнішнього запуску: тут перевіряємо звіт,
# а поведінку timeout окремо моделюємо нижче.
if ! output="$(SETUP_TEST_TIMEOUT=0 SETUP_TEST_ONLY='test-no-clear test-registry-order' SETUP_TEST_SLOW_THRESHOLD=0 bash "$ROOT_DIR/tests/run-tests.sh" 2>&1)"; then
    printf '[FAIL] Вкладений ранер завершився з помилкою:\n%s\n' "$output" >&2
    exit 1
fi
assert_output() {
    local expected="$1" description="$2"
    if [[ "$output" != *"$expected"* ]]; then
        printf '[FAIL] %s: очікувався рядок %q\n' "$description" "$expected" >&2
        printf '%s\n' "$output" >&2
        exit 1
    fi
}

assert_output 'Фінальний статус: УСПІХ' 'фінальний статус першого запуску'
assert_output 'Невдалі тести:' 'розділ невдалих тестів'
assert_output 'FAIL: 0' 'лічильник помилок'
assert_output 'Повільні тести (від 0 с):' 'поріг повільних тестів'
assert_output 'test-registry-order — ' 'тривалість registry-order'
assert_output 'test-no-clear — ' 'тривалість no-clear'

# Інжектований тайм-аут перевіряє звіт при аварійному завершенні.
cat > "$tmp/timeout" <<'WRAPPER'
#!/usr/bin/env bash
exit 124
WRAPPER
chmod +x "$tmp/timeout"
if output="$(PATH="$tmp:$PATH" SETUP_TEST_TIMEOUT=60 SETUP_TEST_ONLY=test-no-clear bash "$ROOT_DIR/tests/run-tests.sh" 2>&1)"; then
    printf '[FAIL] Очікувався ненульовий код\n' >&2
    exit 1
fi
assert_output 'test-no-clear — тайм-аут 60 с' 'повідомлення про тайм-аут'
assert_output 'Фінальний статус: ПОМИЛКА' 'аварійний статус'
assert_output 'FAIL: 1' 'лічильник помилок аварійного запуску'

# Перевірка сортування на синтетичних, різних тривалостях.
report_fn="$(sed -n '/^runner_summary() {/,/^}/p' "$ROOT_DIR/tests/run-tests.sh")"
report="$(bash -c '
    runner_started=$(date +%s)
    runner_pass=3 runner_fail=0 runner_skip=0
    SETUP_TEST_SLOW_THRESHOLD=0
    runner_failed_tests=()
    runner_slow=($'"'"'4\ttest-short'"'"' $'"'"'9\ttest-long'"'"' $'"'"'4\ttest-alpha'"'"')
    eval "$1"
    runner_summary
' bash "$report_fn")"
order="$(printf '%s\n' "$report" | grep ' — [0-9]* с$')"
if [[ "$order" != $'  test-long — 9 с\n  test-alpha — 4 с\n  test-short — 4 с' ]]; then
    printf '[FAIL] Порядок сортування тривалостей:\n%s\n' "$order" >&2
    exit 1
fi
printf '[PASS] test-runner-report-v1421\n'
