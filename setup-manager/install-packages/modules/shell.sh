#!/usr/bin/env bash
# Змінні цього файла читаються іншими модулями через source.
# shellcheck disable=SC2034
# Модуль shell: пакети, конфігурації та необов’язковий post-install hook.
MODULE_ID="shell"
MODULE_TITLE="Shell"
MODULE_ORDER=30
MODULE_DEPENDS=""
MODULE_SERVICES_LIST=""
MODULE_POST_HOOK="configure_default_shell"

# Пакети офіційних репозиторіїв Arch Linux.
PACMAN_PACKAGES=(
    zsh
    zsh-completions
    zsh-syntax-highlighting
    zsh-autocomplete
    zsh-autosuggestions
    starship
)

# Пакети AUR (через paru).
AUR_PACKAGES=(

)

# Зовнішні програми: ID|TYPE|URL|CHECK_COMMAND[|DEST|EXEC_REL].
# Для TYPE=script запускається код із вказаного URL: перевіряйте джерело!
GITHUB_ITEMS=(
)

# Конфіги: ID|SCOPE|SOURCE|DESTINATION (SOURCE відносно DOTFILES_DIR).
# SCOPE: home або system. Для home DESTINATION відносно ~.
CONFIG_ITEMS=(
    "zsh|home|.zshrc|.zshrc"
    "zsh-alias|home|.zsh_alias.zsh|.zsh_alias.zsh"
    "zsh-path|home|.zsh_path.zsh|.zsh_path.zsh"
    "starship|home|.config/starship|.config/starship"
)

# ------------------------------------------------------------
# POST-INSTALL: специфічні налаштування модуля
# ------------------------------------------------------------
configure_default_shell() {
    local zsh_path
    local current_user
    local user_shell
    local root_shell

    # Installer запускається звичайним користувачем, але SUDO_USER
    # залишаємо як безпечний fallback.
    current_user="${SUDO_USER:-${USER:-}}"

    if [[ -z "$current_user" || "$current_user" == root ]]; then
        log_error "Не вдалося визначити звичайного користувача для налаштування Zsh."
        return 1
    fi

    zsh_path="$(command -v zsh || true)"

    # На Arch /sbin є symlink на /usr/bin. Для /etc/shells та chsh
    # використовуємо канонічний шлях, наприклад /usr/bin/zsh.
    if [[ -n "$zsh_path" ]]; then
        zsh_path="$(readlink -f -- "$zsh_path")"
    fi

    if [[ -z "$zsh_path" ]]; then
        # Під час --dry-run Zsh може ще не бути встановлений.
        if [[ "$DRY_RUN" == true ]]; then
            zsh_path="/usr/bin/zsh"
            log_info "[DRY-RUN] Припускаємо шлях Zsh: $zsh_path"
        else
            log_error "Zsh не знайдено після встановлення."
            return 1
        fi
    fi

    log_info "Zsh: $zsh_path"

    # chsh приймає login shell лише з /etc/shells.
    if ! grep -Fxq "$zsh_path" /etc/shells 2>/dev/null; then
        log_step "Додавання Zsh до /etc/shells."

        if [[ "$DRY_RUN" == true ]]; then
            log_info "[DRY-RUN] Додати '$zsh_path' до /etc/shells"
        else
            printf '%s\n' "$zsh_path" | sudo tee -a /etc/shells >/dev/null
            log_ok "Zsh додано до /etc/shells."
        fi
    else
        log_info "Zsh вже присутній у /etc/shells."
    fi

    user_shell="$(getent passwd "$current_user" | cut -d: -f7)"
    if [[ -z "$user_shell" ]]; then
        log_error "Не вдалося визначити login shell користувача '$current_user'."
        return 1
    fi

    if [[ "$user_shell" != "$zsh_path" ]]; then
        log_step "Встановлення Zsh як login shell для '$current_user'."
        run_cmd sudo chsh -s "$zsh_path" "$current_user"
        [[ "$DRY_RUN" == true ]] || log_ok "Login shell для '$current_user' змінено на Zsh."
    else
        log_info "Zsh вже є login shell для '$current_user'."
    fi

    root_shell="$(getent passwd root | cut -d: -f7)"
    if [[ -z "$root_shell" ]]; then
        log_error "Не вдалося визначити login shell користувача root."
        return 1
    fi

    if [[ "$root_shell" != "$zsh_path" ]]; then
        log_step "Встановлення Zsh як login shell для root."
        run_cmd sudo chsh -s "$zsh_path" root
        [[ "$DRY_RUN" == true ]] || log_ok "Login shell для root змінено на Zsh."
    else
        log_info "Zsh вже є login shell для root."
    fi
}
