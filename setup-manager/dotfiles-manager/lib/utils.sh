#!/usr/bin/env bash

confirm() {
    local message="$1"
    local answer

    if [[ "${YES:-false}" == true || "${DRY_RUN:-false}" == true ]]; then
        return 0
    fi

    read -r -p "$message [y/N]: " answer

    case "$answer" in
        y|Y|yes|YES|так|ТАК)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

ensure_directories() {
    if [[ "${DRY_RUN:-false}" == true ]]; then
        return 0
    fi

    mkdir -p -- "$DOTFILES_DIR" "$RECOVERY_DIR" "$ARCHIVE_DIR"
}

path_exists_in_home() {
    [[ -e "$HOME/$1" || -L "$HOME/$1" ]]
}

path_exists_in_backup() {
    [[ -e "$DOTFILES_DIR/$1" || -L "$DOTFILES_DIR/$1" ]]
}

timestamp() {
    date '+%Y-%m-%d_%H-%M-%S'
}

path_is_safe() {
    local path="$1"

    if [[ -z "$path" ]]; then
        return 1
    fi
    if [[ "$path" == /* || "$path" == "." || "$path" == ".." ]]; then
        return 1
    fi
    if [[ "$path" == ../* || "$path" == */../* || "$path" == */.. ]]; then
        return 1
    fi

    return 0
}

normalize_archive_name() {
    local requested="${1:-}"

    if [[ -z "$requested" ]]; then
        printf '%s_%s.tar.gz\n' "$ARCHIVE_PREFIX" "$(timestamp)"
        return 0
    fi

    if [[ "$requested" == */* || "$requested" == "." || "$requested" == ".." ]]; then
        log_error "Некоректне ім'я archive: $requested"
        return 2
    fi

    if [[ "$requested" != *.tar.gz ]]; then
        requested="${requested}.tar.gz"
    fi

    printf '%s\n' "$requested"
}

build_exclude_args() {
    local -n result_ref="$1"
    local pattern
    result_ref=()

    if ! declare -p EXCLUDE_PATTERNS >/dev/null 2>&1; then
        return 0
    fi

    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        result_ref+=("--exclude=$pattern")
    done
}

paths_are_equal() {
    # Всі підсистеми користуються однією реалізацією порівняння.
    if ! declare -F core_compare >/dev/null 2>&1; then
        # Підтримка автономних тестів бібліотеки Dotfiles Manager.
        # shellcheck source=../../lib/core.sh
        source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)/lib/core.sh"
    fi
    core_compare "$1" "$2" "${EXCLUDE_PATTERNS[@]}"
}

paths_differ() {
    local result=0
    paths_are_equal "$1" "$2" || result=$?
    case "$result" in
        0) return 1 ;; # немає розбіжностей
        1) return 0 ;; # є розбіжності
        *) return 2 ;; # помилка (не маскуємо під CHANGED)
    esac
}

