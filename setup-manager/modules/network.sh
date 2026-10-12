#!/usr/bin/env bash
# Перенесено лише списки програм зі старого проєкту.
# shellcheck disable=SC2034
MODULE_ID="network"
MODULE_TITLE="Network"
MODULE_ORDER=70
MODULE_DEPENDS=""
PACMAN_PACKAGES=(
    bind
    iperf3
    nmap
    traceroute
    whois
    tcpdump
    openssh
    ethtool
)
AUR_PACKAGES=(

)
GITHUB_ITEMS=(
)

# Реєстр конфігів Installer, окремий від реєстру Dotfiles Backup.
CONFIG_ITEMS=(
)
