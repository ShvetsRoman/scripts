#!/bin/bash

set -e

# Кольори для виводу
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функції логування
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Налаштування nftables
setup_nftables() {

    log_info "Налаштування nftables..."

    if ! command -v nft >/dev/null 2>&1; then
        log_info "nft не знайдений. Встановлення nftables..."
        pacman -S --noconfirm nftables || {
            log_error "Не вдалося встановити nftables"
            exit 1
        }
    fi
    log_success "nftables встановлено..."

    cat > /etc/nftables.conf << 'EOF'

#!/usr/sbin/nft -f

flush ruleset

table inet filter {

    # IP, заблоковані Fail2ban
    set f2b-sshd {
        type ipv4_addr
        flags dynamic, timeout
        timeout 10m
    }

    chain input {
        type filter hook input priority filter; policy drop;

        # Уже встановлені з'єднання
        ct state established,related accept

        # Некоректні пакети
        ct state invalid drop

        # Loopback
        iifname "lo" accept

        # Fail2ban
        ip saddr @f2b-sshd drop

        # SSH
        tcp dport 2241 ct state new accept

        # HTTP / HTTPS
        # tcp dport { 80, 443 } ct state new accept

        # ICMP
        icmp type echo-request accept

        # Логування тільки відхилених пакетів
        limit rate 5/second burst 10 packets \
            log prefix "nftables-drop: " level warning
    }

    chain forward {
        type filter hook forward priority filter;
        policy drop;
    }

    chain output {
        type filter hook output priority filter;
        policy accept;
    }
}
EOF
    
    # Застосування правил
    nft -f /etc/nftables.conf

    systemctl enable --now nftables
    systemctl is-active --quiet nftables || {
        log_warning "nftables не запущений"
        exit 1
    }
    
    log_success "nftables налаштовано"
}

# Налаштування Fail2ban
setup_fail2ban() {
    log_info "Налаштування Fail2ban..."

    # Встановлення fail2ban
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        log_info "fail2ban не знайдений. Встановлення fail2ban..."
        pacman -S --noconfirm fail2ban || {
            log_error "Не вдалося встановити fail2ban"
            exit 1
        }
    fi
    log_success "Fail2ban встановлено..."

    # Створення конфігурації
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Початковий час блокування IP
bantime = 1h
# Період, протягом якого рахуються невдалі спроби
findtime = 10m
# Кількість невдалих спроб до блокування
maxretry = 3
# Увімкнути поступове збільшення часу блокування
bantime.increment = true
# Множник збільшення часу блокування
bantime.factor = 2
# Максимальний час блокування IP
bantime.maxtime = 1w
# Використовувати systemd journal для аналізу логів
backend = systemd
# IP-адреси, які ніколи не блокувати
ignoreip = 127.0.0.1/8 ::1
# Використовувати nftables для блокування IP
banaction = nftables-multiport
# Використовувати nftables для блокування IP на всіх портах
banaction_allports = nftables-allports

[sshd]
# Увімкнути захист SSH
enabled = true
# Порт SSH
port = 2241
# Кількість невдалих спроб до блокування SSH
maxretry = 3
# Період підрахунку невдалих спроб SSH
findtime = 10m
EOF

    systemctl enable --now fail2ban
    fail2ban-client status
    systemctl is-active --quiet fail2ban-client || {
        log_warning "fail2ban не запущений"
        exit 1
    }

    log_success "Fail2ban налаштовано"
}

setup_nftables
setup_fail2ban
