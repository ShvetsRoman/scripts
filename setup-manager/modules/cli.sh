#!/usr/bin/env bash
# shellcheck disable=SC2034
MODULE_ID="cli"
MODULE_TITLE="CLI"
MODULE_ORDER=20
PACMAN_PACKAGES=(
    bat
    eza
    fd
    ripgrep
    fzf
    jq
    tree
    htop
    btop
    neovim
    wl-clipboard
    fastfetch
    mc
    kitty
    wezterm
    transmission-qt
)
AUR_PACKAGES=()
GITHUB_ITEMS=("superfile|script|https://superfile.dev/install.sh|spf")

CONFIG_ITEMS=(
    nvim
    kitty
    wezterm
    fzf
    eza
    superfile
)
