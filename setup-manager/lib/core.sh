#!/usr/bin/env bash
# ============================================================
# SETUP MANAGER V3.0 — спільне ядро операцій з файлами
# Не містить реєстрів: ними керують Installer і Dotfiles.
# ============================================================

# Список розбіжностей: NEW (лише у HOME), DEL (лише у dotfiles),
# CHANGED (різний вміст або ціль symlink). Метадані ігноруються.
# Виклик: core_changes HOME_PATH DOTFILES_PATH [exclude ...]
# Повертає: 0 — порівняння виконано; 2 — помилка читання/rsync.
core_changes() {
    local source="$1" destination="$2" line code name
    shift 2
    local -a args=(--archive --checksum --delete --dry-run --itemize-changes
                   --no-times --no-perms --no-owner --no-group
                   --out-format='%i|%n')
    local pattern output
    for pattern in "$@"; do args+=("--exclude=$pattern"); done

    if [[ ! -e "$source" && ! -L "$source" ]]; then
        printf 'DEL|%s\n' "${destination##*/}"
        return 0
    fi
    if [[ ! -e "$destination" && ! -L "$destination" ]]; then
        printf 'NEW|%s\n' "${source##*/}"
        return 0
    fi
    if [[ -d "$source" && ! -L "$source" && -d "$destination" && ! -L "$destination" ]]; then
        output="$(rsync "${args[@]}" -- "$source/" "$destination/" 2>/dev/null)" || return 2
        while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            code="${line%%|*}"; name="${line#*|}"
            [[ "$name" == './' ]] && continue
            if [[ "$code" == '*deleting'* ]]; then
                printf 'DEL|%s\n' "$name"
            elif [[ "$code" == *'+++++++++'* ]]; then
                # Не виводимо окремо нові каталоги, лише їхні файли.
                [[ "${code:1:1}" == d ]] || printf 'NEW|%s\n' "$name"
            else
                [[ "${code:1:1}" == d ]] || printf 'CHANGED|%s\n' "$name"
            fi
        done <<< "$output"
        return 0
    fi
    if [[ -L "$source" || -L "$destination" ]]; then
        if [[ -L "$source" && -L "$destination" ]] &&
           [[ "$(readlink -- "$source")" == "$(readlink -- "$destination")" ]]; then
            return 0
        fi
    elif [[ -f "$source" && -f "$destination" ]]; then
        if cmp -s -- "$source" "$destination"; then return 0; fi
    fi
    printf 'CHANGED|%s\n' "${source##*/}"
}

# Однакові правила для Status, Diff та Verify.
# 0 — однакові, 1 — відмінні, 2 — помилка порівняння.
core_compare() {
    local changes
    changes="$(core_changes "$@")" || return 2
    [[ -z "$changes" ]]
}

# Спільний rsync. Для каталогу синхронізує саме вміст.
# Аргументи: source target delete(true/false) dry(true/false) [exclude ...]
core_sync() {
    local source="$1" target="$2" delete_mode="${3:-false}" dry="${4:-false}"
    shift 4
    local -a args=(-a)
    local x
    if [[ "$delete_mode" == true ]]; then args+=(--delete); fi
    if [[ "$dry" == true ]]; then args+=(--dry-run); else mkdir -p -- "$(dirname -- "$target")"; fi
    for x in "$@"; do args+=("--exclude=$x"); done
    if [[ -d "$source" && ! -L "$source" ]]; then
        if [[ "$dry" != true ]]; then mkdir -p -- "$target"; fi
        rsync "${args[@]}" -- "$source/" "$target/"
    else
        rsync "${args[@]}" -- "$source" "$target"
    fi
}

# Захисна копія існуючого об'єкта у приватну папку.
# Аргументи: target backup_path dry(true/false)
core_safety_backup() {
    local target="$1" backup_path="$2" dry="${3:-false}"
    [[ -e "$target" || -L "$target" ]] || return 0
    [[ ! -e "$backup_path" && ! -L "$backup_path" ]] || {
        printf '[ERROR] Backup вже існує: %s\n' "$backup_path" >&2; return 1;
    }
    if [[ "$dry" == true ]]; then
        printf '[DRY-RUN] backup %s -> %s\n' "$target" "$backup_path"
        return 0
    fi
    mkdir -p -- "$(dirname -- "$backup_path")"
    cp -a -- "$target" "$backup_path"
}

# Два реєстри користуються цим API, але не змішують свої шляхи.
core_snapshot() {
    local kind="$1" from="$2" to="$3" dry="${4:-false}"
    case "$kind" in
        installer|recovery) core_safety_backup "$from" "$to" "$dry" ;;
        dotfiles) core_sync "$from" "$to" true "$dry" ;;
        *) printf '[ERROR] Невідомий тип backup: %s\n' "$kind" >&2; return 2 ;;
    esac
}
