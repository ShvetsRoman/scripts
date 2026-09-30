#!/usr/bin/env bash

read_env_value() {
    local file="$1"
    local key="$2"

    sed -n "s/^${key}=//p" "$file" | tail -n 1 | sed -E 's/^"(.*)"$/\1/'
}

check_existing_identity() {
    local env_file="$1"
    local old_mode
    local old_domain
    local old_project

    old_mode="$(read_env_value "$env_file" DEPLOY_MODE)"
    old_domain="$(read_env_value "$env_file" DOMAIN)"
    old_project="$(read_env_value "$env_file" COMPOSE_PROJECT_NAME)"

    if [[ "$FORCE" == false ]]; then
        if [[ -n "$old_mode" && "$old_mode" != "$DEPLOY_MODE" ]]; then
            die "Існуюча інсталяція має DEPLOY_MODE=$old_mode. Для зміни використай --force."
        fi

        if [[ -n "$old_domain" && "$old_domain" != "$DOMAIN" ]]; then
            die "Існуюча інсталяція має DOMAIN=$old_domain. Для зміни використай --force."
        fi

        if [[ "$PROJECT_NAME_EXPLICIT" == true && -n "$old_project" && "$old_project" != "$PROJECT_NAME" ]]; then
            die "Існуюча інсталяція має COMPOSE_PROJECT_NAME=$old_project. Для зміни використай --force."
        fi
    fi

    if [[ "$PROJECT_NAME_EXPLICIT" == false && -n "$old_project" ]]; then
        PROJECT_NAME="$old_project"
    fi
}

create_project_structure() {
    log_step "Створення структури проєкту."

    local directories=(
        "$INSTALL_DIR"
        "$INSTALL_DIR/data"
        "$INSTALL_DIR/data/mysql"
        "$INSTALL_DIR/traefik"
        "$INSTALL_DIR/nginx"
        "$INSTALL_DIR/php"
        "$INSTALL_DIR/backups"
        "$INSTALL_DIR/logs"
        "$INSTALL_DIR/logs/nginx"
        "$INSTALL_DIR/letsencrypt"
    )

    local directory

    for directory in "${directories[@]}"; do
        create_dir "$directory" 0750
    done

    # Bind-mounted WordPress root must be traversable by the Alpine www-data
    # user used by the official WordPress CLI image.
    create_dir "$INSTALL_DIR/data/wordpress" 0755
    create_dir "$INSTALL_DIR/scripts" 0755

    chmod 0700 "$INSTALL_DIR/letsencrypt"
    chmod 0700 "$INSTALL_DIR/backups"

    log_success "Структуру створено у $INSTALL_DIR."
}

create_env_file() {
    local env_file="$INSTALL_DIR/.env"

    local mysql_root_password=""
    local mysql_password=""
    local wordpress_admin_password=""

    if [[ -f "$env_file" ]]; then
        check_existing_identity "$env_file"

        mysql_root_password="$(read_env_value "$env_file" MYSQL_ROOT_PASSWORD)"
        mysql_password="$(read_env_value "$env_file" MYSQL_PASSWORD)"
        wordpress_admin_password="$(read_env_value "$env_file" WORDPRESS_ADMIN_PASSWORD)"

        cp -a -- "$env_file" "${env_file}.bak.$(date '+%Y%m%d_%H%M%S')"
        log_info "Існуючий .env оновлюється зі збереженням секретів."
    else
        log_step "Створення .env."
    fi

    [[ -n "$mysql_root_password" ]] ||
        mysql_root_password="$(generate_password)"

    [[ -n "$mysql_password" ]] ||
        mysql_password="$(generate_password)"

    [[ -n "$wordpress_admin_password" ]] ||
        wordpress_admin_password="$(generate_password)"

    local app_url

    if [[ "$DEPLOY_MODE" == "internet" ]]; then
        app_url="https://${DOMAIN}"
    else
        app_url="http://${DOMAIN}"
    fi

    cat > "$env_file" <<EOF
COMPOSE_PROJECT_NAME=${PROJECT_NAME}

DEPLOY_MODE=${DEPLOY_MODE}
DOMAIN=${DOMAIN}
ACME_EMAIL=${ACME_EMAIL}
APP_URL=${app_url}
INSTALL_DIR=${INSTALL_DIR}
INSTALL_FORCE=${FORCE}

TRAEFIK_VERSION=${TRAEFIK_VERSION}
NGINX_VERSION=${NGINX_VERSION}
WORDPRESS_VERSION=${WORDPRESS_VERSION}
MYSQL_VERSION=${MYSQL_VERSION}
WPCLI_VERSION=${WPCLI_VERSION}

MYSQL_DATABASE=${MYSQL_DATABASE}
MYSQL_USER=${MYSQL_USER}
MYSQL_PASSWORD=${mysql_password}
MYSQL_ROOT_PASSWORD=${mysql_root_password}

WORDPRESS_DB_HOST=db:3306
WORDPRESS_ADMIN_USER=${WORDPRESS_ADMIN_USER}
WORDPRESS_ADMIN_PASSWORD=${wordpress_admin_password}
WORDPRESS_ADMIN_EMAIL=${ADMIN_EMAIL}
WORDPRESS_TITLE="${WORDPRESS_TITLE}"

MEMORY_LIMIT=${MEMORY_LIMIT}
UPLOAD_MAX_FILESIZE=${UPLOAD_MAX_FILESIZE}
POST_MAX_SIZE=${POST_MAX_SIZE}
MAX_EXECUTION_TIME=${MAX_EXECUTION_TIME}
MAX_INPUT_VARS=${MAX_INPUT_VARS}

BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS}
EOF

    chmod 0600 "$env_file"

    log_success ".env готовий."
}

install_template() {
    local source_file="$1"
    local destination_file="$2"
    local mode="${3:-0644}"

    [[ -f "$source_file" ]] ||
        die "Template не знайдено: $source_file"

    install -m "$mode" "$source_file" "$destination_file"
}

install_templates() {
    log_step "Встановлення конфігурацій."

    install_template \
        "$SCRIPT_DIR/templates/compose.yml" \
        "$INSTALL_DIR/compose.yml"

    install_template \
        "$SCRIPT_DIR/templates/nginx/default.conf" \
        "$INSTALL_DIR/nginx/default.conf"

    install_template \
        "$SCRIPT_DIR/templates/nginx/security-headers.conf" \
        "$INSTALL_DIR/nginx/security-headers.conf"

    install_template \
        "$SCRIPT_DIR/templates/php/custom.ini" \
        "$INSTALL_DIR/php/custom.ini"

    install_template \
        "$SCRIPT_DIR/templates/Makefile" \
        "$INSTALL_DIR/Makefile"

    local script

    for script in "$SCRIPT_DIR"/templates/scripts/*.sh; do
        install_template \
            "$script" \
            "$INSTALL_DIR/scripts/$(basename "$script")" \
            0755
    done

    chmod 0755 "$INSTALL_DIR/scripts"
    chmod 0755 "$INSTALL_DIR"/scripts/*.sh

    log_success "Templates встановлено."
}

create_gitignore() {
    cat > "$INSTALL_DIR/.gitignore" <<'EOF'
.env
.env.bak.*
data/
backups/
logs/
letsencrypt/
*.log
*.tar.gz
*.sql.gz
EOF
}

create_readme() {
    install_template \
        "$SCRIPT_DIR/templates/README.md" \
        "$INSTALL_DIR/README.md"
}
