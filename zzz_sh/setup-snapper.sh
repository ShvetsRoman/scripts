#!/usr/bin/env bash
# ============================================================
# Snapper — встановлення та налаштування в Arch Linux
# root/home, timeline, cleanup, snap-pac
# ============================================================
set -Eeuo pipefail

# ==================== НАЛАШТУВАННЯ ==========================
# Змінюй значення лише в цьому блоці.
INSTALL_PACKAGES=true
INSTALL_SNAP_PAC=true        # pre/post snapshots під час транзакцій pacman
INSTALL_GRUB_BTRFS=false     # НЕ встановлювати/не змінювати GRUB без потреби
ENABLE_GRUB_BTRFSD=false     # вмикати grub-btrfsd лише за бажанням
CREATE_MISSING_CONFIGS=false # безпечніше: не створювати нові конфігурації автоматично

CONFIGS=(root home) # Можна прибрати home або root

# Шлях відповідного Btrfs subvolume для create-config (лише коли CREATE_MISSING_CONFIGS=true)
declare -A CONFIG_PATHS=([root]="/" [home]="/home")

TIMELINE_ENABLED=true
TIMELINE_CALENDAR='*-*-* 00,06,12,18:00:00' # кожні 6 годин
TIMELINE_PERSISTENT=true

CLEANUP_ENABLED=true
CLEANUP_CALENDAR='daily' # щодня о 00:00 за локальним часом
CLEANUP_PERSISTENT=true  # один пропущений запуск після ввімкнення
TIMER_ACCURACY='1min'

# Ліміти застосовуються до всіх конфігурацій із масиву CONFIGS.
# TIMELINE_LIMIT_HOURLY = кількість погодинних точок, НЕ тривалість у годинах.
TIMELINE_CREATE='yes'
TIMELINE_CLEANUP='yes'
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

# ==================== СЛУЖБОВІ ФУНКЦІЇ ====================
if [[ -t 1 ]]; then
    GREEN=$'\e[32m'
    YELLOW=$'\e[33m'
    RED=$'\e[31m'
    BLUE=$'\e[36m'
    RESET=$'\e[0m'
else
    GREEN=''
    YELLOW=''
    RED=''
    BLUE=''
    RESET=''
fi
log_info() { printf '%s[INFO]%s %s\n' "$BLUE" "$RESET" "$*"; }
log_ok() { printf '%s[OK]%s %s\n' "$GREEN" "$RESET" "$*"; }
log_warn() { printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
log_error() {
    printf '%s[ERROR]%s %s\n' "$RED" "$RESET" "$*" >&2
    exit 1
}

require_root() {
    [[ $EUID -eq 0 ]] || log_error 'Запусти через sudo: sudo ./setup-snapper.sh'
    command -v pacman >/dev/null 2>&1 || log_error 'Цей скрипт призначено для Arch Linux (pacman).'
}

check_bool() {
    [[ $2 == true || $2 == false ]] || log_error "$1 повинен мати значення true або false"
}

validate() {
    local name
    for name in INSTALL_PACKAGES INSTALL_SNAP_PAC INSTALL_GRUB_BTRFS ENABLE_GRUB_BTRFSD \
        CREATE_MISSING_CONFIGS TIMELINE_ENABLED TIMELINE_PERSISTENT CLEANUP_ENABLED CLEANUP_PERSISTENT; do
        check_bool "$name" "${!name}"
    done
    [[ ${#CONFIGS[@]} -gt 0 ]] || log_error 'CONFIGS не може бути порожнім'
    for name in "${CONFIGS[@]}"; do
        [[ $name =~ ^[a-zA-Z0-9_-]+$ ]] || log_error "Неприпустима назва конфігурації: $name"
        [[ -n ${CONFIG_PATHS[$name]:-} ]] || log_error "Немає CONFIG_PATHS[$name]"
    done
    for name in TIMELINE_MIN_AGE TIMELINE_LIMIT_HOURLY TIMELINE_LIMIT_DAILY \
        TIMELINE_LIMIT_WEEKLY TIMELINE_LIMIT_MONTHLY TIMELINE_LIMIT_YEARLY \
        NUMBER_MIN_AGE EMPTY_PRE_POST_MIN_AGE; do
        [[ ${!name} =~ ^[0-9]+$ ]] || log_error "$name має бути невід'ємним цілим числом"
    done
    [[ $NUMBER_LIMIT =~ ^[0-9]+(-[0-9]+)?$ ]] || log_error 'Невірний NUMBER_LIMIT'
    [[ $NUMBER_LIMIT_IMPORTANT =~ ^[0-9]+(-[0-9]+)?$ ]] || log_error 'Невірний NUMBER_LIMIT_IMPORTANT'
    command -v systemd-analyze >/dev/null || log_error 'systemd-analyze відсутній'
    if [[ $TIMELINE_ENABLED == true ]]; then
        systemd-analyze calendar "$TIMELINE_CALENDAR" >/dev/null || log_error 'Невірний TIMELINE_CALENDAR'
    fi
    if [[ $CLEANUP_ENABLED == true ]]; then
        systemd-analyze calendar "$CLEANUP_CALENDAR" >/dev/null || log_error 'Невірний CLEANUP_CALENDAR'
    fi
}

install_packages() {
    local -a packages=(snapper btrfs-progs)
    [[ $INSTALL_SNAP_PAC == true ]] && packages+=(snap-pac)
    if [[ $INSTALL_GRUB_BTRFS == true ]]; then
        packages+=(grub-btrfs inotify-tools)
    fi
    if [[ $INSTALL_PACKAGES == true ]]; then
        log_info "Встановлення пакетів: ${packages[*]}"
        pacman -S --needed -- "${packages[@]}"
    else
        log_info 'Встановлення пакетів вимкнене'
    fi
    command -v snapper >/dev/null 2>&1 || log_error 'Команда snapper відсутня'
}

# Резервні копії лише тих файлів, які скрипт змінює безпосередньо.
backup_file() {
    local file=$1
    if [[ -f $file && ! -L $file ]]; then
        cp -a -- "$file" "${file}.bak-${BACKUP_STAMP}"
    fi
}

configure_snapper() {
    local config path
    for config in "${CONFIGS[@]}"; do
        path="${CONFIG_PATHS[$config]}"
        if [[ ! -f /etc/snapper/configs/$config ]]; then
            if [[ $CREATE_MISSING_CONFIGS != true ]]; then
                log_warn "Конфігурація $config відсутня — пропущено (CREATE_MISSING_CONFIGS=false)"
                continue
            fi
            [[ -d $path ]] || log_error "Шлях для $config відсутній: $path"
            [[ $(findmnt -n -o FSTYPE -T "$path") == btrfs ]] || log_error "$path не перебуває на Btrfs"
            if [[ -e $path/.snapshots ]]; then
                log_error "Для $config вже існує $path/.snapshots, але немає конфігурації. Перевір монтування вручну; нічого не видаляю."
            fi
            log_info "Створення конфігурації $config для $path"
            snapper -c "$config" create-config "$path"
        fi
        backup_file "/etc/snapper/configs/$config"
        log_info "Налаштування $config"
        snapper -c "$config" set-config \
            "TIMELINE_CREATE=$TIMELINE_CREATE" \
            "TIMELINE_CLEANUP=$TIMELINE_CLEANUP" \
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
        log_ok "Конфігурацію $config оновлено"
    done
}

# systemd drop-in без редагування пакетного unit-файлу.
write_timer_override() {
    local unit=$1 calendar=$2 persistent=$3
    local dir="/etc/systemd/system/${unit}.d"
    local file="${dir}/90-local-schedule.conf"
    mkdir -p -- "$dir"
    backup_file "$file"
    cat >"$file" <<EOF_TIMER
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
    log_ok "Збережено $file"
}

to_systemd_bool() {
    if [[ $1 == true ]]; then printf 'true'; else printf 'false'; fi
}

configure_timers() {
    # Пишемо override також для вимкнених таймерів, щоб повторний запуск був передбачуваним.
    write_timer_override snapper-timeline.timer "$TIMELINE_CALENDAR" "$(to_systemd_bool "$TIMELINE_PERSISTENT")"
    write_timer_override snapper-cleanup.timer "$CLEANUP_CALENDAR" "$(to_systemd_bool "$CLEANUP_PERSISTENT")"
    systemctl daemon-reload
    if [[ $TIMELINE_ENABLED == true ]]; then
        systemctl enable snapper-timeline.timer
        systemctl restart snapper-timeline.timer
        log_ok 'snapper-timeline.timer увімкнено'
    else
        systemctl disable --now snapper-timeline.timer
        log_warn 'snapper-timeline.timer вимкнено'
    fi
    if [[ $CLEANUP_ENABLED == true ]]; then
        systemctl enable snapper-cleanup.timer
        systemctl restart snapper-cleanup.timer
        log_ok 'snapper-cleanup.timer увімкнено'
    else
        systemctl disable --now snapper-cleanup.timer
        log_warn 'snapper-cleanup.timer вимкнено'
    fi
    if [[ $ENABLE_GRUB_BTRFSD == true ]]; then
        systemctl list-unit-files grub-btrfsd.service --no-legend | grep -q '^grub-btrfsd.service' ||
            log_error 'grub-btrfsd.service не встановлено'
        systemctl enable --now grub-btrfsd.service
    fi
}

show_status() {
    printf '\n'
    log_info 'Розклад Snapper:'
    systemctl list-timers --all snapper-timeline.timer snapper-cleanup.timer --no-pager
    printf '\n'
    log_info 'Налаштовані конфігурації:'
    snapper list-configs
    printf '\n'
    log_info 'Перевірка майбутніх запусків:'
    systemd-analyze calendar "$TIMELINE_CALENDAR" --iterations=2 | tail -n 3
    systemd-analyze calendar "$CLEANUP_CALENDAR" --iterations=2 | tail -n 3
}

main() {
    require_root
    validate
    BACKUP_STAMP=$(date +%Y%m%d-%H%M%S)
    install_packages
    configure_snapper
    configure_timers
    show_status
    log_ok 'Налаштування завершено. Старі snapshots примусово не видалялися.'
}
main "$@"
