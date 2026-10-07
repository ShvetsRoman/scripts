#!/usr/bin/env bash

build_rsync_opts() {
    RSYNC_OPTS=(
        --archive
        --verbose
        --human-readable
        --stats
        --itemize-changes
        --protect-args
        --rsh="$RSH_STRING"
    )

    if [[ -f "$EXCLUDE_FILE" ]]; then
        RSYNC_OPTS+=(--exclude-from="$EXCLUDE_FILE")
    fi

    if [[ "$RSYNC_PARTIAL" == true ]]; then
        RSYNC_OPTS+=(--partial --partial-dir=.rsync-partial)
    fi

    if [[ "$RSYNC_COMPRESS" == true ]]; then
        RSYNC_OPTS+=(--compress)
    fi

    if [[ "$DRY_RUN" == true ]]; then
        RSYNC_OPTS+=(--dry-run)
    else
        RSYNC_OPTS+=(--info=progress2)
    fi

    if [[ "$DIRECTION" == up ]]; then
        RSYNC_OPTS+=(--delete-delay)

        if [[ "$RECOVERY_ENABLED" == true && "$DRY_RUN" == false ]]; then
            RSYNC_OPTS+=(
                --backup
                --backup-dir="${REMOTE_DIR}/${RECOVERY_ROOT}/${TIMESTAMP}"
            )
        fi
    elif [[ "$DIRECTION" == down && "$DELETE_ON_DOWN" == true ]]; then
        RSYNC_OPTS+=(--delete-delay)
    fi
}

print_mode_summary() {
    log_title "РЕЖИМ"

    case "$COMMAND" in
        up)
            log_info "Команда   : UP"
            ;;
        down)
            log_info "Команда   : DOWN"
            ;;
        verify)
            log_info "Команда   : VERIFY ($VERIFY_DIRECTION)"
            ;;
        cleanup)
            log_info "Команда   : CLEANUP"
            ;;
    esac

    if [[ "$COMMAND" == up || "$COMMAND" == down ]]; then
        log_info "Напрямок  : $([[ "$DIRECTION" == up ]] && printf 'PC -> SERVER' || printf 'SERVER -> PC')"
        log_info "Dry-run   : $([[ "$DRY_RUN" == true ]] && printf 'ТАК' || printf 'НІ')"
    fi

    if [[ "$COMMAND" != cleanup && "$COMMAND" != help ]]; then
        log_info "SSH       : $SSH_MODE_DESC"
        log_info "Remote    : $SSH_TARGET:$REMOTE_DIR"
        log_info "Local     : $LOCAL_DIR"
        log_info "Disk check: $([[ "$CHECK_DISK_SPACE" == true ]] && printf 'ТАК' || printf 'НІ')"
    fi

    log_info "Log       : $LOG_FILE"
}

confirm_sync() {
    [[ "$DRY_RUN" == true ]] && return 0
    [[ "$ASSUME_YES" == true ]] && return 0

    log_title "ПІДТВЕРДЖЕННЯ"

    if [[ "$DIRECTION" == up ]]; then
        log_warn "PC -> SERVER працює як mirror."
        log_warn "Файли, яких немає локально, будуть видалені на сервері через --delete-delay."

        if [[ "$RECOVERY_ENABLED" == true ]]; then
            log_warn "Старі/видалені серверні версії будуть збережені в recovery."
        fi
    else
        log_warn "SERVER -> PC оновить локальні файли."
        if [[ "$DELETE_ON_DOWN" == true ]]; then
            log_warn "DELETE_ON_DOWN=true: локальні зайві файли також будуть видалені."
        else
            log_warn "DELETE_ON_DOWN=false: локальні зайві файли не видаляються."
        fi
    fi

    local answer
    read -r -p "Продовжити? [y/N] " answer

    case "$answer" in
        y|Y|yes|YES)
            ;;
        *)
            log_info "Скасовано."
            exit 0
            ;;
    esac
}

run_sync_all() {
    build_rsync_opts

    local dir
    for dir in "${BACKUP_DIRS[@]}"; do
        TOTAL=$((TOTAL + 1))
        sync_one_dir "$dir"
    done
}

sync_one_dir() {
    local dir="$1"
    local src dst rc

    log_title "SYNC: $dir"

    if [[ "$DIRECTION" == up ]]; then
        src="${LOCAL_DIR}/${dir}/"
        dst="${SSH_TARGET}:${REMOTE_DIR}/${dir}/"

        if [[ ! -d "$src" ]]; then
            log_warn "Немає локально: $src"
            FAILED=$((FAILED + 1))
            FAILED_DIRS+=("$dir")
            return 0
        fi

        if [[ "$DRY_RUN" == false ]]; then
            "${SSH_CMD[@]}" "$SSH_TARGET" "mkdir -p '${REMOTE_DIR}/${dir}'" || {
                log_warn "Не вдалося створити remote каталог: ${REMOTE_DIR}/${dir}"
                FAILED=$((FAILED + 1))
                FAILED_DIRS+=("$dir")
                return 0
            }
        fi
    else
        src="${SSH_TARGET}:${REMOTE_DIR}/${dir}/"
        dst="${LOCAL_DIR}/${dir}/"

        set +e
        "${SSH_CMD[@]}" "$SSH_TARGET" "test -d '${REMOTE_DIR}/${dir}'"
        rc=$?
        set -e

        if ((rc == 255)); then
            log_error "SSH-помилка при перевірці ${REMOTE_DIR}/${dir}."
        elif ((rc != 0)); then
            log_warn "Немає на remote: ${REMOTE_DIR}/${dir}"
            FAILED=$((FAILED + 1))
            FAILED_DIRS+=("$dir")
            return 0
        fi

        if [[ "$DRY_RUN" == false ]]; then
            mkdir -p -- "$dst" || {
                log_warn "Не вдалося створити локальний каталог: $dst"
                FAILED=$((FAILED + 1))
                FAILED_DIRS+=("$dir")
                return 0
            }
        fi
    fi

    if rsync "${RSYNC_OPTS[@]}" "$src" "$dst"; then
        log_ok "$dir синхронізовано"
        SUCCESS=$((SUCCESS + 1))
    else
        log_warn "$dir — помилка rsync"
        FAILED=$((FAILED + 1))
        FAILED_DIRS+=("$dir")
    fi
}

print_final_summary() {
    END_EPOCH=$(date +%s)

    log_title "ПІДСУМОК"

    if [[ "$COMMAND" == verify ]]; then
        log_info "Усього  : $TOTAL"
        log_info "OK      : $SUCCESS"
        log_info "CHANGED : $CHANGED"
        log_info "FAIL    : $FAILED"

        if ((${#CHANGED_DIRS[@]} > 0)); then
            printf '\n'
            log_warn "Відмінності: ${CHANGED_DIRS[*]}"
        fi

        if ((${#FAILED_DIRS[@]} > 0)); then
            log_warn "З помилками: ${FAILED_DIRS[*]}"
        fi

        if ((START_EPOCH > 0)); then
            log_info "Тривалість : $(human_duration $((END_EPOCH - START_EPOCH)))"
        fi

        if [[ -n "$LOG_FILE" ]]; then
            log_info "Log        : $LOG_FILE"
        fi

        if ((FAILED > 0)); then
            log_warn "VERIFY завершено з помилками."
            return 1
        fi

        if ((CHANGED > 0)); then
            log_warn "VERIFY завершено: знайдено відмінності."
            return 0
        fi

        log_ok "VERIFY завершено: повна відповідність."
        return 0
    fi

    if [[ "$COMMAND" == up || "$COMMAND" == down ]]; then
        log_info "Усього     : $TOTAL"
        log_info "OK         : $SUCCESS"
        log_info "FAIL       : $FAILED"
    fi

    if ((${#FAILED_DIRS[@]} > 0)); then
        log_warn "З помилками : ${FAILED_DIRS[*]}"
    fi

    if ((START_EPOCH > 0)); then
        log_info "Тривалість : $(human_duration $((END_EPOCH - START_EPOCH)))"
    fi

    if [[ -n "$LOG_FILE" ]]; then
        log_info "Log        : $LOG_FILE"
    fi

    if ((FAILED == 0)); then
        log_ok "Готово."
        return 0
    fi

    log_warn "Готово з помилками."
    return 1
}
