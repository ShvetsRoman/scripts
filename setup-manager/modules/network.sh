#!/usr/bin/env bash
# shellcheck disable=SC2034
# network — діагностика мережі, тунелі, ssh.
MODULE_ID="network"
MODULE_TITLE="Network"
MODULE_ORDER=70
PACMAN_PACKAGES=(bind iperf3 nmap traceroute whois tcpdump openssh ethtool)
AUR_PACKAGES=()
GITHUB_ITEMS=()
CONFIG_ITEMS=()
