#!/usr/bin/env bash
setup_update() {
    local archive="${1:-}" mode="${2:-}"
    [[ -n "$archive" && -f "$archive" ]] || { log_error 'Вкажи доступний архів оновлення'; return 2; }
    command -v python3 >/dev/null || { log_error 'Для безпечного оновлення потрібен python3'; return 1; }
    local -a args=("$archive" "$ROOT_DIR")
    if [[ "$mode" == --dry-run ]]; then args+=(--dry-run); fi
    python3 "$ROOT_DIR/tools/update_safe.py" "${args[@]}"
}
