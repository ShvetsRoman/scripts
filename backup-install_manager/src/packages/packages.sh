#!/usr/bin/env bash
# Встановлення пакетів.

# pkgs_install — ставить пакети з pacman або AUR.
# Аргументи: $1 — type (pacman|aur); далі — імена пакетів.
# Пропускає вже встановлені, попереджає про відсутні в репо.
pkgs_install() {
    local type="$1"; shift
    local -a requested=("$@")
    ((${#requested[@]})) || { log info "Пакетів $type немає."; return 0; }
    if [[ "$type" != pacman && "$type" != aur ]]; then
        log error "Невідомий тип пакетів: $type"
        return 2
    fi
    if [[ "${DRY_RUN:-false}" == true ]]; then
        log info "[DRY-RUN] $type: ${requested[*]}"
        return 0
    fi
    local -a available=() missing=() pending=() installed=()
    local pkg installed_output
    local -A is_installed=()
    # Один запит замість pacman -Qq для кожного пакета.
    if ! installed_output="$(pacman -Qq)"; then
        log error 'Не вдалося прочитати список встановлених пакетів'
        return 1
    fi
    if [[ -n "$installed_output" ]]; then
        mapfile -t installed <<< "$installed_output"
    fi
    for pkg in "${installed[@]}"; do is_installed["$pkg"]=1; done
    for pkg in "${requested[@]}"; do
        if [[ -v is_installed["$pkg"] ]]; then
            log info "$pkg вже є"
        else
            pending+=("$pkg")
        fi
    done
    ((${#pending[@]})) || return 0
    if [[ "$type" == aur ]]; then
        command -v paru >/dev/null 2>&1 || { log error 'Потрібен paru'; return 1; }
    elif [[ "$type" != pacman ]]; then
        log error "Невідомий тип пакетів: $type"
        return 2
    fi
    # Швидкий шлях: один запит метаданих для всіх пакетів.
    # Якщо пакет недоступний, уточнюємо поіменно лише для діагностики.
    if [[ "$type" == pacman ]]; then
        if pacman -Si -- "${pending[@]}" >/dev/null 2>&1; then
            available=("${pending[@]}")
        else
            for pkg in "${pending[@]}"; do
                if pacman -Si -- "$pkg" >/dev/null 2>&1; then
                    available+=("$pkg")
                else
                    missing+=("$pkg")
                fi
            done
        fi
    else
        if paru -Si --aur -- "${pending[@]}" >/dev/null 2>&1; then
            available=("${pending[@]}")
        else
            for pkg in "${pending[@]}"; do
                if paru -Si --aur -- "$pkg" >/dev/null 2>&1; then
                    available+=("$pkg")
                else
                    missing+=("$pkg")
                fi
            done
        fi
    fi
    if ((${#missing[@]})); then
        for pkg in "${missing[@]}"; do log error "Не знайдено ($type): $pkg"; done
        # Не запускаємо навіть доступні пакети: група має бути повною.
        return 1
    fi
    ((${#available[@]})) || return 0
    log step "Встановлення $type: ${available[*]}"
    if [[ "${DRY_RUN:-false}" == true ]]; then log info "[DRY-RUN] $type"; return 0; fi
    if [[ "$type" == pacman ]]; then
        local -a pacman_flags=(-S --needed)
        [[ "${SETUP_ASSUME_YES:-false}" == true ]] && pacman_flags+=(--noconfirm)
        sudo pacman "${pacman_flags[@]}" -- "${available[@]}" || return 1
    else
        local -a paru_flags=(-S --needed)
        [[ "${SETUP_ASSUME_YES:-false}" == true ]] && paru_flags+=(--noconfirm)
        paru "${paru_flags[@]}" -- "${available[@]}" || return 1
    fi
}

# Застосувати лише ще не оброблені конфігурації поточного модуля.
# applied_configs належить pkg_run_module і доступний через динамічну область Bash.
pkg_configs_apply_once() {
    local name
    local -a fresh=()
    for name in "$@"; do
        if [[ ! -v applied_configs["$name"] ]]; then
            fresh+=("$name")
            applied_configs["$name"]=1
        fi
    done
    ((${#fresh[@]})) || return 0
    configs_apply "${fresh[@]}"
}

# Прив'язка до пакета зберігає вихідний порядок конфігів.
pkg_configs_apply_bound() {
    local module="$1" pkg="$2"
    local -a entries=()
    read -r -a entries <<< "${PACKAGE_BOUND_CONFIGS["$module|$pkg"]:-}"
    pkg_configs_apply_once "${entries[@]}"
}

# pkg_run_module — запускає один модуль у підshell.
# Порядок: пакети → configs_apply → hooks.
# Підshell потрібен, щоб модуль не забруднював змінні батька.
pkg_run_module() (
    local id="$1"
    registry_valid "$id" || { log error "Немає: $id"; return 1; }
    # Старі тести ізольовано підключають packages.sh без завантаження INI.
    if ! declare -p PACKAGE_BOUND_CONFIGS >/dev/null 2>&1; then
        declare -A PACKAGE_BOUND_CONFIGS=()
    fi
    if ! declare -p PACKAGE_CONFIGS_GROUP >/dev/null 2>&1; then
        declare -A PACKAGE_CONFIGS_GROUP=()
    fi
    packages_select "$id" || return 2
    hooks_validate "$id" || return 2
    MODULE_TITLE="$(registry_title "$id")"

    printf '\n'
    header "Install module: $MODULE_TITLE"

    local type pkg bound name
    local -a skipped_packages=() skipped_hooks=() skipped_configs=() successful_packages=()
    local -A failed_configs_for_package=() applied_configs=()
    local -a list=()
    # Лише у межах цієї операції: без глобального кешу між командами.
    local PKG_DOTFILES_LOADED="${PKG_DOTFILES_LOADED:-false}"
    # Обробляємо кожен пакет окремо, не зупиняючись на його помилці.
    if [[ "${CONFIGS_ONLY:-false}" != true ]]; then
        for type in pacman aur; do
            if [[ "$type" == pacman ]]; then list=("${PACMAN_PACKAGES[@]}"); else list=("${AUR_PACKAGES[@]}"); fi
            ((${#list[@]})) || continue
            stage "INFO встановлюються пакети $type"
            for pkg in "${list[@]}"; do
                bound="${PACKAGE_BOUND_HOOKS["$id|$pkg"]:-}"
                if pkgs_install "$type" "$pkg"; then
                    successful_packages+=("$pkg")
                else
                    log warn "$pkg — помилка встановлення, пропущено"
                    skipped_packages+=("$pkg")
                    if [[ -n "${PACKAGE_BOUND_CONFIGS["$id|$pkg"]:-}" ]]; then
                        local -a missed=()
                        read -r -a missed <<< "${PACKAGE_BOUND_CONFIGS["$id|$pkg"]}"
                        skipped_configs+=("${missed[@]}")
                        for name in "${missed[@]}"; do
                            log info "[SKIP] Конфіг $name для пакета $pkg — пропущено"
                        done
                    fi
                    if [[ -n "$bound" ]]; then
                        log info "[SKIP] Hook $bound для пакета $pkg — пропущено"
                        skipped_hooks+=("$bound (пакет: $pkg)")
                    fi
                fi
            done
        done
    fi

    if [[ "${NO_CONFIGS:-false}" != true ]]; then
        stage "INFO копіюються конфіги"
        # Група застосовується лише за явним configs_group у packages.conf.
        local configs_group="${PACKAGE_CONFIGS_GROUP[$id]:-}"
        if [[ -n "$configs_group" ]]; then
            if [[ "$PKG_DOTFILES_LOADED" != true ]]; then
                sources_load || return 2
                PKG_DOTFILES_LOADED=true
            fi
            local -a group_entries=()
            local group_row
            for group_row in "${SRC_ROWS[@]}"; do
                sources_parse "$group_row" || return 2
                if [[ "${DOTFILES_ITEM_GROUP[$S_NAME]:-}" == "$configs_group" ]]; then
                    group_entries+=("$S_NAME")
                fi
            done
            ((${#group_entries[@]})) || { log error "Порожня або невідома група конфігів: $configs_group"; return 2; }
            pkg_configs_apply_once "${group_entries[@]}" || return 1
        fi
        # Порожнє загальне поле configs не означає відсутність
        # прив'язаних конфігурацій config.<package>.
        if ((${#CONFIG_ITEMS[@]})); then
            pkg_configs_apply_once "${CONFIG_ITEMS[@]}" || return 1
        fi
        if [[ "${CONFIGS_ONLY:-false}" == true ]]; then
            for type in pacman aur; do
                if [[ "$type" == pacman ]]; then list=("${PACMAN_PACKAGES[@]}"); else list=("${AUR_PACKAGES[@]}"); fi
                for pkg in "${list[@]}"; do
                    pkg_configs_apply_bound "$id" "$pkg" || return 1
                done
            done
        else
            for pkg in "${successful_packages[@]}"; do
                local -a bound_configs=()
                read -r -a bound_configs <<< "${PACKAGE_BOUND_CONFIGS["$id|$pkg"]:-}"
                if ((${#bound_configs[@]})) && ! pkg_configs_apply_bound "$id" "$pkg"; then
                    log warn "Конфігурації пакета $pkg не застосовано"
                    failed_configs_for_package["$pkg"]=1
                    skipped_configs+=("${bound_configs[@]}")
                    bound="${PACKAGE_BOUND_HOOKS["$id|$pkg"]:-}"
                    if [[ -n "$bound" ]]; then
                        log info "[SKIP] Hook $bound для пакета $pkg — помилка конфігурації"
                        skipped_hooks+=("$bound (пакет: $pkg; помилка конфігурації)")
                    fi
                fi
            done
        fi
    fi

    # Загальні hooks виконуються перед прив'язаними за новим порядком.
    if [[ "${CONFIGS_ONLY:-false}" != true && -n "${PACKAGE_HOOKS[$id]:-}" ]]; then
        stage "INFO обробляються HOOKS"
        hooks_run "$id" || return 1
    fi

    # Прив'язані hooks — після конфігурацій та загальних hooks.
    if [[ "${CONFIGS_ONLY:-false}" != true ]]; then
        for pkg in "${successful_packages[@]}"; do
            [[ ! -v failed_configs_for_package["$pkg"] ]] || continue
            bound="${PACKAGE_BOUND_HOOKS["$id|$pkg"]:-}"
            if [[ -n "$bound" ]]; then
                hooks_run_bound "$bound" "$pkg" || return 1
            fi
        done
    fi

    printf '\n'
    if ((${#skipped_packages[@]} || ${#skipped_configs[@]})); then
        log warn "$MODULE_TITLE: частковий успіх"
        if ((${#skipped_packages[@]})); then
            log warn "Пропущені пакети (${#skipped_packages[@]}):"
            for pkg in "${skipped_packages[@]}"; do printf '       - %s\n' "$pkg"; done
        fi
        if ((${#skipped_configs[@]})); then
            log warn "Пропущені конфіги (${#skipped_configs[@]}):"
            for name in "${skipped_configs[@]}"; do printf '       - %s\n' "$name"; done
        fi
        if ((${#skipped_hooks[@]})); then
            log warn "Пропущені hooks (${#skipped_hooks[@]}):"
            for name in "${skipped_hooks[@]}"; do printf '       - %s\n' "$name"; done
        fi
    else
        log ok "Модуль: $MODULE_TITLE встановлено"
    fi
)

# packages_main — вхідна точка Installer.
# Приймає вже розібрані CLI аргументи, збирає id та запускає модулі.
packages_main() {
    local -a ids=()
    while (($#)); do
        case "$1" in
            --list|list) registry_show; return 0 ;;
            --help|-h|help) packages_help; return 0 ;;
            all) mapfile -t ids < <(registry_ids) ;;
            --*) log error "Параметр: $1"; return 2 ;;
            *) ids+=("$1") ;;
        esac
        shift
    done
    if [[ "${SYNC_DELETE:-false}" == true && "${SETUP_BACKUP_ENABLED:-true}" != true ]]; then
        log error '--sync-delete потребує backup'; return 2
    fi
    ((${#ids[@]})) || { packages_help; return 2; }
    local id
    for id in "${ids[@]}"; do registry_valid "$id" || { log error "Немає: $id"; return 2; }; done
    # Перевіряємо всі посилання та дублікати до будь-якої зміни системи.
    sources_load || return 2
    packages_validate_references || return 2
    # Динамічна область видимості Bash: тільки на час packages_main().
    # Наступний запуск команди перечитає змінений dotfiles.conf.
    local PKG_DOTFILES_LOADED=true

    ui_clear
    local -a titles=()
    for id in "${ids[@]}"; do
        titles+=("$(registry_title "$id")")
    done
    header "Install: ${titles[*]}"
    for id in "${ids[@]}"; do pkg_run_module "$id" || return 1; done
}

# packages_help — коротка довідка Packages.
packages_help() {
    header 'Packages'
    cat <<'EOT'
./backup-install_manager.sh packages --list
./backup-install_manager.sh packages cli shell
./backup-install_manager.sh packages --dry-run all
./backup-install_manager.sh packages --configs-only --sync-delete --yes cli
# packages.conf: configs_group = font; hooks = docker; hook.zsh = shell
# Порядок: пакети → група → конфіги → загальні hooks → прив’язані hooks
EOT
}
