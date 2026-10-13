#!/usr/bin/env bash
# Динамічний реєстр hooks.

declare -gA HOOKS_REGISTRY=()

# hook_collect — завантажує модуль і збирає функції hook_* у реєстр.
hook_collect() {
    local file="$1"
    [[ -f "$file" ]] || return 1

    local -A before=()
    while IFS= read -r fn; do
        before["$fn"]=1
    done < <(declare -F | awk '{print $3}')

    # shellcheck disable=SC1090
    source "$file"

    local id="${MODULE_ID:-$(basename "$file" .sh)}"

    local -a found=()
    local fn
    while IFS= read -r fn; do
        [[ "$fn" == hook_* ]] || continue
        [[ -n "${before[$fn]:-}" ]] && continue
        found+=("$fn")
    done < <(declare -F | awk '{print $3}')

    if ((${#found[@]})); then
        mapfile -t found < <(printf '%s\n' "${found[@]}" | sort)
        HOOKS_REGISTRY["$id"]="${found[*]}"
    fi
}

# hooks_list — для id повертає список hooks.
hooks_list() {
    printf '%s' "${HOOKS_REGISTRY[${1:-}]:-}"
}

# hooks_run — виконує всі hooks модуля.
hooks_run() {
    local id="$1"
    local list; list="$(hooks_list "$id")"
    [[ -n "$list" ]] || return 0
    local hook
    for hook in $list; do
        log step "Hook $id → $hook"
        "$hook" || { log warn "Hook $hook: помилка"; return 1; }
    done
}
