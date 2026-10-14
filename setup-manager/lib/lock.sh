#!/usr/bin/env bash
# Ексклюзивний flock лише для операцій, що змінюють стан проєкту.
# Код 75 = зайнято іншим процесом (EX_TEMPFAIL).
setup_lock_acquire() {
    local file="$ROOT_DIR/.setup-manager.lock" timeout="${SETUP_LOCK_TIMEOUT:-0}"
    [[ "$timeout" =~ ^[0-9]+$ ]] || {
        log error "SETUP_LOCK_TIMEOUT має бути цілим числом від 0 до 300: $timeout"
        return 2
    }
    # 08 має інтерпретуватися як десяткове число, а не як Bash octal.
    # Обмеження довжини захищає від арифметичного переповнення.
    (( ${#timeout} <= 12 )) || { log error 'SETUP_LOCK_TIMEOUT занадто велике'; return 2; }
    timeout=$((10#$timeout))
    (( timeout <= 300 )) || { log error 'SETUP_LOCK_TIMEOUT має бути <= 300'; return 2; }
    command -v flock >/dev/null 2>&1 || { log error 'Потрібна утиліта flock'; return 2; }
    path_ok_abs "$file" && [[ ! -e "$file" || -f "$file" ]] || {
        log error "Небезпечний lock-файл: $file"; return 2
    }
    # Файл відкриваємо без обрізання: усі процеси мають бачити той самий inode.
    if ! exec {SETUP_LOCK_FD}>> "$file"; then
        log error "Не вдалося відкрити lock: $file"
        return 2
    fi
    if (( timeout > 0 )); then
        if flock -w "$timeout" "$SETUP_LOCK_FD"; then return 0; fi
    else
        if flock -n "$SETUP_LOCK_FD"; then return 0; fi
    fi
    exec {SETUP_LOCK_FD}>&-
    unset SETUP_LOCK_FD
    log error 'Setup Manager уже виконує іншу операцію запису (lock зайнято)'
    return 75
}

setup_lock_release() {
    [[ -n "${SETUP_LOCK_FD:-}" ]] || return 0
    flock -u "$SETUP_LOCK_FD" || true
    exec {SETUP_LOCK_FD}>&-
    unset SETUP_LOCK_FD
}

# У dry-run жодного lock-файла не створюємо.
# Зовнішній process завершується → дескриптор автоматично закривається.
setup_with_lock() {
    if [[ "${DRY_RUN:-false}" == true || -n "${SETUP_LOCK_FD:-}" ]]; then
        "$@"
        return $?
    fi
    setup_lock_acquire || return $?
    local rc=0
    "$@" || rc=$?
    setup_lock_release
    return "$rc"
}
