#!/usr/bin/env bash

install_arch_package_if_missing() {
    local command_name="$1"
    local package_name="$2"

    if command_exists "$command_name"; then
        return 0
    fi

    if [[ -x /usr/bin/pacman ]]; then
        log_info "Встановлення package: $package_name"

        /usr/bin/pacman \
            --noconfirm \
            --needed \
            -S \
            "$package_name"
    else
        die "Не знайдено $command_name. Встанови package: $package_name"
    fi
}

setup_nftables() {
    log_step "Налаштування nftables."

    (( EUID == 0 )) ||
        die "setup_nftables потребує root."

    install_arch_package_if_missing nft nftables

    local rules_dir="/etc/nftables.d"
    local rules_file="$rules_dir/wordpress-stack.nft"

    mkdir -p "$rules_dir"

    if [[ -f "$rules_file" ]]; then
        cp -a -- \
            "$rules_file" \
            "${rules_file}.bak.$(date '+%Y%m%d_%H%M%S')"
    fi

    cat > "$rules_file" <<EOF
# Managed by wordpress-stack installer.
# Existing nftables rules and Docker rules are not flushed.

table inet wordpress_stack {
    # Фільтруємо лише трафік, призначений хосту.
    # Forwarding (Docker-контейнери) не перехоплюємо:
    # Docker керує власними правилами NAT/filter у окремих ланцюгах.
    chain input {
        type filter hook input priority filter; policy drop;

        ct state invalid drop
        ct state established,related accept

        iifname "lo" accept

        # SSH та порти web-stack (Traefik 80/443).
        tcp dport ${SSH_PORT} accept
        tcp dport 80 accept
        tcp dport 443 accept

        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept
    }
}
EOF

    if [[ ! -f /etc/nftables.conf ]]; then
        cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
include "/etc/nftables.d/*.nft"
EOF
    elif ! grep -Fq \
        'include "/etc/nftables.d/*.nft"' \
        /etc/nftables.conf
    then
        printf '\ninclude "/etc/nftables.d/*.nft"\n' \
            >> /etc/nftables.conf
    fi

    nft -c -f /etc/nftables.conf
    nft -f /etc/nftables.conf

    if command_exists systemctl; then
        systemctl enable --now nftables
    fi

    log_success "nftables integration готова (input: policy drop, відкрито SSH ${SSH_PORT}, 80, 443)."
    log_warning "Інші порти хоста, крім SSH ${SSH_PORT}, 80 і 443, тепер закриті для нових вхідних з'єднань."
}

setup_fail2ban() {
    log_step "Налаштування Fail2ban."

    (( EUID == 0 )) ||
        die "setup_fail2ban потребує root."

    install_arch_package_if_missing \
        fail2ban-client \
        fail2ban

    mkdir -p /etc/fail2ban/jail.d /etc/fail2ban/filter.d

    cat > /etc/fail2ban/filter.d/wordpress-stack.conf <<'EOF'
# Лічильник спроб входу WordPress (POST /wp-login.php).
# Бан після maxretry спроб за findtime.
[Definition]
failregex = ^<HOST> .* "POST /wp-login\.php[^"]*".*$
ignoreregex =
EOF

    cat > /etc/fail2ban/jail.d/wordpress-stack.conf <<EOF
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

bantime.increment = true
bantime.factor = 2
bantime.maxtime = 1w

backend = systemd

ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
port = ${SSH_PORT}
maxretry = 3
findtime = 10m
bantime = 1h

[wordpress]
enabled = true
filter = wordpress-stack
backend = auto
logpath = ${INSTALL_DIR}/logs/nginx/access.log
maxretry = 5
findtime = 10m
bantime = 1h
EOF

    fail2ban-client -t

    if command_exists systemctl; then
        systemctl enable --now fail2ban
        systemctl restart fail2ban
    fi

    log_success "Fail2ban jails налаштовано: SSH + WordPress (wp-login.php)."
}

schedule_cron_tasks() {
    local cron_file="/etc/cron.d/wordpress-stack"

    log_step "Налаштування cron-завдань."

    (( EUID == 0 )) ||
        die "--enable-cron потребує root."

    [[ -d /etc/cron.d ]] ||
        die "Каталог /etc/cron.d не знайдено (cron не встановлено?)."

    [[ -f "$INSTALL_DIR/scripts/backup.sh" ]] ||
        die "backup.sh не знайдено: $INSTALL_DIR/scripts/backup.sh"

    [[ -f "$INSTALL_DIR/scripts/logrotate-nginx.sh" ]] ||
        die "logrotate-nginx.sh не знайдено: $INSTALL_DIR/scripts/logrotate-nginx.sh"

    cat > "$cron_file" <<EOF
# Managed by wordpress-stack installer.
# Щоденний backup та ротація nginx-логів.

SHELL=/bin/bash

0 3 * * * root bash ${INSTALL_DIR}/scripts/backup.sh >> ${INSTALL_DIR}/backups/backup.cron.log 2>&1
30 3 * * * root bash ${INSTALL_DIR}/scripts/logrotate-nginx.sh >> ${INSTALL_DIR}/logs/logrotate.cron.log 2>&1
EOF

    chmod 0644 "$cron_file"

    mkdir -p "$INSTALL_DIR/backups" "$INSTALL_DIR/logs"

    log_success "Cron-завдання встановлено: ${cron_file} (backup 03:00, logrotate 03:30)."
}
