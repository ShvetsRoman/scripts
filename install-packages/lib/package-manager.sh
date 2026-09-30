#!/usr/bin/env bash

# ============================================================
# РОБОТА З PACMAN ТА PARU
# ============================================================

package_installed() {
    pacman -Q "$1" >/dev/null 2>&1
}

install_pacman() {
    local packages=("$@")
    ((${#packages[@]})) || return 0

    local missing=()
    local package

    for package in "${packages[@]}"; do
        if package_installed "$package"; then
            log_info "$package вже встановлено."
        else
            missing+=("$package")
        fi
    done

    if ((${#missing[@]} == 0)); then
        log_ok "Усі pacman-пакети вже встановлені."
        return 0
    fi

    echo
    log_step "Встановлення pacman-пакетів:"
    printf '  - %s\n' "${missing[@]}"

    local args=(sudo pacman -S --needed)
    [[ "$ASSUME_YES" == true ]] && args+=(--noconfirm)
    args+=("${missing[@]}")

    run_cmd "${args[@]}"
}

install_paru_helper() {
    if command -v paru >/dev/null 2>&1; then
        return 0
    fi

    echo
    log_step "Встановлення AUR helper paru."
    install_pacman base-devel git

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Було б встановлено paru з AUR."
        return 0
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf -- "${tmp_dir:-}"' RETURN

    git clone https://aur.archlinux.org/paru.git "$tmp_dir/paru"
    (
        cd "$tmp_dir/paru"
        local makepkg_args=(-si)
        [[ "$ASSUME_YES" == true ]] && makepkg_args+=(--noconfirm)
        makepkg "${makepkg_args[@]}"
    )

    rm -rf "$tmp_dir"
    trap - RETURN

    log_ok "paru встановлено."
}

install_paru() {
    local packages=("$@")
    ((${#packages[@]})) || return 0

    local missing=()
    local package

    for package in "${packages[@]}"; do
        if package_installed "$package"; then
            log_info "$package вже встановлено."
        else
            missing+=("$package")
        fi
    done

    if ((${#missing[@]} == 0)); then
        log_ok "Усі AUR-пакети вже встановлені."
        return 0
    fi

    install_paru_helper

    echo
    log_step "Встановлення AUR-пакетів:"
    printf '  - %s\n' "${missing[@]}"

    local args=(paru -S --needed)
    [[ "$ASSUME_YES" == true ]] && args+=(--noconfirm)
    args+=("${missing[@]}")

    run_cmd "${args[@]}"
}

# ------------------------------------------------------------
# Status одного пакета.
# ------------------------------------------------------------
print_package_status() {
    local package="$1"

    if package_installed "$package"; then
        printf '  %-34s %b\n' "$package" "${GREEN}INSTALLED${NC}"
        return 0
    fi

    printf '  %-34s %b\n' "$package" "${YELLOW}MISSING${NC}"
    return 1
}
