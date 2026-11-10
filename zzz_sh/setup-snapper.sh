#!/usr/bin/env bash
# ============================================================
# Snapper — встановлення та налаштування в Arch Linux (v2)
# root/home, timeline, cleanup, snap-pac
# Використання:
#   sudo ./setup-snapper.sh [--dry-run] [--yes] [--help]
# ============================================================
set -Eeuo pipefail

# ==================== НАЛАШТУВАННЯ ==========================
# Змінюй значення лише в цьому блоці.
INSTALL_PACKAGES=true
INSTALL_SNAP_PAC=true        # pre/post snapshots під час транзакцій pacman
INSTALL_GRUB_BTRFS=false     # лише для GRUB; НЕ чіпає GRUB, якщо false
ENABLE_GRUB_BTRFSD=false     # вмикати grub-btrfsd лише за бажанням
CREATE_MISSING_CONFIGS=false # безпечніше: не створювати нові конфігурації автоматично

CONFIGS=(root home) # Можна прибрати home або root

# Для яких конфігурацій snap-pac має робити pre/post snapshots.
# За замовчуванням — для всіх із CONFIGS.
SNAP_PAC_CONFIGS=("${CONFIGS[@]}")

# Шляхи Btrfs subvolume (потрібні лише для create-config, коли CREATE_MISSING_CONFIGS=true)
declare -A CONFIG_PATHS=([root]="/" [home]="/home")

TIMELINE_ENABLED=true                       # керує і таймером, і TIMELINE_CREATE у конфігу snapper
TIMELINE_CALENDAR='*-*-* 00,06,12,18:00:00' # кожні 6 годин
TIMELINE_PERSISTENT=true

CLEANUP_ENABLED=true              # керує і таймером, і TIMELINE_CLEANUP у конфігу snapper
CLEANUP_CALENDAR='*-*-* 03:30:00' # щодня о 03:30, не збігається з timeline
CLEANUP_PERSISTENT=true           # наздогнати один пропущений запуск
TIMER_ACCURACY='1min'

# Ліміти застосовуються до всіх конфігурацій із масиву CONFIGS.
# Це КІЛЬКІСТЬ знімків відповідної категорії, а не тривалість.
# При розкладі "кожні 6 годин" HOURLY=4 означає приблизно 4 останні знімки (~1 доба).
TIMELINE_MIN_AGE=3600
TIMELINE_LIMIT_HOURLY=4
TIMELINE_LIMIT_DAILY=7
TIMELINE_LIMIT_WEEKLY=4
TIMELINE_LIMIT_MONTHLY=3
TIMELINE_LIMIT_YEARLY=0

# Для snapshots, створених за алгоритмом number (зокрема snap-pac).
NUMBER_CLEANUP='yes'
NUMBER_MIN_AGE=3600
NUMBER_LIMIT='10'
NUMBER_LIMIT_IMPORTANT='5'

# Очищення порожніх pre/post snapshots
EMPTY_PRE_POST_CLEANUP='yes'
EMPTY_PRE_POST_MIN_AGE=3600

# Куди складати резервні копії змінених файлів і списки знімків
BACKUP_DIR='/var/backups/setup-snapper'
LOCK_FILE='/run/lock/setup-snapper.lock'
SNAP_PAC_INI='/etc/snap-pac.ini'

# ==================== СЛУЖБОВІ ФУНКЦІЇ ====================
DRY_RUN=false
ASSUME_YES=false
BACKUP_STAMP=$(date +%Y%m%d-%H%M%S)

if [[ -t 1 ]]; then
    GREEN=$'\e[32m'
    YELLOW=$'\e[33m'
    RED=$'\e[31m'
    BLUE=$'\e[36m'
    RESET=$'\e[0m'
else
    GREEN='' YELLOW='' RED='' BLUE='' RESET=''
fi
log_info() { printf '%s[INFO]%s %s\n' "$BLUE" "$RESET" "$*"; }
log_ok() { printf '%s[OK]%s %s\n' "$GREEN" "$RESET" "$*"; }
log_warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
log_dry() { printf '%s[DRY-RUN]%s %s\n' "$YELLOW" "$RESET" "$*"; }
die() {
    printf '%s[ERROR]%s %s\n' "$RED" "$RESET" "$*" >&2
    exit 1
}

trap 'printf "%s[ERROR]%s Скрипт перервано: рядок %s, команда: %s\n" "$RED" "$RESET" "$LINENO" "$BASH_COMMAND" >&2' ERR

usage() {
    cat <<EOF_USAGE
Використання: sudo $0 [параметри]

  --dry-run   показати, що буде зроблено, нічого не змінюючи
  -y, --yes   не питати підтвердження (і передати --noconfirm до pacman)
  -h, --help  ця довідка
EOF_USAGE
}

# Виконує команду або лише друкує її в режимі --dry-run.
run() {
    if [[ $DRY_RUN == true ]]; then
        log_dry "$*"
    else
        "$@"
    fi
}

confirm() {
    [[ $ASSUME_YES == true ]] && return 0
    [[ $DRY_RUN == true ]] && return 0
    [[ -t 0 ]] || die 'Потрібне підтвердження, але термінал неінтерактивний. Додай --yes.'
    local answer
    read -r -p "$1 [y/N] " answer
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]] || die 'Скасовано користувачем.'
}

parse_args() {
    local arg
    for arg in "$@"; do
        case $arg in
            --dry-run) DRY_RUN=true ;;
            -y | --yes) ASSUME_YES=true ;;
            -h | --help)
                usage
                exit 0
                ;;
            *)
                usage >&2
                die "Невідомий параметр: $arg"
                ;;
        esac
    done
}

require_root() {
    [[ $EUID -eq 0 ]] || die "Запусти через sudo: sudo $0"
}

require_arch() {
    command -v pacman >/dev/null 2>&1 || die 'Цей скрипт призначено для Arch Linux (pacman).'
}

acquire_lock() {
    command -v flock >/dev/null 2>&1 || die 'flock відсутній (util-linux)'
    exec 9>"$LOCK_FILE"
    flock -n 9 || die 'Скрипт уже запущено в іншому процесі'
}

require_systemd() {
    if [[ -d /run/systemd/system ]]; then
        return 0
    fi
    if [[ $DRY_RUN == true ]]; then
        log_warn 'systemd не запущено (chroot?). Реальний запуск буде відхилено.'
    else
        die 'systemd не запущено (arch-chroot?). Запусти скрипт після першого завантаження встановленої системи.'
    fi
}

check_bool() {
    [[ $2 == true || $2 == false ]] || die "$1 повинен мати значення true або false (зараз: '$2')"
}

check_yesno() {
    [[ $2 == yes || $2 == no ]] || die "$1 повинен мати значення yes або no (зараз: '$2')"
}

validate() {
    local name
    for name in INSTALL_PACKAGES INSTALL_SNAP_PAC INSTALL_GRUB_BTRFS ENABLE_GRUB_BTRFSD \
        CREATE_MISSING_CONFIGS TIMELINE_ENABLED TIMELINE_PERSISTENT CLEANUP_ENABLED CLEANUP_PERSISTENT; do
        check_bool "$name" "${!name}"
    done
    for name in NUMBER_CLEANUP EMPTY_PRE_POST_CLEANUP; do
        check_yesno "$name" "${!name}"
    done

    [[ ${#CONFIGS[@]} -gt 0 ]] || die 'CONFIGS не може бути порожнім'
    for name in "${CONFIGS[@]}"; do
        [[ $name =~ ^[a-zA-Z0-9_-]+$ ]] || die "Неприпустима назва конфігурації: $name"
    done
    for name in "${SNAP_PAC_CONFIGS[@]}"; do
        [[ $name =~ ^[a-zA-Z0-9_-]+$ ]] || die "Неприпустима назва в SNAP_PAC_CONFIGS: $name"
    done

    for name in TIMELINE_MIN_AGE TIMELINE_LIMIT_HOURLY TIMELINE_LIMIT_DAILY \
        TIMELINE_LIMIT_WEEKLY TIMELINE_LIMIT_MONTHLY TIMELINE_LIMIT_YEARLY \
        NUMBER_MIN_AGE EMPTY_PRE_POST_MIN_AGE; do
        [[ ${!name} =~ ^[0-9]+$ ]] || die "$name має бути невід'ємним цілим числом"
    done
    [[ $NUMBER_LIMIT =~ ^[0-9]+(-[0-9]+)?$ ]] || die 'Невірний NUMBER_LIMIT'
    [[ $NUMBER_LIMIT_IMPORTANT =~ ^[0-9]+(-[0-9]+)?$ ]] || die 'Невірний NUMBER_LIMIT_IMPORTANT'

    command -v systemd-analyze >/dev/null || die 'systemd-analyze відсутній'
    systemd-analyze timespan "$TIMER_ACCURACY" >/dev/null 2>&1 || die "Невірний TIMER_ACCURACY: $TIMER_ACCURACY"
    if [[ $TIMELINE_ENABLED == true ]]; then
        systemd-analyze calendar "$TIMELINE_CALENDAR" >/dev/null 2>&1 || die 'Невірний TIMELINE_CALENDAR'
    fi
    if [[ $CLEANUP_ENABLED == true ]]; then
        systemd-analyze calendar "$CLEANUP_CALENDAR" >/dev/null 2>&1 || die 'Невірний CLEANUP_CALENDAR'
    fi

    if [[ $CLEANUP_ENABLED == false ]]; then
        log_warn 'CLEANUP_ENABLED=false: знімки НЕ будуть автоматично очищатися, диск може заповнитися.'
    fi
    if [[ $INSTALL_GRUB_BTRFS == true ]] && ! command -v grub-mkconfig >/dev/null 2>&1; then
        log_warn 'INSTALL_GRUB_BTRFS=true, але GRUB не знайдено (systemd-boot/інший завантажувач?).'
    fi
}

# ==================== РЕЗЕРВНІ КОПІЇ ======================
backup_file() {
    local file=$1 name
    if [[ -f $file && ! -L $file ]]; then
        mkdir -p -- "$BACKUP_DIR"
        name=${file//\//_}
        cp -a -- "$file" "${BACKUP_DIR}/${name}.bak-${BACKUP_STAMP}"
    fi
}

# Читає вміст зі stdin і записує у файл (з резервною копією); у dry-run лише повідомляє.
write_file() {
    local file=$1
    if [[ $DRY_RUN == true ]]; then
        log_dry "записав би $file:"
        sed 's/^/    | /'
        return 0
    fi
    backup_file "$file"
    cat >"$file"
    log_ok "Збережено $file"
}

# ==================== ПАКЕТИ ===============================
install_packages() {
    local -a packages=(snapper btrfs-progs)
    local -a pacman_args=(-S --needed)
    [[ $INSTALL_SNAP_PAC == true ]] && packages+=(snap-pac)
    [[ $INSTALL_GRUB_BTRFS == true ]] && packages+=(grub-btrfs inotify-tools)
    [[ $ASSUME_YES == true ]] && pacman_args+=(--noconfirm)

    if [[ $INSTALL_PACKAGES == true ]]; then
        log_info "Встановлення пакетів: ${packages[*]}"
        run pacman "${pacman_args[@]}" -- "${packages[@]}"
    else
        log_info 'Встановлення пакетів вимкнене'
    fi

    if ! command -v snapper >/dev/null 2>&1; then
        if [[ $DRY_RUN == true ]]; then
            log_warn 'snapper не встановлено; кроки, що його потребують, буде лише описано.'
        else
            die 'Команда snapper відсутня'
        fi
    fi
}

# ==================== ПЕРЕВІРКА ПЕРЕД ЗМІНАМИ ================
count_snapshots() {
    # Рахуємо лише знімки з номером >= 1 (0 — це поточна система).
    snapper -c "$1" --csvout list --columns number 2>/dev/null |
        grep -Ec '^"?[1-9][0-9]*"?$' || true
}

preflight() {
    command -v snapper >/dev/null 2>&1 || return 0

    local config count threshold number_max timeline_total flagged=false
    number_max=${NUMBER_LIMIT##*-}
    timeline_total=$((TIMELINE_LIMIT_HOURLY + TIMELINE_LIMIT_DAILY + TIMELINE_LIMIT_WEEKLY + \
        TIMELINE_LIMIT_MONTHLY + TIMELINE_LIMIT_YEARLY))
    threshold=$((number_max > timeline_total ? number_max : timeline_total))

    for config in "${CONFIGS[@]}"; do
        [[ -f /etc/snapper/configs/$config ]] || continue
        count=$(count_snapshots "$config")
        log_info "Конфігурація '$config': знімків зараз — $count"

        if [[ $DRY_RUN == false ]]; then
            mkdir -p -- "$BACKUP_DIR"
            snapper -c "$config" list >"${BACKUP_DIR}/snapshots-${config}-${BACKUP_STAMP}.txt" 2>&1 || true
        fi

        if ((count > threshold)); then
            log_warn "'$config': $count знімків > орієнтовного ліміту $threshold. Cleanup-таймер може швидко видалити надлишок."
            flagged=true
        fi
    done

    if [[ $flagged == true ]]; then
        log_warn "Списки поточних знімків збережено в $BACKUP_DIR"
        confirm 'Нові ліміти можуть призвести до видалення старих знімків. Продовжити?'
    fi
}

# ==================== SNAPPER ==============================
configure_snapper() {
    local config path timeline_create timeline_cleanup
    timeline_create=$([[ $TIMELINE_ENABLED == true ]] && echo yes || echo no)
    timeline_cleanup=$([[ $CLEANUP_ENABLED == true ]] && echo yes || echo no)

    for config in "${CONFIGS[@]}"; do
        if [[ ! -f /etc/snapper/configs/$config ]]; then
            if [[ $CREATE_MISSING_CONFIGS != true ]]; then
                log_warn "Конфігурація '$config' відсутня — пропущено (CREATE_MISSING_CONFIGS=false)"
                continue
            fi

            path=${CONFIG_PATHS[$config]:-}
            [[ -n $path ]] || die "Немає CONFIG_PATHS[$config] — потрібен для create-config"
            [[ -d $path ]] || die "Шлях для '$config' відсутній: $path"
            [[ $(findmnt -n -o FSTYPE -T "$path") == btrfs ]] || die "$path не перебуває на Btrfs (для /home потрібен окремий subvolume)"
            if [[ -e $path/.snapshots ]]; then
                die "Для '$config' вже існує $path/.snapshots, але немає конфігурації.
       Типова причина на Arch: окремий subvolume @snapshots змонтовано в $path/.snapshots,
       а snapper create-config хоче створити власний. Нічого не видаляю.
       Рішення вручну: тимчасово розмонтуй .snapshots, виконай
       'snapper -c $config create-config $path', видали створений вкладений subvolume
       'btrfs subvolume delete $path/.snapshots', створи каталог і змонтуй @snapshots назад."
            fi
            log_info "Створення конфігурації '$config' для $path"
            run snapper -c "$config" create-config "$path"
        fi

        if [[ $DRY_RUN == false ]]; then
            backup_file "/etc/snapper/configs/$config"
        fi
        log_info "Налаштування '$config'"
        run snapper -c "$config" set-config \
            "TIMELINE_CREATE=$timeline_create" \
            "TIMELINE_CLEANUP=$timeline_cleanup" \
            "TIMELINE_MIN_AGE=$TIMELINE_MIN_AGE" \
            "TIMELINE_LIMIT_HOURLY=$TIMELINE_LIMIT_HOURLY" \
            "TIMELINE_LIMIT_DAILY=$TIMELINE_LIMIT_DAILY" \
            "TIMELINE_LIMIT_WEEKLY=$TIMELINE_LIMIT_WEEKLY" \
            "TIMELINE_LIMIT_MONTHLY=$TIMELINE_LIMIT_MONTHLY" \
            "TIMELINE_LIMIT_YEARLY=$TIMELINE_LIMIT_YEARLY" \
            "NUMBER_CLEANUP=$NUMBER_CLEANUP" \
            "NUMBER_MIN_AGE=$NUMBER_MIN_AGE" \
            "NUMBER_LIMIT=$NUMBER_LIMIT" \
            "NUMBER_LIMIT_IMPORTANT=$NUMBER_LIMIT_IMPORTANT" \
            "EMPTY_PRE_POST_CLEANUP=$EMPTY_PRE_POST_CLEANUP" \
            "EMPTY_PRE_POST_MIN_AGE=$EMPTY_PRE_POST_MIN_AGE"
        log_ok "Конфігурацію '$config' оновлено"
    done
}

# ==================== SNAP-PAC ==============================
# snap-pac за замовчуванням знімає лише root. Для інших конфігів (напр. home)
# потрібна секція в $SNAP_PAC_INI. Існуючі секції НЕ змінюються.
# Формат перевір за `man snap-pac` для своєї версії.
configure_snap_pac() {
    [[ $INSTALL_SNAP_PAC == true ]] || return 0
    if [[ $DRY_RUN == false ]] && ! pacman -Q snap-pac >/dev/null 2>&1; then
        log_warn 'snap-pac не встановлено — пропускаю налаштування snap-pac.ini'
        return 0
    fi

    local config
    for config in "${SNAP_PAC_CONFIGS[@]}"; do
        # Пропускаємо конфіги, яких немає (інакше snap-pac лише шумітиме помилками).
        if [[ ! -f /etc/snapper/configs/$config ]]; then
            log_warn "snap-pac: конфігурація snapper '$config' відсутня — секцію не додаю"
            continue
        fi
        if [[ -f $SNAP_PAC_INI ]] && grep -qE "^\[${config}\][[:space:]]*$" "$SNAP_PAC_INI"; then
            log_info "snap-pac: секція [$config] уже є в $SNAP_PAC_INI — не чіпаю (перевір snapshot = True)"
            continue
        fi
        log_info "snap-pac: додаю секцію [$config] у $SNAP_PAC_INI"
        if [[ $DRY_RUN == true ]]; then
            log_dry "дописав би у $SNAP_PAC_INI: [$config] / snapshot = True"
        else
            backup_file "$SNAP_PAC_INI"
            printf '\n[%s]\nsnapshot = True\n' "$config" >>"$SNAP_PAC_INI"
            log_ok "snap-pac: [$config] додано"
        fi
    done
}

# ==================== SYSTEMD ===============================
# drop-in без редагування пакетного unit-файлу.
write_timer_override() {
    local unit=$1 calendar=$2 persistent=$3
    local dir="/etc/systemd/system/${unit}.d"
    local file="${dir}/90-local-schedule.conf"
    run mkdir -p -- "$dir"
    write_file "$file" <<EOF_TIMER
# Розклад, керований setup-snapper.sh
[Timer]
# Скидаємо старі календарні та відносні тригери.
OnCalendar=
OnActiveSec=
OnBootSec=
OnStartupSec=
OnUnitActiveSec=
OnUnitInactiveSec=

OnCalendar=$calendar
Persistent=$persistent
AccuracySec=$TIMER_ACCURACY
EOF_TIMER
}

configure_timers() {
    # Override пишемо й для вимкнених таймерів, щоб повторний запуск був передбачуваним.
    write_timer_override snapper-timeline.timer "$TIMELINE_CALENDAR" "$TIMELINE_PERSISTENT"
    write_timer_override snapper-cleanup.timer "$CLEANUP_CALENDAR" "$CLEANUP_PERSISTENT"
    run systemctl daemon-reload

    if [[ $TIMELINE_ENABLED == true ]]; then
        run systemctl enable snapper-timeline.timer
        run systemctl restart snapper-timeline.timer
        log_ok 'snapper-timeline.timer увімкнено'
    else
        run systemctl disable --now snapper-timeline.timer
        log_warn 'snapper-timeline.timer вимкнено'
    fi

    if [[ $CLEANUP_ENABLED == true ]]; then
        run systemctl enable snapper-cleanup.timer
        run systemctl restart snapper-cleanup.timer
        log_ok 'snapper-cleanup.timer увімкнено'
    else
        run systemctl disable --now snapper-cleanup.timer
        log_warn 'snapper-cleanup.timer вимкнено'
    fi

    if [[ $ENABLE_GRUB_BTRFSD == true ]]; then
        if [[ $DRY_RUN == false ]]; then
            systemctl cat grub-btrfsd.service >/dev/null 2>&1 || die 'grub-btrfsd.service не встановлено'
        fi
        run systemctl enable --now grub-btrfsd.service
    fi
}

show_status() {
    printf '\n'
    if [[ $DRY_RUN == false ]]; then
        log_info 'Розклад Snapper:'
        systemctl list-timers --all snapper-timeline.timer snapper-cleanup.timer --no-pager
        printf '\n'
        log_info 'Налаштовані конфігурації:'
        snapper list-configs
        printf '\n'
    fi
    if [[ $TIMELINE_ENABLED == true ]]; then
        log_info 'Найближчі запуски timeline:'
        systemd-analyze calendar "$TIMELINE_CALENDAR" --iterations=3
    fi
    if [[ $CLEANUP_ENABLED == true ]]; then
        log_info 'Найближчі запуски cleanup:'
        systemd-analyze calendar "$CLEANUP_CALENDAR" --iterations=3
    fi
}

main() {
    parse_args "$@"
    require_root
    require_arch
    acquire_lock
    validate
    require_systemd

    [[ $DRY_RUN == true ]] && log_warn 'Режим --dry-run: нічого не змінюється.'

    install_packages
    preflight
    configure_snapper
    configure_snap_pac
    configure_timers
    show_status

    if [[ $DRY_RUN == true ]]; then
        log_ok 'Dry-run завершено. Жодних змін не внесено.'
    else
        log_ok 'Налаштування завершено. Скрипт знімки не видаляв, але нові ліміти застосує snapper-cleanup.timer.'
        log_info "Резервні копії та списки знімків: $BACKUP_DIR"
    fi
}

main "$@"
