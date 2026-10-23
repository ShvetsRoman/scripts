#!/usr/bin/env bash
# Привілейоване відновлення лише зареєстрованих звичайних файлів /etc.
# Не підтримує каталоги, symlink або --sync-delete.
# Копіювання системного файлу; тести використовують лише тимчасові шляхи.
_system_restore_copy() {
    local src="$1" dst="$2" backup_dir="$3" tmp='' mode owner group rc=0
    shift 3
    local -a root=("$@")

    "${root[@]}" install -d -m 0700 -- "$backup_dir" || return 2
    "${root[@]}" cp -a -- "$dst" "$backup_dir/original" || return 2
    mode="$("${root[@]}" stat -c %a -- "$dst")" || return 2
    owner="$("${root[@]}" stat -c %u -- "$dst")" || return 2
    group="$("${root[@]}" stat -c %g -- "$dst")" || return 2
    tmp="$("${root[@]}" mktemp "${dst}.setup-manager.XXXXXXXX")" || return 2

    if ! "${root[@]}" install -m "$mode" -o "$owner" -g "$group" -- "$src" "$tmp"; then
        "${root[@]}" rm -f -- "$tmp" || log error "Не вдалося прибрати тимчасовий файл: $tmp"
        return 2
    fi
    if ! "${root[@]}" mv -f -- "$tmp" "$dst"; then
        "${root[@]}" rm -f -- "$tmp" || log error "Не вдалося прибрати тимчасовий файл: $tmp"
        return 2
    fi

    "${root[@]}" cmp -s -- "$src" "$dst" || rc=$?
    if ((rc != 0)); then
        log error "System restore: перевірка запису не пройдена, виконую rollback"
        if ! "${root[@]}" cp -a -- "$backup_dir/original" "$dst"; then
            log error "System restore: rollback не вдався; backup: $backup_dir"
        fi
        return 2
    fi
    return 0
}

system_restore() {
    local src="$1" dst="$2" label="$3" backup_dir stamp
    APPLY_RESULT=skipped
    if [[ "$dst" != /etc/* ]] || [[ "$dst" == /etc/*/../* ]]; then
        log error "$label — system restore дозволений тільки в /etc"
        return 2
    fi
    if [[ "${SYNC_DELETE:-false}" == true ]]; then
        log error "$label — --sync-delete заборонено для system restore"
        return 2
    fi
    if ! path_ok_abs "$src"; then
        log error "Небезпечний шлях джерела: $src"
        return 2
    fi

    if ! path_ok_abs "$dst"; then
        log error "Небезпечний шлях призначення: $dst"
        return 2
    fi
    [[ -f "$src" && ! -L "$src" ]] || {
        log error "$label — потрібен звичайний файл у dotfiles"
        return 2
    }
    [[ -f "$dst" && ! -L "$dst" ]] || {
        log error "$label — ціль має існувати та бути звичайним файлом"
        return 2
    }
    # Зіставляємо точний вміст, не приховуючи помилку читання.
    if cmp -s -- "$src" "$dst"; then
        APPLY_RESULT=unchanged
        log info "$label — без змін"
        return 0
    fi
    if [[ "${DRY_RUN:-false}" == true ]]; then
        APPLY_RESULT=changed
        log info "[DRY-RUN] system restore: $label → $dst"
        return 0
    fi
    if [[ "${SETUP_BACKUP_ENABLED:-true}" != true ]]; then
        log error "$label — system restore потребує backup"
        return 2
    fi
    if [[ "${SETUP_ASSUME_YES:-false}" != true ]]; then
        setup_confirm "Відновити системний файл $dst із захисною копією?" || return 2
    fi
    # Запускаємо root-команди тільки після перевірок і підтвердження.
    local -a root=()
    if ((EUID != 0)); then
        command -v sudo >/dev/null 2>&1 || {
            log error "$label — для system restore потрібен sudo"
            return 2
        }
        root=(sudo --)
    fi
    stamp="$(date +%Y%m%d-%H%M%S)-$$"
    backup_dir="$(path_system_backup "$stamp")"
    _system_restore_copy "$src" "$dst" "$backup_dir" "${root[@]}" || return 2
    # shellcheck disable=SC2034 # Використовується іншими модулями через source
    APPLY_RESULT=changed
    log ok "$label — системний файл відновлено (backup: $backup_dir)"
    return 0
}
