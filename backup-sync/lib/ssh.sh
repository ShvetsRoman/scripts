#!/usr/bin/env bash

configure_ssh() {
    local common_opts=(
        -o BatchMode=yes
        -o ConnectTimeout="$SSH_CONNECT_TIMEOUT"
        -o ServerAliveInterval="$SSH_SERVER_ALIVE_INTERVAL"
        -o ServerAliveCountMax="$SSH_SERVER_ALIVE_COUNT_MAX"
    )

    if [[ -n "$SSH_HOST" ]]; then
        SSH_TARGET="$SSH_HOST"
        SSH_CMD=(ssh "${common_opts[@]}")
        RSYNC_RSH_CMD=(ssh "${common_opts[@]}")
        SSH_MODE_DESC="SSH alias '$SSH_HOST'"
    else
        [[ -f "$SSH_KEY" ]] || log_error "SSH ключ не знайдено: $SSH_KEY"

        SSH_TARGET="${SSH_USER}@${SSH_IP}"
        SSH_CMD=(ssh "${common_opts[@]}" -p "$SSH_PORT" -i "$SSH_KEY")
        RSYNC_RSH_CMD=(ssh "${common_opts[@]}" -p "$SSH_PORT" -i "$SSH_KEY")
        SSH_MODE_DESC="direct ${SSH_USER}@${SSH_IP}:${SSH_PORT}"
    fi

    build_rsh_string
}

build_rsh_string() {
    local arg quoted
    RSH_STRING=""

    for arg in "${RSYNC_RSH_CMD[@]}"; do
        printf -v quoted '%q' "$arg"
        if [[ -z "$RSH_STRING" ]]; then
            RSH_STRING="$quoted"
        else
            RSH_STRING+=" $quoted"
        fi
    done
}

preflight() {
    log_title "PRE-FLIGHT"

    "${SSH_CMD[@]}" "$SSH_TARGET" true ||
        log_error "SSH недоступний: $SSH_TARGET"

    log_ok "SSH OK"

    "${SSH_CMD[@]}" "$SSH_TARGET" "command -v rsync >/dev/null 2>&1" ||
        log_error "rsync не встановлений на remote: $SSH_TARGET"

    log_ok "Remote rsync OK"

    if [[ "$COMMAND" == up && "$DRY_RUN" == false ]]; then
        "${SSH_CMD[@]}" "$SSH_TARGET" "mkdir -p '$REMOTE_DIR'" ||
            log_error "Не вдалося створити REMOTE_DIR: $REMOTE_DIR"
    else
        "${SSH_CMD[@]}" "$SSH_TARGET" "test -d '$REMOTE_DIR'" ||
            log_error "REMOTE_DIR не існує: $REMOTE_DIR"
    fi

    if [[ "$COMMAND" == up || "$COMMAND" == down || "$COMMAND" == verify ]]; then
        if [[ "$CHECK_DISK_SPACE" == true ]]; then
            check_free_space
        else
            log_warn "Перевірку вільного місця вимкнено (--no-space-check)."
        fi
    fi
}
