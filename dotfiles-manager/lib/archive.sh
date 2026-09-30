#!/usr/bin/env bash

archive_create() {
    local archive
    local name

    name="$(normalize_archive_name "${1:-}")" || return
    archive="$ARCHIVE_DIR/$name"

    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_error "Backup directory не існує: $DOTFILES_DIR"
        return 1
    fi

    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "[DRY-RUN] Створення archive: $archive"
        return 0
    fi

    mkdir -p -- "$ARCHIVE_DIR"
    tar -czf "$archive" --exclude='.git' -C "$DOTFILES_DIR" .
    log_success "Archive створено: $archive"
}

resolve_archive() {
    local requested="${1:-}"
    local name

    if [[ -z "$requested" ]]; then
        log_error "Archive не вказано."
        return 2
    fi

    name="$(normalize_archive_name "$requested")" || return
    printf '%s/%s\n' "$ARCHIVE_DIR" "$name"
}

archive_list() {
    local archive

    archive="$(resolve_archive "${1:-}")" || return

    if [[ ! -f "$archive" ]]; then
        log_error "Archive не знайдено: $archive"
        return 1
    fi

    tar -tzf "$archive"
}

archive_is_safe() {
    local archive="$1"
    local entry

    while IFS= read -r entry; do
        if [[ "$entry" == /* || "$entry" == ../* || "$entry" == */../* || "$entry" == */.. ]]; then
            log_error "Archive містить небезпечний шлях: $entry"
            return 1
        fi
    done < <(tar -tzf "$archive")
}

archive_restore() {
    local archive

    archive="$(resolve_archive "${1:-}")" || return

    if [[ ! -f "$archive" ]]; then
        log_error "Archive не знайдено: $archive"
        return 1
    fi
    if ! archive_is_safe "$archive"; then
        return 1
    fi
    if ! confirm "Відновити archive у '$DOTFILES_DIR'?"; then
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "[DRY-RUN] Відновлення archive: $archive"
        log_info "[DRY-RUN] Ціль: $DOTFILES_DIR"
        return 0
    fi

    mkdir -p -- "$DOTFILES_DIR"
    tar -xzf "$archive" -C "$DOTFILES_DIR" --no-same-owner --no-same-permissions
    log_success "Archive відновлено: $DOTFILES_DIR"
}
