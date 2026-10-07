#!/usr/bin/env bash

# ============================================================
# VERIFY
# ============================================================

verify_path() {
    local path
    local home_path
    local backup_path

    path="$(resolve_backup_path "${1:-}")" || return 1

    home_path="$HOME/$path"
    backup_path="$DOTFILES_DIR/$path"

    if ! path_exists_in_home "$path"; then
        printf '%b[FAILED]%b %s — відсутній у HOME\n' \
            "$RED" "$NC" "$path" >&2
        return 1
    fi

    if ! path_exists_in_backup "$path"; then
        printf '%b[FAILED]%b %s — відсутній у backup\n' \
            "$RED" "$NC" "$path" >&2
        return 1
    fi

    if paths_differ "$home_path" "$backup_path"; then
        printf '%b[FAILED]%b %s\n' \
            "$RED" "$NC" "$path" >&2
        return 1
    fi

    log_success "$path"
    return 0
}


verify_all() {
    local path
    local failed=0

    for path in "${BACKUP_DIRS[@]}" "${BACKUP_FILES[@]}"; do
        if ! verify_path "$path"; then
            failed=$((failed + 1))
        fi
    done

    echo

    if ((failed > 0)); then
        log_error "Verify завершено з помилками: $failed"
        return 1
    fi

    log_success "Verify успішний для всіх шляхів."
    return 0
}
