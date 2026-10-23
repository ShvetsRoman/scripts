#!/usr/bin/env bash
# Перевірка кодів завершення та очищення тестового середовища.
set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
printf '%s\n' \
    "trap 'exit 130' INT" \
    "trap 'exit 143' TERM" > "$tmp/signals.sh"
for pair in 'INT 130' 'TERM 143'; do
    read -r signal expected <<< "$pair"
    rc=0
    bash -c 'source "$1"; kill -s "$2" "$BASHPID"' bash "$tmp/signals.sh" "$signal" >/dev/null 2>&1 || rc=$?
    [[ "$rc" == "$expected" ]]
done
# Збереження коду завершення CLI на невідомій команді.
rc=0
SETUP_TEST_MODE=true bash "$root/backup-install_manager.sh" __invalid_command__ >/dev/null 2>&1 || rc=$?
[[ "$rc" != 0 ]]
# Функція cleanup тестового ранера зберігає exit status.
grep -Fq 'local rc=$?' "$root/tests/run-tests.sh"
grep -Fq 'rm -rf -- "$_test_log_dir"' "$root/tests/run-tests.sh"
printf '[PASS] test-exit-cleanup-v1434\n'
