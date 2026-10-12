#!/usr/bin/env bash
# Декларативні модулі завантажуються у власних підпроцесах через функції.
registry_files() {
    find "$ROOT_DIR/modules" -maxdepth 1 -type f -name '*.sh' -print | sort
}
registry_ids() {
    local file
    while IFS= read -r file; do basename "$file" .sh; done < <(registry_files)
}
registry_valid() {
    local id="$1"
    [[ "$id" =~ ^[a-z][a-z0-9_-]*$ && -f "$ROOT_DIR/modules/$id.sh" ]]
}
registry_show() {
    local f
    while IFS= read -r f; do
        ( # Декларативні модулі визначаються під час виконання.
          # shellcheck disable=SC1090
          source "$f"; printf '%-15s %s\n' "$MODULE_ID" "$MODULE_TITLE" )
    done < <(registry_files)
}
