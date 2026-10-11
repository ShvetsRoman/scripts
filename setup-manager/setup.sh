#!/usr/bin/env bash
# ShellCheck без -x не переходить за source до локальних бібліотек.
# shellcheck disable=SC1091
# ============================================================
# SETUP MANAGER V3.0 — спільне керування двома незалежними системами
# ============================================================
# Не підключаємо бібліотеки підпроєктів через source:
# різні функції та глобальні змінні не конфліктуватимуть.
set -Eeuo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR
readonly INSTALLER="$ROOT_DIR/install-packages/install.sh"
readonly DOTFILES="$ROOT_DIR/dotfiles-manager/dotfiles-manager.sh"
# Спільний файловий API для обох підсистем
source "$ROOT_DIR/lib/core.sh"
# shellcheck source=config/setup.conf
source "$ROOT_DIR/config/setup.conf"

# Єдиний формат кольорів і повідомлень для всіх підсистем.
source "$ROOT_DIR/lib/ui.sh"

# Окремий журнал Setup Manager без ANSI-кодів (Installer має власний журнал).
_setup_log_sink() {
    local level="$1" message="$2"
    if [[ "${SETUP_ENABLE_LOG:-false}" == true ]]; then
        mkdir -p -- "$SETUP_LOG_DIR"
        printf '%s [%s] %s\n' "$(date '+%F %T')" "$level" "$message" >>"$SETUP_LOG_DIR/setup.log"
    fi
}
log() {
    local level="$1"
    shift
    printf '[%s] %s\n' "$level" "$*" >&2
    if ! _setup_log_sink "$level" "$*"; then
        printf '[WARN] Не вдалося записати повідомлення до журналу Setup Manager.\n' >&2
    fi
}

run_installer() { bash "$INSTALLER" "$@"; }
run_dotfiles() { bash "$DOTFILES" "$@"; }

# 90 — внутрішній сигнал повного виходу із вкладеного меню.
# Використовується тільки для інтерактивного меню, не для CLI-команд.
run_nested_menu() {
    local target="$1" rc=0
    SETUP_MENU_CHILD=1 bash "$target" || rc=$?
    if ((rc == 90)); then
        exit 0
    fi
    return "$rc"
}

usage() {
    cat <<'EOF'
Setup Manager V3.0 — допомога

  ./setup.sh                           Головне меню
  ./setup.sh smart                     Smart Setup (інтерактивний майстер)
  ./setup.sh smart --dry-run cli shell  План для заданих модулів без змін
  ./setup.sh doctor                    Діагностика системи й проєкту
  ./setup.sh status [all|packages|dotfiles]  Стан обох підсистем
  ./setup.sh verify [all|packages|dotfiles] Перевірка (невідповідність = код 1)
  ./setup.sh test                      Запуск обох комплектів тестів
  ./setup.sh packages [аргументи]      Передати аргументи інсталятору
  ./setup.sh dotfiles [аргументи]      Передати аргументи Dotfiles Manager
  ./setup.sh backup [changed|шлях]    Backup dotfiles
  ./setup.sh restore [шлях]           Відновити dotfiles
  ./setup.sh diff [шлях]              Порівняти dotfiles
  ./setup.sh archive ...              Керування архівами
  ./setup.sh recovery ...             Керування recovery
  ./setup.sh maintenance              Меню обслуговування
  ./setup.sh --help                    Ця довідка

Приклад: ./setup.sh packages --dry-run cli
У Smart Setup прапорці --dry-run / --yes підтримуються перед або після назви модуля.
Не запускайте setup.sh від root.
EOF
}

# Запустити обидві підсистем навіть якщо одна завершилась помилкою.
# Фінальний код ненульовий, якщо будь-яка перевірка неуспішна.
combined() {
    local action="$1" area="${2:-all}" rc=0
    case "$area" in
        packages | install) run_installer "$action" || return $? ;;
        dotfiles) run_dotfiles "$action" || return $? ;;
        all)
            printf '\n=== INSTALLER: %s ===\n' "$action"
            run_installer "$action" || rc=1
            printf '\n=== DOTFILES: %s ===\n' "$action"
            run_dotfiles "$action" || rc=1
            if ((rc)); then log WARN "${action}: є проблеми в одній або обох підсистемах"; fi
            return "$rc"
            ;;
        *)
            log ERROR "Невідомий компонент: $area"
            return 2
            ;;
    esac
}

# Діагностика нічого не змінює; відсутність pacman поза Arch — попередження.
doctor() {
    local errors=0 warnings=0 cmd
    printf '=== Setup Manager V3.0: Doctor ===\n'
    for cmd in bash rsync diff cmp readlink find flock git tar; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf '[OK] %s\n' "$cmd"
        else
            printf '[FAIL] Не встановлено: %s\n' "$cmd"
            errors=$((errors + 1))
        fi
    done
    for cmd in sudo pacman getent; do
        if command -v "$cmd" >/dev/null 2>&1; then
            printf '[OK] %s\n' "$cmd"
        else
            printf '[WARN] %s (потрібен для встановлення на Arch)\n' "$cmd"
            warnings=$((warnings + 1))
        fi
    done
    if command -v paru >/dev/null 2>&1; then
        printf '[OK] paru (AUR)\n'
    else
        printf '[WARN] paru: AUR-пакети недоступні\n'
        warnings=$((warnings + 1))
    fi
    for cmd in "$INSTALLER" "$DOTFILES" "$ROOT_DIR/lib/core.sh" \
        "$ROOT_DIR/dotfiles-manager/config/dotfiles.conf" \
        "$ROOT_DIR/install-packages/config/installer.conf"; do
        if [[ -f "$cmd" ]]; then
            printf '[OK] %s\n' "${cmd#"$ROOT_DIR"/}"
        else
            printf '[FAIL] Відсутній файл: %s\n' "${cmd#"$ROOT_DIR"/}"
            errors=$((errors + 1))
        fi
    done
    local path count=0
    for path in "$ROOT_DIR"/install-packages/modules/*.sh; do
        [[ -f "$path" ]] || continue
        if ! bash -n "$path"; then
            printf '[FAIL] Bash-синтаксис: %s\n' "$path"
            errors=$((errors + 1))
        fi
        count=$((count + 1))
    done
    if ((count == 0)); then
        printf '[FAIL] Не знайдено модулів інсталятора\n'
        errors=$((errors + 1))
    fi
    if bash -n "$INSTALLER" "$DOTFILES" "$ROOT_DIR/setup.sh"; then
        printf '[OK] Синтаксис точок входу\n'
    else
        errors=$((errors + 1))
    fi
    # ANSI-кольори лише у справжньому терміналі, без кольорових кодів у логах.
    local green='' red='' orange='' reset=''
    if [[ -t 1 && "${NO_COLOR:-}" == "" && "${TERM:-dumb}" != dumb ]]; then
        green=$'\033[32m'
        red=$'\033[31m'
        orange=$'\033[38;5;208m'
        reset=$'\033[0m'
    fi
    # Підсвічуємо цілий показник; нульові помилки й попередження не підсвічуємо.
    local error_color='' warning_color=''
    if ((errors > 0)); then error_color="$red"; fi
    if ((warnings > 0)); then warning_color="$orange"; fi
    printf '\nПідсумок: %sмодулів %d%s, %sпомилок %d%s, %sпопереджень %d%s\n\n' \
        "$green" "$count" "$reset" \
        "$error_color" "$errors" "$reset" \
        "$warning_color" "$warnings" "$reset"
    ((errors == 0))
}

# Не залежить від команд пакункового менеджера; запускає лише тести.
run_tests() {
    local rc=0
    printf '\n=== Тести Setup Manager ===\n'
    bash "$ROOT_DIR/tests/run-tests.sh" || rc=1
    printf '\n=== Тести Installer Packages ===\n'
    bash "$ROOT_DIR/install-packages/tests/run-tests.sh" || rc=1
    printf '\n=== Тести Dotfiles Manager ===\n'
    bash "$ROOT_DIR/dotfiles-manager/tests/run-tests.sh" || rc=1
    return "$rc"
}

# Зчитування модулів тільки за назвами файлів, без source чужого коду.
list_smart_modules() {
    local p
    printf '\nДоступні модулі:\n'
    for p in "$ROOT_DIR"/install-packages/modules/*.sh; do
        [[ -f "$p" ]] || continue
        printf '  %s\n' "${p##*/}"
    done
}
valid_module() {
    local name="$1"
    [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || return 1
    [[ -f "$ROOT_DIR/install-packages/modules/$name.sh" ]]
}
ask_yes() {
    local answer
    read -r -p "$1 [y/N]: " answer || return 1
    [[ "$answer" =~ ^[YyТт]$ ]]
}
smart() {
    local dry=false yes=false no_backup=false token input rc=0
    local -a modules=() args=()
    if (($#)); then
        for token in "$@"; do
            case "$token" in
                --dry-run) dry=true ;;
                --yes | -y) yes=true ;;
                --no-backup) no_backup=true ;;
                --*)
                    log ERROR "Невідомий прапорець Smart Setup: $token"
                    return 2
                    ;;
                *) modules+=("$token") ;;
            esac
        done
    fi
    if ((${#modules[@]} == 0)); then
        if [[ ! -t 0 ]]; then
            log ERROR 'Без інтерактивного термінала вкажіть модулі: smart --dry-run cli shell'
            return 2
        fi
        list_smart_modules
        read -r -p 'Модулі через пробіл (або all): ' input || return 1
        read -r -a modules <<<"$input"
    fi
    ((${#modules[@]} > 0)) || {
        log ERROR 'Не вибрано жодного модуля'
        return 2
    }
    for token in "${modules[@]}"; do
        if [[ "$token" != all ]] && ! valid_module "$token"; then
            log ERROR "Невідомий модуль: $token"
            return 2
        fi
    done
    printf '\n=== SMART SETUP: ПЛАН ===\n'
    printf 'Модулі: %s\n' "${modules[*]}"
    printf 'Копіювання конфігів: із власного реєстру Installer Packages\n'
    if [[ "$no_backup" == true ]]; then
        printf 'Захисні backups Installer: ВИМКНЕНО (--no-backup)\n'
    else
        printf 'Захисні backups Installer: за налаштуванням CONFIG_BACKUP\n'
    fi
    printf 'Dotfiles Manager: незалежний реєстр, додатковий backup за запитом\n'
    if [[ "$dry" == true ]]; then
        printf '\n[DRY-RUN] Лише симуляція встановлення; backup Dotfiles не запускається.\n'
        if [[ "$no_backup" == true ]]; then args+=(--no-backup); fi
        run_installer --dry-run "${args[@]}" "${modules[@]}"
        return $?
    fi
    doctor || {
        log ERROR 'Doctor виявив критичні проблеми'
        return 1
    }
    if [[ "$yes" != true ]]; then
        ask_yes 'Продовжити встановлення?' || {
            printf '\n'
            log INFO 'Скасовано'
            return 0
        }
        printf '\n'
    fi
    if [[ "$yes" == true ]]; then args+=(--yes); fi
    if [[ "$no_backup" == true ]]; then args+=(--no-backup); fi
    run_installer "${args[@]}" "${modules[@]}" || rc=$?
    if ((rc)); then
        log ERROR 'Встановлення не завершено. Додатковий backup пропущено.'
        return "$rc"
    fi
    if [[ "$SETUP_SMART_OFFER_BACKUP" == true && -t 0 ]]; then
        printf '\n'
        log_info 'Додатковий backup синхронізує змінені HOME-конфіги зі сховищем Dotfiles Manager.'
        log_info 'У сховищі можуть бути замінені попередні версії; це не захисний архів.'
        printf '\n'
        if ask_yes 'Синхронізувати змінені конфіги з Dotfiles Manager?'; then
            printf '\n'
            run_dotfiles backup changed || rc=$?
        fi
        printf '\n'
    fi
    printf '\n=== ПІДСУМКОВИЙ STATUS ===\n'
    combined status all || rc=1
    printf '\n=== ПІДСУМКОВИЙ VERIFY ===\n'
    combined verify all || rc=1
    return "$rc"
}

menu() {
    local choice
    while true; do
        print_header 'SETUP MANAGER V3.0'
        cat <<'EOF'
1) Встановлення програм (Installer)
2) Керування Dotfiles
3) Smart Setup — майстер встановлення
4) Status — стан пакетів і dotfiles
5) Verify — перевірка обох систем
6) Doctor — діагностика
7) Maintenance — backup, архіви, recovery
8) Запуск тестів

9) Допомога

0) Назад
00) Вихід

EOF
        read -r -p 'Оберіть дію: ' choice || return 0
        case "$choice" in
            1) run_nested_menu "$INSTALLER" || log WARN 'Інсталятор повернув помилку' ;;
            2) run_nested_menu "$DOTFILES" || log WARN 'Dotfiles Manager повернув помилку' ;;
            3) smart || log WARN 'Smart Setup завершено з помилкою' ;;
            4) combined status all || true ;;
            5) combined verify all || true ;;
            6) doctor || true ;;
            7) maintenance ;;
            8) run_tests || log WARN 'Частина тестів не пройшла' ;;
            9) usage ;;
            0) return 0 ;;
            00) exit 0 ;;
            *) log WARN 'Невідомий пункт меню' ;;
        esac
    done
}
# ============================================================
# MAINTENANCE — окреме обслуговування архівів, recovery і журналів.
# Видалення дозволене лише в каталогах, визначених цим проєктом.
# ============================================================
readonly M_DOTFILES_ARCHIVES="$ROOT_DIR/dotfiles-manager/dotfiles-archive"
readonly M_DOTFILES_RECOVERY="$ROOT_DIR/dotfiles-manager/dotfiles-recovery"
readonly M_INSTALLER_BACKUPS="$ROOT_DIR/install-packages/backups"
readonly M_INSTALLER_LOGS="$ROOT_DIR/install-packages/log"

# Обмежуємо імена об'єктів одним компонентом шляху.
maintenance_valid_name() {
    [[ "$1" =~ ^[a-zA-Z0-9][a-zA-Z0-9._-]*$ && "$1" != *..* ]]
}

maintenance_choose() {
    local kind="$1" directory="$2" entry name
    local -a names=()
    if [[ ! -d "$directory" ]]; then
        printf '[INFO] Каталог відсутній: %s\n' "$directory" >&2
        return 1
    fi
    while IFS= read -r -d '' entry; do
        name="${entry##*/}"
        maintenance_valid_name "$name" || continue
        names+=("$name")
    done < <(if [[ "$kind" == archive ]]; then
        find "$directory" -mindepth 1 -maxdepth 1 -type f -name '*.tar.gz' -print0
    else
        find "$directory" -mindepth 1 -maxdepth 1 -type d -print0
    fi)
    if ((${#names[@]} == 0)); then
        printf "[INFO] Немає доступних об'єктів.\n" >&2
        return 1
    fi
    printf '\nДоступні %s:\n' "$kind" >&2
    printf '  %s\n' "${names[@]}" >&2
    read -r -p 'Введіть точну назву (Enter — скасувати): ' name || return 1
    maintenance_valid_name "$name" || {
        log WARN 'Некоректна назва або скасовано'
        return 1
    }
    if [[ "$kind" == archive ]]; then
        [[ -f "$directory/$name" && ! -L "$directory/$name" ]] || return 1
    else
        [[ -d "$directory/$name" && ! -L "$directory/$name" ]] || return 1
    fi
    printf '%s\n' "$name"
}

maintenance_list_archives() {
    printf '\n=== АРХІВИ DOTFILES ===\n'
    if [[ -d "$M_DOTFILES_ARCHIVES" ]]; then
        find "$M_DOTFILES_ARCHIVES" -mindepth 1 -maxdepth 1 -type f -name '*.tar.gz' -printf '%f (%s байт)\n' | sort -r
    else
        printf 'Архівів немає.\n'
    fi
}

maintenance_restore_archive() {
    local name
    name="$(maintenance_choose archive "$M_DOTFILES_ARCHIVES")" || return 0
    printf '[INFO] Архів: %s/%s\n' "$M_DOTFILES_ARCHIVES" "$name"
    printf '[INFO] Відновлення замінить відповідні файли у сховищі dotfiles.\n'
    # Перед відновленням зберегти поточний вміст сховища як окремий архів.
    ask_yes 'Створити захисний архів поточного сховища перед відновленням?' || return 0
    run_dotfiles archive create || return $?
    run_dotfiles archive restore "$name"
}

maintenance_restore_recovery() {
    local name
    name="$(maintenance_choose recovery "$M_DOTFILES_RECOVERY")" || return 0
    printf '[WARN] Recovery відновить файли у HOME (без видалення сторонніх файлів).\n'
    printf '[INFO] Перед відновленням буде створено окремий захисний recovery HOME.\n'
    ask_yes 'Створити захисну копію HOME перед відновленням?' || return 0
    # Задокументована команда для створення recovery відсутня; використовуємо
    # backup HOME→dotfiles? Ні: це змінило б сховище. Тому нижче використано
    # безпечне явне копіювання лише тих HOME-шляхів, що є в recovery.
    maintenance_protect_home "$M_DOTFILES_RECOVERY/$name" || return $?
    run_dotfiles recovery restore "$name"
}

maintenance_protect_home() {
    local snapshot="$1" entry rel target stamp destination
    local -a entries=()
    local dest_root="$M_DOTFILES_RECOVERY"
    stamp="$(date '+%Y-%m-%d_%H-%M-%S')-before-restore-$$"
    destination="$dest_root/$stamp"
    while IFS= read -r -d '' entry; do
        rel="${entry#"$snapshot"/}"
        target="$HOME/$rel"
        if [[ -e "$target" || -L "$target" ]]; then entries+=("$rel"); fi
    done < <(find "$snapshot" -mindepth 1 -maxdepth 1 -print0)
    mkdir -p -- "$destination"
    for rel in "${entries[@]}"; do
        # cp -a бере права, симлінки й дати без переходу за ними.
        cp -a -- "$HOME/$rel" "$destination/$rel" || return 1
    done
    printf '[OK] Захисна копія HOME: %s\n' "$destination"
}

maintenance_delete_recovery() {
    local name
    name="$(maintenance_choose recovery "$M_DOTFILES_RECOVERY")" || return 0
    printf '[WARN] Буде видалено: %s/%s\n' "$M_DOTFILES_RECOVERY" "$name"
    ask_yes 'Видалити цю recovery-копію?' || return 0
    run_dotfiles recovery delete "$name"
}

maintenance_cleanup_recovery() {
    local limit=5 count=0 entry
    local -a names=()
    [[ -d "$M_DOTFILES_RECOVERY" ]] || {
        printf '[INFO] Recovery відсутні.\n'
        return 0
    }
    while IFS= read -r entry; do names+=("$entry"); done < <(
        find "$M_DOTFILES_RECOVERY" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r
    )
    if ((${#names[@]} <= limit)); then
        printf '[INFO] Очищення не потрібне: %d recovery (ліміт %d).\n' "${#names[@]}" "$limit"
        return 0
    fi
    printf '[WARN] Старі recovery, які буде видалено (залишимо %d новіших):\n' "$limit"
    for ((count = limit; count < ${#names[@]}; count++)); do printf '  %s\n' "${names[$count]}"; done
    ask_yes 'Видалити перелічені recovery?' || return 0
    for ((count = limit; count < ${#names[@]}; count++)); do
        entry="${names[$count]}"
        maintenance_valid_name "$entry" || return 2
        # Не дозволяємо очищення кореня або каталогу поза recovery.
        [[ -n "${M_DOTFILES_RECOVERY:-}" && "$M_DOTFILES_RECOVERY" != / ]] || return 2
        [[ -d "$M_DOTFILES_RECOVERY" && ! -L "$M_DOTFILES_RECOVERY" ]] || return 2
        [[ -d "$M_DOTFILES_RECOVERY/$entry" && ! -L "$M_DOTFILES_RECOVERY/$entry" ]] || return 2
        rm -rf -- "${M_DOTFILES_RECOVERY:?}/$entry" || return 1
    done
    printf '[OK] Старі recovery очищено.\n'
}

# Очищаємо лише записи старші за задану кількість днів.
# Перед rm обов'язково показуємо план; не працюємо з симлінками.
maintenance_cleanup_old() {
    local directory="$1" kind="$2" days="${SETUP_MAINTENANCE_DAYS:-30}" item
    local -a targets=()
    if [[ ! "$days" =~ ^[0-9]+$ ]] || ((days < 1)); then
        log ERROR 'Некоректний строк зберігання'
        return 2
    fi
    [[ -d "$directory" && ! -L "$directory" ]] || {
        printf '[INFO] Каталог відсутній: %s\n' "$directory"
        return 0
    }
    if [[ "$kind" == backups ]]; then
        while IFS= read -r -d '' item; do targets+=("$item"); done < <(
            find "$directory" -mindepth 1 -maxdepth 1 -type d -mtime +"$((days - 1))" -print0
        )
    else
        while IFS= read -r -d '' item; do targets+=("$item"); done < <(
            find "$directory" -mindepth 1 -maxdepth 1 -type f -name '*.log' -mtime +"$((days - 1))" -print0
        )
    fi
    if ((${#targets[@]} == 0)); then
        printf '[INFO] Немає %s старших за %d днів.\n' "$kind" "$days"
        return 0
    fi
    printf '[WARN] Будуть видалені %s старші за %d днів:\n' "$kind" "$days"
    printf '  %s\n' "${targets[@]}"
    ask_yes 'Підтверджуєте видалення?' || return 0
    for item in "${targets[@]}"; do
        [[ "$item" == "$directory/"* && ! -L "$item" ]] || return 2
        if [[ "$kind" == backups ]]; then rm -rf -- "$item"; else rm -f -- "$item"; fi || return 1
    done
    printf '[OK] Очищення завершено.\n'
}

maintenance_disk_usage() {
    printf '\n=== ВИКОРИСТАННЯ ДИСКА ===\n'
    local directory
    for directory in "$M_INSTALLER_BACKUPS" "$M_DOTFILES_ARCHIVES" "$M_DOTFILES_RECOVERY" \
        "$M_INSTALLER_LOGS" "$ROOT_DIR/log" "$ROOT_DIR/dotfiles-manager/dotfiles"; do
        if [[ -d "$directory" ]]; then du -sh -- "$directory"; fi
    done
    df -h -- "$ROOT_DIR"
}

maintenance() {
    local choice
    while true; do
        print_header 'MAINTENANCE'
        cat <<'EOF'
1) Backup усіх dotfiles
2) Backup змінених dotfiles
3) Створити архів dotfiles
4) Переглянути архіви
5) Відновити з архіву
6) Переглянути recovery
7) Відновити з recovery
8) Видалити recovery
9) Очистити старі recovery
10) Очистити старі backups Installer
11) Очистити старі журнали
12) Показати використання диска

0) Назад
00) Вихід

EOF
        read -r -p 'Оберіть дію: ' choice || return 0
        case "$choice" in
            1) run_dotfiles backup || log WARN 'Backup не завершився' ;;
            2) run_dotfiles backup changed || log WARN 'Backup змінених конфігів не завершився' ;;
            3) run_dotfiles archive create || log WARN 'Архів не створено' ;;
            4) maintenance_list_archives ;;
            5) maintenance_restore_archive || log WARN 'Не вдалося відновити архів' ;;
            6) run_dotfiles recovery list || log WARN 'Помилка перегляду recovery' ;;
            7) maintenance_restore_recovery || log WARN 'Не вдалося відновити recovery' ;;
            8) maintenance_delete_recovery || log WARN 'Не вдалося видалити recovery' ;;
            9) maintenance_cleanup_recovery || log WARN 'Не вдалося очистити recovery' ;;
            10) maintenance_cleanup_old "$M_INSTALLER_BACKUPS" backups || log WARN 'Не вдалося очистити backups' ;;
            11)
                maintenance_cleanup_old "$M_INSTALLER_LOGS" logs || log WARN 'Не вдалося очистити журнали Installer'
                maintenance_cleanup_old "$ROOT_DIR/log" logs || log WARN 'Не вдалося очистити журнали Setup Manager'
                ;;
            12) maintenance_disk_usage ;;
            0) return 0 ;;
            00) exit 0 ;;
            *) log WARN 'Невідомий пункт меню' ;;
        esac
    done
}

main() {
    local cmd="${1:-menu}" area
    if (($#)); then shift; fi
    case "$cmd" in
        menu) menu ;;
        maintenance) maintenance ;;
        smart) smart "$@" ;;
        doctor) doctor "$@" ;;
        test | tests) run_tests ;;
        status | verify)
            area="${1:-all}"
            if (($#)); then shift; fi
            (($# == 0)) || {
                log ERROR 'Зайві аргументи'
                return 2
            }
            combined "$cmd" "$area"
            ;;
        install | packages) run_installer "$@" ;;
        dotfiles) run_dotfiles "$@" ;;
        backup | restore | diff | archive | recovery | clean | clean-all | config) run_dotfiles "$cmd" "$@" ;;
        help | -h | --help) usage ;;
        *)
            log ERROR "Невідома команда: $cmd"
            usage >&2
            return 2
            ;;
    esac
}
main "$@"
