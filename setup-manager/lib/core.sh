#!/usr/bin/env bash
# Базові файлові операції з чіткими результатами: 0=однаково, 1=різниця, 2=помилка.
core_safe_relative() {
    local path="$1"
    [[ -n "$path" && "$path" != /* && "$path" != '.' && "$path" != '..' && "$path" != *'/../'* && "$path" != ../* && "$path" != */.. && "$path" != *'/./'* && "$path" != ./* && "$path" != *$'\n'* ]]
}
core_compare() {
    local a="$1" b="$2" output rc
    if [[ ! -e "$a" && ! -L "$a" ]]; then return 1; fi
    if [[ ! -e "$b" && ! -L "$b" ]]; then return 1; fi
    if [[ -d "$a" && -d "$b" ]]; then
        if output="$(rsync -a -c --no-times --no-perms --no-owner --no-group --delete --dry-run --itemize-changes -- "$a/" "$b/" 2>&1)"; then
            [[ -z "$output" ]] && return 0 || return 1
        else
            log_error "Помилка rsync: $output"; return 2
        fi
    elif [[ -f "$a" && -f "$b" ]]; then
        if cmp -s -- "$a" "$b"; then return 0; else rc=$?; [[ "$rc" == 1 ]] && return 1 || return 2; fi
    elif [[ -L "$a" && -L "$b" ]]; then
        [[ "$(readlink -- "$a")" == "$(readlink -- "$b")" ]] && return 0 || return 1
    fi
    return 1
}
# 0 — джерело повністю представлене в призначенні; додаткові файли дозволені.
# 1 — нові/змінені файли; 2 — помилка перевірки.
core_compare_copy() {
    local src="$1" dst="$2" output rc
    if [[ ! -e "$src" && ! -L "$src" ]]; then return 1; fi
    if [[ ! -e "$dst" && ! -L "$dst" ]]; then return 1; fi
    if [[ -d "$src" && -d "$dst" ]]; then
        if output="$(rsync -a -c --no-times --no-perms --no-owner --no-group --dry-run --itemize-changes -- "$src/" "$dst/" 2>&1)"; then
            [[ -z "$output" ]] && return 0 || return 1
        else
            log_error "Помилка rsync: $output"
            return 2
        fi
    else
        core_compare "$src" "$dst"
        rc=$?
        return "$rc"
    fi
}

# Порахувати зайві файли/каталоги, що потребують --sync-delete.
core_extras() {
    local src="$1" dst="$2"
    [[ -d "$src" && -d "$dst" ]] || return 0
    rsync -a -c --no-times --no-perms --no-owner --no-group --delete --dry-run --itemize-changes -- "$src/" "$dst/" |
        grep '^\*deleting ' || true
}

core_copy() {
    local src="$1" dest="$2"
    [[ -e "$src" || -L "$src" ]] || { log_error "Джерело відсутнє: $src"; return 1; }
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "[DRY-RUN] Звідки: $src"
        log_info "[DRY-RUN] Куди: $dest"
        return 0
    fi
    mkdir -p -- "$(dirname -- "$dest")" || return 1
    if [[ -d "$src" ]]; then
        mkdir -p -- "$dest" || return 1
        if [[ "${SYNC_DELETE:-false}" == true ]]; then
            rsync -a -c --delete -- "$src/" "$dest/" >/dev/null || return 1
        else
            rsync -a -c -- "$src/" "$dest/" >/dev/null || return 1
        fi
    else
        rsync -a -c -- "$src" "$dest" >/dev/null || return 1
    fi
}
core_protect() {
    local src="$1" group="$2" relative="$3" target
    [[ -e "$src" || -L "$src" ]] || return 0
    core_safe_relative "$relative" || { log_error "Небезпечний шлях: $relative"; return 1; }
    target="$ROOT_DIR/backups/$group/$(date +%Y-%m-%d_%H-%M-%S)_$$/$relative"
    log_step "Захисний backup: $relative"
    core_copy "$src" "$target"
}
