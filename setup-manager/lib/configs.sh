#!/usr/bin/env bash
# Конфіги Installer: режим копіювання та явна повна синхронізація.
configs_install() {
    local entry id scope rel_source rel_target source target rc extras
    local -a entries=("$@")

    if [[ "${SYNC_DELETE:-false}" == true && "${SETUP_BACKUP_ENABLED:-true}" != true ]]; then
        log_error '--sync-delete несумісний з --no-backup: потрібен захисний backup.'
        return 2
    fi

    for entry in "${entries[@]}"; do
        IFS='|' read -r id scope rel_source rel_target <<< "$entry"
        if [[ "$scope" != home ]]; then
            log_warn "Системний конфіг $id потребує окремої реалізації; пропущено."
            continue
        fi
        if ! core_safe_relative "$rel_source" || ! core_safe_relative "$rel_target"; then
            log_error "Некоректний шлях конфігу: $id"
            return 1
        fi
        source="$ROOT_DIR/dotfiles/$rel_source"
        target="$HOME/$rel_target"
        if [[ ! -e "$source" && ! -L "$source" ]]; then
            log_warn "Конфіг $id не знайдено, пропускаю: $source"
            if [[ "${STRICT_CONFIGS:-false}" == true ]]; then return 1; fi
            continue
        fi
        # Не дозволяємо rsync слідувати за symlink у батьківських каталогах HOME.
        if [[ -L "$target" && -d "$source" ]] || [[ -L "$source" && -d "$target" ]]; then
            log_error "Небезпечна зміна типу конфігу: $id"
            return 1
        fi
        if [[ "${SYNC_DELETE:-false}" == true ]]; then
            if core_compare "$source" "$target"; then
                log_info "Конфіг: $id вже повністю синхронізовано, пропускаю."
                continue
            else
                rc=$?
            fi
        else
            if core_compare_copy "$source" "$target"; then
                log_info "Конфіг: $id вже синхронізовано (без видалення зайвого), пропускаю."
                extras="$(core_extras "$source" "$target")"
                if [[ -n "$extras" ]]; then
                    log_warn "У HOME залишилися зайві файли для $id; використайте --sync-delete для повної синхронізації."
                fi
                continue
            else
                rc=$?
            fi
        fi
        if ((rc == 2)); then return 1; fi

        if [[ "${SYNC_DELETE:-false}" == true ]]; then
            if [[ "${DRY_RUN:-false}" != true ]] && ! setup_confirm "Синхронізувати $id з видаленням зайвих файлів у $target?"; then
                log_warn "Пропущено: $id (немає підтвердження)."
                return 1
            fi
            log_warn "Для $id увімкнено видалення зайвих файлів (--sync-delete)."
        fi
        if [[ "${SETUP_BACKUP_ENABLED:-true}" == true ]]; then
            # Для --sync-delete потрібна копія ВСЬОГО попереднього каталогу.
            core_protect "$target" installer "$rel_target" || return 1
        fi
        log_step "Копіювання конфігу: $id"
        log_info "Звідки: $source"
        log_info "Куди: $target"
        core_copy "$source" "$target" || return 1
        if [[ "${DRY_RUN:-false}" == true ]]; then
            log_info "[DRY-RUN] Конфіг: $id буде скопійовано."
            continue
        fi
        # Критерій успіху залежить від обраної політики копіювання.
        if [[ "${SYNC_DELETE:-false}" == true ]]; then
            if ! core_compare "$source" "$target"; then
                log_error "Конфіг $id не синхронізований після копіювання."
                return 1
            fi
            log_ok "Конфіг: $id повністю синхронізовано."
        else
            if ! core_compare_copy "$source" "$target"; then
                log_error "Конфіг $id не скопійований повністю."
                return 1
            fi
            extras="$(core_extras "$source" "$target")"
            log_ok "Конфіг: $id скопійовано."
            if [[ -n "$extras" ]]; then
                log_warn "У HOME залишилися зайві файли для $id; повна синхронізація потребує --sync-delete."
            fi
        fi
    done
}
