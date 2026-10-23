#!/usr/bin/env bash

# Видаляє (або у --dry-run лише показує) старі файли за шаблоном.
cleanup_files_older_than() {
    local dir="$1"
    local pattern="$2"
    local days="$3"

    [[ -d "$dir" ]] || return 0

    if [[ "$DRY_RUN" == true ]]; then
        find "$dir" -type f -name "$pattern" -mtime +"$days" -print
    else
        find "$dir" -type f -name "$pattern" -mtime +"$days" -delete
    fi
}

# Локальні recovery-каталоги. Видаляються ЛИШЕ каталоги з іменем-таймстемпом (TS_NAME_GLOB).
cleanup_ts_dirs_local() {
    local root="$1"
    local days="$2"

    [[ -d "$root" ]] || return 0

    if [[ "$DRY_RUN" == true ]]; then
        find "$root" -mindepth 1 -maxdepth 1 -type d -name "$TS_NAME_GLOB" -mtime +"$days" -print
    else
        find "$root" -mindepth 1 -maxdepth 1 -type d -name "$TS_NAME_GLOB" -mtime +"$days" -print -exec rm -rf -- {} +
    fi
}

# Те саме на сервері. Скрипт отримує значення як позиційні аргументи (жодної підстановки у рядок).
cleanup_ts_dirs_remote() {
    local script mode cmd

    # Ручний cleanup працює незалежно від перемикачів recovery: інакше після вимкнення recovery
    # раніше збережені копії лишились би на сервері назавжди.

    # shellcheck disable=SC2016  # змінні розкриваються на remote, не локально
    script='root=$1; days=$2; mode=$3; glob=$4
[ -d "$root" ] || exit 0
if [ "$mode" = dry ]; then
    find "$root" -mindepth 1 -maxdepth 1 -type d -name "$glob" -mtime +"$days" -print
else
    find "$root" -mindepth 1 -maxdepth 1 -type d -name "$glob" -mtime +"$days" -print -exec rm -rf -- {} +
fi'

    mode=run
    if [[ "$DRY_RUN" == true ]]; then
        mode=dry
    fi

    cmd="sh -c $(shq "$script") sh $(shq "${REMOTE_DIR}/${RECOVERY_ROOT}") ${KEEP_RECOVERY_DAYS} ${mode} $(shq "$TS_NAME_GLOB")"
    "${SSH_CMD[@]}" "$SSH_TARGET" "$cmd"
}

cleanup_logs() {
    log_title "CLEANUP"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "DRY-RUN: нічого не видаляється, нижче — лише список кандидатів."
    fi

    cleanup_files_older_than "$LOG_DIR" 'backup-sync_*.log' "$KEEP_LOG_DAYS"
    log_ok "Старі logs: оброблено (старші за ${KEEP_LOG_DAYS} дн.)."

    cleanup_ts_dirs_local "$LOCAL_RECOVERY_DIR" "$KEEP_LOCAL_RECOVERY_DAYS"
    log_ok "Локальний recovery (DOWN): оброблено (старші за ${KEEP_LOCAL_RECOVERY_DAYS} дн.)."

    cleanup_ts_dirs_remote
    log_ok "Remote recovery (UP): оброблено (старші за ${KEEP_RECOVERY_DAYS} дн.)."
}

# Автоматичне очищення recovery ПІСЛЯ УСПІШНОГО up/down (AUTO_CLEANUP_RECOVERY=true або --auto-cleanup).
#  - Лише без помилок: якщо щось не синхронізувалось, старі recovery-копії можуть знадобитись.
#  - Чистить recovery того напрямку, який щойно записував: up -> серверний, down -> локальний.
#  - Працює під remote-lock (його знімає on_exit вже після цього) і не торкається поточного запуску:
#    видаляються лише каталоги-таймстемпи старші за KEEP_*_DAYS.
#  - Збій очищення НІКОЛИ не змінює результат і код виходу синхронізації.
auto_cleanup_recovery() {
    local out="" rc=0 days removed

    [[ "$AUTO_CLEANUP_RECOVERY" == true ]] || return 0
    [[ "$DRY_RUN" == false ]] || return 0
    recovery_enabled || return 0

    if ((FAILED > 0)); then
        log_warn "Auto-cleanup recovery пропущено: були помилки (старі recovery-копії можуть знадобитись)."
        return 0
    fi

    log_title "AUTO-CLEANUP RECOVERY"

    if [[ "$DIRECTION" == up ]]; then
        days="$KEEP_RECOVERY_DAYS"
        out=$(cleanup_ts_dirs_remote) || rc=$?
    else
        days="$KEEP_LOCAL_RECOVERY_DAYS"
        out=$(cleanup_ts_dirs_local "$LOCAL_RECOVERY_DIR" "$days") || rc=$?
    fi

    if ((rc != 0)); then
        log_warn "Auto-cleanup recovery не вдався (код $rc). Синхронізація від цього не страждає; спробуйте пізніше: ./backup-sync.sh cleanup"
        return 0
    fi

    removed=$(grep -c . <<<"$out" || true)
    if ((removed > 0)); then
        printf '%s\n' "$out" | sed 's/^/        видалено: /'
        log_ok "Auto-cleanup recovery: видалено ${removed} (старші за ${days} дн.)."
    else
        log_info "Auto-cleanup recovery: немає копій старших за ${days} дн."
    fi
}
