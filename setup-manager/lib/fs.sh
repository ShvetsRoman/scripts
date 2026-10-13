#!/usr/bin/env bash
# Файлове ядро.

# _FS_BASE — базові опції rsync, спільні для всіх операцій.
# -a: архівний режим; -c: порівнювати за контрольною сумою;
# --no-times/perms/owner/group: не чіпати метадані;
# --safe-links: не слідувати symlink, що вказують за межі dst.
_FS_BASE=(rsync -a -c --no-times --no-perms --no-owner --no-group --safe-links)

# _FS_DIFF — dry-run з деталізацією змін.
_FS_DIFF=("${_FS_BASE[@]}" --dry-run --itemize-changes)

# _FS_DIFF_DEL — те саме, але з --delete (показує, що буде видалено).
_FS_DIFF_DEL=("${_FS_DIFF[@]}" --delete)

# fs_compare — точне порівняння src і dst.
# Повертає: 0=однаково, 1=різниця, 2=помилка.
# Для каталогів використовує rsync --dry-run --delete (dst має точно відповідати src).
fs_compare() {
    local a="$1" b="$2" out
    [[ -e "$a" || -L "$a" ]] || return 1
    [[ -e "$b" || -L "$b" ]] || return 1
    if [[ -d "$a" && -d "$b" ]]; then
        if out="$("${_FS_DIFF_DEL[@]}" -- "$a/" "$b/" 2>&1)"; then
            [[ -z "$out" ]] && return 0 || return 1
        fi
        log error "rsync: $out"; return 2
    fi
    if [[ -f "$a" && -f "$b" ]]; then
        cmp -s -- "$a" "$b"; local rc=$?
        (( rc == 0 )) && return 0
        (( rc == 1 )) && return 1
        return 2
    fi
    if [[ -L "$a" && -L "$b" ]]; then
        [[ "$(readlink -- "$a")" == "$(readlink -- "$b")" ]] && return 0 || return 1
    fi
    return 1
}

# fs_compare_copy — чи src повністю представлений у dst (без перевірки зайвого).
# Для каталогів — rsync --dry-run БЕЗ --delete.
fs_compare_copy() {
    local a="$1" b="$2" out
    [[ -e "$a" || -L "$a" ]] || return 1
    [[ -e "$b" || -L "$b" ]] || return 1
    if [[ -d "$a" && -d "$b" ]]; then
        if out="$("${_FS_DIFF[@]}" -- "$a/" "$b/" 2>&1)"; then
            [[ -z "$out" ]] && return 0 || return 1
        fi
        log error "rsync: $out"; return 2
    fi
    fs_compare "$a" "$b"
}

# fs_extras — список зайвих файлів у dst, які видалив би --delete.
fs_extras() {
    local a="$1" b="$2"
    [[ -d "$a" && -d "$b" ]] || return 0
    "${_FS_DIFF_DEL[@]}" -- "$a/" "$b/" | grep '^\*deleting ' || true
}

# fs_copy — копіювання src → dst.
# DRY_RUN=true → лише лог.
# SYNC_DELETE=true → rsync з --delete (dst точно відповідатиме src).
fs_copy() {
    local src="$1" dst="$2"
    [[ -e "$src" || -L "$src" ]] || { log error "Немає джерела: $src"; return 1; }
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log info "[DRY-RUN] $src → $dst"
        return 0
    fi
    mkdir -p -- "$(dirname -- "$dst")" || return 1
    local -a opts=("${_FS_BASE[@]}")
    [[ "${SYNC_DELETE:-false}" == true ]] && opts+=(--delete)
    if [[ -d "$src" ]]; then
        mkdir -p -- "$dst" || return 1
        "${opts[@]}" -- "$src/" "$dst/" >/dev/null || return 1
    else
        "${opts[@]}" -- "$src" "$dst" >/dev/null || return 1
    fi
}

# fs_protect — захисна копія перед записом.
# Кладе src у backups/<group>/<timestamp>_<pid>/<rel>.
# Завжди без --delete, щоб не видалити нічого у бекапі.
fs_protect() {
    local src="$1" group="$2" rel="$3"
    [[ -e "$src" || -L "$src" ]] || return 0
    path_ok_rel "$rel" || { log error "Небезпечний шлях: $rel"; return 1; }
    local dst="$ROOT_DIR/backups/$group/$(date +%Y-%m-%d_%H-%M-%S)_$$/$rel"
    log step "backup: $rel"
    ( SYNC_DELETE=false; fs_copy "$src" "$dst" )
}
