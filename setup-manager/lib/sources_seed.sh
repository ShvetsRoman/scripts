#!/usr/bin/env bash
# seed + scan.

# _SEED_GROUPS — категорії файлів для швидкого старту.
# Формат: "name:file1 file2 ..." (шляхи відносно $HOME).
_SEED_GROUPS=(
    "shell:.zshrc .zsh_alias.zsh .zsh_path.zsh .p10k_my.zsh .p10k_my_nordic_v1.zsh .p10k.zsh"
    "git:.gitconfig .gitignore_global"
    "general:.fonts.conf .gtkrc-2.0 .inputrc"
    "terminals:.config/kitty .config/wezterm .config/alacritty .config/foot"
    "editors:.config/nvim .config/helix .config/kate .config/zed"
    "cli:.config/starship .config/fzf .config/eza .config/superfile .config/zoxide .config/bat"
    "tui:.config/btop .config/htop .config/yazi .config/zellij .config/mc .config/vifm .config/lazydocker .config/lazygit .config/lazyrsync"
    "kde:.config/kdeglobals .config/kwinrc .config/kglobalshortcutsrc .config/katerc .config/dolphinrc .config/konsolerc .config/krusaderrc .config/plasmashellrc .config/plasma-org.kde.plasma.desktop-appletsrc .config/mimeapps.list .config/menus .config/Kvantum .config/kscreenlockerrc"
    "gtk:.config/gtk-3.0 .config/gtk-4.0 .config/fontconfig .config/QtProject.conf .config/Trolltech.conf"
    "multimedia:.config/deadbeef .config/transmission .config/vlc .config/ktorrentrc .config/mpv"
)

# _SEED_SKIP_PATTERNS — категорії, які НІКОЛИ не додаються автоматично.
# Кеш, приватні ключі, історія, великі дані.
_SEED_SKIP_PATTERNS=(
    '.cache' '.cargo' '.npm' '.rustup' '.nvm' '.pyenv'
    '.ssh' '.gnupg' '.wireguard' '.pki' '.pulse-cookie' '.zsh_history' '.bash_history'
    '.config/google-chrome' '.config/chromium' '.config/VirtualBox' '.config/Code'
    '.config/unity3d' '.config/kconf_updaterc' '.config/kactivitymanagerd-statsrc'
    '.config/RecentlyDocuments' '.config/qymcad' '.config/cadcraft'
    'Downloads' 'Videos' 'Pictures' 'Documents' 'Music' 'Public' 'Templates'
    '.steam' '.lmstudio' '.var'
)

# _seed_exists — чи існує шлях у $HOME (враховує symlink).
_seed_exists() {
    local rel="$1"
    [[ -e "$HOME/$rel" || -L "$HOME/$rel" ]]
}

# _seed_classify — класифікує шлях: suggest / skip / ask.
# suggest: у відомій групі (shell/kde/cli/...) → радимо додати.
# skip: у _SEED_SKIP_PATTERNS → небезпечно/сміття.
# ask: усе інше з .config/* або .local/share/fonts → вирішує користувач.
_seed_classify() {
    local rel="$1"
    local pat
    for pat in "${_SEED_SKIP_PATTERNS[@]}"; do
        [[ "$rel" == "$pat" || "$rel" == "$pat"/* ]] && { printf 'skip'; return; }
    done
    local group g
    for group in "${_SEED_GROUPS[@]}"; do
        local items="${group#*:}"
        for g in $items; do
            [[ "$rel" == "$g" ]] && { printf 'suggest'; return; }
        done
    done
    case "$rel" in
        .config/*|.local/share/fonts) printf 'ask' ;;
        _*) printf 'ask' ;;
        *) printf 'skip' ;;
    esac
}

# sources_scan — dry-run: показати, що є у $HOME, і як класифіковано.
# НЕ пише у реєстр. Лише показує, що варто додати.
sources_scan() {
    sources_load
    local -A in_registry=()
    local row
    for row in "${SRC_ROWS[@]}"; do
        sources_parse "$row"
        in_registry["$S_SRC"]=1
    done

    header 'SCAN: $HOME ↔ реєстр'
    local suggested=0 asked=0 skipped=0
    local rel kind

    while IFS= read -r -d '' path; do
        rel="$(basename -- "$path")"
        kind="$(_seed_classify "$rel")"
        local state="new"
        [[ -n "${in_registry[$rel]:-}" ]] && state="in-registry"
        case "$kind" in
            suggest) printf '  [suggest] %-45s (%s)\n' "$rel" "$state"; ((suggested+=1)) ;;
            ask)     printf '  [ask]     %-45s (%s)\n' "$rel" "$state"; ((asked+=1)) ;;
            skip)    printf '  [skip]    %-45s\n' "$rel"; ((skipped+=1)) ;;
        esac
    done < <(find -P "$HOME" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | sort -z)

    if [[ -d "$HOME/.config" ]]; then
        printf '\n  .config/:\n'
        while IFS= read -r -d '' path; do
            rel=".config/$(basename -- "$path")"
            kind="$(_seed_classify "$rel")"
            local state="new"
            [[ -n "${in_registry[$rel]:-}" ]] && state="in-registry"
            case "$kind" in
                suggest) printf '  [suggest] %-45s (%s)\n' "$rel" "$state"; ((suggested+=1)) ;;
                ask)     printf '  [ask]     %-45s (%s)\n' "$rel" "$state"; ((asked+=1)) ;;
                skip)    printf '  [skip]    %-45s\n' "$rel"; ((skipped+=1)) ;;
            esac
        done < <(find -P "$HOME/.config" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | sort -z)
    fi

    printf '\nРазом: %d suggest, %d ask, %d skip\n' "$suggested" "$asked" "$skipped"
    printf 'Команда для запису: ./setup.sh sources seed\n'
}

# sources_seed — інтерактивно додає вибрані групи у реєстр.
# Показує список груп з кількістю файлів, які РЕАЛЬНО існують.
# Користувач вибирає номери через пробіл або 'all'.
# Додає лише ті шляхи, яких ще немає в реєстрі.
sources_seed() {
    header 'SEED: вибір груп'
    printf 'Доступні групи:\n\n'

    local -a names=()
    local i=1 g name items count
    for g in "${_SEED_GROUPS[@]}"; do
        name="${g%%:*}"
        items="${g#*:}"
        names+=("$name")
        count=0
        local item
        for item in $items; do
            _seed_exists "$item" && ((count+=1))
        done
        printf '  %2d) %-12s (%d з %d існує)\n' "$i" "$name" "$count" "$(printf '%s' "$items" | wc -w)"
        ((i+=1))
    done
    printf '\nВведіть номери груп через пробіл (напр. "1 3 4") або "all": '
    local choice
    read -r choice || return 1

    local -a selected=()
    if [[ "$choice" == all ]]; then
        for g in "${_SEED_GROUPS[@]}"; do selected+=("${g#*:}"); done
    else
        local n
        for n in $choice; do
            if [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#names[@]} )); then
                for g in "${_SEED_GROUPS[@]}"; do
                    [[ "${g%%:*}" == "${names[n-1]}" ]] && selected+=("${g#*:}")
                done
            fi
        done
    fi

    if ((${#selected[@]} == 0)); then
        log warn 'Нічого не вибрано.'
        return 0
    fi

    local added=0 skipped=0
    for items in "${selected[@]}"; do
        local item
        for item in $items; do
            _seed_exists "$item" || { ((skipped+=1)); continue; }
            sources_load
            local dup=0 row
            for row in "${SRC_ROWS[@]}"; do
                sources_parse "$row"
                [[ "$S_SRC" == "$item" ]] && { dup=1; break; }
            done
            (( dup )) && { ((skipped+=1)); continue; }
            sources_add home "$item" "$item" dotfiles >/dev/null 2>&1 && ((added+=1)) || ((skipped+=1))
        done
    done

    log ok "Seed: додано $added, пропущено $skipped"
}
