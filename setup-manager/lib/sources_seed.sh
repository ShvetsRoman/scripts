#!/usr/bin/env bash
# sources_scan — dry-run перегляд $HOME.
# Класифікує кожен шлях: suggest / ask / skip.

# _SCAN_SKIP_PATTERNS — категорії, які не показуємо як suggest.
_SCAN_SKIP_PATTERNS=(
    '.cache' '.cargo' '.npm' '.rustup' '.nvm' '.pyenv'
    '.ssh' '.gnupg' '.wireguard' '.pki' '.pulse-cookie' '.zsh_history' '.bash_history'
    '.config/google-chrome' '.config/chromium' '.config/VirtualBox' '.config/Code'
    '.config/unity3d' '.config/kconf_updaterc' '.config/kactivitymanagerd-statsrc'
    '.config/RecentlyDocuments' '.config/qymcad' '.config/cadcraft'
    'Downloads' 'Videos' 'Pictures' 'Documents' 'Music' 'Public' 'Templates'
    '.steam' '.lmstudio' '.var'
)

# _SCAN_SUGGEST — типові dotfiles, які варто бекапити.
_SCAN_SUGGEST=(
    '.zshrc' '.zsh_alias.zsh' '.zsh_path.zsh' '.p10k_my.zsh' '.p10k_my_nordic_v1.zsh'
    '.gitconfig' '.gitignore_global' '.fonts.conf' '.gtkrc-2.0' '.inputrc'
    '.config/kitty' '.config/wezterm' '.config/alacritty' '.config/foot'
    '.config/nvim' '.config/helix' '.config/kate' '.config/zed'
    '.config/starship' '.config/fzf' '.config/eza' '.config/superfile' '.config/zoxide' '.config/bat'
    '.config/btop' '.config/htop' '.config/yazi' '.config/zellij' '.config/mc'
    '.config/vifm' '.config/lazydocker' '.config/lazygit' '.config/lazyrsync'
    '.config/kdeglobals' '.config/kwinrc' '.config/kglobalshortcutsrc' '.config/katerc'
    '.config/dolphinrc' '.config/konsolerc' '.config/krusaderrc' '.config/plasmashellrc'
    '.config/plasma-org.kde.plasma.desktop-appletsrc' '.config/mimeapps.list'
    '.config/menus' '.config/Kvantum' '.config/kscreenlockerrc'
    '.config/gtk-3.0' '.config/gtk-4.0' '.config/fontconfig' '.config/QtProject.conf' '.config/Trolltech.conf'
    '.config/deadbeef' '.config/transmission' '.config/vlc' '.config/ktorrentrc' '.config/mpv'
    '.local/share/fonts'
)

# _scan_classify — suggest / skip / ask.
_scan_classify() {
    local rel="$1"
    local pat g

    for pat in "${_SCAN_SKIP_PATTERNS[@]}"; do
        [[ "$rel" == "$pat" || "$rel" == "$pat"/* ]] && { printf 'skip'; return; }
    done

    for g in "${_SCAN_SUGGEST[@]}"; do
        [[ "$rel" == "$g" ]] && { printf 'suggest'; return; }
    done

    case "$rel" in
        .config/*|.local/share/fonts) printf 'ask' ;;
        _*) printf 'ask' ;;
        *) printf 'skip' ;;
    esac
}

# sources_scan — dry-run перегляд $HOME, без запису.
sources_scan() {
    sources_load || return 2
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
        kind="$(_scan_classify "$rel")"
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
            kind="$(_scan_classify "$rel")"
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
    printf 'Додати вручну: ./setup.sh sources add NAME MODE SRC DST\n'
}
