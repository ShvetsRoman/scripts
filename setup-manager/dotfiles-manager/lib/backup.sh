#!/usr/bin/env bash

rsync_backup() {
    local source="$1" destination="$2" delete_mode="${3:-false}"
    core_sync "${source%/}" "${destination%/}" "$delete_mode" "${DRY_RUN:-false}" "${EXCLUDE_PATTERNS[@]}"
}

backup_directory() {
    local path="$1"
    local source="$HOME/$path/"
    local destination="$DOTFILES_DIR/$path/"

    if ! path_exists_in_home "$path"; then
        log_warn "У HOME відсутня директорія: $path"
        return 1
    fi
    if [[ ! -d "$HOME/$path" || -L "$HOME/$path" ]]; then
        log_error "Очікувалась директорія: $path"
        return 1
    fi

    if [[ "${DRY_RUN:-false}" != true ]]; then
        mkdir -p -- "$destination"
    fi

    log_step "Backup: $path"
    rsync_backup "$source" "$destination" true
}

backup_file() {
    local path="$1"
    local source="$HOME/$path"
    local destination="$DOTFILES_DIR/$path"

    if ! path_exists_in_home "$path"; then
        log_warn "У HOME відсутній файл: $path"
        return 1
    fi
    if [[ -d "$HOME/$path" && ! -L "$HOME/$path" ]]; then
        log_error "Очікувався файл або symlink: $path"
        return 1
    fi

    if [[ "${DRY_RUN:-false}" != true ]]; then
        mkdir -p -- "$(dirname -- "$destination")"
    fi

    log_step "Backup: $path"
    rsync_backup "$source" "$destination" false
}

backup_path() {
    local path

    path="$(resolve_backup_path "${1:-}")" || return

    if [[ -d "$HOME/$path" && ! -L "$HOME/$path" ]]; then
        if ! backup_directory "$path"; then
            return 1
        fi
    elif path_exists_in_home "$path"; then
        if ! backup_file "$path"; then
            return 1
        fi
    else
        log_warn "Шлях у HOME не існує: $path"
        return 1
    fi

    log_ok "Backup завершено: $path"
    echo
}

backup_all() {
    local path
    local failed=0

    echo
    log_step "Починаємо повний backup."
    echo

    for path in "${BACKUP_DIRS[@]}"; do
        if ! backup_directory "$path"; then
            failed=$((failed + 1))
        fi
    done

    for path in "${BACKUP_FILES[@]}"; do
        if ! backup_file "$path"; then
            failed=$((failed + 1))
        fi
    done

    echo

    if ((failed != 0)); then
        log_warn "Backup завершено з пропущеними/помилковими шляхами: $failed"
        return 1
    fi

    log_ok "Повний backup завершено."
}

backup_changed() {
    local path
    local source
    local destination
    local changed=false
    local failed=0

    echo
    log_step "Backup лише змінених шляхів."
    echo

    for path in "${BACKUP_DIRS[@]}" "${BACKUP_FILES[@]}"; do
        source="$HOME/$path"
        destination="$DOTFILES_DIR/$path"

        if ! path_exists_in_home "$path"; then
            continue
        fi

        if ! path_exists_in_backup "$path"; then
            log_info "[NEW] $path"
            changed=true
            if ! backup_path "$path"; then
                failed=$((failed + 1))
            fi
            continue
        fi

        if paths_differ "$source" "$destination"; then
            log_info "[CHANGED] $path"
            changed=true
            if ! backup_path "$path"; then
                failed=$((failed + 1))
            fi
        fi
    done

    if ((failed != 0)); then
        log_error "Backup changed завершено з помилками: $failed"
        return 1
    fi

    if [[ "$changed" == true ]]; then
        log_ok "Backup змінених шляхів завершено."
    else
        log_ok "Змін не знайдено."
    fi
}

clean_backup() {
    local -a unmanaged=()
    local item
    local rel

    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_info "Backup directory відсутня."
        return 0
    fi

    while IFS= read -r -d '' item; do
        rel="${item#"$DOTFILES_DIR/"}"
        if ! is_managed_or_parent "$rel"; then
            unmanaged+=("$item")
        fi
    done < <(find "$DOTFILES_DIR" -mindepth 1 -maxdepth 1 ! -name '.git' -print0)

    if ((${#unmanaged[@]} == 0)); then
        log_ok "Unmanaged entries не знайдено."
        return 0
    fi

    echo "Буде видалено:"
    printf '  %s\n' "${unmanaged[@]}"

    if ! confirm "Очистити unmanaged entries?"; then
        return 0
    fi

    if [[ "${DRY_RUN:-false}" != true ]]; then
        rm -rf -- "${unmanaged[@]}"
    fi

    echo
    log_ok "Backup очищено."
}

clean_all() {
    if [[ ! -d "$DOTFILES_DIR" ]]; then
        return 0
    fi
    if [[ -z "$DOTFILES_DIR" || "$DOTFILES_DIR" == "/" || "$DOTFILES_DIR" == "$HOME" ]]; then
        log_error "Небезпечний DOTFILES_DIR: $DOTFILES_DIR"
        return 1
    fi
    if ! confirm "Видалити весь backup '$DOTFILES_DIR'?"; then
        return 0
    fi

    if [[ "${DRY_RUN:-false}" != true ]]; then
        rm -rf -- "${DOTFILES_DIR:?}"
    fi

    echo
    log_ok "Весь backup видалено."
}
