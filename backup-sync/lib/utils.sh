#!/usr/bin/env bash

check_local_dependencies() {
    local cmd
    for cmd in bash rsync ssh tee mkdir mktemp find stat date df flock awk sed grep head; do
        command -v "$cmd" >/dev/null 2>&1 || {
            printf '[ERROR] Не знайдено обов’язкову команду: %s\n' "$cmd" >&2
            exit 1
        }
    done
}

# Безпечне взяття рядка в одинарні лапки для віддаленої POSIX-оболонки.
shq() {
    local s="${1//\'/\'\\\'\'}"
    printf "'%s'" "$s"
}

is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }

load_config() {
    [[ -f "$CONFIG_FILE" ]] || {
        printf '[ERROR] Config не знайдено: %s\n' "$CONFIG_FILE" >&2
        exit 1
    }

    # shellcheck disable=SC1090
    source "$CONFIG_FILE"

    : "${LOCAL_DIR:?LOCAL_DIR не задано}"
    : "${REMOTE_DIR:?REMOTE_DIR не задано}"
    : "${LOG_DIR:?LOG_DIR не задано}"
    : "${STATE_DIR:?STATE_DIR не задано}"
    : "${LOCAL_RECOVERY_DIR:=$STATE_DIR/recovery-down}"

    if ((${#BACKUP_DIRS[@]} == 0)); then
        printf '[ERROR] BACKUP_DIRS порожній\n' >&2
        exit 1
    fi

    # CLI має пріоритет над конфігом.
    if [[ -n "$CLI_MAX_DELETE" ]]; then
        MAX_DELETE="$CLI_MAX_DELETE"
    fi
    if [[ "$CLI_ALLOW_EMPTY" == true ]]; then
        ALLOW_EMPTY_SOURCE=true
    fi
    if [[ -n "$CLI_AUTO_CLEANUP" ]]; then
        AUTO_CLEANUP_RECOVERY="$CLI_AUTO_CLEANUP"
    fi
    # --recovery / --no-recovery перекривають ВСІ перемикачі конфігу (загальний і за напрямком).
    if [[ -n "$CLI_RECOVERY" ]]; then
        RECOVERY_ENABLED="$CLI_RECOVERY"
        RECOVERY_UP_ENABLED="$CLI_RECOVERY"
        RECOVERY_DOWN_ENABLED="$CLI_RECOVERY"
    fi

    validate_config
}

# Усі значення, від яких залежить видалення файлів, перевіряються ДО будь-яких дій.
validate_config() {
    local v d i first

    for v in KEEP_LOG_DAYS KEEP_RECOVERY_DAYS KEEP_LOCAL_RECOVERY_DAYS MIN_FREE_MIB MAX_DELETE \
             SSH_CONNECT_TIMEOUT SSH_SERVER_ALIVE_INTERVAL SSH_SERVER_ALIVE_COUNT_MAX; do
        is_uint "${!v}" ||
            die "$v має бути невід’ємним цілим числом (зараз: '${!v}')."
    done

    for v in RECOVERY_ENABLED RECOVERY_UP_ENABLED RECOVERY_DOWN_ENABLED RSYNC_PARTIAL RSYNC_COMPRESS RSYNC_CHECKSUM_VERIFY \
             DELETE_ON_DOWN ALLOW_EMPTY_SOURCE PREVIEW_BEFORE_CONFIRM AUTO_CLEANUP_RECOVERY \
             RSYNC_PRESERVE_HARDLINKS RSYNC_PRESERVE_ACLS RSYNC_PRESERVE_XATTRS; do
        [[ "${!v}" == true || "${!v}" == false ]] ||
            die "$v має бути true або false (зараз: '${!v}')."
    done

    case "$SPACE_CHECK_METHOD" in
        dry-run|threshold) ;;
        *) die "SPACE_CHECK_METHOD: допустимо dry-run або threshold (зараз: '$SPACE_CHECK_METHOD')." ;;
    esac

    if [[ -n "$EXCLUDE_DIR" && ! -d "$EXCLUDE_DIR" ]]; then
        die "EXCLUDE_DIR не існує або не є каталогом: $EXCLUDE_DIR"
    fi

    case "$SSH_STRICT_HOST_KEY_CHECKING" in
        ""|yes|no|ask|accept-new) ;;
        *) die "SSH_STRICT_HOST_KEY_CHECKING: допустимо порожнє, yes, no, ask або accept-new (зараз: '$SSH_STRICT_HOST_KEY_CHECKING')." ;;
    esac

    # Корені: абсолютні, не "/", без "..".
    [[ "$LOCAL_DIR" == /* ]]  || die "LOCAL_DIR має бути абсолютним шляхом: '$LOCAL_DIR'"
    [[ "$REMOTE_DIR" == /* ]] || die "REMOTE_DIR має бути абсолютним шляхом: '$REMOTE_DIR'"
    LOCAL_DIR="${LOCAL_DIR%/}"
    REMOTE_DIR="${REMOTE_DIR%/}"
    [[ -n "$LOCAL_DIR" ]]  || die "LOCAL_DIR не може бути '/'."
    [[ -n "$REMOTE_DIR" ]] || die "REMOTE_DIR не може бути '/'."
    [[ "/$LOCAL_DIR/"  != *"/../"* ]] || die "LOCAL_DIR не може містити '..': $LOCAL_DIR"
    [[ "/$REMOTE_DIR/" != *"/../"* ]] || die "REMOTE_DIR не може містити '..': $REMOTE_DIR"

    # RECOVERY_ROOT — одне безпечне ім’я каталогу (без '/', '..', порожнього значення).
    if [[ ! "$RECOVERY_ROOT" =~ ^[A-Za-z0-9._-]+$ || "$RECOVERY_ROOT" == . || "$RECOVERY_ROOT" == .. ]]; then
        die "RECOVERY_ROOT має бути одним іменем каталогу ([A-Za-z0-9._-], не '.'/'..', не порожнім): '$RECOVERY_ROOT'"
    fi

    # BACKUP_DIRS: відносні шляхи без '..', не збігаються з RECOVERY_ROOT.
    for i in "${!BACKUP_DIRS[@]}"; do
        d="${BACKUP_DIRS[$i]%/}"
        BACKUP_DIRS[i]="$d"
        [[ -n "$d" ]]                 || die "BACKUP_DIRS містить порожній елемент."
        [[ "$d" != /* ]]              || die "BACKUP_DIRS: шлях має бути відносним: '$d'"
        [[ "/$d/" != *"/../"* && "/$d/" != *"/./"* ]] ||
            die "BACKUP_DIRS: '.' та '..' заборонені: '$d'"
        first="${d%%/*}"
        [[ "$first" != "$RECOVERY_ROOT" ]] ||
            die "BACKUP_DIRS: '$d' збігається з RECOVERY_ROOT ('$RECOVERY_ROOT')."
        [[ "$first" != "$REMOTE_LOCK_NAME" ]] ||
            die "BACKUP_DIRS: '$d' збігається з іменем lock-каталогу ('$REMOTE_LOCK_NAME')."
    done

    # Локальний recovery не може лежати всередині синхронізованих каталогів (і навпаки).
    [[ "$LOCAL_RECOVERY_DIR" == /* ]] ||
        die "LOCAL_RECOVERY_DIR має бути абсолютним шляхом: '$LOCAL_RECOVERY_DIR'"
    LOCAL_RECOVERY_DIR="${LOCAL_RECOVERY_DIR%/}"
    [[ -n "$LOCAL_RECOVERY_DIR" ]] || die "LOCAL_RECOVERY_DIR не може бути '/'."
    for d in "${BACKUP_DIRS[@]}"; do
        case "$LOCAL_RECOVERY_DIR/" in
            "$LOCAL_DIR/$d/"*)
                die "LOCAL_RECOVERY_DIR ($LOCAL_RECOVERY_DIR) знаходиться всередині синхронізованого каталогу $d." ;;
        esac
        case "$LOCAL_DIR/$d/" in
            "$LOCAL_RECOVERY_DIR/"*)
                die "Синхронізований каталог $d знаходиться всередині LOCAL_RECOVERY_DIR." ;;
        esac
    done
}

init_runtime() {
    ( umask 077; mkdir -p -- "$STATE_DIR" "$LOG_DIR" )

    LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/backup-sync-${UID}.lock"
}

acquire_lock() {
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        die "Інший процес backup-sync уже запущений."
    fi
}

human_duration() {
    local seconds="$1"
    printf '%02d:%02d:%02d' \
        $((seconds / 3600)) \
        $(((seconds % 3600) / 60)) \
        $((seconds % 60))
}

# Читає вивід `df` зі stdin і друкує доступні KiB останнього рядка.
# Шукаємо поле перед "NN%" — це стійко до переносу довгих назв ФС на новий рядок.
parse_df_avail_kib() {
    awk 'NR > 1 { line = $0 }
         END {
             n = split(line, f, " ")
             for (i = 2; i <= n; i++) if (f[i] ~ /%$/) { print f[i - 1]; exit }
         }'
}

# Повертають MiB; код 1 — не вдалося визначити (ніколи не завершують скрипт мовчки).
# Якщо шляху ще немає (напр., REMOTE_DIR буде створено після підтвердження), беруться дані
# найближчого ІСНУЮЧОГО батьківського каталогу — це та сама файлова система.
dir_free_mib_local() {
    local p="$1" out kib

    while [[ ! -d "$p" && "$p" != / ]]; do
        p=$(dirname -- "$p")
    done

    out=$(df -Pk "$p" 2>/dev/null) || return 1
    kib=$(parse_df_avail_kib <<<"$out")
    is_uint "$kib" || return 1
    printf '%s\n' $((kib / 1024))
}

dir_free_mib_remote() {
    local script out kib

    # shellcheck disable=SC2016  # змінні розкриваються на remote
    script='p=$1
while [ ! -d "$p" ] && [ "$p" != / ]; do p=$(dirname "$p"); done
df -Pk "$p" 2>/dev/null || df -k "$p" 2>/dev/null'

    out=$("${SSH_CMD[@]}" "$SSH_TARGET" "sh -c $(shq "$script") sh $(shq "$1")") || return 1
    kib=$(parse_df_avail_kib <<<"$out")
    is_uint "$kib" || return 1
    printf '%s\n' $((kib / 1024))
}

# Короткі підписи для повідомлень (замість «A && B || C», яке не є if-then-else: SC2015).
yes_no()          { if [[ "$1" == true ]]; then printf 'ТАК'; else printf 'НІ'; fi; }
direction_label() { if [[ "$1" == up ]]; then printf 'PC -> SERVER'; else printf 'SERVER -> PC'; fi; }

# 1536 -> "1.5 KiB" (для повідомлень).
human_bytes() {
    awk -v b="$1" 'BEGIN {
        split("B KiB MiB GiB TiB", u, " "); i = 1
        while (b >= 1024 && i < 5) { b /= 1024; i++ }
        if (i == 1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
    }'
}

# Перевірка вільного місця на стороні ПРИЗНАЧЕННЯ (up -> сервер, down -> локально).
# Потрібно: обсяг, який rsync передасть (з dry-run), + запас MIN_FREE_MIB.
# verify/cleanup/--dry-run нічого не записують, тож не перевіряються.
check_space_for_run() {
    local side free dir state bytes need_bytes=0 need_mib=0
    local unknown=()

    [[ "$COMMAND" == up || "$COMMAND" == down ]] || return 0
    [[ "$DRY_RUN" == false ]] || return 0

    if [[ "$CHECK_DISK_SPACE" != true ]]; then
        log_warn "Перевірку вільного місця вимкнено (--no-space-check)."
        return 0
    fi

    log_title "ВІЛЬНЕ МІСЦЕ"

    if [[ "$DIRECTION" == up ]]; then
        side="на сервері (${REMOTE_DIR})"
        free=$(dir_free_mib_remote "$REMOTE_DIR") ||
            die "Не вдалося визначити вільне місце на remote для $REMOTE_DIR (ssh/df). Можна обійти: --no-space-check."
    else
        side="локально (${LOCAL_DIR})"
        free=$(dir_free_mib_local "$LOCAL_DIR") ||
            die "Не вдалося визначити вільне місце локально для $LOCAL_DIR (df). Можна обійти: --no-space-check."
    fi

    if [[ "$SPACE_CHECK_METHOD" == dry-run && "$SCAN_DONE" == true ]]; then
        for dir in "${BACKUP_DIRS[@]}"; do
            state="${SCAN_STATE[$dir]}"
            case "$state" in
                ok)
                    bytes="${SCAN_BYTES[$dir]}"
                    need_bytes=$((need_bytes + bytes))
                    ;;
                skipped) ;;
                *) unknown+=("$dir") ;;
            esac
        done
        need_mib=$(((need_bytes + 1048575) / 1048576))

        log_info "Вільно ${side}: ${free} MiB"
        log_info "Буде передано (dry-run): ≈ $(human_bytes "$need_bytes") + запас ${MIN_FREE_MIB} MiB"

        if ((${#unknown[@]} > 0)); then
            log_warn "Обсяг не вдалося оцінити для: ${unknown[*]} — для них враховано лише запас."
        fi
    else
        log_info "Вільно ${side}: ${free} MiB (метод threshold: перевіряється лише запас ${MIN_FREE_MIB} MiB)"
    fi

    if ((free < need_mib + MIN_FREE_MIB)); then
        die "Недостатньо місця ${side}: вільно ${free} MiB, потрібно ≈ ${need_mib} MiB + запас ${MIN_FREE_MIB} MiB. Звільніть місце, зменште MIN_FREE_MIB або --no-space-check."
    fi

    log_ok "Місця достатньо."
}
