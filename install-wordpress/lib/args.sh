#!/usr/bin/env bash

show_help() {
    cat <<EOF
Використання:
  sudo ./wordpress-stack.sh [OPTIONS]

Обов'язково:
  --mode internet|lan

Для Internet:
  --domain DOMAIN
  --email EMAIL

Опції:
  --dir PATH             Директорія встановлення
                         Default: /opt/wordpress

  --ssh-port PORT        SSH-порт для nftables/Fail2ban
                         Default: 2241

  --manage-firewall      Додати окрему таблицю nftables
                         для захисту host INPUT

  --no-fail2ban          Не налаштовувати Fail2ban

  --no-start             Створити/перевірити stack,
                         але не запускати його

  --force                Перегенерувати .env і конфігурації,
                         які містять секрети

  -h, --help             Допомога

Приклади:

  sudo ./wordpress-stack.sh \
      --mode internet \
      --domain example.com \
      --email admin@example.com

  sudo ./wordpress-stack.sh \
      --mode internet \
      --domain example.com \
      --email admin@example.com \
      --manage-firewall

  sudo ./wordpress-stack.sh --mode lan

  sudo ./wordpress-stack.sh \
      --mode lan \
      --domain wp.local \
      --no-start
EOF
}

require_arg_value() {
    local option="$1"
    local value="${2:-}"

    if [[ -z "$value" || "$value" == --* ]]; then
        die "Параметр $option потребує значення."
    fi
}

parse_args() {
    while (( $# > 0 )); do
        case "$1" in
            --mode)
                require_arg_value "$1" "${2:-}"
                DEPLOY_MODE="$2"
                shift 2
                ;;
            --domain)
                require_arg_value "$1" "${2:-}"
                DOMAIN="$2"
                shift 2
                ;;
            --email)
                require_arg_value "$1" "${2:-}"
                EMAIL="$2"
                shift 2
                ;;
            --dir)
                require_arg_value "$1" "${2:-}"
                INSTALL_DIR="$2"
                shift 2
                ;;
            --ssh-port)
                require_arg_value "$1" "${2:-}"
                SSH_PORT="$2"
                shift 2
                ;;
            --manage-firewall)
                MANAGE_FIREWALL=true
                shift
                ;;
            --no-fail2ban)
                ENABLE_FAIL2BAN=false
                shift
                ;;
            --no-start)
                NO_START=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                die "Невідомий параметр: $1"
                ;;
        esac
    done
}

validate_args() {
    case "$DEPLOY_MODE" in
        internet|lan)
            ;;
        "")
            die "Не вказано --mode internet|lan"
            ;;
        *)
            die "Некоректний режим: $DEPLOY_MODE"
            ;;
    esac

    if [[ "$DEPLOY_MODE" == "internet" ]]; then
        [[ -n "$DOMAIN" ]] || die "Для internet mode необхідний --domain."
        [[ -n "$EMAIL" ]] || die "Для internet mode необхідний --email."

        if [[ ! "$DOMAIN" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            die "Некоректний domain: $DOMAIN"
        fi

        if [[ ! "$EMAIL" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]; then
            die "Некоректний email: $EMAIL"
        fi
    else
        DOMAIN="${DOMAIN:-wp.local}"
        EMAIL="${EMAIL:-admin@localhost}"
    fi

    if [[ ! "$SSH_PORT" =~ ^[0-9]+$ ]]; then
        die "Некоректний SSH port: $SSH_PORT"
    fi

    if (( SSH_PORT < 1 || SSH_PORT > 65535 )); then
        die "SSH port має бути в діапазоні 1-65535."
    fi

    if [[ "$INSTALL_DIR" != /* ]]; then
        die "--dir має бути абсолютним шляхом."
    fi

    if [[ "$INSTALL_DIR" == "/" ]]; then
        die "INSTALL_DIR не може бути /."
    fi
}
