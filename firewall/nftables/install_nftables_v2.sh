#!/bin/bash

# ============================================================
# Налаштування nftables (+ опційно Fail2ban) для Arch Linux
# Використання:
#   ./install_nftables_v2.sh                 # запитає про Fail2ban інтерактивно
#   ./install_nftables_v2.sh --ssh-port 2241 --fail2ban
#   ./install_nftables_v2.sh --no-fail2ban
# ============================================================

set -euo pipefail

CONF_NFT="/etc/nftables.conf"
FAIL2BAN_SERVICE_DIR="/etc/systemd/system/fail2ban.service.d"

# Кольори для виводу
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функції логування ($* — усі аргументи; log_error завершує скрипт)
log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

SSH_PORT=""
WITH_F2B=""

# ---------- Парсинг аргументів ----------
usage() {
    cat <<USAGE
Використання: $0 [ options ]
  --ssh-port PORT      Порт SSH для правила nftables / jail.local
                       (за замовчуванням визначається автоматично)
  --fail2ban           Встановити та налаштувати Fail2ban
  --no-fail2ban        Пропустити Fail2ban
  -h, --help           Ця довідка
USAGE
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ssh-port)    [[ $# -ge 2 ]] || log_error "--ssh-port потребує аргументу"; SSH_PORT="$2"; shift 2 ;;
        --fail2ban)    WITH_F2B="yes"; shift ;;
        --no-fail2ban) WITH_F2B="no"; shift ;;
        -h|--help)     usage ;;
        *)             usage ;;
    esac
done

# ---------- Перевірки середовища ----------
[[ $EUID -eq 0 ]] || log_error "Цей скрипт потрібно запускати від root"
if { [[ -f /etc/os-release ]] && grep -qi "^ID=arch" /etc/os-release; }; then
    :
else
    log_warning "Виглядає не як Arch Linux — pacman може не бути доступним"
fi

command -v pacman >/dev/null 2>&1 || log_error "pacman не знайдений"
command -v nft    >/dev/null 2>&1 || true

# Визначення SSH-порту пріоритетом: аргумент CLI > running sshd > sshd_config > 22
detect_ssh_port() {
    if [[ -n "$SSH_PORT" ]]; then
        return
    fi

    local port=""
    # Порт із конфігів sshd (перший рядок 'Port' виграє)
    if [[ -d /etc/ssh/sshd_config.d ]]; then
        port=$(grep -rhsip --include='*.conf' -e '^[[:space:]]*Port[[:space:]]' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null \
            | head -n1 | awk '{print $2}') || port=""
    else
        port=$(grep -hip -e '^[[:space:]]*Port[[:space:]]' /etc/ssh/sshd_config 2>/dev/null \
            | head -n1 | awk '{print $2}') || port=""
    fi

    # Фактично слухані sshd порти (якщо sshd запущений)
    local listening=""
    if pidof sshd >/dev/null 2>&1; then
        listening=$(ss -tlnp 2>/dev/null | awk '/sshd/ {print $4}' | grep -oP '\K[0-9]+$' | sort -un | head -n1 || true)
    fi

    if [[ -n "$listening" ]]; then
        SSH_PORT="$listening"
        [[ -n "$port" && "$port" != "$listening" ]] && \
            log_warning "sshd_config вказує '$port', але слухається '$listening'. Використовую '$listening'."
    elif [[ -n "$port" ]]; then
        SSH_PORT="$port"
    else
        SSH_PORT="22"
    fi
}

# Слідкуючий запасний порт перед застосуванням правил
confirm_ssh_port() {
    if pidof sshd >/dev/null 2>&1; then
        if ! ss -tln | grep -qE "[[:space:]]:${SSH_PORT}[[:space:]]"; then
            log_warning "SSH-порт $SSH_PORT зараз НЕ слухається — перевірте конфіг до продовження!"
            read -r -p "Все одно продовжити? [y/N] " ans
            [[ "$ans" =~ ^[Yy]$ ]] || log_error "Скасовано користувачем"
        fi
    else
        log_warning "sshd не запущений — правило для порту $SSH_PORT додано, але перевірте його вручну"
    fi
}

# Бекап існуючого файлу перед перезаписом
backup_file() {
    if [[ -f "$1" ]]; then
        cp -a "$1" "${1}.bak.$(date +%Y%m%d-%H%M%S)"
        log_info "Бекап: ${1}.bak.$(date +%Y%m%d-%H%M%S)"
    fi
}

# Очікування юніту systemd
wait_for_unit() {
    local unit="$1" i
    for (( i = 0; i < 15; i++ )); do
        systemctl is-active --quiet "$unit" && return 0
        sleep 1
    done
    return 1
}

# ============================================================
# nftables
# ============================================================
setup_nftables() {
    log_info "Налаштування nftables..."

    if ! command -v nft >/dev/null 2>&1; then
        log_info "nft не знайдено. Встановлення nftables..."
        pacman -S --noconfirm --needed nftables || log_error "Не вдалося встановити nftables"
    fi
    log_success "nftables встановлено"

    backup_file "$CONF_NFT"

    # Примітка: Fail2ban (якщо ввімкнений) зі стандартним banaction
    # nftables-multiport створює власну таблицю f2b — окремий set тут не потрібен.
    cat > "$CONF_NFT" <<EOF

#!/usr/sbin/nft -f

flush ruleset

table inet filter {

    chain input {
        type filter hook input priority filter; policy drop;
        counter

        # Уже встановлені та пов'язані з'єднання
        ct state established,related accept

        # Некоректні пакети
        ct state invalid drop

        # Loopback
        iifname "lo" counter accept

        # ICMPv6 Neighbor/Router Discovery — без цього не працює IPv6
        icmpv6 type { nd-neighbor-solicit, nd-neighbor-advert, nd-router-advert, nd-router-solicit } accept

        # Ping: обмежена швидкість (анти-flood)
        limit rate 10/second icmp type echo-request accept
        icmp type { destination-unreachable, time-exceeded, parameter-problem } accept

        # SSH
        tcp dport ${SSH_PORT} ct state new counter accept comment "SSH"

        # HTTP / HTTPS
        # tcp dport { 80, 443 } ct state new counter accept

        # Логування лише відхилених пакетів (з лімітом)
        limit rate 5/second burst 10 packets counter log prefix "nftables-drop: " level warning
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
        counter
    }

    chain output {
        type filter hook output priority filter; policy accept;
        counter
    }
}
EOF

    # Спочатку лише перевірка синтаксису — щоб не залишити машину без правил
    nft -c -f "$CONF_NFT" || log_error "Синтаксична помилка в ${CONF_NFT}"

    # Застосування правил
    nft -f "$CONF_NFT"

    systemctl enable --now nftables

    if wait_for_unit nftables; then
        log_success "nftables налаштовано"
    else
        log_error "nftables не запустився після увімкнення"
    fi
}

# ============================================================
# Fail2ban (опційно)
# ============================================================
setup_fail2ban() {
    log_info "Налаштування Fail2ban..."

    if ! command -v fail2ban-client >/dev/null 2>&1; then
        log_info "fail2ban не знайдено. Встановлення fail2ban..."
        pacman -S --noconfirm --needed fail2ban || log_error "Не вдалося встановити fail2ban"
    fi
    log_success "Fail2ban встановлено"

    backup_file /etc/fail2ban/jail.local

    cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
# Початковий час блокування IP
bantime = 1h
# Період, протягом якого рахуються невдалі спроби
findtime = 10m
# Кількість невдалих спроб до блокування
maxretry = 3
# Поступове збільшення часу блокування
bantime.increment = true
bantime.factor = 2
bantime.maxtime = 1w
# systemd journal як джерело логів
backend = systemd
# IP, які ніколи не блокувати
ignoreip = 127.0.0.1/8 ::1
# Блокування через nftables (власна таблиця f2b)
banaction = nftables-multiport
banaction_allports = nftables-allports

[sshd]
enabled = true
# Порт SSH — те саме джерело, що й у nftables.conf (одне значення, без дублікатів)
port = ${SSH_PORT}
maxretry = 3
findtime = 10m
EOF

    # Fail2ban має вмикатися ПІСЛЯ nftables — інакше перезапуск
    # nftables (flush ruleset) зітре таблицю f2b до перезапуску fail2ban.
    mkdir -p "$FAIL2BAN_SERVICE_DIR"
    cat > "${FAIL2BAN_SERVICE_DIR}/order.conf" <<'EOF'
[Unit]
After=nftables.service
EOF
    systemctl daemon-reload

    systemctl enable --now fail2ban

    if wait_for_unit fail2ban; then
        log_success "Fail2ban налаштовано"
        fail2ban-client status || log_warning "fail2ban-client status повернув помилку"
    else
        log_warning "fail2ban не запустився за 15 секунд — перевірте: journalctl -u fail2ban"
    fi
}

# ============================================================
# Питання про Fail2ban, якщо не задано через CLI
# ============================================================
ask_fail2ban() {
    if [[ -n "$WITH_F2B" ]]; then
        return
    fi
    if [[ ! -t 0 ]]; then
        log_warning "Немає інтерактивного терміналу — Fail2ban пропущено (--no-fail2ban)"
        WITH_F2B="no"
        return
    fi
    read -r -p "Встановити Fail2ban (блокування брутфорсу SSH)? [Y/n] " ans
    case "$ans" in
        [nN]*) WITH_F2B="no" ;;
        *)     WITH_F2B="yes" ;;
    esac
}

# ---------- Точка входу ----------
detect_ssh_port
log_info "SSH-порт: ${SSH_PORT}"
confirm_ssh_port

ask_fail2ban
if [[ "$WITH_F2B" == "yes" ]]; then
    log_info "Fail2ban: УВІМКНЕНО"
else
    log_info "Fail2ban: вимкнено"
fi

setup_nftables
[[ "$WITH_F2B" == "yes" ]] && setup_fail2ban

log_success "Готово. Результат — firewall: ${WITH_F2B}"
