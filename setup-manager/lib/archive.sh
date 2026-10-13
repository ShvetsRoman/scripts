#!/usr/bin/env bash
# Архіви.

# archive_dir — каталог архівів.
archive_dir() { printf '%s/archives' "$ROOT_DIR"; }

# archive_valid_name — чи ім’я архіву безпечне.
# Дозволяє лише [a-zA-Z0-9._-]+.tar.gz без '..'.
archive_valid_name() {
    [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*\.tar\.gz$ && "$1" != *..* ]]
}

# archive_list — список архівів (новіші першими).
# Аргумент --quiet пригнічує log_info (для парсингу).
archive_list() {
    clear 2>/dev/null || true
    local quiet=false
    if [[ "${1:-}" != --quiet ]]; then header '■  archive list'; fi
    [[ "${1:-}" == --quiet ]] && quiet=true
    local dir; dir="$(archive_dir)"
    [[ -d "$dir" ]] || { $quiet || log info 'Архівів немає.'; return 0; }
    local -a files=()
    mapfile -t files < <(find "$dir" -maxdepth 1 -type f -name '*.tar.gz' -printf '%f\n' | sort -r)
    ((${#files[@]})) || { $quiet || log info 'Архівів немає.'; return 0; }
    printf '%s\n' "${files[@]}"
}

# _archive_helper — шлях до python3-утиліти перевірки архівів.
_archive_helper() { printf '%s/tools/archive_safe.py' "$ROOT_DIR"; }

# archive_verify — перевіряє архів через archive_safe.py verify.
archive_verify() {
    command -v python3 >/dev/null || { log error 'Потрібен python3'; return 1; }
    python3 "$(_archive_helper)" verify "$1"
}

# archive_create — створює новий архів dotfiles/.
# Унікальність забезпечує mktemp + ln: колізія навіть у межах секунди неможлива.
archive_create() {
    clear 2>/dev/null || true
    header '■  archive create'
    local prefix="${SETUP_ARCHIVE_PREFIX:-dotfiles-backup}"
    [[ "$prefix" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]] || { log error "Префікс: $prefix"; return 2; }
    local ts; ts="$(date +%Y-%m-%d_%H-%M-%S)"
    local dir; dir="$(archive_dir)"
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log info "[DRY-RUN] $dir/${prefix}_${ts}_UNIQUE.tar.gz"; return 0
    fi
    mkdir -p -- "$dir" || return 1
    local tmp; tmp="$(mktemp "$dir/.creating.XXXXXXXX")" || return 1
    tar -C "$ROOT_DIR" --exclude='.git' -czf "$tmp" dotfiles || { rm -f -- "$tmp"; return 1; }
    local token="${tmp##*.creating.}"
    local dest="$dir/${prefix}_${ts}_${token}.tar.gz"
    ln -- "$tmp" "$dest" || { rm -f -- "$tmp"; log error "ln: $dest"; return 1; }
    rm -f -- "$tmp"
    log ok "Архів: $dest"
}

# archive_restore — замінює dotfiles/ вмістом архіву.
# Перед заміною створює захисний архів поточного стану.
archive_restore() {
    clear 2>/dev/null || true
header "■  archive restore: $1"
    local name="$1"
    archive_valid_name "$name" || { log error "Ім’я: $name"; return 2; }
    local file="$ROOT_DIR/archives/$name"
    [[ -f "$file" && ! -L "$file" ]] || { log error "Немає: $file"; return 1; }
    archive_verify "$file" || { log error 'Небезпечний архів'; return 1; }
    [[ "${DRY_RUN:-false}" == true ]] && { log info "[DRY-RUN] restore: $name"; return 0; }
    setup_confirm "Замінити dotfiles з $name?" || return 0
    archive_create || return 1
    local tmp; tmp="$(mktemp -d "$ROOT_DIR/.restore.XXXXXXXX")" || return 1
    python3 "$(_archive_helper)" extract "$file" "$tmp" || { rm -rf -- "$tmp"; return 1; }
    [[ -d "$tmp/dotfiles" ]] || { rm -rf -- "$tmp"; return 1; }
    mv -- "$ROOT_DIR/dotfiles" "$tmp/previous" || { rm -rf -- "$tmp"; return 1; }
    if ! mv -- "$tmp/dotfiles" "$ROOT_DIR/dotfiles"; then
        mv -- "$tmp/previous" "$ROOT_DIR/dotfiles" || true
        rm -rf -- "$tmp"; return 1
    fi
    rm -rf -- "$tmp"
    log ok "Відновлено: $name"
}

# archive_main — диспетчер підкоманд archive.
archive_main() {
    case "${1:-list}" in
        list) archive_list ;;
        create) archive_create ;;
        restore) [[ -n "${2:-}" ]] || { log error 'Потрібне ім’я'; return 2; }; archive_restore "$2" ;;
        *) log error 'archive list|create|restore NAME'; return 2 ;;
    esac
}
