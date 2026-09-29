#!/usr/bin/env bash

# ============================================================
# RECOVERY
# ============================================================

create_recovery_snapshot() {
    local snapshot
    local destination
    local path

    snapshot="$(timestamp)"
    destination="$RECOVERY_DIR/$snapshot"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Створення recovery snapshot: $snapshot"
        return 0
    fi

    mkdir -p "$destination"

    for path in "${BACKUP_DIRS[@]}" "${BACKUP_FILES[@]}"; do
        if path_exists_in_home "$path"; then
            mkdir -p "$destination/$(dirname "$path")"

            if [[ -d "$HOME/$path" ]]; then
                rsync -a \
                    "$HOME/$path" \
                    "$destination/$(dirname "$path")/"
            else
                rsync -a \
                    "$HOME/$path" \
                    "$destination/$path"
            fi
        fi
    done

    log_success "Recovery snapshot створено: $snapshot"

    cleanup_recovery_snapshots
}

cleanup_recovery_snapshots() {
    if [[ "${DRY_RUN:-false}" == true ]]; then
        return 0
    fi
    if [[ ! -d "$RECOVERY_DIR" ]]; then
        return 0
    fi

    if [[ -z "$RECOVERY_DIR" || "$RECOVERY_DIR" == "/" ]]; then
        log_error "Небезпечний RECOVERY_DIR: '${RECOVERY_DIR:-<unset>}'"
        return 1
    fi

    mapfile -t snapshots < <(
        find "$RECOVERY_DIR" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -printf '%f\n' |
        sort -r
    )

    if ((${#snapshots[@]} <= RECOVERY_LIMIT)); then
        return 0
    fi

    local i
    local snapshot_path

    for ((i = RECOVERY_LIMIT; i < ${#snapshots[@]}; i++)); do
        snapshot_path="$RECOVERY_DIR/${snapshots[$i]}"

        if [[ -z "$snapshot_path" ]]; then
            continue
        fi

        rm -rf -- "${snapshot_path:?}"
    done
}

recovery_list() {
    if [[ ! -d "$RECOVERY_DIR" ]]; then
        log_info "Recovery directory відсутня."
        return 0
    fi

    find "$RECOVERY_DIR" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -printf '%f\n' |
    sort -r
}

recovery_restore() {
    local snapshot="${1:-}"
    local source

    if [[ -z "$snapshot" || "$snapshot" == */* || "$snapshot" == .* ]]; then
        log_error "Некоректний snapshot."
        return 2
    fi

    source="$RECOVERY_DIR/$snapshot"

    if [[ ! -d "$source" ]]; then
        log_error "Snapshot не знайдено: $snapshot"
        return 1
    fi

    if ! confirm "Відновити snapshot '$snapshot' у HOME?"; then
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Відновлення snapshot: $snapshot"
        log_info "[DRY-RUN] Джерело: $source"
        log_info "[DRY-RUN] Ціль: $HOME"
        return 0
    fi

    rsync -a \
        --human-readable \
        "$source/" \
        "$HOME/"

    log_success "Snapshot відновлено: $snapshot"
}

recovery_delete() {
    local snapshot="${1:-}"
    local target

    if [[ -z "$snapshot" || "$snapshot" == */* || "$snapshot" == .* ]]; then
        log_error "Некоректний snapshot."
        return 2
    fi

    target="$RECOVERY_DIR/$snapshot"

    if [[ ! -d "$target" ]]; then
        log_error "Snapshot не знайдено: $snapshot"
        return 1
    fi

    if ! confirm "Видалити snapshot '$snapshot'?"; then
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Видалення snapshot: $snapshot"
        return 0
    fi

    rm -rf -- "${target:?}"

    log_success "Snapshot видалено: $snapshot"
}
