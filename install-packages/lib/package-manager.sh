#!/usr/bin/env bash

# ============================================================
# РОБОТА З PACMAN, PARU ТА ЗОВНІШНІМИ INSTALL-SCRIPT
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

# ------------------------------------------------------------
# Перевірка та автоматичне встановлення paru.
# makepkg повинен виконуватися від звичайного користувача,
# тому весь installer заборонено запускати від root.
# ------------------------------------------------------------
ensure_paru() {
    if command -v paru >/dev/null 2>&1; then
        return 0
    fi

    echo
    log_step "paru не знайдено. Встановлення paru."

    # Необхідні залежності для складання AUR package.
    install_pacman base-devel git

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] git clone https://aur.archlinux.org/paru.git <tmp>/paru"
        if [[ "$ASSUME_YES" == true ]]; then
            log_info "[DRY-RUN] makepkg -si --noconfirm"
        else
            log_info "[DRY-RUN] makepkg -si"
        fi
        return 0
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)"

    if ! git clone https://aur.archlinux.org/paru.git "$tmp_dir/paru"; then
        rm -rf -- "$tmp_dir"
        log_error "Не вдалося клонувати paru з AUR."
        return 1
    fi

    if ! (
        cd "$tmp_dir/paru"
        local -a makepkg_args=(-si)
        [[ "$ASSUME_YES" == true ]] && makepkg_args+=(--noconfirm)
        makepkg "${makepkg_args[@]}"
    ); then
        rm -rf -- "$tmp_dir"
        log_error "Не вдалося зібрати або встановити paru."
        return 1
    fi

    rm -rf -- "$tmp_dir"

    if ! command -v paru >/dev/null 2>&1; then
        log_error "paru не знайдено після встановлення."
        return 1
    fi

    log_ok "paru встановлено."
}

# Сумісність зі старою назвою функції.
install_paru_helper() {
    ensure_paru
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

    ensure_paru

    echo
    log_step "Встановлення AUR-пакетів:"
    printf '  - %s\n' "${missing[@]}"

    local args=(paru -S --needed)
    [[ "$ASSUME_YES" == true ]] && args+=(--noconfirm)
    args+=("${missing[@]}")

    run_cmd "${args[@]}"
}

# ============================================================
# ЗОВНІШНІ / GITHUB ПАКЕТИ
# ============================================================

# Розгортає ~ на початку шляху.
expand_user_path() {
    local path="$1"

    case "$path" in
        '~')
            printf '%s\n' "$HOME"
            ;;
        '\~/'*)
            printf '%s/%s\n' "$HOME" "${path#~/}"
            ;;
        *)
            printf '%s\n' "$path"
            ;;
    esac
}

# ------------------------------------------------------------
# Розбір GITHUB_PACKAGES.
#
# Формати:
#   script|URL|CHECK_COMMAND
#   git|URL|CHECK_COMMAND|DEST_DIR|EXECUTABLE_REL
#   binary|URL|CHECK_COMMAND|DEST_FILE
# ------------------------------------------------------------
parse_github_package() {
    local package_id="$1"
    local mapping="${GITHUB_PACKAGES[$package_id]-}"

    [[ -n "$mapping" ]] || {
        log_error "Не знайдено GITHUB_PACKAGES[$package_id]."
        return 1
    }

    local type field2 field3 field4 field5 extra
    IFS='|' read -r type field2 field3 field4 field5 extra <<< "$mapping"

    case "$type" in
        script)
            if [[ -z "$field2" || -z "$field3" || -n "${field4:-}" || -n "${field5:-}" || -n "${extra:-}" ]]; then
                log_error "Некоректний script package '$package_id': $mapping"
                return 1
            fi
            ;;
        git)
            if [[ -z "$field2" || -z "$field3" || -z "$field4" || -z "$field5" || -n "${extra:-}" ]]; then
                log_error "Некоректний git package '$package_id': $mapping"
                return 1
            fi
            ;;
        binary)
            if [[ -z "$field2" || -z "$field3" || -z "$field4" || -n "${field5:-}" || -n "${extra:-}" ]]; then
                log_error "Некоректний binary package '$package_id': $mapping"
                return 1
            fi
            ;;
        *)
            log_error "Непідтримуваний TYPE '$type' для '$package_id'."
            return 1
            ;;
    esac

    # CHECK_COMMAND має бути ім'ям команди без /.
    if [[ "$field3" == */* ]]; then
        log_error "CHECK_COMMAND для '$package_id' має бути ім'ям команди, а не шляхом: $field3"
        return 1
    fi

    printf '%s\t%s\t%s\t%s\t%s\n' \
        "$type" "$field2" "$field3" "${field4:-}" "${field5:-}"
}

# Перевіряє, чи зовнішня програма вже доступна в PATH.
github_package_installed() {
    local package_id="$1"
    local parsed type source check_command field4 field5

    parsed="$(parse_github_package "$package_id")" || return 1
    IFS=$'\t' read -r type source check_command field4 field5 <<< "$parsed"

    command -v "$check_command" >/dev/null 2>&1
}

# ------------------------------------------------------------
# TYPE=script
# ------------------------------------------------------------
install_script_package() {
    local package_id="$1"
    local url="$2"
    local check_command="$3"

    if command -v "$check_command" >/dev/null 2>&1; then
        log_info "$package_id вже встановлено."
        return 0
    fi

    command -v curl >/dev/null 2>&1 || install_pacman curl

    echo
    log_step "Встановлення зовнішнього пакета: $package_id"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] bash -c \"\$(curl -fsSL '$url')\""
        return 0
    fi

    bash -c "$(curl -fsSL "$url")"

    if ! command -v "$check_command" >/dev/null 2>&1; then
        log_error "$package_id не знайдено після встановлення (очікувана команда: $check_command)."
        return 1
    fi

    log_ok "$package_id встановлено."
}

# ------------------------------------------------------------
# TYPE=git
#
# Клонує repository у DEST_DIR, а executable з EXECUTABLE_REL
# лінкує у ~/.local/bin/CHECK_COMMAND.
# ------------------------------------------------------------
install_git_package() {
    local package_id="$1"
    local repo_url="$2"
    local check_command="$3"
    local dest_dir_raw="$4"
    local executable_rel="$5"

    if command -v "$check_command" >/dev/null 2>&1; then
        log_info "$package_id вже встановлено."
        return 0
    fi

    command -v git >/dev/null 2>&1 || install_pacman git

    local dest_dir executable link_dir link_path
    dest_dir="$(expand_user_path "$dest_dir_raw")"
    executable="$dest_dir/$executable_rel"
    link_dir="$HOME/.local/bin"
    link_path="$link_dir/$check_command"

    echo
    log_step "Встановлення Git package: $package_id"

    if [[ "$DRY_RUN" == true ]]; then
        if [[ -d "$dest_dir/.git" ]]; then
            log_info "[DRY-RUN] git -C $dest_dir pull --ff-only"
        else
            log_info "[DRY-RUN] git clone $repo_url $dest_dir"
        fi
        log_info "[DRY-RUN] chmod +x $executable"
        log_info "[DRY-RUN] mkdir -p $link_dir"
        log_info "[DRY-RUN] ln -sfn $executable $link_path"
        return 0
    fi

    if [[ -e "$dest_dir" && ! -d "$dest_dir/.git" ]]; then
        log_error "Destination існує, але не є git repository: $dest_dir"
        return 1
    fi

    if [[ -d "$dest_dir/.git" ]]; then
        git -C "$dest_dir" pull --ff-only
    else
        mkdir -p "$(dirname "$dest_dir")"
        git clone "$repo_url" "$dest_dir"
    fi

    if [[ ! -f "$executable" ]]; then
        log_error "Executable не знайдено після git clone: $executable"
        return 1
    fi

    chmod +x "$executable"
    mkdir -p "$link_dir"
    ln -sfn "$executable" "$link_path"

    if ! command -v "$check_command" >/dev/null 2>&1; then
        log_error "$package_id встановлено, але '$check_command' не знайдено у PATH. Перевір ~/.local/bin у PATH."
        return 1
    fi

    log_ok "$package_id встановлено."
}

# ------------------------------------------------------------
# TYPE=binary
#
# Завантажує готовий executable з URL у DEST_FILE.
# Для системного destination (/usr/*, /opt/*) використовує sudo.
# ------------------------------------------------------------
install_binary_package() {
    local package_id="$1"
    local url="$2"
    local check_command="$3"
    local dest_file_raw="$4"

    if command -v "$check_command" >/dev/null 2>&1; then
        log_info "$package_id вже встановлено."
        return 0
    fi

    command -v curl >/dev/null 2>&1 || install_pacman curl

    local dest_file tmp_file
    dest_file="$(expand_user_path "$dest_file_raw")"

    echo
    log_step "Встановлення binary package: $package_id"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] curl -fL --retry 3 -o <tmp> $url"
        if [[ "$dest_file" == /usr/* || "$dest_file" == /opt/* ]]; then
            log_info "[DRY-RUN] sudo install -Dm755 <tmp> $dest_file"
        else
            log_info "[DRY-RUN] install -Dm755 <tmp> $dest_file"
        fi
        return 0
    fi

    tmp_file="$(mktemp)"

    if ! curl -fL --retry 3 -o "$tmp_file" "$url"; then
        rm -f -- "$tmp_file"
        log_error "Не вдалося завантажити binary для '$package_id'."
        return 1
    fi

    if [[ "$dest_file" == /usr/* || "$dest_file" == /opt/* ]]; then
        sudo install -Dm755 "$tmp_file" "$dest_file"
    else
        install -Dm755 "$tmp_file" "$dest_file"
    fi

    rm -f -- "$tmp_file"

    if ! command -v "$check_command" >/dev/null 2>&1; then
        log_error "$package_id встановлено, але '$check_command' не знайдено у PATH."
        return 1
    fi

    log_ok "$package_id встановлено."
}

# Універсальний dispatcher зовнішнього package.
install_github_package() {
    local package_id="$1"
    local parsed type source check_command field4 field5

    parsed="$(parse_github_package "$package_id")" || return 1
    IFS=$'\t' read -r type source check_command field4 field5 <<< "$parsed"

    case "$type" in
        script)
            install_script_package "$package_id" "$source" "$check_command"
            ;;
        git)
            install_git_package "$package_id" "$source" "$check_command" "$field4" "$field5"
            ;;
        binary)
            install_binary_package "$package_id" "$source" "$check_command" "$field4"
            ;;
    esac
}

# ------------------------------------------------------------
# Status одного pacman/AUR пакета.
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

# Status зовнішнього package.
print_github_package_status() {
    local package_id="$1"

    if github_package_installed "$package_id"; then
        printf '  %-34s %b\n' "$package_id" "${GREEN}INSTALLED${NC}"
        return 0
    fi

    printf '  %-34s %b\n' "$package_id" "${YELLOW}MISSING${NC}"
    return 1
}
