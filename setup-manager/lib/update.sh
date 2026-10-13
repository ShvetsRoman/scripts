#!/usr/bin/env bash
# Оновлення.

# setup_update — оновлює код (не дані) з архіву через update_safe.py.
setup_update() {
    local archive="${1:-}" mode="${2:-}"
    [[ -n "$archive" && -f "$archive" ]] || { log error 'Вкажи архів'; return 2; }
    command -v python3 >/dev/null || { log error 'Потрібен python3'; return 1; }
    local -a args=("$archive" "$ROOT_DIR")
    [[ "$mode" == --dry-run ]] && args+=(--dry-run)
    python3 "$ROOT_DIR/tools/update_safe.py" "${args[@]}"
}
