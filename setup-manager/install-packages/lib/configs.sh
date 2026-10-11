#!/usr/bin/env bash

# ============================================================
# КОПІЮВАННЯ ТА ПЕРЕВІРКА КОНФІГІВ ІЗ DOTFILES-MANAGER
# ============================================================

CURRENT_BACKUP_DIR=""

declare -Ag MODULE_CONFIGS

validate_dotfiles_dir() {
    if [[ ! -d "$DOTFILES_DIR" ]]; then
        log_warn "Каталог dotfiles не знайдено: $DOTFILES_DIR"
        log_warn "Пакети можна встановлювати, але конфіги будуть недоступні."
        return 1
    fi
    return 0
}

# ------------------------------------------------------------
# Автоматично будує MODULE_CONFIGS із CONFIG_MAP.
#
# CONFIG_MAP:
#   [id]="module|scope|source|destination"
#
# Результат:
#   MODULE_CONFIGS[cli]="kitty nvim wezterm"
#   MODULE_CONFIGS[shell]="starship zsh zsh-alias zsh-path"
#
# Асоціативний масив CONFIG_MAP не гарантує порядок ключів,
# тому ID конфігів сортуються для стабільного результату.
# ------------------------------------------------------------
build_module_configs() {
    MODULE_CONFIGS=()

    local module config_id mapping mapped_module scope source_relative target_value extra

    # Кожен відомий модуль отримує запис, навіть якщо конфігів немає.
    for module in "${MODULES[@]}"; do
        MODULE_CONFIGS["$module"]=""
    done

    while IFS= read -r config_id; do
        [[ -n "$config_id" ]] || continue

        mapping="${CONFIG_MAP[$config_id]}"
        IFS='|' read -r mapped_module scope source_relative target_value extra <<< "$mapping"

        if [[ -z "$mapped_module" || -z "$scope" || -z "$source_relative" || -z "$target_value" || -n "${extra:-}" ]]; then
            log_error "Некоректний mapping '$config_id': $mapping"
            return 1
        fi

        module_exists "$mapped_module" || {
            log_error "Config '$config_id' посилається на невідомий модуль '$mapped_module'."
            return 1
        }

        if [[ -n "${MODULE_CONFIGS[$mapped_module]}" ]]; then
            MODULE_CONFIGS["$mapped_module"]+=" $config_id"
        else
            MODULE_CONFIGS["$mapped_module"]="$config_id"
        fi
    done < <(printf '%s\n' "${!CONFIG_MAP[@]}" | sort)
}

# ------------------------------------------------------------
# Валідація CONFIG_MAP.
# ------------------------------------------------------------
validate_config_map() {
    local name mapping module scope source_relative target_value extra

    for name in "${!CONFIG_MAP[@]}"; do
        mapping="${CONFIG_MAP[$name]}"
        IFS='|' read -r module scope source_relative target_value extra <<< "$mapping"

        if [[ -z "$module" || -z "$scope" || -z "$source_relative" || -z "$target_value" || -n "${extra:-}" ]]; then
            log_error "Некоректний mapping '$name': $mapping"
            return 1
        fi

        module_exists "$module" || {
            log_error "Mapping '$name' посилається на невідомий модуль '$module'."
            return 1
        }

        case "$scope" in
            home)
                [[ "$target_value" != /* ]] || {
                    log_error "Home destination повинен бути відносним: $name -> $target_value"
                    return 1
                }
                ;;
            system)
                [[ "$target_value" == /* ]] || {
                    log_error "System destination повинен бути абсолютним: $name -> $target_value"
                    return 1
                }
                ;;
            *)
                log_error "Невідомий scope '$scope' у mapping '$name'."
                return 1
                ;;
        esac

        if [[ "/$source_relative/" == *"/../"* || "/$target_value/" == *"/../"* ]]; then
            log_error "Mapping '$name' містить небезпечний '..': $mapping"
            return 1
        fi
    done
}

ensure_backup_dir() {
    [[ -n "$CURRENT_BACKUP_DIR" ]] && return 0

    local timestamp
    timestamp="$(date '+%Y-%m-%d_%H-%M-%S')"
    CURRENT_BACKUP_DIR="$BACKUP_ROOT/$timestamp"
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Каталог backup: $CURRENT_BACKUP_DIR"
    else
        mkdir -p -- "$CURRENT_BACKUP_DIR"
    fi
}

backup_config() {
    local target="$1"
    local config_label="${2:-$(basename -- "$target")}"
    local relative_path
    local backup_target

    # --no-backup або CONFIG_BACKUP=false повністю вимикає backup.
    [[ "$CONFIG_BACKUP" == true ]] || return 0

    # Якщо конфігу ще немає — backup не потрібен.
    if [[ ! -e "$target" && ! -L "$target" ]]; then
        return 0
    fi

    # --------------------------------------------------------
    # Гарантуємо, що каталог поточного backup вже визначений.
    # --------------------------------------------------------
    ensure_backup_dir


    # --------------------------------------------------------
    # HOME-конфіг.
    # /home/roman/.config/kitty
    # ->
    # backups/<timestamp>/home/.config/kitty
    # --------------------------------------------------------
    if [[ "$target" == "$HOME/"* ]]; then
        relative_path="${target#"$HOME"/}"
        backup_target="$CURRENT_BACKUP_DIR/home/$relative_path"

    # --------------------------------------------------------
    # Системний конфіг.
    # /etc/ssh/sshd_config
    # ->
    # backups/<timestamp>/system/etc/ssh/sshd_config
    # --------------------------------------------------------
    else
        relative_path="${target#/}"
        backup_target="$CURRENT_BACKUP_DIR/system/$relative_path"
    fi

    log_step "Backup конфігу: $config_label"
    log_info "Звідки: $target"
    log_info "Куди:   $backup_target"

    # Одна реалізація захисного backup для всього Setup Manager.
    core_snapshot installer "$target" "$backup_target" "$DRY_RUN"
    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Захисний backup: $config_label буде виконано."
    else
        log_ok "Захисний backup: $config_label виконано."
    fi

}

handle_missing_config() {
    local source="$1"
    local config_label="${2:-$(basename -- "$source")}"

    if [[ "$STRICT_CONFIGS" == true ]]; then
        log_error "Конфіг $config_label не знайдено: $source"
        return 1
    fi

    log_warn "Конфіг $config_label не знайдено, пропускаю: $source"
    return 0
}

# ------------------------------------------------------------
# Повертає module/scope/source/target через TAB.
# ------------------------------------------------------------
parse_config_mapping() {
    local config_name="$1"
    local mapping="${CONFIG_MAP[$config_name]-}"

    [[ -n "$mapping" ]] || {
        log_error "Mapping конфігу не знайдено: $config_name"
        return 1
    }

    local module scope source_relative target_value extra
    IFS='|' read -r module scope source_relative target_value extra <<< "$mapping"

    [[ -z "${extra:-}" ]] || return 1
    printf '%s\t%s\t%s\t%s\n' "$module" "$scope" "$source_relative" "$target_value"
}

resolve_config_target() {
    local scope="$1"
    local target_value="$2"

    case "$scope" in
        home) printf '%s/%s\n' "$HOME" "$target_value" ;;
        system) printf '%s\n' "$target_value" ;;
        *) return 1 ;;
    esac
}

copy_config_path() {
    local scope="$1"
    local source_relative="$2"
    local target_value="$3"
    local config_label="${4:-$(basename -- "$target_value")}"

    local source="$DOTFILES_DIR/$source_relative"
    local target
    target="$(resolve_config_target "$scope" "$target_value")"

    [[ -e "$source" || -L "$source" ]] || {
        handle_missing_config "$source" "$config_label"
        return $?
    }

    # Smart Copy: порівнюємо вміст, а не час зміни чи права файлів.
    # Код 0 — однаково; 1 — є зміни; 2 — помилка порівняння.
    # Якщо ціль відсутня, конфіг потрібно скопіювати без backup.
    local compare_rc=1
    if [[ -e "$target" || -L "$target" ]]; then
        if [[ "$scope" == home ]]; then
            if core_compare "$source" "$target"; then
                compare_rc=0
            else
                compare_rc=$?
            fi
        elif [[ -d "$source" && ! -L "$source" && -d "$target" && ! -L "$target" ]]; then
            # Для system-конфігів потрібні права читання цільового каталогу.
            local system_changes
            if system_changes="$(sudo rsync -a --checksum --delete --dry-run --itemize-changes \
                --no-times --no-perms --no-owner --no-group \
                -- "$source/" "$target/" 2>/dev/null)"; then
                [[ -n "$system_changes" ]] && compare_rc=1 || compare_rc=0
            else
                compare_rc=2
            fi
        elif [[ -f "$source" && -f "$target" ]]; then
            if sudo cmp -s -- "$source" "$target"; then
                compare_rc=0
            else
                # cmp з кодом 2 означає помилку читання.
                compare_rc=$?
                [[ "$compare_rc" == 1 ]] || compare_rc=2
            fi
        else
            compare_rc=1
        fi
    fi

    if (( compare_rc == 0 )); then
        log_info "Конфіг: $config_label вже синхронізовано, пропускаю."
        return 0
    elif (( compare_rc != 1 )); then
        log_error "Не вдалося порівняти конфіг: $config_label ($source -> $target)."
        return 1
    fi

    # Захисний backup створюється лише за наявності реальних змін.
    echo
    backup_config "$target" "$config_label"

    log_step "Копіювання конфігу: $config_label"
    log_info "Звідки: $source"
    log_info "Куди:   $target"

    local rsync_args=(-a)
    [[ "$SYNC_DELETE" == true ]] && rsync_args+=(--delete)

    if [[ "$scope" == home ]]; then
        # core_sync сам створює необхідні каталоги лише за реального запуску.
        # При --dry-run mkdir не потрібен.
        if [[ -d "$source" && ! -L "$source" ]]; then
            core_sync "$source" "$target" "$SYNC_DELETE" "$DRY_RUN"
        else
            core_sync "$source" "$target" false "$DRY_RUN"
        fi
    else
        run_cmd sudo mkdir -p "$(dirname "$target")"

        if [[ -d "$source" && ! -L "$source" ]]; then
            run_cmd sudo mkdir -p "$target"
            run_cmd sudo rsync "${rsync_args[@]}" "$source/" "$target/"
        else
            run_cmd sudo cp -a "$source" "$target"
        fi
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Конфіг: $config_label буде скопійовано."
    else
        log_ok "Конфіг: $config_label скопійовано."
    fi
}

install_mapped_config() {
    local config_name="$1"
    local parsed module scope source_relative target_value

    parsed="$(parse_config_mapping "$config_name")" || {
        log_error "Некоректний mapping для '$config_name'."
        return 1
    }
    IFS=$'\t' read -r module scope source_relative target_value <<< "$parsed"

    copy_config_path "$scope" "$source_relative" "$target_value" "$config_name"
}

install_module_configs() {
    local module="$1"

    [[ "$INSTALL_CONFIGS" == true ]] || {
        log_info "Копіювання конфігів вимкнено: $module"
        return 0
    }

    local config_list="${MODULE_CONFIGS[$module]-}"
    [[ -n "$config_list" ]] || {
        log_info "Для модуля '$module' конфіги не задані."
        return 0
    }

    if [[ ! -d "$DOTFILES_DIR" ]]; then
        [[ "$STRICT_CONFIGS" != true ]] || {
            log_error "Каталог dotfiles не знайдено: $DOTFILES_DIR"
            return 1
        }
        log_warn "Пропускаю конфіги модуля '$module': каталог dotfiles відсутній."
        return 0
    fi

    echo
    log_step "Встановлення конфігів модуля: $module"

    local config_name
    for config_name in $config_list; do
        install_mapped_config "$config_name"
    done
}

config_matches() {
    local config_name="$1"
    local parsed module scope source_relative target_value

    parsed="$(parse_config_mapping "$config_name")" || return 2
    IFS=$'\t' read -r module scope source_relative target_value <<< "$parsed"

    local source="$DOTFILES_DIR/$source_relative"
    local target
    target="$(resolve_config_target "$scope" "$target_value")" || return 2

    [[ -e "$source" || -L "$source" ]] || return 2
    [[ -e "$target" || -L "$target" ]] || return 1

    if [[ -d "$source" && ! -L "$source" ]]; then
        [[ -d "$target" && ! -L "$target" ]] || return 1

        local diff_output
        if [[ "$scope" == system ]]; then
            diff_output="$(sudo rsync -a --checksum --delete --dry-run --itemize-changes --no-times --no-perms --no-owner --no-group -- "$source/" "$target/" 2>/dev/null)" || return 2
        else
            core_compare "$source" "$target"; return $?
        fi
        [[ -z "$diff_output" ]]
    else
        if [[ "$scope" == system ]]; then
            sudo cmp -s -- "$source" "$target"
        else
            core_compare "$source" "$target"
        fi
    fi
}

print_config_status() {
    local config_name="$1"
    local parsed module scope source_relative target_value target

    parsed="$(parse_config_mapping "$config_name")" || return 1
    IFS=$'\t' read -r module scope source_relative target_value <<< "$parsed"
    target="$(resolve_config_target "$scope" "$target_value")"

    if config_matches "$config_name"; then
        printf '  %-20s %-42s %b\n' "$config_name" "$target" "${GREEN}OK${NC}"
        return 0
    fi

    local rc=$?
    if ((rc == 2)); then
        printf '  %-20s %-42s %b\n' "$config_name" "$target" "${RED}SOURCE ERROR${NC}"
    elif [[ -e "$target" || -L "$target" ]]; then
        printf '  %-20s %-42s %b\n' "$config_name" "$target" "${YELLOW}CHANGED${NC}"
    else
        printf '  %-20s %-42s %b\n' "$config_name" "$target" "${YELLOW}MISSING${NC}"
    fi
    return 1
}

verify_module_configs() {
    local module="$1"
    local config_list="${MODULE_CONFIGS[$module]-}"
    [[ -n "$config_list" ]] || return 0

    local failed=0 config_name
    for config_name in $config_list; do
        print_config_status "$config_name" || failed=1
    done
    return "$failed"
}

list_config_mappings() {
    local config_name mapping module scope source_relative target_value

    printf '%-18s %-12s %-8s %-35s %s\n' "ІМ'Я" "МОДУЛЬ" "ТИП" "SOURCE" "DESTINATION"
    printf '%-18s %-12s %-8s %-35s %s\n' "------------------" "------------" "--------" "-----------------------------------" "------------------------------"

    while IFS= read -r config_name; do
        mapping="${CONFIG_MAP[$config_name]}"
        IFS='|' read -r module scope source_relative target_value <<< "$mapping"
        [[ "$scope" == home ]] && target_value="\$HOME/$target_value"
        printf '%-18s %-12s %-8s %-35s %s\n' "$config_name" "$module" "$scope" "$source_relative" "$target_value"
    done < <(printf '%s\n' "${!CONFIG_MAP[@]}" | sort)
}
