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
        printf '%s-%s.tar.gz\n' "$ARCHIVE_PREFIX" "$(timestamp)"
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
    local source="$1"
    local destination="$2"
    local output
    local -a excludes=()

    if [[ ! -e "$source" && ! -L "$source" ]]; then
        return 1
    fi
    if [[ ! -e "$destination" && ! -L "$destination" ]]; then
        return 1
    fi

    if [[ -L "$source" || -L "$destination" ]]; then
        if [[ ! -L "$source" || ! -L "$destination" ]]; then
            return 1
        fi

        [[ "$(readlink -- "$source")" == "$(readlink -- "$destination")" ]]
        return
    fi

    if [[ -d "$source" || -d "$destination" ]]; then
        if [[ ! -d "$source" || ! -d "$destination" ]]; then
            return 1
        fi

        build_exclude_args excludes
        output="$(rsync --archive --checksum --dry-run --delete --itemize-changes "${excludes[@]}" -- "$source/" "$destination/")"
        [[ -z "$output" ]]
        return
    fi

    if [[ ! -f "$source" || ! -f "$destination" ]]; then
        return 1
    fi

    cmp -s -- "$source" "$destination"
}

paths_differ() {
    if paths_are_equal "$1" "$2"; then
        return 1
    fi

    return 0
}
