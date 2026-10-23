#!/usr/bin/env bash
# Застосування CONFIG_ITEMS модуля.
# Формат entry: "name" — ім'я з dotfiles.conf.

configs_apply() {
    local -a entries=("$@")
    ((${#entries[@]})) || { log info 'Конфігів немає.'; return 0; }

    if [[ "${SYNC_DELETE:-false}" == true && "${SETUP_BACKUP_ENABLED:-true}" != true ]]; then
        log error '--sync-delete несумісний з --no-backup'; return 2
    fi

    # Реєстр уже перевірений викликачем Packages. Поза ним читаємо заново.
    if [[ "${PKG_DOTFILES_LOADED:-false}" != true ]]; then
        sources_load || return 2
    fi
    local entry id from to st
    for entry in "${entries[@]}"; do
        id="$entry"

        st=0
        sources_find "$id" || st=$?
        if (( st == 2 )); then return 2; fi
        if (( st == 1 )); then
            log warn "Конфіг '$id' не знайдено у dotfiles.conf, пропущено"
            [[ "${STRICT_CONFIGS:-false}" == true ]] && return 1
            continue
        fi

        [[ "$S_MODE" == home ]] || {
            log warn "Конфіг $id: mode=$S_MODE, не підтримується"
            continue
        }

        from="$(path_repo_for "$S_MODE" "$S_SRC")"
        to="$(path_live_for "$S_MODE" "$S_SRC")"

        [[ -e "$from" || -L "$from" ]] || {
            log warn "Конфіг $id: немає $from"
            [[ "${STRICT_CONFIGS:-false}" == true ]] && return 1
            continue
        }

        if [[ -L "$to" && -d "$from" ]] || [[ -L "$from" && -d "$to" ]]; then
            log error "Небезпечна зміна типу: $id"; return 1
        fi

        st=0
        apply "$from" "$to" packages "$id" || st=$?
        if (( st != 0 )); then
            log error "Конфіг $id: помилка apply"
            return 1
        fi
    done
}
