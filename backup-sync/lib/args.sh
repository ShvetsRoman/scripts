#!/usr/bin/env bash

print_help() {
    cat <<'EOF'
Backup-Sync V2.6.3

Використання:
  backup-sync.sh up [OPTIONS]
  backup-sync.sh down [OPTIONS]
  backup-sync.sh verify [up|down|both] [OPTIONS]
  backup-sync.sh cleanup
  backup-sync.sh help

Команди:
  up              PC -> SERVER
  down            SERVER -> PC
  verify          Перевірити відповідність без змін
  cleanup         Очистити старі log/recovery (з --dry-run лише показує, що буде видалено)
  help            Показати допомогу

OPTIONS:
  --dry-run        Тестовий запуск без змін
  -y, --yes        Не питати підтвердження
  --host HOST      SSH alias із ~/.ssh/config
  --no-space-check Не перевіряти вільне місце
  --max-delete N   Макс. кількість видалень на каталог (0 = без ліміту; за замовч. MAX_DELETE з конфігу)
  --allow-empty    Дозволити mirror із порожнього джерела (інакше такий каталог пропускається)
  --break-lock     Зняти застарілий remote-lock (лише якщо впевнені, що інший запуск не триває)
  --recovery       Увімкнути recovery для цього запуску (перекриває конфіг)
  --no-recovery    Вимкнути recovery для цього запуску: перезаписані/видалені файли НЕ зберігаються
  --auto-cleanup   Після УСПІШНОГО up/down видалити старі recovery-копії (перевизначає AUTO_CLEANUP_RECOVERY)
  --no-auto-cleanup Не видаляти recovery автоматично (перевизначає AUTO_CLEANUP_RECOVERY=true)
  -h, --help       Допомога

Коди виходу:
  0  успішно
  1  помилка (або є каталоги з помилками)
  2  некоректні аргументи
  3  verify: знайдено відмінності (помилок немає)
  4  операцію скасовано користувачем

Приклади:
  ./backup-sync.sh up --dry-run
  ./backup-sync.sh up -y
  ./backup-sync.sh up --host serv
  ./backup-sync.sh down
  ./backup-sync.sh verify up
  ./backup-sync.sh verify both --host serv
EOF
}

parse_args() {
    if (($# == 0)); then
        COMMAND="help"
        return
    fi

    case "$1" in
        up|down|verify|cleanup|help)
            COMMAND="$1"
            shift
            ;;
        -h|--help)
            COMMAND="help"
            shift
            ;;
        *)
            printf '[ERROR] Невідома команда: %s\n\n' "$1" >&2
            print_help
            exit "$EX_USAGE"
            ;;
    esac

    while (($# > 0)); do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                ASSUME_YES=true
                shift
                ;;
            --host)
                [[ $# -ge 2 ]] || {
                    printf '[ERROR] --host потребує значення\n' >&2
                    exit "$EX_USAGE"
                }
                SSH_HOST="$2"
                shift 2
                ;;
            --no-space-check)
                CHECK_DISK_SPACE=false
                shift
                ;;
            --max-delete)
                [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || {
                    printf '[ERROR] --max-delete потребує невід’ємного цілого числа\n' >&2
                    exit "$EX_USAGE"
                }
                CLI_MAX_DELETE="$2"
                shift 2
                ;;
            --allow-empty)
                CLI_ALLOW_EMPTY=true
                shift
                ;;
            --break-lock)
                BREAK_LOCK=true
                shift
                ;;
            --recovery)
                CLI_RECOVERY=true
                shift
                ;;
            --no-recovery)
                CLI_RECOVERY=false
                shift
                ;;
            --auto-cleanup)
                CLI_AUTO_CLEANUP=true
                shift
                ;;
            --no-auto-cleanup)
                CLI_AUTO_CLEANUP=false
                shift
                ;;
            up|down|both)
                # Напрямок verify — позиційний аргумент, може стояти будь-де серед опцій.
                if [[ "$COMMAND" == verify ]]; then
                    VERIFY_DIRECTION="$1"
                    shift
                else
                    printf '[ERROR] Невідомий аргумент: %s\n' "$1" >&2
                    exit "$EX_USAGE"
                fi
                ;;
            -h|--help)
                COMMAND="help"
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                printf '[ERROR] Невідомий аргумент: %s\n' "$1" >&2
                exit "$EX_USAGE"
                ;;
        esac
    done

    if (($# > 0)); then
        printf '[ERROR] Зайві аргументи: %s\n' "$*" >&2
        exit "$EX_USAGE"
    fi
}

configure_mode() {
    case "$COMMAND" in
        up)
            DIRECTION="up"
            ;;
        down)
            DIRECTION="down"
            ;;
        verify|cleanup|help)
            ;;
        *)
            printf '[ERROR] Некоректна команда: %s\n' "$COMMAND" >&2
            exit "$EX_USAGE"
            ;;
    esac
}
