#!/usr/bin/env bash
# shellcheck disable=SC2034
# font — nerd-шрифти та fontconfig.
MODULE_ID="font"
MODULE_TITLE="Fonts"
MODULE_ORDER=40
PACMAN_PACKAGES=(ttf-nerd-fonts-symbols-mono)
AUR_PACKAGES=()
GITHUB_ITEMS=()
CONFIG_ITEMS=(
    "font|home|.local/share/fonts|.local/share/fonts"
    "font-conf|home|.fonts.conf|.fonts.conf"
)

# Hook: оновити кеш шрифтів.
hook_update_font_cache() {
    command -v fc-cache >/dev/null || return 0
    [[ "${DRY_RUN:-false}" == true ]] && { log info '[DRY-RUN] fc-cache -fv'; return 0; }
    fc-cache -fv >/dev/null && log ok 'Кеш шрифтів'
}
