#!/usr/bin/env bash

# ============================================================
# ДИНАМІЧНЕ МЕНЮ, CLI ТА ЗАЛЕЖНОСТІ МОДУЛІВ
# ============================================================
#
# У V1.6 меню формується автоматично з MODULES і MODULE_TITLES.
# Додавати case-пункти для нового модуля більше не потрібно.
# ============================================================

REQUESTED_MODULES=()
RESOLVED_MODULES=()
COMMAND="install"

declare -Ag _RESOLVE_VISITING=()
declare -Ag _RESOLVE_DONE=()

show_help() {
    cat <<'HELP'
Installer Packages V1.6

ПРИЗНАЧЕННЯ
  Модульний installer для Arch Linux:
  - pacman-пакети;
  - AUR-пакети через paru;
  - зовнішні install-script/GitHub пакети;
  - копіювання конфігів із ../dotfiles-manager/dotfiles;
  - backup конфігів;
  - systemd-сервіси та post-install hooks;
  - Status / Verify;
  - очищення backups та logs.

ВИКОРИСТАННЯ
  ./install.sh
      Відкрити інтерактивне меню.

  ./install.sh <module> [module...]
      Встановити один або декілька модулів.

  ./install.sh all
      Встановити всі модулі.

  ./install.sh status [module...|all]
      Показати детальний поточний стан пакетів, конфігів і сервісів.

  ./install.sh verify [module...|all]
      Строго перевірити очікуваний стан.
      Exit code 1 означає, що знайдено невідповідності.

ОПЦІЇ
  --list
      Показати доступні модулі та їх залежності.

  --list-configs
      Показати mapping конфігів source -> destination.

  --dry-run
      Нічого не змінювати, лише показати майбутні дії.

  --yes, -y
      Автоматично підтверджувати операції.

  --no-configs
      Встановити пакети/сервіси, але не копіювати конфігурації.

  --configs-only
      Копіювати лише конфіги без пакетів, сервісів і post-hooks.

  --no-backup
      Не створювати backup існуючих конфігів.

  --strict-configs
      Вважати відсутній source-конфіг помилкою.

  --sync-delete
      Для каталогів використовувати rsync --delete.
      У destination будуть видалені файли, яких немає у source.

  --no-deps
      Не встановлювати залежності модулів автоматично.

  --help, -h, help
      Показати цю довідку.

ПРИКЛАДИ
  ./install.sh cli
  ./install.sh cli shell dev
  ./install.sh all
  ./install.sh --dry-run all
  ./install.sh --yes desktop
  ./install.sh --configs-only cli shell
  ./install.sh --no-configs docker
  ./install.sh status all
  ./install.sh status network
  ./install.sh verify cli shell
  ./install.sh --list
  ./install.sh --list-configs

ДЕ ЩО НАЛАШТОВУЄТЬСЯ
  config/packages.conf
      Списки pacman/AUR пакетів і адреси зовнішніх install-script.

  config/modules.conf
      Прив'язка package-масивів до модулів, dependencies,
      systemd services та post-install hooks.

  config/configs.conf
      Mapping конфігів:
      [ID]="MODULE|SCOPE|SOURCE|DESTINATION"

  modules/<module>.sh
      Мінімальний wrapper модуля та, за потреби, спеціальні hooks.

ДОДАВАННЯ PACMAN-ПАКЕТА
  Додати пакет у потрібний масив config/packages.conf, наприклад:

    CLI_PACKAGES=(
        bat
        eza
        my-package
    )

ДОДАВАННЯ AUR-ПАКЕТА
  Додати пакет у AUR-масив:

    DESKTOP_AUR_PACKAGES=(
        google-chrome
        my-aur-package
    )

  paru перевіряється автоматично. Якщо paru відсутній,
  installer встановить base-devel + git, збере paru з AUR,
  а потім продовжить встановлення.

ДОДАВАННЯ ЗОВНІШНЬОЇ / GITHUB-ПРОГРАМИ
  1. Додати ID до масиву модуля:

    CLI_GITHUB_PACKAGES=(
        superfile
        my-git-tool
        my-binary
    )

  2. Додати запис у GITHUB_PACKAGES.

  TYPE=script:

    [superfile]="script|https://superfile.dev/install.sh|spf"

    Формат:
      ID="script|URL|CHECK_COMMAND"

  TYPE=git:

    [my-git-tool]="git|https://github.com/user/repo.git|mytool|~/.local/share/mytool|bin/mytool"

    Формат:
      ID="git|REPOSITORY_URL|CHECK_COMMAND|DEST_DIR|EXECUTABLE_REL"

    Installer clone/pull repository і створить symlink:
      ~/.local/bin/CHECK_COMMAND -> DEST_DIR/EXECUTABLE_REL

  TYPE=binary:

    [my-binary]="binary|https://github.com/user/repo/releases/download/v1.0/mytool|mytool|~/.local/bin/mytool"

    Формат:
      ID="binary|BINARY_URL|CHECK_COMMAND|DEST_FILE"

    Installer завантажить executable та встановить права 755.
    Для /usr/* та /opt/* автоматично використовується sudo.

  CHECK_COMMAND використовується для Install/Status/Verify.

ДОДАВАННЯ КОНФІГУ
  config/configs.conf:

    [superfile]="cli|home|.config/superfile|.config/superfile"

  Це означає:
    source:      ../dotfiles-manager/dotfiles/.config/superfile
    destination: ~/.config/superfile

ДОДАВАННЯ SYSTEMD-СЕРВІСУ
  config/modules.conf:

    MODULE_SERVICES[network]="sshd"

  Installer виконає:
    sudo systemctl enable --now sshd

ОБСЛУГОВУВАННЯ
  Через пункт "Обслуговування" доступно:
  1) Видалити всі backups
  2) Залишити останні 3 backups
  3) Видалити backups старші за 30 днів
  4) Видалити всі logs
  5) Залишити останні 10 logs
  6) Видалити logs старші за 30 днів

BACKUP
  Backup створюється у:
    installer-packages/backups/YYYY-MM-DD_HH-MM-SS/

LOG
  Logs створюються у:
    installer-packages/log/

ВАЖЛИВО
  Не запускай installer через sudo:
    ./install.sh ...

  sudo викликається всередині installer тільки там, де потрібні
  системні права.
HELP

    echo
    echo "Доступні модулі:"
    list_modules
}

module_exists() {
    local candidate="$1" module
    for module in "${MODULES[@]}"; do
        [[ "$candidate" == "$module" ]] && return 0
    done
    return 1
}

list_modules() {
    local module deps i=1
    printf '%-4s %-16s %-16s %s\n'  "№"       "МОДУЛЬ"            "НАЗВА"                "ЗАЛЕЖНОСТІ"
    printf '%-4s %-16s %-16s %s\n' "---" "----------------" "----------------" "------------------------------"

    for module in "${MODULES[@]}"; do
        deps="${MODULE_DEPENDENCIES[$module]-}"
        printf '%-4d %-16s %-16s %s\n' \
            "$i" "$module" "${MODULE_TITLES[$module]:-$module}" "${deps:--}"
        ((i += 1))
    done
}

add_requested_module() {
    local candidate="$1" existing
    for existing in "${REQUESTED_MODULES[@]}"; do
        [[ "$existing" == "$candidate" ]] && return 0
    done
    REQUESTED_MODULES+=("$candidate")
}

# shellcheck disable=SC2034
parse_arguments() {
    while (($#)); do
        case "$1" in
            status|verify)
                COMMAND="$1"
                ;;
            --dry-run) DRY_RUN=true ;;
            --yes|-y) ASSUME_YES=true ;;
            --no-configs) INSTALL_CONFIGS=false ;;
            --configs-only)
                CONFIGS_ONLY=true
                INSTALL_CONFIGS=true
                ;;
            --no-backup) CONFIG_BACKUP=false ;;
            --strict-configs) STRICT_CONFIGS=true ;;
            --sync-delete) SYNC_DELETE=true ;;
            --no-deps) INSTALL_DEPENDENCIES=false ;;
            --list)
                list_modules
                exit 0
                ;;
            --list-configs)
                list_config_mappings
                exit 0
                ;;
            --help|-h|help)
                show_help
                exit 0
                ;;
            all)
                REQUESTED_MODULES=("${MODULES[@]}")
                ;;
            --*)
                log_error "Невідома опція: $1"
                exit 1
                ;;
            *)
                module_exists "$1" || {
                    log_error "Невідомий модуль: $1"
                    exit 1
                }
                add_requested_module "$1"
                ;;
        esac
        shift
    done

    # status/verify без списку модулів перевіряє все.
    if [[ "$COMMAND" != install && ${#REQUESTED_MODULES[@]} -eq 0 ]]; then
        REQUESTED_MODULES=("${MODULES[@]}")
    fi
}

resolve_module_recursive() {
    local module="$1" dep

    [[ -n "${_RESOLVE_DONE[$module]-}" ]] && return 0
    [[ -z "${_RESOLVE_VISITING[$module]-}" ]] || {
        log_error "Циклічна залежність модулів біля: $module"
        return 1
    }

    _RESOLVE_VISITING[$module]=1

    if [[ "$INSTALL_DEPENDENCIES" == true ]]; then
        for dep in ${MODULE_DEPENDENCIES[$module]-}; do
            module_exists "$dep" || {
                log_error "Модуль '$module' залежить від невідомого модуля '$dep'."
                return 1
            }
            resolve_module_recursive "$dep"
        done
    fi

    unset '_RESOLVE_VISITING[$module]'
    _RESOLVE_DONE[$module]=1
    RESOLVED_MODULES+=("$module")
}

resolve_requested_modules() {
    RESOLVED_MODULES=()
    _RESOLVE_VISITING=()
    _RESOLVE_DONE=()

    local module
    for module in "${REQUESTED_MODULES[@]}"; do
        resolve_module_recursive "$module"
    done
}

run_module() {
    local module="$1"
    local file="$ROOT_DIR/modules/$module.sh"

    [[ -f "$file" ]] || {
        log_error "Файл модуля не знайдено: $file"
        return 1
    }

    echo
    log_step "Запуск модуля: $module"

    # shellcheck source=/dev/null
    source "$file"

    declare -F install_module >/dev/null 2>&1 || {
        log_error "Модуль $module не містить функцію install_module()."
        return 1
    }

    install_module
    unset -f install_module
    echo
    log_ok "Модуль завершено: $module"
}

run_requested_modules() {
    resolve_requested_modules

    if [[ "$INSTALL_DEPENDENCIES" == true ]]; then
        echo
        log_info "Порядок виконання: ${RESOLVED_MODULES[*]}"
    fi

    local module
    for module in "${RESOLVED_MODULES[@]}"; do
        run_module "$module"
    done
}

run_status_command() {
    status_modules "${REQUESTED_MODULES[@]}"
}

run_verify_command() {
    verify_modules "${REQUESTED_MODULES[@]}"
}

# Динамічний вибір декількох модулів.
multi_select() {
    echo
    echo "Введи номери модулів через пробіл:"

    local i=1 module
    for module in "${MODULES[@]}"; do
        printf '  %d) %s\n' "$i" "${MODULE_TITLES[$module]:-$module}"
        ((i += 1))
    done
    echo

    local input=() item index
    read -r -a input
    REQUESTED_MODULES=()

    for item in "${input[@]}"; do
        [[ "$item" =~ ^[0-9]+$ ]] || {
            log_warn "Невідомий пункт: $item"
            continue
        }

        index=$((item - 1))
        if ((index < 0 || index >= ${#MODULES[@]})); then
            log_warn "Невідомий пункт: $item"
            continue
        fi

        add_requested_module "${MODULES[$index]}"
    done

    ((${#REQUESTED_MODULES[@]})) && run_requested_modules
}

# Друкує меню та повертає номери службових пунктів через глобальні
# змінні MENU_*; усі номери залежать від кількості MODULES.
render_main_menu() {
    local i=1 module

    for module in "${MODULES[@]}"; do
        printf ' %2d) %s\n' "$i" "${MODULE_TITLES[$module]:-$module}"
        ((i += 1))
    done

    MENU_INSTALL_ALL=$i
    MENU_MULTI=$((i + 1))
    MENU_STATUS=$((i + 2))
    MENU_VERIFY=$((i + 3))
    MENU_CONFIGS=$((i + 4))
    MENU_DEPS=$((i + 5))
    MENU_CLEANUP=$((i + 6))
    MENU_HELP=$((i + 7))

    echo
    printf ' %2d) Встановити всі модулі\n' "$MENU_INSTALL_ALL"
    printf ' %2d) Вибрати декілька модулів\n' "$MENU_MULTI"
    printf ' %2d) Status — детальний стан усіх модулів\n' "$MENU_STATUS"
    printf ' %2d) Verify — строга перевірка всіх модулів\n' "$MENU_VERIFY"
    printf ' %2d) Показати mapping конфігів\n' "$MENU_CONFIGS"
    printf ' %2d) Показати залежності модулів\n' "$MENU_DEPS"
    echo
    printf ' %2d) Обслуговування\n' "$MENU_CLEANUP"
    printf ' %2d) Допомога\n' "$MENU_HELP"
    echo
    echo "  0) Вихід"
    echo
}

show_main_menu() {
    while true; do
        clear
        print_header "INSTALLER PACKAGES V1.6"
        render_main_menu

        local choice
        read -r -p "Вибір: " choice

        # Пункти модулів обробляються без окремого case.
        if [[ "$choice" =~ ^[0-9]+$ ]] && \
           ((choice >= 1 && choice <= ${#MODULES[@]})); then
            REQUESTED_MODULES=("${MODULES[$((choice - 1))]}")
            run_requested_modules
            pause
            continue
        fi

        case "$choice" in
            "$MENU_INSTALL_ALL")
                if confirm "Встановити всі модулі?"; then
                    REQUESTED_MODULES=("${MODULES[@]}")
                    run_requested_modules
                fi
                pause
                ;;
            "$MENU_MULTI")
                multi_select
                pause
                ;;
            "$MENU_STATUS")
                status_modules "${MODULES[@]}"
                pause
                ;;
            "$MENU_VERIFY")
                verify_modules "${MODULES[@]}" || true
                pause
                ;;
            "$MENU_CONFIGS")
                list_config_mappings
                pause
                ;;
            "$MENU_DEPS")
                list_modules
                pause
                ;;
            "$MENU_CLEANUP")
                maintenance_menu
                ;;
            "$MENU_HELP")
                show_help
                pause
                ;;
            0)
                log_info "Завершення роботи."
                exit 0
                ;;
            *)
                log_error "Невірний вибір."
                pause
                ;;
        esac
    done
}

maintenance_menu() {
    local choice

    while true; do
        clear

        echo "============================================"
        echo " ОБСЛУГОВУВАННЯ"
        echo "============================================"
        echo
        echo "  1) Видалити всі backups"
        echo "  2) Залишити останні 3 backups"
        echo "  3) Видалити backups старші за 30 днів"
        echo
        echo "  4) Видалити всі logs"
        echo "  5) Залишити останні 10 logs"
        echo "  6) Видалити logs старші за 30 днів"
        echo
        echo "  0) Назад"
        echo

        read -rp "Вибір: " choice

        case "$choice" in
            1)
                cleanup_all_backups
                pause
                ;;

            2)
                cleanup_keep_last_backups
                pause
                ;;

            3)
                cleanup_old_backups
                pause
                ;;

            4)
                cleanup_all_logs
                pause
                ;;

            5)
                cleanup_keep_last_logs
                pause
                ;;

            6)
                cleanup_old_logs
                pause
                ;;

            0)
                return 0
                ;;

            *)
                log_error "Невірний вибір."
                pause
                ;;
        esac
    done
}
