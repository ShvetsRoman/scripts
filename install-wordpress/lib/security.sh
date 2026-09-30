#!/usr/bin/env bash

install_arch_package_if_missing() {
    local command_name="$1"
    local package_name="$2"

    if command_exists "$command_name"; then
        return 0
    fi

    if command_exists pacman; then
        log_info "Встановлення package: $package_name"
        pacman -S --needed --noconfirm "$package_name"
    else
        die "Не знайдено $command_name. Встанови package: $package_name"
    fi
}

setup_nftables() {
    log_step "Налаштування nftables."

    install_arch_package_if_missing nft nftables

    local rules_dir="/etc/nftables.d"
    local rules_file="$rules_dir/wordpress-stack.nft"

    mkdir -p "$rules_dir"

    if [[ -f "$rules_file" ]]; then
        cp -a -- "$rules_file" "${rules_file}.bak.$(date '+%Y%m%d_%H%M%S')"
    fi

    cat > "$rules_file" <<EOF
# Managed by wordpress-stack installer.
# This table protects host INPUT only.
# Docker forwarding/NAT remains managed by Docker.

table inet wordpress_stack {
    chain input {
        type filter hook input priority filter; policy accept;

        ct state invalid drop
        ct state established,related accept

        iifname "lo" accept

        # Allow SSH used by this server.
        tcp dport ${SSH_PORT} accept

        # ICMP / ICMPv6 remain available for network diagnostics and PMTU.
        ip protocol icmp accept
        ip6 nexthdr ipv6-icmp accept

        # Do not set policy drop here: this installer must not silently
        # lock out unrelated host services. Harden the global host policy
        # separately after reviewing all required ports.
    }
}
EOF

    if [[ ! -f /etc/nftables.conf ]]; then
        cat > /etc/nftables.conf <<'EOF'
#!/usr/sbin/nft -f
include "/etc/nftables.d/*.nft"
EOF
    elif ! grep -Fq 'include "/etc/nftables.d/*.nft"' /etc/nftables.conf; then
        printf '\ninclude "/etc/nftables.d/*.nft"\n' >> /etc/nftables.conf
    fi

    nft -c -f /etc/nftables.conf
    nft -f /etc/nftables.conf

    if command_exists systemctl; then
        systemctl enable --now nftables
    fi

    log_success "nftables table wordpress_stack додано без flush ruleset."
}

setup_fail2ban() {
    log_step "Налаштування Fail2ban."

    install_arch_package_if_missing fail2ban-client fail2ban

    mkdir -p /etc/fail2ban/jail.d

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
EOF

    fail2ban-client -t

    if command_exists systemctl; then
        systemctl enable --now fail2ban
        systemctl restart fail2ban
    fi

    log_success "Fail2ban SSH jail налаштовано."
}
