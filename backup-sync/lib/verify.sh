#!/usr/bin/env bash

run_verify_all() {
    local verify_dir

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
            log_error "Невідомий verify direction: $VERIFY_DIRECTION"
            ;;
    esac
}

verify_direction() {
    local direction="$1"
    local dir

    log_title "VERIFY $([[ "$direction" == up ]] && printf 'PC -> SERVER' || printf 'SERVER -> PC')"

    for dir in "${BACKUP_DIRS[@]}"; do
        TOTAL=$((TOTAL + 1))
        verify_one_dir "$direction" "$dir"
    done
}

verify_one_dir() {
    local direction="$1"
    local dir="$2"
    local src dst output rc
    local opts=(
        --archive
        --dry-run
        --itemize-changes
        --protect-args
        --delete
        --rsh="$RSH_STRING"
    )

    if [[ "$RSYNC_CHECKSUM_VERIFY" == true ]]; then
        opts+=(--checksum)
    fi

    if [[ -f "$EXCLUDE_FILE" ]]; then
        opts+=(--exclude-from="$EXCLUDE_FILE")
    fi

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

        set +e
        "${SSH_CMD[@]}" "$SSH_TARGET" "test -d '${REMOTE_DIR}/${dir}'"
        rc=$?
        set -e

        if ((rc != 0)); then
            log_warn "[VERIFY] Немає remote: ${REMOTE_DIR}/${dir}"
            FAILED=$((FAILED + 1))
            FAILED_DIRS+=("verify-down:$dir")
            return 0
        fi
    fi

    set +e
    output=$(rsync "${opts[@]}" "$src" "$dst" 2>&1)
    rc=$?
    set -e

    if ((rc != 0)); then
        log_warn "[VERIFY] $dir — rsync error rc=$rc"
        printf '%s\n' "$output"
        FAILED=$((FAILED + 1))
        FAILED_DIRS+=("verify-${direction}:$dir")
        return 0
    fi

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
