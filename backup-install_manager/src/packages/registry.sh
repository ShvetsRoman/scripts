#!/usr/bin/env bash
# Парсер packages.conf: збирає всі синтаксичні помилки з номерами рядків.
# Реєстр не можна використовувати, доки файл не пройшов перевірку.
packages_load() {
    local file="$1" line key value section='' id token bound package found
    local lineno=0 errors=0
    local collect="${2:-}"
    # shellcheck disable=SC2034
    PACKAGES_SYNTAX_ERRORS=0
    declare -gA PACKAGE_FIELD_LINES=() PACKAGE_SECTION_LINES=()
    local -A seen=() seen_fields=() field_lines=() section_lines=()
    local -A config_seen=()
    local -a values=()
    PACKAGE_IDS=()
    declare -gA PACKAGE_TITLES=() PACKAGE_PACMAN=() PACKAGE_AUR=() PACKAGE_CONFIGS=() PACKAGE_CONFIGS_GROUP=() PACKAGE_HOOKS=() PACKAGE_BOUND_HOOKS=() PACKAGE_BOUND_CONFIGS=() PACKAGE_DEPENDS=()
    [[ -f "$file" && ! -L "$file" ]] || { printf '[ERROR] packages.conf відсутній або symlink\n' >&2; return 2; }
    while IFS= read -r line || [[ -n "$line" ]]; do
        lineno=$((lineno + 1))
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
        if [[ "$line" =~ ^\[([a-z][a-z0-9_-]*)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            if [[ -v seen["$section"] ]]; then
                printf '[ERROR] packages.conf:%s: повторна група %s (перша: рядок %s)\n' "$lineno" "$section" "${section_lines[$section]}" >&2
                errors=$((errors + 1))
                # Не перезаписувати попередню групу.
                section=''
                continue
            fi
            seen["$section"]=1
            section_lines["$section"]="$lineno"
            # shellcheck disable=SC2034
            PACKAGE_SECTION_LINES["$section"]="$lineno"
            PACKAGE_IDS+=("$section")
            continue
        fi
        if [[ -z "$section" || ! "$line" =~ ^([a-z][a-z_]*(\.[a-zA-Z0-9@_+.-]+)?)[[:space:]]*=[[:space:]]*(.*)$ ]]; then
            printf '[ERROR] packages.conf:%s: некоректний рядок: %s\n' "$lineno" "$line" >&2
            errors=$((errors + 1))
            continue
        fi
        key="${BASH_REMATCH[1]}" value="${BASH_REMATCH[3]}"
        if [[ -v seen_fields["${section}.${key}"] ]]; then
            printf '[ERROR] packages.conf:%s: повторне поле %s.%s (перше: рядок %s)\n' "$lineno" "$section" "$key" "${field_lines["${section}.${key}"]}" >&2
            errors=$((errors + 1))
            continue
        fi
        seen_fields["${section}.${key}"]=1
        field_lines["${section}.${key}"]="$lineno"
        # shellcheck disable=SC2034
        PACKAGE_FIELD_LINES["${section}.${key}"]="$lineno"
        value="${value%"${value##*[![:space:]]}"}"
        case "$key" in
            depends) PACKAGE_DEPENDS["$section"]="$value" ;;
            title) PACKAGE_TITLES["$section"]="$value" ;;
            pacman) PACKAGE_PACMAN["$section"]="$value" ;;
            aur) PACKAGE_AUR["$section"]="$value" ;;
            configs_group)
                if [[ -n "$value" && ! "$value" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
                    printf '[ERROR] packages.conf:%s: некоректна група configs_group: %s\n' "$lineno" "$value" >&2
                    errors=$((errors + 1))
                else
                    # shellcheck disable=SC2034
                    PACKAGE_CONFIGS_GROUP["$section"]="$value"
                fi ;;
            configs) PACKAGE_CONFIGS["$section"]="$value" ;;
            hooks) PACKAGE_HOOKS["$section"]="$value" ;;
            config.*) PACKAGE_BOUND_CONFIGS["$section|${key#config.}"]="$value" ;;
            hook.*)
                if [[ -z "$value" || ! "$value" =~ ^[a-z][a-z0-9_-]*$ ]]; then
                    printf '[ERROR] packages.conf:%s: некоректний hook: %s.%s\n' "$lineno" "$section" "$key" >&2
                    errors=$((errors + 1))
                else
                    PACKAGE_BOUND_HOOKS["$section|${key#hook.}"]="$value"
                fi ;;
            *)
                printf '[ERROR] packages.conf:%s: невідоме поле: %s\n' "$lineno" "$key" >&2
                errors=$((errors + 1)) ;;
        esac
    done < "$file"
    if ((${#PACKAGE_IDS[@]} == 0)); then
        printf '[ERROR] packages.conf:0: немає жодної коректної групи\n' >&2
        errors=$((errors + 1))
    fi
    for id in "${PACKAGE_IDS[@]}"; do
        if [[ -z "${PACKAGE_TITLES[$id]:-}" ]]; then
            printf '[ERROR] packages.conf:%s: не задано title: %s\n' "${section_lines[$id]}" "$id" >&2
            errors=$((errors + 1))
        fi
        for key in pacman aur configs hooks depends; do
            values=()
            case "$key" in
                pacman) read -r -a values <<< "${PACKAGE_PACMAN[$id]:-}" ;;
                aur) read -r -a values <<< "${PACKAGE_AUR[$id]:-}" ;;
                configs) read -r -a values <<< "${PACKAGE_CONFIGS[$id]:-}" ;;
                hooks) read -r -a values <<< "${PACKAGE_HOOKS[$id]:-}" ;;
                depends) read -r -a values <<< "${PACKAGE_DEPENDS[$id]:-}" ;;
            esac
            local -A seen_tokens=()
            for token in "${values[@]}"; do
                if [[ -v seen_tokens["$token"] ]]; then
                    printf '[ERROR] packages.conf:%s: повторне значення %s.%s: %s\n' "${field_lines["$id.$key"]:-${section_lines[$id]}}" "$id" "$key" "$token" >&2
                    errors=$((errors + 1))
                else
                    seen_tokens["$token"]=1
                fi
                if [[ ! "$token" =~ ^[a-zA-Z0-9][a-zA-Z0-9@._+-]*$ ]]; then
                    printf '[ERROR] packages.conf:%s: неправильне значення %s.%s: %s\n' "${field_lines["$id.$key"]:-${section_lines[$id]}}" "$id" "$key" "$token" >&2
                    errors=$((errors + 1))
                fi
            done
        done
    done
    for id in "${PACKAGE_IDS[@]}"; do
        for token in ${PACKAGE_CONFIGS[$id]:-}; do config_seen["$id|$token"]=1; done
    done
    for bound in "${!PACKAGE_BOUND_CONFIGS[@]}"; do
        id="${bound%%|*}"; package="${bound#*|}"; found=false
        for token in ${PACKAGE_PACMAN[$id]:-} ${PACKAGE_AUR[$id]:-}; do
            if [[ "$token" == "$package" ]]; then found=true; break; fi
        done
        if [[ "$found" != true ]]; then
            printf '[ERROR] packages.conf:%s: config.%s: пакет відсутній у групі %s\n' "${field_lines["$id.config.$package"]}" "$package" "$id" >&2
            errors=$((errors + 1))
        fi
        for token in ${PACKAGE_BOUND_CONFIGS[$bound]}; do
            if [[ ! "$token" =~ ^[a-zA-Z0-9][a-zA-Z0-9@._+-]*$ ]]; then
                printf '[ERROR] packages.conf:%s: некоректний config.%s: %s\n' "${field_lines["$id.config.$package"]}" "$package" "$token" >&2
                errors=$((errors + 1))
            fi
            if [[ -v config_seen["$id|$token"] ]]; then
                printf '[ERROR] packages.conf:%s: повторна конфігурація %s у групі %s\n' "${field_lines["$id.config.$package"]}" "$token" "$id" >&2
                errors=$((errors + 1))
            fi
            config_seen["$id|$token"]=1
        done
    done
    for bound in "${!PACKAGE_BOUND_HOOKS[@]}"; do
        id="${bound%%|*}"; package="${bound#*|}"; found=false
        for token in ${PACKAGE_PACMAN[$id]:-} ${PACKAGE_AUR[$id]:-}; do
            if [[ "$token" == "$package" ]]; then found=true; break; fi
        done
        if [[ "$found" != true ]]; then
            printf '[ERROR] packages.conf:%s: hook.%s: пакет відсутній у групі %s\n' "${field_lines["$id.hook.$package"]}" "$package" "$id" >&2
            errors=$((errors + 1))
        fi
        for token in ${PACKAGE_HOOKS[$id]:-}; do
            if [[ "$token" == "${PACKAGE_BOUND_HOOKS[$bound]}" ]]; then
                printf '[ERROR] packages.conf:%s: hook %s дублюється у групі %s\n' "${field_lines["$id.hook.$package"]}" "$token" "$id" >&2
                errors=$((errors + 1))
            fi
        done
    done
    # Перевірка посилань і циклів виконується тільки після синтаксичного розбору.
    if (( errors == 0 )); then
        for id in "${PACKAGE_IDS[@]}"; do
            for token in ${PACKAGE_DEPENDS[$id]:-}; do
                if ! registry_valid "$token"; then
                    printf '[ERROR] packages.conf:%s: невідома залежність %s -> %s\n' "${field_lines["$id.depends"]:-${section_lines[$id]}}" "$id" "$token" >&2
                    errors=$((errors + 1))
                fi
                if [[ "$token" == "$id" ]]; then
                    printf '[ERROR] packages.conf: самозалежність %s\n' "$id" >&2
                    errors=$((errors + 1))
                fi
            done
        done
        if (( errors == 0 )) && ! registry_graph_order >/dev/null; then
            printf '[ERROR] packages.conf: цикл залежностей\n' >&2
            errors=$((errors + 1))
        fi
    fi
    # shellcheck disable=SC2034
    PACKAGES_SYNTAX_ERRORS="$errors"
    if (( errors > 0 )); then
        printf '[ERROR] packages.conf: синтаксичних помилок: %s\n' "$errors" >&2
        if [[ "$collect" != --collect ]]; then
            PACKAGE_IDS=()
        fi
        return 2
    fi
    return 0
}
registry_ids() { printf '%s\n' "${PACKAGE_IDS[@]}"; }
registry_valid() {
    local id="$1" known
    [[ "$id" =~ ^[a-z][a-z0-9_-]*$ ]] || return 1
    for known in "${PACKAGE_IDS[@]}"; do [[ "$known" == "$id" ]] && return 0; done
    return 1
}
registry_title() { printf '%s' "${PACKAGE_TITLES[$1]:-$1}"; }
registry_show() {
    local id
    for id in "${PACKAGE_IDS[@]}"; do printf '%-15s %s\n' "$id" "$(registry_title "$id")"; done
}
packages_select() {
    local id="$1"
    registry_valid "$id" || return 2
    # Масиви читаються в src/packages/packages.sh після виклику packages_select.
    # shellcheck disable=SC2034
    read -r -a PACMAN_PACKAGES <<< "${PACKAGE_PACMAN[$id]:-}"
    # shellcheck disable=SC2034
    read -r -a AUR_PACKAGES <<< "${PACKAGE_AUR[$id]:-}"
    # shellcheck disable=SC2034
    read -r -a CONFIG_ITEMS <<< "${PACKAGE_CONFIGS[$id]:-}"
    return 0
}

# Топологічне сортування без виконання операцій і без зміни порядку реєстру.
registry_graph_order() {
    local id dep progress remaining
    local -A visited=()
    local -a order=()
    remaining=${#PACKAGE_IDS[@]}
    while (( remaining > 0 )); do
        progress=false
        for id in "${PACKAGE_IDS[@]}"; do
            [[ -v visited["$id"] ]] && continue
            local ready=true
            for dep in ${PACKAGE_DEPENDS[$id]:-}; do
                if [[ ! -v visited["$dep"] ]]; then ready=false; break; fi
            done
            if [[ "$ready" == true ]]; then
                visited["$id"]=1
                order+=("$id")
                remaining=$((remaining - 1))
                progress=true
            fi
        done
        [[ "$progress" == true ]] || return 2
    done
    printf '%s\n' "${order[@]}"
}
