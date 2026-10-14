#!/usr/bin/env bash
# Встановлення пакетів.

# pkgs_install — ставить пакети з pacman або AUR.
# Аргументи: $1 — type (pacman|aur); далі — імена пакетів.
# Пропускає вже встановлені, попереджає про відсутні в репо.
pkgs_install() {
    local type="$1"; shift
    local -a requested=("$@")
    ((${#requested[@]})) || { log info "Пакетів $type немає."; return 0; }
    local -a available=() missing=() pkg
    for pkg in "${requested[@]}"; do
        pacman -Qq -- "$pkg" >/dev/null 2>&1 && { log info "$pkg вже є"; continue; }
        if [[ "$type" == pacman ]]; then
            pacman -Si -- "$pkg" >/dev/null 2>&1 && available+=("$pkg") || missing+=("$pkg")
        else
            command -v paru >/dev/null || { log error 'Потрібен paru'; return 1; }
            paru -Si --aur -- "$pkg" >/dev/null 2>&1 && available+=("$pkg") || missing+=("$pkg")
        fi
    done
    for pkg in "${missing[@]}"; do log warn "Не знайдено ($type): $pkg"; done
    ((${#available[@]})) || return 0
    log step "Встановлення $type: ${available[*]}"
    if [[ "${DRY_RUN:-false}" == true ]]; then log info "[DRY-RUN] $type"; return 0; fi
    if [[ "$type" == pacman ]]; then
        sudo pacman -S --needed -- "${available[@]}" || return 1
    else
        paru -S --needed -- "${available[@]}" || return 1
    fi
}

# pkg_run_module — запускає один модуль у підshell.
# Порядок: пакети → configs_apply → hooks.
# Підshell потрібен, щоб модуль не забруднював змінні батька.
pkg_run_module() (
    local id="$1"
    registry_valid "$id" || { log error "Немає: $id"; return 1; }
    hook_collect "$(registry_dir)/$id.sh"

    printf '\n'
    header "Install module: $MODULE_TITLE"

    # ─── Pacman ───────────────────────────────────────────────────────────
    if [[ "${CONFIGS_ONLY:-false}" != true ]]; then
        stage "INFO встановлюються пакети Pacman"
        pkgs_install pacman "${PACMAN_PACKAGES[@]}" || return 1
    fi

    # ─── AUR ──────────────────────────────────────────────────────────────
    if [[ "${CONFIGS_ONLY:-false}" != true ]]; then
        stage "INFO встановлюються пакети AUR"
        pkgs_install aur "${AUR_PACKAGES[@]}" || return 1
    fi

    # ─── GitHub ───────────────────────────────────────────────────────────
    if [[ "${CONFIGS_ONLY:-false}" != true && ${#GITHUB_ITEMS[@]} -gt 0 ]]; then
        stage "INFO встановлюються пакети GitHub"
        local item name kind url cmd
        for item in "${GITHUB_ITEMS[@]}"; do
            IFS='|' read -r name kind url cmd _ <<< "$item"
            if [[ "$kind" != script ]]; then
                log warn "$name: тип $kind"
            elif command -v "$cmd" >/dev/null; then
                log info "$name вже є"
            else
                log warn "$name ($url): сторонні скрипти вимкнено"
            fi
        done
    fi

    # ─── Конфіги ──────────────────────────────────────────────────────────
    if [[ "${NO_CONFIGS:-false}" != true ]]; then
        stage "INFO копіюються конфіги"
        configs_apply "${CONFIG_ITEMS[@]}" || return 1
    fi

    # ─── Hooks ────────────────────────────────────────────────────────────
    if [[ "${CONFIGS_ONLY:-false}" != true ]]; then
        local h
        local -a hlist=()
        for h in $(hooks_list "$id"); do
            hlist+=("$h")
        done

        if ((${#hlist[@]})); then
            stage "INFO обробляється HOOK"
            if [[ "${DRY_RUN:-false}" == true ]]; then
                for h in "${hlist[@]}"; do
                    log info "hook: $h"
                done
            else
                hooks_run "$id" || return 1
            fi
        fi
    fi

    printf '\n'
    log ok "Модуль: $MODULE_TITLE встановлено"
)

# packages_main — вхідна точка Installer.
# Парсить прапорці, збирає список id, запускає кожен.
packages_main() {
    local -a ids=()
    while (($#)); do
        case "$1" in
            --dry-run) DRY_RUN=true; export DRY_RUN ;;
            --yes|-y) SETUP_ASSUME_YES=true; export SETUP_ASSUME_YES ;;
            --no-backup) SETUP_BACKUP_ENABLED=false ;;
            --no-configs) NO_CONFIGS=true ;;
            --configs-only) CONFIGS_ONLY=true ;;
            --sync-delete) SYNC_DELETE=true ;;
            --strict-configs)
                # Значення читає configs_apply() у lib/configs.sh.
                # shellcheck disable=SC2034
                STRICT_CONFIGS=true ;;
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

    ui_clear
    local -a titles=()
    for id in "${ids[@]}"; do
        titles+=("$(registry_title "$id")")
    done
    header "Install: ${titles[*]}"
    for id in "${ids[@]}"; do pkg_run_module "$id" || return 1; done
}

# packages_help — коротка довідка Installer.
packages_help() {
    header 'Installer'
    cat <<'EOT'
./setup.sh installer --list
./setup.sh installer cli shell
./setup.sh installer --dry-run all
./setup.sh installer --configs-only --sync-delete --yes cli
EOT
}
