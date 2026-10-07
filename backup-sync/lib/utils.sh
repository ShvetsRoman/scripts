#!/usr/bin/env bash

check_local_dependencies() {
    local cmd
    for cmd in bash rsync ssh tee mkdir find stat date df flock awk sed grep; do
        command -v "$cmd" >/dev/null 2>&1 || {
            printf '[ERROR] Не знайдено обов’язкову команду: %s\n' "$cmd" >&2
            exit 1
        }
    done
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] || {
        printf '[ERROR] Config не знайдено: %s\n' "$CONFIG_FILE" >&2
        exit 1
    }

    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    : "${LOCAL_DIR:?LOCAL_DIR не задано}"
    : "${REMOTE_DIR:?REMOTE_DIR не задано}"
    : "${LOG_DIR:?LOG_DIR не задано}"
    : "${KEEP_LOG_DAYS:?KEEP_LOG_DAYS не задано}"
    : "${MIN_FREE_MIB:?MIN_FREE_MIB не задано}"

    if ((${#BACKUP_DIRS[@]} == 0)); then
        printf '[ERROR] BACKUP_DIRS порожній\n' >&2
        exit 1
    fi
}

init_runtime() {
    mkdir -p -- "$STATE_DIR" "$LOG_DIR"

    LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/backup-sync-${UID}.lock"
}

acquire_lock() {
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        log_error "Інший процес backup-sync уже запущений."
    fi
}

human_duration() {
    local seconds="$1"
    printf '%02d:%02d:%02d' \
        $((seconds / 3600)) \
        $(((seconds % 3600) / 60)) \
        $((seconds % 60))
}

dir_free_mib_local() {
    df -Pm -- "$1" | awk 'NR==2 {print $4}'
}

dir_free_mib_remote() {
    "${SSH_CMD[@]}" "$SSH_TARGET" \
        "df -Pm -- '$1' 2>/dev/null | awk 'NR==2 {print \$4}'"
}

check_free_space() {
    local local_free remote_free

    local_free=$(dir_free_mib_local "$LOCAL_DIR")
    remote_free=$(dir_free_mib_remote "$REMOTE_DIR")

    log_info "Вільно локально : ${local_free} MiB"
    log_info "Вільно remote   : ${remote_free} MiB"

    if (( local_free < MIN_FREE_MIB )); then
        log_error "На локальному диску менше ${MIN_FREE_MIB} MiB вільного місця."
    fi

    if (( remote_free < MIN_FREE_MIB )); then
        log_error "На сервері менше ${MIN_FREE_MIB} MiB вільного місця."
    fi
}
