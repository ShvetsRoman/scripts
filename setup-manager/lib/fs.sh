#!/usr/bin/env bash
# Файлове ядро Setup Manager.
_FS_BASE=(rsync -a -c --no-times --no-perms --no-owner --no-group --safe-links)
_FS_DIFF=("${_FS_BASE[@]}" --dry-run --itemize-changes)
_FS_DIFF_DEL=("${_FS_DIFF[@]}" --delete)

# У режимі --sync-delete обов'язково має бути дозволене захисне копіювання.
fs_guard_delete() {
    if [[ "${SYNC_DELETE:-false}" == true && "${SETUP_BACKUP_ENABLED:-true}" != true ]]; then
        log error '--sync-delete потребує backup (не можна з --no-backup)'
        return 2
    fi
    return 0
}

fs_compare() {
    local a="$1" b="$2" out rc
    [[ -e "$a" || -L "$a" ]] || return 1
    [[ -e "$b" || -L "$b" ]] || return 1
    if [[ -d "$a" && -d "$b" ]]; then
        if out="$("${_FS_DIFF_DEL[@]}" -- "$a/" "$b/" 2>&1)"; then
            [[ -z "$out" ]] && return 0 || return 1
        fi
        log error "rsync: $out"; return 2
    fi
    if [[ -f "$a" && -f "$b" ]]; then
        cmp -s -- "$a" "$b" && return 0
        rc=$?
        (( rc == 1 )) && return 1
        return 2
    fi
    if [[ -L "$a" && -L "$b" ]]; then
        [[ "$(readlink -- "$a")" == "$(readlink -- "$b")" ]] && return 0 || return 1
    fi
    return 1
}

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

fs_extras() {
    local a="$1" b="$2"
    [[ -d "$a" && -d "$b" ]] || return 0
    "${_FS_DIFF_DEL[@]}" -- "$a/" "$b/" | grep '^\*deleting ' || true
}

# Відмова від часткового backup: rsync --safe-links може пропустити symlink
# усередині дерева, через що копія була б неповною.
fs_no_nested_links() {
    local src="$1" found
    [[ -d "$src" ]] || return 0
    if ! found="$(find -P "$src" -type l -print -quit 2>&1)"; then
        log error "Помилка перевірки дерева: $src: $found"
        return 2
    fi
    [[ -z "$found" ]] || { log error "Symlink усередині дерева не підтримується: $found"; return 2; }
    return 0
}

fs_copy() {
    local src="$1" dst="$2"
    fs_guard_delete || return 2
    [[ -e "$src" || -L "$src" ]] || { log error "Немає джерела: $src"; return 1; }
    # Відхиляємо symlink (як джерело і як будь-який компонент призначення).
    path_ok_abs "$src" || { log error "Небезпечне джерело: $src"; return 2; }
    path_ok_abs "$dst" || { log error "Небезпечне призначення: $dst"; return 2; }
    [[ "$src" != / && "$dst" != / ]] || { log error 'Копіювання кореневого каталогу заборонене'; return 2; }
    fs_no_nested_links "$src" || return 2
    if [[ -d "$src" && "$dst" == "$src/"* ]]; then
        log error 'Призначення всередині джерела: рекурсивне копіювання заборонене'
        return 2
    fi
    [[ "${DRY_RUN:-false}" == true ]] && { log info "[DRY-RUN] $src → $dst"; return 0; }
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

# Створює окремий recovery-знімок з manifest.tsv: rel<TAB>abs-target.
# Старі знімки без manifest можуть бути неоднозначними і не відновлюються автоматично.
fs_protect() {
    local src="$1" group="$2" rel="$3" base snap id attempt
    # Стан читається apply() в іншому source-модулі.
    # shellcheck disable=SC2034
    FS_PROTECT_SNAPSHOT=''
    [[ -e "$src" || -L "$src" ]] || return 0
    path_ok_abs "$src" || { log error "Небезпечний шлях backup: $src"; return 2; }
    rel="${rel%/}"
    path_ok_rel "$rel" || { log error "Небезпечний шлях backup: $rel"; return 2; }
    [[ "$group" =~ ^[a-zA-Z0-9_-]+$ ]] || { log error "Група: $group"; return 2; }
    base="$ROOT_DIR/backups/$group"
    path_ok_abs "$base" || { log error "Небезпечний каталог backup: $base"; return 2; }
    [[ "${DRY_RUN:-false}" == true ]] && { log info "[DRY-RUN] backup: $src"; return 0; }
    mkdir -p -- "$base" || return 2
    snap=''
    for ((attempt=0; attempt<30; attempt++)); do
        id="$(date +%Y-%m-%d_%H-%M-%S)_$$_${RANDOM}"
        if mkdir -- "$base/$id" 2>/dev/null; then snap="$base/$id"; break; fi
    done
    [[ -n "$snap" ]] || { log error 'Не вдалося створити унікальний backup'; return 2; }
    log step "backup: $src"
    if ! (SYNC_DELETE=false; DRY_RUN=false; fs_copy "$src" "$snap/data/$rel"); then
        rm -rf -- "$snap"; return 2
    fi
    # Усі нові захисні копії мають manifest + SHA-256 (не тільки recovery).
    if ! printf '%s\t%s\n' "$rel" "$src" > "$snap/manifest.tsv"; then
        rm -rf -- "$snap"; return 2
    fi
    local helper
    helper="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../tools" && pwd)/recovery_safe.py" || {
        rm -rf -- "$snap"; return 2;
    }
    if ! python3 "$helper" create "$snap"; then
        rm -rf -- "$snap"; log error 'Не вдалося створити перевірку цілісності'; return 2
    fi
    # shellcheck disable=SC2034
    FS_PROTECT_SNAPSHOT="$snap"
    return 0
}
