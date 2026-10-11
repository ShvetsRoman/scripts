#!/usr/bin/env bash

# ============================================================
# ОЧИЩЕННЯ BACKUPS ТА LOGS
# Можливості:
# - видалити всі backups;
# - залишити останні 3 backups;
# - видалити backups старші за 30 днів;
# - видалити всі logs;
# - залишити останні 10 logs;
# - видалити logs старші за 30 днів.
# Підтримується:
# - --dry-run;
# - --yes.
# ============================================================

# ============================================================
# ДОПОМІЖНІ ФУНКЦІЇ
# ============================================================

# ------------------------------------------------------------
# Перевірити, чи каталог існує та містить файли.
# ------------------------------------------------------------
dir_has_content() {
    local dir="$1"

    [[ -d "$dir" ]] || return 1

    [[ -n "$(find "$dir" -mindepth 1 -print -quit 2>/dev/null)" ]]
}

# ------------------------------------------------------------
# Показати розмір каталогу.
# ------------------------------------------------------------
show_dir_size() {
    local dir="$1"

    if [[ -d "$dir" ]]; then
        du -sh "$dir" 2>/dev/null | awk '{print $1}'
    else
        echo "0"
    fi
}

# ------------------------------------------------------------
# Запит підтвердження.
# ------------------------------------------------------------
cleanup_confirm() {
    local message="$1"
    local answer

    # --yes автоматично підтверджує операцію.
    if [[ "$ASSUME_YES" == true ]]; then
        return 0
    fi

    read -rp "$message [y/N]: " answer

    [[ "$answer" =~ ^[YyТт]$ ]]
}

# ============================================================
# BACKUPS
# ============================================================

# ------------------------------------------------------------
# Видалити всі backups.
# ------------------------------------------------------------
cleanup_all_backups() {
    echo

    log_info "Каталог backups: $BACKUP_ROOT"
    log_info "Розмір: $(show_dir_size "$BACKUP_ROOT")"

    if ! dir_has_content "$BACKUP_ROOT"; then
        log_info "Каталог backups порожній."
        return 0
    fi

    cleanup_confirm "Видалити всі backups?" || {
        log_info "Операцію скасовано."
        return 0
    }

    echo
    log_step "Видалення всіх backups."

    if [[ "$DRY_RUN" == true ]]; then
        find "$BACKUP_ROOT" \
            -mindepth 1 \
            -maxdepth 1 \
            -print |
            while IFS= read -r item; do
                log_info "[DRY-RUN] rm -rf $item"
            done

        return 0
    fi

    find "$BACKUP_ROOT" \
        -mindepth 1 \
        -maxdepth 1 \
        -exec rm -rf -- {} +

    log_ok "Усі backups видалено."
}

# ------------------------------------------------------------
# Залишити останні 3 backups.
# Backup-каталоги мають формат:
# YYYY-MM-DD_HH-MM-SS
# Завдяки такому формату звичайне сортування за назвою
# відповідає хронологічному порядку.
# ------------------------------------------------------------
cleanup_keep_last_backups() {
    local keep=3
    local -a backups=()
    local delete_count
    local i

    if [[ ! -d "$BACKUP_ROOT" ]]; then
        log_info "Каталог backups не існує."
        return 0
    fi

    mapfile -t backups < <(
        find "$BACKUP_ROOT" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -printf '%f\n' |
            sort
    )

    if ((${#backups[@]} <= keep)); then
        log_info "Backups: ${#backups[@]}. Видаляти нічого."
        return 0
    fi

    delete_count=$((${#backups[@]} - keep))

    echo
    log_info "Всього backups: ${#backups[@]}"
    log_info "Залишити: $keep"
    log_info "Буде видалено: $delete_count"

    cleanup_confirm "Видалити старі backups?" || {
        log_info "Операцію скасовано."
        return 0
    }

    echo
    log_step "Видалення старих backups."

    for ((i = 0; i < delete_count; i++)); do
        local target="$BACKUP_ROOT/${backups[$i]}"

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY-RUN] rm -rf $target"
        else
            rm -rf -- "$target"
            log_info "Видалено: ${backups[$i]}"
        fi
    done

    if [[ "$DRY_RUN" != true ]]; then
        log_ok "Залишено останні $keep backups."
    fi
}

# ------------------------------------------------------------
# Видалити backups старші за 30 днів.
# ------------------------------------------------------------
cleanup_old_backups() {
    local days=30
    local count

    if [[ ! -d "$BACKUP_ROOT" ]]; then
        log_info "Каталог backups не існує."
        return 0
    fi

    count="$(
        find "$BACKUP_ROOT" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -mtime +"$days" |
            wc -l
    )"

    if ((count == 0)); then
        log_info "Backups старші за $days днів відсутні."
        return 0
    fi

    echo
    log_info "Backups старші за $days днів: $count"

    cleanup_confirm "Видалити backups старші за $days днів?" || {
        log_info "Операцію скасовано."
        return 0
    }

    echo
    log_step "Видалення backups старші за $days днів."

    if [[ "$DRY_RUN" == true ]]; then
        find "$BACKUP_ROOT" \
            -mindepth 1 \
            -maxdepth 1 \
            -type d \
            -mtime +"$days" \
            -print |
            while IFS= read -r item; do
                log_info "[DRY-RUN] rm -rf $item"
            done

        return 0
    fi

    find "$BACKUP_ROOT" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -mtime +"$days" \
        -exec rm -rf -- {} +

    log_ok "Старі backups видалено."
}

# ============================================================
# LOGS
# ============================================================

# ------------------------------------------------------------
# Видалити всі logs.
# ------------------------------------------------------------
cleanup_all_logs() {
    echo

    log_info "Каталог logs: $LOG_ROOT"
    log_info "Розмір: $(show_dir_size "$LOG_ROOT")"

    if ! dir_has_content "$LOG_ROOT"; then
        log_info "Каталог logs порожній."
        return 0
    fi

    cleanup_confirm "Видалити всі logs?" || {
        log_info "Операцію скасовано."
        return 0
    }

    echo
    log_step "Видалення всіх logs."

    if [[ "$DRY_RUN" == true ]]; then
        find "$LOG_ROOT" \
            -mindepth 1 \
            -maxdepth 1 \
            -print |
            while IFS= read -r item; do
                log_info "[DRY-RUN] rm -rf $item"
            done

        return 0
    fi

    find "$LOG_ROOT" \
        -mindepth 1 \
        -maxdepth 1 \
        -exec rm -rf -- {} +

    log_ok "Усі logs видалено."
}

# ------------------------------------------------------------
# Залишити останні 10 logs.
# Сортування виконується за часом модифікації файлів.
# ------------------------------------------------------------
cleanup_keep_last_logs() {
    local keep=10
    local -a logs=()
    local delete_count
    local i

    if [[ ! -d "$LOG_ROOT" ]]; then
        log_info "Каталог logs не існує."
        return 0
    fi

    mapfile -t logs < <(
        find "$LOG_ROOT" \
            -mindepth 1 \
            -maxdepth 1 \
            -type f \
            -printf '%T@|%p\n' |
            sort -n |
            cut -d'|' -f2-
    )

    if ((${#logs[@]} <= keep)); then
        log_info "Logs: ${#logs[@]}. Видаляти нічого."
        return 0
    fi

    delete_count=$((${#logs[@]} - keep))

    echo
    log_info "Всього logs: ${#logs[@]}"
    log_info "Залишити: $keep"
    log_info "Буде видалено: $delete_count"

    cleanup_confirm "Видалити старі logs?" || {
        log_info "Операцію скасовано."
        return 0
    }

    echo
    log_step "Видалення старих logs."

    for ((i = 0; i < delete_count; i++)); do
        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY-RUN] rm -f ${logs[$i]}"
        else
            rm -f -- "${logs[$i]}"
            log_info "Видалено: $(basename "${logs[$i]}")"
        fi
    done

    if [[ "$DRY_RUN" != true ]]; then
        log_ok "Залишено останні $keep logs."
    fi
}

# ------------------------------------------------------------
# Видалити logs старші за 30 днів.
# ------------------------------------------------------------
cleanup_old_logs() {
    local days=30
    local count

    if [[ ! -d "$LOG_ROOT" ]]; then
        log_info "Каталог logs не існує."
        return 0
    fi

    count="$(
        find "$LOG_ROOT" \
            -mindepth 1 \
            -maxdepth 1 \
            -type f \
            -mtime +"$days" |
            wc -l
    )"

    if ((count == 0)); then
        log_info "Logs старші за $days днів відсутні."
        return 0
    fi

    echo
    log_info "Logs старші за $days днів: $count"

    cleanup_confirm "Видалити logs старші за $days днів?" || {
        log_info "Операцію скасовано."
        return 0
    }

    echo
    log_step "Видалення logs старші за $days днів."

    if [[ "$DRY_RUN" == true ]]; then
        find "$LOG_ROOT" \
            -mindepth 1 \
            -maxdepth 1 \
            -type f \
            -mtime +"$days" \
            -print |
            while IFS= read -r item; do
                log_info "[DRY-RUN] rm -f $item"
            done

        return 0
    fi

    find "$LOG_ROOT" \
        -mindepth 1 \
        -maxdepth 1 \
        -type f \
        -mtime +"$days" \
        -delete

    log_ok "Старі logs видалено."
}
