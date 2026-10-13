#!/usr/bin/env bash
# shellcheck disable=SC2034
MODULE_ID="shell"
MODULE_TITLE="Shell"
MODULE_ORDER=30
PACMAN_PACKAGES=(
    zsh
    zsh-completions
    zsh-syntax-highlighting
    zsh-autocomplete
    zsh-autosuggestions
    starship
)
AUR_PACKAGES=()
GITHUB_ITEMS=()

# CONFIG_ITEMS — імена з sources.conf (S_NAME).
CONFIG_ITEMS=(
    zsh
    zsh-alias
    zsh-path
    starship
)

# Hook: зробити zsh типовою оболонкою.
# Враховує, що chsh суворо перевіряє /etc/shells.
hook_set_zsh_default() {
    local user="${SUDO_USER:-$USER}"
    local zsh
    zsh="$(command -v zsh || true)"
    [[ -n "$zsh" ]] || {
        log warn 'Zsh не знайдено'
        return 0
    }
    [[ "$user" == root ]] && {
        log warn 'chsh для root пропущено'
        return 0
    }

    # chsh суворо перевіряє /etc/shells. Резолвимо symlink.
    local real
    real="$(readlink -f "$zsh")"
    if [[ -n "$real" && -x "$real" ]]; then
        zsh="$real"
    fi

    # Якщо шляху немає у /etc/shells — шукаємо той самий файл за inode.
    if ! grep -qxF "$zsh" /etc/shells 2>/dev/null; then
        local line
        while IFS= read -r line; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            if [[ -x "$line" && "$(readlink -f "$line")" == "$zsh" ]]; then
                zsh="$line"
                break
            fi
        done </etc/shells

        if ! grep -qxF "$zsh" /etc/shells 2>/dev/null; then
            log error "chsh: '$zsh' немає у /etc/shells"
            log info "Додайте вручну: echo '$zsh' | sudo tee -a /etc/shells"
            return 0
        fi
    fi

    local cur
    cur="$(getent passwd "$user" | cut -d: -f7)"
    if [[ "$cur" == "$zsh" ]]; then
        log info 'Zsh уже стандартна'
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == true ]]; then
        log info "[DRY-RUN] chsh -s $zsh $user"
        return 0
    fi

    log info "chsh -s $zsh $user"
    if chsh -s "$zsh" "$user"; then
        log ok "Оболонка змінена на $zsh"
    else
        log warn "chsh: не вдалося. Спробуйте вручну: chsh -s $zsh $user"
    fi
}
