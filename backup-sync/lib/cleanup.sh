#!/usr/bin/env bash

cleanup_files_older_than() {
    local dir="$1"
    local pattern="$2"
    local days="$3"

    [[ -d "$dir" ]] || return 0

    find "$dir" \
        -type f \
        -name "$pattern" \
        -mtime +"$days" \
        -delete
}

cleanup_dirs_older_than_remote() {
    [[ "$RECOVERY_ENABLED" == true ]] || return 0

    "${SSH_CMD[@]}" "$SSH_TARGET" \
        "recovery='${REMOTE_DIR}/${RECOVERY_ROOT}'; \
         if [ -d \"\$recovery\" ]; then \
             find \"\$recovery\" -mindepth 1 -maxdepth 1 -type d -mtime +${KEEP_RECOVERY_DAYS} -exec rm -rf -- {} +; \
         fi"
}

cleanup_logs() {
    log_title "CLEANUP"

    cleanup_files_older_than "$LOG_DIR" 'backup-sync_*.log' "$KEEP_LOG_DAYS"
    log_ok "Старі logs очищено."

    if [[ -n "${SSH_TARGET:-}" ]]; then
        cleanup_dirs_older_than_remote
        log_ok "Старі recovery-каталоги очищено."
    fi
}
