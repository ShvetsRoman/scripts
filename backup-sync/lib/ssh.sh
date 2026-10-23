#!/usr/bin/env bash

configure_ssh() {
    local common_opts=(
        -o BatchMode=yes
        -o ConnectTimeout="$SSH_CONNECT_TIMEOUT"
        -o ServerAliveInterval="$SSH_SERVER_ALIVE_INTERVAL"
        -o ServerAliveCountMax="$SSH_SERVER_ALIVE_COUNT_MAX"
    )

    if [[ -n "$SSH_STRICT_HOST_KEY_CHECKING" ]]; then
        common_opts+=(-o StrictHostKeyChecking="$SSH_STRICT_HOST_KEY_CHECKING")
    fi

    if [[ -n "$SSH_HOST" ]]; then
        SSH_TARGET="$SSH_HOST"
        SSH_CMD=(ssh "${common_opts[@]}")
        RSYNC_RSH_CMD=(ssh "${common_opts[@]}")
        SSH_MODE_DESC="SSH alias '$SSH_HOST'"
    else
        : "${SSH_IP:?SSH_IP не задано (або використайте --host)}"
        : "${SSH_USER:?SSH_USER не задано (або використайте --host)}"
        : "${SSH_PORT:?SSH_PORT не задано (або використайте --host)}"
        : "${SSH_KEY:?SSH_KEY не задано (або використайте --host)}"
        [[ -f "$SSH_KEY" ]] || die "SSH ключ не знайдено: $SSH_KEY"

        SSH_TARGET="${SSH_USER}@${SSH_IP}"
        # IdentitiesOnly: використовувати лише вказаний ключ, а не всі з ssh-agent
        # (інакше сервер може відхилити з'єднання через забагато спроб автентифікації).
        SSH_CMD=(ssh "${common_opts[@]}" -p "$SSH_PORT" -i "$SSH_KEY" -o IdentitiesOnly=yes)
        RSYNC_RSH_CMD=(ssh "${common_opts[@]}" -p "$SSH_PORT" -i "$SSH_KEY" -o IdentitiesOnly=yes)
        SSH_MODE_DESC="direct ${SSH_USER}@${SSH_IP}:${SSH_PORT}"
    fi

    build_rsh_string
}

# Рядок для `rsync --rsh=`. rsync сам розбиває його за пробілами і розуміє лише
# одинарні/подвійні лапки (не backslash-екранування з `printf %q`).
build_rsh_string() {
    local arg quoted
    RSH_STRING=""

    for arg in "${RSYNC_RSH_CMD[@]}"; do
        if [[ "$arg" =~ ^[A-Za-z0-9_./:=@%+,-]+$ ]]; then
            quoted="$arg"
        elif [[ "$arg" != *\'* ]]; then
            quoted="'$arg'"
        elif [[ "$arg" != *\"* ]]; then
            quoted="\"$arg\""
        else
            die "Аргумент ssh містить одночасно ' та \": $arg"
        fi

        if [[ -z "$RSH_STRING" ]]; then
            RSH_STRING="$quoted"
        else
            RSH_STRING+=" $quoted"
        fi
    done
}

# Стан можливості у виводі `rsync --version`: yes | no | unknown.
# rsync 3.x друкує "Capabilities:" з токенами "ACLs", "xattrs", "hardlinks";
# відсутню можливість позначає як "no ACLs". Старіші формати → unknown.
rsync_cap_state() {
    local text="$1" feature="$2"

    if ! grep -q 'Capabilities' <<<"$text"; then
        printf 'unknown'
    elif grep -Eq "(^|[[:space:],])no ${feature}([[:space:],]|\$)" <<<"$text"; then
        printf 'no'
    elif grep -Eq "(^|[[:space:],])${feature}([[:space:],]|\$)" <<<"$text"; then
        printf 'yes'
    else
        printf 'unknown'
    fi
}

# Якщо в конфігу ввімкнено -H/-A/-X, обидва rsync (локальний і віддалений) мають їх підтримувати:
# інакше rsync впаде посеред синхронізації. Перевіряємо ДО початку роботи.
check_rsync_capabilities() {
    local flag feature name local_text remote_text state side
    local wanted=()

    [[ "$RSYNC_PRESERVE_HARDLINKS" == true ]] && wanted+=("hardlinks:hardlinks:RSYNC_PRESERVE_HARDLINKS")
    [[ "$RSYNC_PRESERVE_ACLS" == true ]]      && wanted+=("ACLs:ACL:RSYNC_PRESERVE_ACLS")
    [[ "$RSYNC_PRESERVE_XATTRS" == true ]]    && wanted+=("xattrs:xattrs:RSYNC_PRESERVE_XATTRS")

    ((${#wanted[@]} > 0)) || return 0

    local_text=$(rsync --version 2>/dev/null) || local_text=""
    remote_text=$("${SSH_CMD[@]}" "$SSH_TARGET" "rsync --version" 2>/dev/null) || remote_text=""

    for flag in "${wanted[@]}"; do
        feature="${flag%%:*}"
        name="${flag#*:}"; name="${name%%:*}"
        flag="${flag##*:}"

        for side in local remote; do
            if [[ "$side" == local ]]; then
                state=$(rsync_cap_state "$local_text" "$feature")
            else
                state=$(rsync_cap_state "$remote_text" "$feature")
            fi

            case "$state" in
                no)
                    die "rsync на ${side} не підтримує ${name} (${flag}=true). Вимкніть ${flag} у конфігу або оновіть rsync."
                    ;;
                unknown)
                    log_warn "Не вдалося визначити підтримку ${name} у rsync (${side}); якщо її немає, rsync завершиться з помилкою."
                    ;;
            esac
        done
    done

    log_ok "rsync: підтримка потрібних можливостей підтверджена (або не спростована)."
}

preflight() {
    log_title "PRE-FLIGHT"

    local rc=0

    "${SSH_CMD[@]}" "$SSH_TARGET" true ||
        die "SSH недоступний: $SSH_TARGET (перевірте мережу, ключ і known_hosts; при першому підключенні виконайте ssh вручну або задайте SSH_STRICT_HOST_KEY_CHECKING=accept-new)"

    log_ok "SSH OK"

    "${SSH_CMD[@]}" "$SSH_TARGET" "command -v rsync >/dev/null 2>&1" ||
        die "rsync не встановлений на remote: $SSH_TARGET"

    log_ok "Remote rsync OK"

    if [[ "$COMMAND" != cleanup ]]; then
        check_rsync_capabilities
    fi

    # REMOTE_DIR для up створюється ПІСЛЯ підтвердження (ensure_remote_dir), а не тут:
    # скасований запуск не має лишати слідів на сервері.
    "${SSH_CMD[@]}" "$SSH_TARGET" "test -d $(shq "$REMOTE_DIR")" || rc=$?
    if ((rc == 255)); then
        die "SSH-помилка при перевірці REMOTE_DIR: $REMOTE_DIR"
    elif ((rc != 0)); then
        if [[ "$COMMAND" == up ]]; then
            REMOTE_DIR_MISSING=true
            log_info "REMOTE_DIR ще не існує: $REMOTE_DIR — буде створено після підтвердження (у --dry-run не створюється)."
        else
            die "REMOTE_DIR не існує: $REMOTE_DIR"
        fi
    fi
}

# Створення REMOTE_DIR — лише для реального up і лише після підтвердження.
ensure_remote_dir() {
    [[ "$COMMAND" == up && "$DRY_RUN" == false ]] || return 0

    "${SSH_CMD[@]}" "$SSH_TARGET" "mkdir -p $(shq "$REMOTE_DIR")" ||
        die "Не вдалося створити REMOTE_DIR: $REMOTE_DIR"

    if [[ "$REMOTE_DIR_MISSING" == true ]]; then
        log_ok "Створено REMOTE_DIR: $REMOTE_DIR"
        REMOTE_DIR_MISSING=false
    fi
}
