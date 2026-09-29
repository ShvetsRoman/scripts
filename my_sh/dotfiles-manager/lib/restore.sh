#!/usr/bin/env bash

create_recovery_snapshot_if_possible() {
    if [[ "${DRY_RUN:-false}" == true ]]; then
        return 0
    fi

    create_recovery_snapshot
}

restore_directory() {
    local path="$1"
    local source="$DOTFILES_DIR/$path/"
    local destination="$HOME/$path/"
    local -a args=(--archive --checksum --human-readable --itemize-changes --delete)
    local -a excludes=()

    if ! path_exists_in_backup "$path"; then
        log_warning "У backup відсутня директорія: $path"
        return 1
    fi
    if [[ ! -d "$DOTFILES_DIR/$path" || -L "$DOTFILES_DIR/$path" ]]; then
        log_error "У backup очікувалась директорія: $path"
        return 1
    fi

    if [[ "${DRY_RUN:-false}" != true ]]; then
        mkdir -p -- "$destination"
    fi

    build_exclude_args excludes
    args+=("${excludes[@]}")

    if [[ "${VERBOSE:-false}" == true ]]; then
        args+=(--verbose)
    fi
    if [[ "${DRY_RUN:-false}" == true ]]; then
        args+=(--dry-run)
    fi

    log_step "Restore: $path"
    rsync "${args[@]}" -- "$source" "$destination"
}

restore_file() {
    local path="$1"
    local source="$DOTFILES_DIR/$path"
    local destination="$HOME/$path"
    local -a args=(--archive --checksum --human-readable --itemize-changes)

    if ! path_exists_in_backup "$path"; then
        log_warning "У backup відсутній файл: $path"
        return 1
    fi

    if [[ "${DRY_RUN:-false}" != true ]]; then
        mkdir -p -- "$(dirname -- "$destination")"
    fi
    if [[ "${VERBOSE:-false}" == true ]]; then
        args+=(--verbose)
    fi
    if [[ "${DRY_RUN:-false}" == true ]]; then
        args+=(--dry-run)
    fi

    log_step "Restore: $path"
    rsync "${args[@]}" -- "$source" "$destination"
}

restore_path() {
    local path

    path="$(resolve_backup_path "${1:-}")" || return

    if ! path_exists_in_backup "$path"; then
        log_error "Шлях відсутній у backup: $path"
        return 1
    fi
    if ! confirm "Відновити '$path' з backup?"; then
        log_warning "Restore скасовано."
        return 0
    fi

    create_recovery_snapshot_if_possible

    if [[ -d "$DOTFILES_DIR/$path" && ! -L "$DOTFILES_DIR/$path" ]]; then
        if ! restore_directory "$path"; then
            return 1
        fi
    else
        if ! restore_file "$path"; then
            return 1
        fi
    fi

    log_success "Restore завершено: $path"
}

restore_all() {
    local path
    local failed=0

    if ! confirm "Відновити весь backup у HOME?"; then
        log_warning "Restore скасовано."
        return 0
    fi

    create_recovery_snapshot_if_possible

    for path in "${BACKUP_DIRS[@]}"; do
        if ! restore_directory "$path"; then
            failed=$((failed + 1))
        fi
    done

    for path in "${BACKUP_FILES[@]}"; do
        if ! restore_file "$path"; then
            failed=$((failed + 1))
        fi
    done

    if ((failed != 0)); then
        log_error "Restore завершено з помилками: $failed"
        return 1
    fi

    log_success "Повний restore завершено."
}
