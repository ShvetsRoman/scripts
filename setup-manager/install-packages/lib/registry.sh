#!/usr/bin/env bash
# Спільний контракт змінних між Bash-модулями.
# shellcheck disable=SC2034
# Автоматичний реєстр V2.0. Не редагуйте для додавання програми.
# Декларації з modules/*.sh виконуються як Bash: довіряйте цим файлам.

MODULES=()
declare -Ag MODULE_TITLES=() MODULE_DEPENDENCIES=() MODULE_PACMAN_ARRAYS=()
declare -Ag MODULE_AUR_ARRAYS=() MODULE_GITHUB_ARRAYS=()
declare -Ag MODULE_SERVICES=() MODULE_POST_HOOKS=()
declare -Ag CONFIG_MAP=() GITHUB_PACKAGES=()

load_module_registry() {
    # Дозволяє повторне завантаження без дублювання старих записів.
    MODULES=()
    MODULE_TITLES=()
    MODULE_DEPENDENCIES=()
    MODULE_PACMAN_ARRAYS=()
    MODULE_AUR_ARRAYS=()
    MODULE_GITHUB_ARRAYS=()
    MODULE_SERVICES=()
    MODULE_POST_HOOKS=()
    CONFIG_MAP=()
    GITHUB_PACKAGES=()
    local file id entry key scope src dest extra kind url cmd arg1 arg2
    local -a discovered=()
    local -A seen_dest=()
    shopt -s nullglob
    for file in "$ROOT_DIR"/modules/*.sh; do
        # Очищення значень, щоб попередній модуль не протікав у наступний.
        local MODULE_ID="" MODULE_TITLE="" MODULE_ORDER=9999
        local MODULE_DEPENDS="" MODULE_SERVICES_LIST="" MODULE_POST_HOOK=""
        local -a PACMAN_PACKAGES=() AUR_PACKAGES=() GITHUB_ITEMS=() CONFIG_ITEMS=()
        # Єдиний файл модуля: параметри та за потреби оголошення hook.
        # source виконує код, тому використовуйте тільки перевірені файли.
        # Модулі виявляються динамічно, тому статичний шлях source неможливий.
        # shellcheck disable=SC1090
        source "$file"
        [[ "$MODULE_ID" =~ ^[a-z][a-z0-9_-]*$ ]] || { echo "Помилка ID: $file" >&2; return 1; }
        [[ "${file##*/}" == "$MODULE_ID.sh" ]] || { echo "Назва файлу не відповідає ID: $file" >&2; return 1; }
        [[ -z "${MODULE_TITLES[$MODULE_ID]+x}" ]] || { echo "Повторений ID: $MODULE_ID" >&2; return 1; }
        [[ "$MODULE_ORDER" =~ ^[0-9]+$ ]] || { echo "Некоректний порядок: $file" >&2; return 1; }
        MODULE_TITLES[$MODULE_ID]="${MODULE_TITLE:-$MODULE_ID}"
        MODULE_DEPENDENCIES[$MODULE_ID]="$MODULE_DEPENDS"
        MODULE_SERVICES[$MODULE_ID]="$MODULE_SERVICES_LIST"
        MODULE_POST_HOOKS[$MODULE_ID]="$MODULE_POST_HOOK"
        local var_prefix="MOD_${MODULE_ID//-/_}"
        local p_name="${var_prefix}_PACMAN" a_name="${var_prefix}_AUR" g_name="${var_prefix}_GITHUB"
        declare -g -a "$p_name" "$a_name" "$g_name"
        local -n p_ref="$p_name" a_ref="$a_name" g_ref="$g_name"
        p_ref=("${PACMAN_PACKAGES[@]}")
        a_ref=("${AUR_PACKAGES[@]}")
        g_ref=()
        MODULE_PACMAN_ARRAYS[$MODULE_ID]="$p_name"
        MODULE_AUR_ARRAYS[$MODULE_ID]="$a_name"
        MODULE_GITHUB_ARRAYS[$MODULE_ID]="$g_name"
        for entry in "${GITHUB_ITEMS[@]}"; do
            IFS='|' read -r id kind url cmd arg1 arg2 extra <<< "$entry"
            [[ "$id" =~ ^[a-zA-Z0-9_-]+$ && -n "$kind" && -n "$url" && -n "$cmd" && -z "${extra:-}" ]] || { echo "Некоректний GitHub-запис: $entry" >&2; return 1; }
            [[ -z "${GITHUB_PACKAGES[$id]+x}" ]] || { echo "Повторений GitHub ID: $id" >&2; return 1; }
            GITHUB_PACKAGES[$id]="${entry#*|}"
            g_ref+=("$id")
        done
        for entry in "${CONFIG_ITEMS[@]}"; do
            IFS='|' read -r id scope src dest extra <<< "$entry"
            [[ "$id" =~ ^[a-zA-Z0-9_-]+$ && -n "$scope" && -n "$src" && -n "$dest" && -z "${extra:-}" ]] || { echo "Некоректний конфіг: $entry" >&2; return 1; }
            [[ -z "${CONFIG_MAP[$id]+x}" ]] || { echo "Повторений ID конфігу: $id" >&2; return 1; }
            CONFIG_MAP[$id]="$MODULE_ID|$scope|$src|$dest"
            key="$scope:$dest"
            [[ -z "${seen_dest[$key]+x}" ]] || { echo "Конфлікт призначення: $key" >&2; return 1; }
            seen_dest[$key]=1
        done
        discovered+=("$(printf '%08d:%s' "$MODULE_ORDER" "$MODULE_ID")")
    done
    shopt -u nullglob
    ((${#discovered[@]})) || { echo 'Немає modules/*.sh' >&2; return 1; }
    while IFS= read -r entry; do
        MODULES+=("${entry#*:}")
    done < <(printf '%s\n' "${discovered[@]}" | sort)
}

load_module_registry
