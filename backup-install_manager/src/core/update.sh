#!/usr/bin/env bash
# Оновлення.

# setup_update — оновлює код (не дані) з архіву через update_safe.py.
setup_update() {
    local archive="${1:-}" mode="${2:-}" expected="${3:-}"
    # Сумісність із синтаксисом: update ARCHIVE --sha256 HEX [--dry-run].
    if [[ "$mode" == --sha256 ]]; then
        expected="${3:-}"
        mode="${4:-}"
    elif [[ "$mode" != --dry-run && -n "$mode" ]]; then
        log error 'update ARCHIVE [--sha256 HEX] [--dry-run]'; return 2
    fi
    [[ -n "$archive" && -f "$archive" ]] || { log error 'Вкажи архів'; return 2; }
    if [[ -n "$expected" ]]; then
        [[ "$expected" =~ ^[[:xdigit:]]{64}$ ]] || { log error 'Некоректний SHA-256'; return 2; }
        command -v sha256sum >/dev/null || { log error 'Потрібен sha256sum'; return 2; }
        local actual
        actual="$(sha256sum -- "$archive")" || return 2
        actual="${actual%% *}"
        [[ "${actual,,}" == "${expected,,}" ]] || { log error 'SHA-256 архіву не збігається'; return 2; }
    else
        log warn 'Цілісність архіву не підтверджена: рекомендовано --sha256 HASH'
    fi
    command -v python3 >/dev/null || { log error 'Потрібен python3'; return 1; }
    local -a args=("$archive" "$ROOT_DIR")
    [[ "$mode" == --dry-run ]] && args+=(--dry-run)
    python3 "$(path_release_tool)" "${args[@]}"
}
