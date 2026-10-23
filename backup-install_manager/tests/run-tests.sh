#!/usr/bin/env bash
# Загальний ранер тестів.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Всі вкладені CLI-процеси успадковують заборону на clear.
export SETUP_TEST_MODE=true
# Негативні тести не мають забруднювати logs/ реального проєкту.
_test_log_dir="$(mktemp -d)"
# Підсумок виводиться також після помилки або тайм-ауту.
runner_started="$(date +%s)"
runner_pass=0
runner_fail=0
runner_skip=0
runner_slow=()
runner_failed_tests=()
SETUP_TEST_SLOW_THRESHOLD="${SETUP_TEST_SLOW_THRESHOLD:-3}"
if [[ ! "$SETUP_TEST_SLOW_THRESHOLD" =~ ^[0-9]+$ ]] || (( ${#SETUP_TEST_SLOW_THRESHOLD} > 6 )); then
    printf '[FAIL] SETUP_TEST_SLOW_THRESHOLD має бути числом 0–999999\n' >&2
    exit 1
fi
SETUP_TEST_SLOW_THRESHOLD=$((10#$SETUP_TEST_SLOW_THRESHOLD))
runner_summary() {
    local elapsed
    elapsed=$(( $(date +%s) - runner_started ))
    printf '\n=== Підсумок тестування ===\n'
    printf 'PASS: %s | FAIL: %s | SKIP: %s | Час: %s с\n' \
        "$runner_pass" "$runner_fail" "$runner_skip" "$elapsed"
    printf 'Повільні тести (від %s с):\n' "$SETUP_TEST_SLOW_THRESHOLD"
    if ((${#runner_slow[@]} == 0)); then
        printf '  Немає\n'
    else
        printf '%s\n' "${runner_slow[@]}" | LC_ALL=C sort -t $'\t' -k1,1nr -k2,2 | while IFS=$'\t' read -r duration name; do
            printf '  %s — %s с\n' "$name" "$duration"
        done
    fi
    printf 'Невдалі тести:\n'
    if ((${#runner_failed_tests[@]} == 0)); then
        printf '  Немає\n'
    else
        printf '  %s\n' "${runner_failed_tests[@]}"
    fi
}
runner_cleanup() {
    local rc=$?
    trap - EXIT
    runner_summary
    if (( rc == 0 && runner_fail == 0 )); then
        printf '[OK] Фінальний статус: УСПІХ\n'
    else
        printf '[FAIL] Фінальний статус: ПОМИЛКА\n'
    fi
    rm -rf -- "$_test_log_dir"
    return "$rc"
}
trap runner_cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
export SETUP_LOG_FILE="$_test_log_dir/setup-tests.log"
pass() { runner_pass=$((runner_pass + 1)); printf '[PASS] %s\n' "$*"; }
fail() { runner_fail=$((runner_fail + 1)); runner_failed_tests+=("$*"); printf '[FAIL] %s\n' "$*" >&2; exit 1; }

# 1. Синтаксис усіх .sh.
while IFS= read -r -d '' f; do
    bash -n "$f" || fail "Синтаксис $f"
done < <(find "$ROOT_DIR" -name '*.sh' -type f -print0)
pass 'Синтаксис Bash'

# 2. Версія.
expected="$(bash -c 'source "$1/config/setup.conf"; source "$1/src/core/version.sh"; printf "%s" "$SETUP_VERSION"' bash "$ROOT_DIR")"
[[ "$(bash "$ROOT_DIR/backup-install_manager.sh" --version)" == "$expected" ]] || fail 'Версія'
pass 'Версія'

# 3. Реєстр модулів.
mapfile -t ids < <(bash "$ROOT_DIR/backup-install_manager.sh" packages --list | awk '{print $1}')
(( ${#ids[@]} >= 1 )) || fail 'Реєстр порожній'
pass "Реєстр: ${#ids[@]} модулів"

# 4. Help містить усі команди. Зберігаємо вивід один раз:
# grep -q у pipe з pipefail може спричинити SIGPIPE (код 141) у producer.
help_output="$(bash "$ROOT_DIR/backup-install_manager.sh" --help)" || fail 'Help: execution'
[[ "$help_output" == *'sources add'* ]] || fail 'Help: sources add'
[[ "$help_output" == *'archive'* ]] || fail 'Help: archive'
[[ "$help_output" == *'recovery'* ]] || fail 'Help: recovery'
[[ "$help_output" == *'dotfiles plan'* ]] || fail 'Help: dotfiles plan'
[[ "$help_output" == *'recovery list|verify'* ]] || fail 'Help: recovery verify'
[[ "$help_output" == *'dotfiles backup changed'* ]] || fail 'Help: backup changed'
dotfiles_help="$(bash "$ROOT_DIR/backup-install_manager.sh" dotfiles --help)" || fail 'Help: dotfiles execution'
[[ "$dotfiles_help" == *'dotfiles backup changed'* ]] || fail 'Help: dotfiles --help'
pass 'Help'

# Ліміт часу для окремого підтесту: типово 60 с, 0 — без обмеження.
SETUP_TEST_TIMEOUT="${SETUP_TEST_TIMEOUT:-60}"
if [[ ! "$SETUP_TEST_TIMEOUT" =~ ^[0-9]+$ ]] || (( ${#SETUP_TEST_TIMEOUT} > 6 )); then
    fail 'SETUP_TEST_TIMEOUT має бути цілим числом секунд (0–999999)'
fi
SETUP_TEST_TIMEOUT=$((10#$SETUP_TEST_TIMEOUT))
if (( SETUP_TEST_TIMEOUT > 0 )) && ! command -v timeout >/dev/null 2>&1; then
    fail 'Для SETUP_TEST_TIMEOUT потрібна команда timeout'
fi

# 5. Підтести. За потреби запускаємо лише вибрані через SETUP_TEST_ONLY.
ALL_TESTS=(test-docs-menu-v202 test-backups-menu-hints-v201 test-backups-menu-lock-v201 test-entrypoint-rename test-packages-empty-stage-v201 test-dotfiles-status-ui-v201 test-module-graph-v200 test-reports-v200 test-update-safety-v151 test-release-contract-v1440 test-cli-contract-v1439 test-hooks-contract-v1438 test-packages-contract-v1437 test-recovery-integrity-v1436 test-fs-safety-v1435 test-exit-cleanup-v1434 test-hook-isolation-v1433 test-dependency-order-v1432 test-source-audit-v1431 test-release-layout-v1430 test-audit-functions-v1429 test-configs-executor-v1428 test-registry-reload-v1427 test-cli-flags-v1426 test-structure-audit-v1425 test-structure-v1424 test-bootstrap-v1423 test-hook-runtime-v1422 test-runner-report-v1421 test-runner-summary-v1420 test-runner-timeout-v1419 test-packages-unified-doctor-v1418 test-packages-syntax-v1417 test-packages-diagnostics-v1416 test-configs-dedup-v1415 test-packages-validation-v1414 test-configs-group-v1413 test-menu-escape-v1412 test-dotfiles-menu-groups-v1411 test-path-context-v1410 test-migration-v1410 test-path-registry-v1410 test-path-operations-v1410 test-path test-fs test-apply test-sources test-sync test-archive test-recovery test-scan test-safety test-lock test-validation test-cli test-plan test-verify test-recovery-integrity test-no-clear test-backup-changed test-rollback-v3 test-recovery-selective test-rotation-v3 test-backups-v3 test-logs-v3 test-status-color test-status-counts test-snapper test-sources-v4 test-dotfiles-groups-v149 test-registry-order test-packages-batch test-packages-failure-v144 test-packages-bound-v145 test-packages-config-bound-v146 test-packages-stage-order-v147 test-packages-config-failure-v148 test-symlinks-v4 test-sync-classify-v4 test-system-restore-v4 test-system-copy-v4 test-transaction-safety-v4 test-rollback-verify-v4 test-menu-layout-v4 test-packages-config-v4 test-packages-doctor-v141 test-hooks-standalone-v4 test-hooks-failure-v142 test-unified-logging-v4 test-log-lifecycle-v143)
SELECTED_TESTS=("${ALL_TESTS[@]}")

if [[ -n "${SETUP_TEST_ONLY:-}" ]]; then
    read -r -a SELECTED_TESTS <<< "$SETUP_TEST_ONLY"
    (( ${#SELECTED_TESTS[@]} > 0 )) || fail 'SETUP_TEST_ONLY порожній'
    for requested in "${SELECTED_TESTS[@]}"; do
        valid=false
        for available in "${ALL_TESTS[@]}"; do
            if [[ "$requested" == "$available" ]]; then
                valid=true
                break
            fi
        done
        [[ "$valid" == true ]] || fail "Невідомий підтест: $requested"
    done
fi

for t in "${SELECTED_TESTS[@]}"; do
    f="$ROOT_DIR/tests/$t.sh"
    [[ -f "$f" ]] || fail "Відсутній підтест: $t"
    printf '[RUN] %s\n' "$t"
    started="$(date +%s)"
    rc=0
    if (( SETUP_TEST_TIMEOUT > 0 )); then
        timeout --signal=TERM --kill-after=5s "${SETUP_TEST_TIMEOUT}s" bash "$f" || rc=$?
    else
        bash "$f" || rc=$?
    fi
    elapsed=$(( $(date +%s) - started ))
    if (( elapsed >= SETUP_TEST_SLOW_THRESHOLD )); then
        runner_slow+=("$elapsed"$'\t'"$t")
    fi
    if (( rc == 124 )); then
        runner_fail=$((runner_fail + 1))
        runner_failed_tests+=("$t — тайм-аут ${SETUP_TEST_TIMEOUT} с")
        printf '[FAIL] %s: перевищено ліміт %s с (SETUP_TEST_TIMEOUT)\n' "$t" "$SETUP_TEST_TIMEOUT" >&2
        exit 1
    fi
    if (( rc != 0 )); then
        runner_fail=$((runner_fail + 1))
        runner_failed_tests+=("$t — код $rc")
        printf '[FAIL] %s (код %s, %s с)\n' "$t" "$rc" "$elapsed" >&2
        exit 1
    fi
    runner_pass=$((runner_pass + 1))
    printf '[DONE] %s (%s с)\n' "$t" "$elapsed"
done
pass 'Підтести'

# 6. ShellCheck.
if command -v shellcheck >/dev/null 2>&1; then
    mapfile -d '' -t files < <(find "$ROOT_DIR" -name '*.sh' -type f -print0)
    shellcheck -x --source-path=SCRIPTDIR -S warning "${files[@]}" || fail 'ShellCheck'
    pass 'ShellCheck'
else
    runner_skip=$((runner_skip + 1))
    printf '[SKIP] ShellCheck\n'
fi

printf '\n[PASS] Усі перевірки пройдено\n'
