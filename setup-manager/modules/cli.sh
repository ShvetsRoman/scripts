#!/usr/bin/env bash
# shellcheck disable=SC2034
# cli — консольні утиліти, редактори, менеджери файлів.
MODULE_ID="cli"
MODULE_TITLE="CLI"
MODULE_ORDER=20
PACMAN_PACKAGES=(bat eza fd ripgrep fzf jq tree htop btop neovim xclip wl-clipboard fastfetch mc kitty wezterm transmission-qt)
AUR_PACKAGES=()
GITHUB_ITEMS=("superfile|script|https://superfile.dev/install.sh|spf")
CONFIG_ITEMS=(
    "nvim|home|.config/nvim|.config/nvim"
    "kitty|home|.config/kitty|.config/kitty"
    "wezterm|home|.config/wezterm|.config/wezterm"
    "fzf|home|.config/fzf|.config/fzf"
    "eza|home|.config/eza|.config/eza"
    "superfile|home|.config/superfile|.config/superfile"
)
