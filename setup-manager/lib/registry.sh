#!/usr/bin/env bash
# Реєстр модулів.

# registry_dir — каталог з модулями.
registry_dir() { printf '%s/modules' "$ROOT_DIR"; }

# registry_ids — список id модулів (без .sh), відсортований.
registry_ids() {
    find "$(registry_dir)" -maxdepth 1 -type f -name '*.sh' -printf '%f\n' \
        | sed 's/\.sh$//' | sort
}

# registry_valid — чи існує модуль з таким id і чи правильний формат.
registry_valid() {
    local id="$1"
    [[ "$id" =~ ^[a-z][a-z0-9_-]*$ && -f "$(registry_dir)/$id.sh" ]]
}

# _REG_TITLE — кеш заголовків (щоб не робити source N×M разів у меню).
declare -A _REG_TITLE=()

# registry_title — читає MODULE_TITLE з модуля (кешує).
registry_title() {
    local id="$1"
    if [[ -z "${_REG_TITLE[$id]:-}" ]]; then
        _REG_TITLE[$id]="$(
            # shellcheck disable=SC1090
            source "$(registry_dir)/$id.sh"
            printf '%s' "${MODULE_TITLE:-$id}"
        )"
    fi
    printf '%s' "${_REG_TITLE[$id]}"
}

# registry_show — таблиця id + title усіх модулів.
registry_show() {
    local id
    while IFS= read -r id; do
        printf '%-15s %s\n' "$id" "$(registry_title "$id")"
    done < <(registry_ids)
}
