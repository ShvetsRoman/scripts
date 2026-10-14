#!/usr/bin/env bash
# apply SRC DST GROUP LABEL: 0 — успіх; 2 — помилка.
# APPLY_RESULT: changed | unchanged | skipped; не використовуємо 1 як успіх.
# APPLY_RESULT читає sync_run() у lib/sync.sh та зовнішні виклики apply().
# ShellCheck запускається для кожного файлу окремо.
# shellcheck disable=SC2034
# Відкат ТІЛЬКИ поточного об'єкта після помилки копіювання/перевірки.
# Не гарантує rollback після SIGKILL чи втрати живлення.
apply_rollback() {
    local dst="$1" label="$2" snapshot="$3" existed="$4" helper
    if [[ -n "$snapshot" ]]; then
        helper="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../tools" && pwd)/recovery_safe.py" || return 2
        if ! python3 "$helper" verify "$snapshot"; then
            log error "$label — захисна копія пошкоджена, rollback неможливий"
            return 2
        fi
        if ! ( SYNC_DELETE=true; SETUP_BACKUP_ENABLED=true; DRY_RUN=false;
               fs_copy "$snapshot/data/$label" "$dst" ); then
            log error "$label — rollback завершився помилкою"
            return 2
        fi
        log warn "$label — відновлено попередній стан після помилки"
        return 0
    fi
    if [[ "$existed" == false ]]; then
        path_ok_abs "$dst" || { log error "$label — небезпечний шлях для rollback"; return 2; }
        if [[ -e "$dst" || -L "$dst" ]]; then
            rm -rf -- "$dst" || return 2
        fi
        log warn "$label — частково створений об'єкт видалено"
        return 0
    fi
    log error "$label — rollback неможливий: backup вимкнено"
    return 2
}

apply() {
    local src="$1" dst="$2" group="$3" label="$4" rc
    APPLY_RESULT=skipped
    fs_guard_delete || return 2
    path_ok_abs "$dst" || { log error "Небезпечне призначення: $dst"; return 2; }
    [[ "$dst" != / ]] || { log error 'Призначення / заборонено'; return 2; }
    [[ -e "$src" || -L "$src" ]] || { log warn "[SKIP] $label: немає $src"; return 0; }
    path_ok_abs "$src" || { log error "Небезпечне джерело: $src"; return 2; }
    [[ "$src" != / ]] || { log error "Джерело / заборонено"; return 2; }
    fs_no_nested_links "$src" || return 2
    if [[ -d "$dst" ]]; then
        fs_no_nested_links "$dst" || return 2
    fi
    local backup_allowed="${SETUP_BACKUP_ENABLED:-true}"
    if [[ "$group" == recovery && "${SETUP_RECOVERY_ENABLED:-true}" != true ]]; then
        backup_allowed=false
    fi
    if [[ "${SYNC_DELETE:-false}" == true && "$backup_allowed" != true ]]; then
        log error '--sync-delete потребує recovery/backup'
        return 2
    fi
    if [[ -e "$dst" ]]; then
        if [[ -d "$src" && ! -d "$dst" ]] || [[ -f "$src" && ! -f "$dst" ]]; then
            log error "$label — конфлікт типів (файл/каталог): $src → $dst"
            return 2
        fi
    fi
    if fs_compare "$src" "$dst"; then rc=0; else rc=$?; fi
    (( rc == 2 )) && return 2
    if (( rc == 0 )); then
        APPLY_RESULT=unchanged
        log info "$label — синхронізовано"
        return 0
    fi
    if fs_compare_copy "$src" "$dst"; then rc=0; else rc=$?; fi
    (( rc == 2 )) && return 2
    if (( rc == 0 )) && [[ "${SYNC_DELETE:-false}" != true ]]; then
        APPLY_RESULT=unchanged
        log warn "$label — зайві файли у призначенні (залишено)"
        return 0
    fi
    if [[ "${DRY_RUN:-false}" == true ]]; then
        APPLY_RESULT=changed
        log info "$label: $src → $dst"
        return 0
    fi
    local existed=false snapshot=''
    [[ -e "$dst" || -L "$dst" ]] && existed=true
    if [[ "$backup_allowed" == true && "$existed" == true ]]; then
        fs_protect "$dst" "$group" "$label" || return 2
        snapshot="${FS_PROTECT_SNAPSHOT:-}"
    fi
    log step "$label: $src → $dst"
    if ! fs_copy "$src" "$dst"; then
        log error "$label — копіювання не вдалося"
        apply_rollback "$dst" "$label" "$snapshot" "$existed" || true
        return 2
    fi
    if fs_compare_copy "$src" "$dst"; then
        APPLY_RESULT=changed
        return 0
    fi
    log error "$label — верифікація не пройдена"
    apply_rollback "$dst" "$label" "$snapshot" "$existed" || true
    return 2
}
