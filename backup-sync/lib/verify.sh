#!/usr/bin/env bash

run_verify_all() {
    case "$VERIFY_DIRECTION" in
        up)
            verify_direction "up"
            ;;
        down)
            verify_direction "down"
            ;;
        both)
            verify_direction "up"
            verify_direction "down"
            ;;
        *)
            die "Невідомий verify direction: $VERIFY_DIRECTION"
            ;;
    esac
}

verify_direction() {
    local direction="$1"
    local dir

    log_title "VERIFY $(direction_label "$direction")"

    for dir in "${BACKUP_DIRS[@]}"; do
        TOTAL=$((TOTAL + 1))
        verify_one_dir "$direction" "$dir"
    done
}

# Чи видаляє реальна синхронізація у цьому напрямку (verify має показувати те саме).
verify_delete_active() {
    [[ "$1" == up ]] && return 0
    [[ "$1" == down && "$DELETE_ON_DOWN" == true ]]
}

verify_one_dir() {
    local direction="$1"
    local dir="$2"
    local src dst output errors errfile rc=0
    local opts=(
        --archive
        --dry-run
        --itemize-changes
        --protect-args
        --rsh="$RSH_STRING"
    )

    if verify_delete_active "$direction"; then
        opts+=(--delete)
    fi

    if [[ "$RSYNC_CHECKSUM_VERIFY" == true ]]; then
        opts+=(--checksum)
    fi

    build_preserve_opts
    opts+=("${PRESERVE_OPTS[@]}")

    build_exclude_opts "$dir"
    opts+=("${DIR_EXCLUDE_OPTS[@]}")

    if [[ "$direction" == up ]]; then
        src="${LOCAL_DIR}/${dir}/"
        dst="${SSH_TARGET}:${REMOTE_DIR}/${dir}/"

        if [[ ! -d "$src" ]]; then
            log_warn "[VERIFY] Немає локально: $src"
            FAILED=$((FAILED + 1))
            FAILED_DIRS+=("verify-up:$dir")
            return 0
        fi
    else
        src="${SSH_TARGET}:${REMOTE_DIR}/${dir}/"
        dst="${LOCAL_DIR}/${dir}/"

        "${SSH_CMD[@]}" "$SSH_TARGET" "test -d $(shq "${REMOTE_DIR}/${dir}")" || rc=$?

        if ((rc == 255)); then
            log_warn "[VERIFY] SSH-помилка при перевірці ${REMOTE_DIR}/${dir}"
            FAILED=$((FAILED + 1))
            FAILED_DIRS+=("verify-down:$dir")
            return 0
        elif ((rc != 0)); then
            log_warn "[VERIFY] Немає remote: ${REMOTE_DIR}/${dir}"
            FAILED=$((FAILED + 1))
            FAILED_DIRS+=("verify-down:$dir")
            return 0
        fi
        rc=0
    fi

    # stdout (itemize) і stderr (повідомлення ssh/rsync) розділяємо:
    # інакше банери та попередження виглядають як «відмінності».
    errfile=$(mktemp)
    TMP_FILES+=("$errfile")

    output=$(rsync "${opts[@]}" "$src" "$dst" 2>"$errfile") || rc=$?
    errors=$(<"$errfile")
    rm -f -- "$errfile"

    if ((rc != 0 && rc != 24)); then
        log_warn "[VERIFY] $dir — rsync error rc=$rc"
        printf '%s\n' "$output"
        printf '%s\n' "$errors" >&2
        FAILED=$((FAILED + 1))
        FAILED_DIRS+=("verify-${direction}:$dir")
        return 0
    fi

    if [[ -n "$errors" ]]; then
        log_warn "[VERIFY] $dir — повідомлення rsync/ssh:"
        printf '%s\n' "$errors" >&2
    fi

    # Рядки вигляду ".d..t......" — відрізняється лише mtime каталогу, це не відмінність вмісту.
    output=$(grep -Ev '^\.d\.\.t\.+ ' <<<"$output" || true)

    if [[ -z "$output" ]]; then
        log_ok "[VERIFY] $dir — повна відповідність"
        SUCCESS=$((SUCCESS + 1))
    else
        log_warn "[VERIFY] $dir — знайдено відмінності"
        printf '%s\n' "$output"
        CHANGED=$((CHANGED + 1))
        CHANGED_DIRS+=("$dir")
    fi
}
