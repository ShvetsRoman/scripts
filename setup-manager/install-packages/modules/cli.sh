#!/usr/bin/env bash
# Змінні цього файла читаються іншими модулями через source.
# shellcheck disable=SC2034
# Модуль cli: пакети, конфігурації та необов’язковий post-install hook.
MODULE_ID="cli"
MODULE_TITLE="CLI"
MODULE_ORDER=20
MODULE_DEPENDS=""
MODULE_SERVICES_LIST=""
MODULE_POST_HOOK=""

# Пакети офіційних репозиторіїв Arch Linux.
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
    xclip
    wl-clipboard
    fastfetch
    mc
    kitty
    wezterm
    transmission-qt
)

# Пакети AUR (через paru).
AUR_PACKAGES=(

)

# Зовнішні програми: ID|TYPE|URL|CHECK_COMMAND[|DEST|EXEC_REL].
# Для TYPE=script запускається код із вказаного URL: перевіряйте джерело!
GITHUB_ITEMS=(
    "superfile|script|https://superfile.dev/install.sh|spf"
)

# Конфіги: ID|SCOPE|SOURCE|DESTINATION (SOURCE відносно DOTFILES_DIR).
# SCOPE: home або system. Для home DESTINATION відносно ~.
CONFIG_ITEMS=(
    "nvim|home|.config/nvim|.config/nvim"
    "kitty|home|.config/kitty|.config/kitty"
    "wezterm|home|.config/wezterm|.config/wezterm"
    "fzf|home|.config/fzf|.config/fzf"
    "superfile|home|.config/superfile|.config/superfile"
)
