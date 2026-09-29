#!/usr/bin/env bash

verify_path() {
    local path
    local home_path
    local backup_path

    path="$(resolve_backup_path "${1:-}")" || return
    home_path="$HOME/$path"
    backup_path="$DOTFILES_DIR/$path"

    if ! path_exists_in_home "$path" || ! path_exists_in_backup "$path"; then
        log_error "[FAILED] $path — шлях відсутній з одного боку"
        return 1
    fi

    if paths_differ "$home_path" "$backup_path"; then
        log_error "[FAILED] $path"
        return 1
    fi

    log_success "[OK] $path"
}

verify_all() {
    local path
    local failed=0

    for path in "${BACKUP_DIRS[@]}" "${BACKUP_FILES[@]}"; do
        if ! verify_path "$path"; then
            failed=$((failed + 1))
        fi
    done

    if ((failed != 0)); then
        log_error "Verify завершено з помилками: $failed"
        return 1
    fi

    echo
    log_success "Verify успішний для всіх шляхів."
}
