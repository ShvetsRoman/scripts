#!/usr/bin/env bash
#
# Віддалений lock між РІЗНИМИ ПК, що пишуть на один сервер (локальний flock цього не покриває).
# Реалізація через атомарний `mkdir` — працює на будь-якій файловій системі і в busybox/toybox.
# Lock береться лише для режимів, що змінюють дані: up, down (без --dry-run) і cleanup (без --dry-run).
# verify та dry-run нічого не міняють і lock не беруть.
#
# Lock НЕ знімається автоматично при аварійному завершенні (kill -9, відключення живлення):
# безпечніше зупинитись, ніж дозволити двом mirror-запускам одночасно видаляти файли.
# Зняти застарілий lock: --break-lock (або вручну rm -rf на сервері).

needs_remote_lock() {
    [[ "$DRY_RUN" == false ]] || return 1
    case "$COMMAND" in
        up|down|cleanup) return 0 ;;
        *) return 1 ;;
    esac
}

acquire_remote_lock() {
    local lock owner script out rc=0

    needs_remote_lock || return 0

    lock="${REMOTE_DIR}/${REMOTE_LOCK_NAME}"
    REMOTE_LOCK_TOKEN="${HOSTNAME:-host}-$$-${RANDOM}${RANDOM}"
    owner="host=${HOSTNAME:-unknown} user=${USER:-${UID}} pid=$$ cmd=${COMMAND} started=$(date '+%Y-%m-%d %H:%M:%S')"

    if [[ "$BREAK_LOCK" == true ]]; then
        log_warn "--break-lock: знімаю наявний remote-lock ${lock}"
        "${SSH_CMD[@]}" "$SSH_TARGET" "rm -rf $(shq "$lock")" ||
            die "Не вдалося зняти remote-lock: $lock"
    fi

    # shellcheck disable=SC2016  # змінні розкриваються на remote
    script='lock=$1; token=$2; owner=$3
if mkdir "$lock" 2>/dev/null; then
    printf "%s\n%s\n" "$token" "$owner" > "$lock/owner"
    exit 0
fi
echo "Власник lock:"
sed -n "2p" "$lock/owner" 2>/dev/null || echo "(невідомий)"
exit 3'

    out=$("${SSH_CMD[@]}" "$SSH_TARGET" \
        "sh -c $(shq "$script") sh $(shq "$lock") $(shq "$REMOTE_LOCK_TOKEN") $(shq "$owner")") || rc=$?

    case "$rc" in
        0)
            REMOTE_LOCK_HELD=true
            log_info "Remote-lock взято: ${SSH_TARGET}:${lock}"
            ;;
        3)
            printf '%s\n' "$out" >&2
            die "Сервер зайнятий: інший запуск backup-sync (можливо, з іншого ПК) тримає lock ${lock}. Якщо він завершився аварійно — перезапустіть з --break-lock."
            ;;
        *)
            die "Не вдалося взяти remote-lock (ssh rc=$rc): ${lock}"
            ;;
    esac
}

# Знімає lock лише якщо він досі НАШ (токен збігається): якщо хтось зробив --break-lock
# і взяв його сам, чужий lock не чіпаємо.
release_remote_lock() {
    local lock script

    [[ "$REMOTE_LOCK_HELD" == true ]] || return 0
    REMOTE_LOCK_HELD=false

    lock="${REMOTE_DIR}/${REMOTE_LOCK_NAME}"

    # shellcheck disable=SC2016  # змінні розкриваються на remote
    script='lock=$1; token=$2
if [ "$(sed -n "1p" "$lock/owner" 2>/dev/null)" = "$token" ]; then
    rm -rf "$lock"
fi
true'

    "${SSH_CMD[@]}" "$SSH_TARGET" \
        "sh -c $(shq "$script") sh $(shq "$lock") $(shq "$REMOTE_LOCK_TOKEN")" >/dev/null 2>&1 ||
        log_warn "Не вдалося зняти remote-lock. Зніміть вручну: ssh ${SSH_TARGET} rm -rf '${lock}' (або --break-lock)."
}
