#!/usr/bin/env bash

print_help() {
    cat <<'EOF'
Backup-Sync V2.0

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
  cleanup         Очистити старі log/recovery
  help            Показати допомогу

OPTIONS:
  --dry-run        Тестовий запуск без змін
  -y, --yes        Не питати підтвердження
  --host HOST      SSH alias із ~/.ssh/config
  --no-space-check Не перевіряти вільне місце
  -h, --help       Допомога

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
            exit 2
            ;;
    esac

    if [[ "$COMMAND" == verify && $# -gt 0 ]]; then
        case "$1" in
            up|down|both)
                VERIFY_DIRECTION="$1"
                shift
                ;;
        esac
    fi

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
                    exit 2
                }
                SSH_HOST="$2"
                shift 2
                ;;
            --no-space-check)
                CHECK_DISK_SPACE=false
                shift
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
                exit 2
                ;;
        esac
    done

    if (($# > 0)); then
        printf '[ERROR] Зайві аргументи: %s\n' "$*" >&2
        exit 2
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
            exit 2
            ;;
    esac
}
