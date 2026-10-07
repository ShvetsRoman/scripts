#!/usr/bin/env bash

log_info()  { printf '%s[INFO]%s %s\n'  "$C_BLUE"   "$C_RESET" "$*"; }
log_ok()    { printf '%s[ OK ]%s %s\n'  "$C_GREEN"  "$C_RESET" "$*"; }
log_warn()  { printf '%s[WARN]%s %s\n'  "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_error() { printf '%s[ERROR]%s %s\n' "$C_RED"    "$C_RESET" "$*" >&2; exit 1; }
log_title() { printf '\n%s── %s ──%s\n' "$C_CYAN" "$*" "$C_RESET"; }

init_logging() {
    mkdir -p -- "$LOG_DIR"

    printf -v TIMESTAMP '%(%Y-%m-%d_%H-%M-%S)T' -1
    LOG_FILE="$LOG_DIR/backup-sync_${TIMESTAMP}.log"

    exec 3>&1 4>&2
    exec > >(tee -a "$LOG_FILE") 2>&1

    trap on_exit EXIT
    trap 'on_signal INT 130' INT
    trap 'on_signal TERM 143' TERM

    START_EPOCH=$(date +%s)
}

on_signal() {
    local signal="$1"
    local rc="$2"
    log_warn "Отримано сигнал $signal. Завершення роботи."
    exit "$rc"
}

on_exit() {
    local rc=$?

    if [[ -n "${LOG_DIR:-}" && -d "${LOG_DIR:-}" ]]; then
        cleanup_files_older_than "$LOG_DIR" 'backup-sync_*.log' "$KEEP_LOG_DAYS" >/dev/null 2>&1 || true
    fi

    exec 1>&3 2>&4 || true
    exec 3>&- 4>&- || true
    wait || true
    return "$rc"
}
