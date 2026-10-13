#!/usr/bin/env bash
# Одна операція: apply SRC DST GROUP LABEL.
#   0=без змін, 1=скопійовано, 2=помилка.

apply() {
    local src="$1" dst="$2" group="$3" label="$4"

    [[ -e "$src" || -L "$src" ]] || {
        log warn "[SKIP] $label: джерело відсутнє → $src"
        return 0
    }

    # У dry-run: показати, що планується.
    if [[ "${DRY_RUN:-false}" == true ]]; then
        fs_compare "$src" "$dst"
        local rc=$?
        if (( rc == 0 )); then
            log info "$label — без змін"
        elif (( rc == 2 )); then
            log error "$label: помилка порівняння"
            return 2
        else
            log info "$label: $src → $dst"
        fi
        return 0
    fi

    fs_compare "$src" "$dst"; local rc=$?
    (( rc == 2 )) && return 2
    if (( rc == 0 )); then
        log info "$label — синхронізовано"
        return 0
    fi

    fs_compare_copy "$src" "$dst"; rc=$?
    (( rc == 2 )) && return 2
    if (( rc == 0 )) && [[ "${SYNC_DELETE:-false}" != true ]]; then
        log warn "$label — зайві файли у призначенні, залишено без змін"
        return 0
    fi

    if [[ "${SETUP_BACKUP_ENABLED:-true}" == true && ( -e "$dst" || -L "$dst" ) ]]; then
        fs_protect "$dst" "$group" "$label" || return 2
    fi

    log step "$label: $src → $dst"
    fs_copy "$src" "$dst" || return 2

    if [[ "${DRY_RUN:-false}" != true ]]; then
        fs_compare_copy "$src" "$dst" || { log error "$label — верифікація не пройдена"; return 2; }
    fi
    return 1
}
