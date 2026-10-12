#!/usr/bin/env bash
# Архіви містять лише дерево dotfiles/; запис — через тимчасовий файл.
archive_root() { printf '%s/archives' "$ROOT_DIR"; }
archive_valid_name() { [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*\.tar\.gz$ && "$1" != *..* ]]; }
archive_list() {
    local dir
    dir="$(archive_root)"
    if [[ ! -d "$dir" ]]; then
        log_info 'Архівів немає.'
        return 0
    fi
    local -a archives=()
    mapfile -t archives < <(find "$dir" -maxdepth 1 -type f -name '*.tar.gz' -printf '%f\n' | sort -r)
    if ((${#archives[@]} == 0)); then
        log_info 'Архівів немає.'
        return 0
    fi
    printf '%s\n' "${archives[@]}"
}
archive_create() {
    local prefix name dest tmp token timestamp
    prefix="${SETUP_ARCHIVE_PREFIX:-dotfiles-backup}"
    if [[ ! "$prefix" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]*$ ]]; then
        log_error "Некоректний префікс архіву: $prefix"
        return 2
    fi
    timestamp="$(date +%Y-%m-%d_%H-%M-%S)"
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log_info "[DRY-RUN] Створення нового архіву: $(archive_root)/${prefix}_${timestamp}_UNIQUE.tar.gz"
        return 0
    fi
    mkdir -p -- "$(archive_root)" || return 1
    tmp="$(mktemp "$(archive_root)/.creating.XXXXXXXX")" || return 1
    if ! tar -C "$ROOT_DIR" -czf "$tmp" dotfiles; then
        rm -f -- "$tmp"
        return 1
    fi
    # Унікальність забезпечує mktemp, а ln не дозволяє перезаписати архів,
    # навіть якщо архів із таким ім'ям з'явиться під час виконання.
    token="${tmp##*.creating.}"
    name="${prefix}_${timestamp}_${token}.tar.gz"
    dest="$(archive_root)/$name"
    if ! ln -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        log_error "Не вдалося зберегти новий архів: $dest"
        return 1
    fi
    rm -f -- "$tmp"
    log_ok "Архів створено: $dest"
}

archive_safe_helper() {
    cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && printf "%s/tools/archive_safe.py" "$PWD"
}
archive_verify() {
    command -v python3 >/dev/null || { log_error 'Для безпечного відновлення потрібен python3'; return 1; }
    python3 "$(archive_safe_helper)" verify "$1"
}
archive_restore() {
    local name="$1" file tmp
    archive_valid_name "$name" || { log_error "Некоректне ім’я архіву"; return 2; }
    file="$(archive_root)/$name"
    [[ -f "$file" && ! -L "$file" ]] || return 1
    archive_verify "$file" || { log_error 'Архів містить небезпечні або пошкоджені записи'; return 1; }
    if [[ "${DRY_RUN:-false}" == true ]]; then log_info "[DRY-RUN] Відновлення архіву: $name"; return 0; fi
    setup_confirm "Замінити сховище dotfiles з архіву $name?" || return 0
    # Перед відновленням завжди створюємо захисний архів поточного сховища.
    archive_create || return 1
    tmp="$(mktemp -d "$ROOT_DIR/.restore.XXXXXXXX")" || return 1
    if ! python3 "$(archive_safe_helper)" extract "$file" "$tmp"; then rm -rf -- "$tmp"; return 1; fi
    [[ -d "$tmp/dotfiles" ]] || { rm -rf -- "$tmp"; return 1; }
    # Захист від підміни файлів шляхом символьних посилань перевірений вище.
    mv -- "$ROOT_DIR/dotfiles" "$tmp/previous" || { rm -rf -- "$tmp"; return 1; }
    if ! mv -- "$tmp/dotfiles" "$ROOT_DIR/dotfiles"; then
        mv -- "$tmp/previous" "$ROOT_DIR/dotfiles" || :
        rm -rf -- "$tmp"
        return 1
    fi
    rm -rf -- "$tmp"
    log_ok "Сховище dotfiles відновлено з архіву: $name"
}
archive_main() {
    local action="${1:-list}" name="${2:-}"
    case "$action" in
        list) archive_list ;;
        create) archive_create ;;
        restore) [[ -n "$name" ]] || { log_error 'Вкажи назву архіву'; return 2; }; archive_restore "$name" ;;
        *) log_error 'archive create|list|restore ІМЯ'; return 2 ;;
    esac
}
