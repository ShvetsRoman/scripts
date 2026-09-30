#!/usr/bin/env bash

create_project_structure() {
    log_step "Створення структури проєкту."

    create_dir "$INSTALL_DIR" 0750

    local directories=(
        "$INSTALL_DIR/data/mysql"
        "$INSTALL_DIR/data/wordpress"
        "$INSTALL_DIR/traefik"
        "$INSTALL_DIR/nginx"
        "$INSTALL_DIR/php"
        "$INSTALL_DIR/scripts"
        "$INSTALL_DIR/backups"
        "$INSTALL_DIR/logs/nginx"
        "$INSTALL_DIR/letsencrypt"
    )

    local directory
    for directory in "${directories[@]}"; do
        create_dir "$directory"
    done

    chmod 0700 "$INSTALL_DIR/letsencrypt"

    log_success "Структуру створено."
}

create_env_file() {
    local env_file="$INSTALL_DIR/.env"

    if [[ -e "$env_file" && "$FORCE" == false ]]; then
        log_info ".env вже існує — секрети залишено без змін."
        return 0
    fi

    if [[ -e "$env_file" && "$FORCE" == true ]]; then
        cp -a -- "$env_file" "${env_file}.bak.$(date '+%Y%m%d_%H%M%S')"
        log_warning "Попередній .env збережено як backup."
    fi

    log_step "Створення .env."

    local mysql_root_password
    local mysql_password
    local wordpress_admin_password
    local app_url

    mysql_root_password="$(generate_password)"
    mysql_password="$(generate_password)"
    wordpress_admin_password="$(generate_password)"

    if [[ "$DEPLOY_MODE" == "internet" ]]; then
        app_url="https://${DOMAIN}"
    else
        app_url="http://${DOMAIN}"
    fi

    cat > "$env_file" <<EOF
COMPOSE_PROJECT_NAME=wordpress

DEPLOY_MODE=${DEPLOY_MODE}
DOMAIN=${DOMAIN}
EMAIL=${EMAIL}
APP_URL=${app_url}

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
WORDPRESS_ADMIN_EMAIL=${EMAIL}
WORDPRESS_TITLE="${WORDPRESS_TITLE}"

MEMORY_LIMIT=${MEMORY_LIMIT}
UPLOAD_MAX_FILESIZE=${UPLOAD_MAX_FILESIZE}
POST_MAX_SIZE=${POST_MAX_SIZE}
MAX_EXECUTION_TIME=${MAX_EXECUTION_TIME}
MAX_INPUT_VARS=${MAX_INPUT_VARS}

BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS}
EOF

    chmod 0600 "$env_file"
    chown root:root "$env_file"

    log_success ".env створено."
}

install_template() {
    local source_file="$1"
    local destination_file="$2"
    local mode="${3:-0644}"

    [[ -f "$source_file" ]] || die "Template не знайдено: $source_file"

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
        install_template "$script" "$INSTALL_DIR/scripts/$(basename "$script")" 0750
    done

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
