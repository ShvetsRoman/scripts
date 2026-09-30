#!/usr/bin/env bash

show_help() {
    cat <<EOF
Використання:
  ./wordpress-stack.sh [OPTIONS]

За замовчуванням sudo НЕ потрібен.

Обов'язково:
  --mode internet|lan

Для Internet:
  --domain DOMAIN
  --email EMAIL
      Email для Let's Encrypt.

Опції:
  --admin-email EMAIL
      Email адміністратора WordPress.
      Internet default: значення --email
      LAN default: admin@example.com

  --dir PATH
      Абсолютний шлях встановлення.
      Default: <home-каталог користувача>/wordpress

  --project-name NAME
      Docker Compose project name.
      Для існуючої інсталяції зберігається попереднє значення.
      Для нової генерується автоматично з install path.

  --ssh-port PORT
      SSH-порт для Fail2ban/nftables.
      Default: 2241

  --enable-fail2ban
      Встановити та налаштувати Fail2ban.
      Потребує root.

  --manage-firewall
      Додати nftables integration.
      Потребує root.

  --no-start
      Створити та перевірити stack,
      але не запускати Docker containers.

  --force
      Дозволити зміну mode/domain/project-name
      існуючої інсталяції.
      Паролі бази даних при цьому НЕ обнуляються.

  -h, --help
      Допомога.

Приклади:

  ./wordpress-stack.sh --mode lan

  ./wordpress-stack.sh \
      --mode lan \
      --admin-email admin@example.com \
      --dir "\$HOME/sites/wordpress"

  ./wordpress-stack.sh \
      --mode internet \
      --domain example.com \
      --email letsencrypt@example.com \
      --admin-email admin@example.com

  sudo ./wordpress-stack.sh \
      --mode internet \
      --domain example.com \
      --email letsencrypt@example.com \
      --dir /srv/wordpress \
      --enable-fail2ban \
      --manage-firewall
EOF
}

require_arg_value() {
    local option="$1"
    local value="${2:-}"

    if [[ -z "$value" || "$value" == --* ]]; then
        die "Параметр $option потребує значення."
    fi
}

is_valid_email() {
    local value="$1"
    [[ "$value" =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]]
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
                DOMAIN_EXPLICIT=true
                shift 2
                ;;
            --email)
                require_arg_value "$1" "${2:-}"
                ACME_EMAIL="$2"
                shift 2
                ;;
            --admin-email)
                require_arg_value "$1" "${2:-}"
                ADMIN_EMAIL="$2"
                ADMIN_EMAIL_EXPLICIT=true
                shift 2
                ;;
            --dir)
                require_arg_value "$1" "${2:-}"
                INSTALL_DIR="$2"
                shift 2
                ;;
            --project-name)
                require_arg_value "$1" "${2:-}"
                PROJECT_NAME="$2"
                PROJECT_NAME_EXPLICIT=true
                shift 2
                ;;
            --ssh-port)
                require_arg_value "$1" "${2:-}"
                SSH_PORT="$2"
                shift 2
                ;;
            --enable-fail2ban)
                ENABLE_FAIL2BAN=true
                shift
                ;;
            --manage-firewall)
                MANAGE_FIREWALL=true
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
        [[ -n "$DOMAIN" ]] ||
            die "Для internet mode необхідний --domain."

        [[ -n "$ACME_EMAIL" ]] ||
            die "Для internet mode необхідний --email."

        if [[ ! "$DOMAIN" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            die "Некоректний domain: $DOMAIN"
        fi

        if ! is_valid_email "$ACME_EMAIL"; then
            die "Некоректний Let's Encrypt email: $ACME_EMAIL"
        fi
    else
        DOMAIN="${DOMAIN:-wp.home.arpa}"
    fi

    if [[ -n "$ADMIN_EMAIL" ]] && ! is_valid_email "$ADMIN_EMAIL"; then
        die "Некоректний WordPress admin email: $ADMIN_EMAIL"
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

    if [[ "$INSTALL_DIR" =~ [[:space:]] ]]; then
        die "Шлях встановлення не повинен містити пробіли: $INSTALL_DIR"
    fi

    INSTALL_DIR="$(realpath -m -- "$INSTALL_DIR")"

    case "$INSTALL_DIR" in
        /|/bin|/boot|/dev|/etc|/home|/lib|/lib64|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var)
            die "Небезпечний шлях встановлення: $INSTALL_DIR"
            ;;
    esac

    if [[ -n "$PROJECT_NAME" && ! "$PROJECT_NAME" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        die "Некоректний project name: $PROJECT_NAME"
    fi
}
