#!/usr/bin/env bash
# Конфіги модулів.

# configs_apply — застосовує CONFIG_ITEMS модуля.
# Кожен entry: "id|scope|rel_src|rel_dst".
# Використовує apply, тому логіка та сама, що для dotfiles.
configs_apply() {
    local -a entries=("$@")
    ((${#entries[@]})) || { log info 'Конфігів немає.'; return 0; }

    if [[ "${SYNC_DELETE:-false}" == true && "${SETUP_BACKUP_ENABLED:-true}" != true ]]; then
        log error '--sync-delete несумісний з --no-backup'; return 2
    fi

    local entry id scope rel_src rel_dst from to st
    for entry in "${entries[@]}"; do
        IFS='|' read -r id scope rel_src rel_dst <<< "$entry"
        [[ "$scope" == home ]] || { log warn "Конфіг $id: не home, пропущено"; continue; }
        path_ok_rel "$rel_src" || { log error "$id: src"; return 1; }
        path_ok_rel "$rel_dst" || { log error "$id: dst"; return 1; }

        from="$ROOT_DIR/dotfiles/$rel_src"
        to="$HOME/$rel_dst"

        [[ -e "$from" || -L "$from" ]] || {
            log warn "Конфіг $id: немає $from"
            [[ "${STRICT_CONFIGS:-false}" == true ]] && return 1
            continue
        }
        if [[ -L "$to" && -d "$from" ]] || [[ -L "$from" && -d "$to" ]]; then
            log error "Небезпечна зміна типу: $id"; return 1
        fi

        st=0
        apply "$from" "$to" installer "$id" || st=$?
        if (( st == 2 )); then
            log error "Конфіг $id: помилка apply"
            return 1
        fi
    done
}
