#!/bin/bash

# ============================================================
# PRODUCTION WORDPRESS STACK INSTALLER
# ============================================================
# Повноцінне production-розгортання WordPress з:
# - Traefik (reverse proxy + Let's Encrypt)
# - Nginx (web server + security)
# - PHP-FPM 8.3 (WordPress)
# - MySQL 8.4 (database)
# - WP-CLI (management)
# - nftables + Fail2ban (firewall + security)
# - Автоматичний backup + healthcheck
# ============================================================

set -e

# Кольори для виводу
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Глобальні змінні
DEPLOY_MODE=""
DOMAIN=""
EMAIL=""
INSTALL_DIR="/opt/wordpress"

# Функції логування
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Функція генерації паролів
generate_password() {
    openssl rand -base64 32 | tr -d '/+=' | cut -c1-32
}

# Функція перевірки команд
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 не встановлено. Будь ласка, встановіть $1"
    fi
}

# Функція створення директорії з правами
create_secure_dir() {
    local dir="$1"
    local perms="${2:-750}"
    local owner="${3:-root:root}"
    
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
        chmod "$perms" "$dir"
        chown "$owner" "$dir"
        log_success "Створено директорію: $dir (${perms})"
    else
        log_info "Директорія вже існує: $dir"
    fi
}

# Парсинг аргументів командного рядка
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain)
                DOMAIN="$2"
                shift 2
                ;;
            --email)
                EMAIL="$2"
                shift 2
                ;;
            --mode)
                DEPLOY_MODE="$2"
                if [[ "$DEPLOY_MODE" != "internet" && "$DEPLOY_MODE" != "lan" ]]; then
                    log_error "Режим має бути 'internet' або 'lan'"
                fi
                shift 2
                ;;
            --dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Невідомий параметр: $1"
                ;;
        esac
    done
    
    # Валідація обов'язкових параметрів
    if [ -z "$DEPLOY_MODE" ]; then
        log_error "Необхідно вказати режим розгортання: --mode internet|lan"
    fi
    
    if [ "$DEPLOY_MODE" = "internet" ]; then
        if [ -z "$DOMAIN" ]; then
            log_error "Для режиму 'internet' необхідно вказати домен: --domain example.com"
        fi
        if [ -z "$EMAIL" ]; then
            log_error "Для режиму 'internet' необхідно вказати email: --email admin@example.com"
        fi
    fi
}

# Показати допомогу
show_help() {
    cat << EOF
Використання: $0 [OPTIONS]

Production розгортання WordPress стеку з Traefik + Let's Encrypt

Обов'язкові параметри:
  --mode internet|lan    Режим розгортання
  
Для режиму internet:
  --domain DOMAIN        Доменне ім'я (наприклад: example.com)
  --email EMAIL          Email для Let's Encrypt

Опціональні параметри:
  --dir DIR             Директорія встановлення (за замовчуванням: /opt/wordpress)
  --help, -h            Показати цю допомогу

Приклади:
  # Режим Internet з Let's Encrypt
  sudo $0 --mode internet --domain example.com --email admin@example.com
  
  # Режим LAN
  sudo $0 --mode lan
  
  # З власною директорією
  sudo $0 --mode internet --domain example.com --email admin@example.com --dir /srv/wordpress
EOF
}

# Перевірка системи
check_system() {
    log_info "Перевірка системи..."
    
    # Перевірка прав
    if [ "$EUID" -ne 0 ]; then 
        log_error "Скрипт має запускатися з правами root"
    fi
    
    # Перевірка архітектури
    ARCH=$(uname -m)
    if [[ "$ARCH" != "x86_64" && "$ARCH" != "aarch64" ]]; then
        log_warning "Архітектура $ARCH може мати обмежену підтримку"
    fi
    
    # Перевірка необхідних команд
    check_command docker
    check_command docker-compose
    check_command openssl
    check_command curl
    
    # Перевірка Docker
    if ! systemctl is-active --quiet docker; then
        log_error "Docker не запущено. Запустіть: systemctl start docker"
    fi
    
    log_success "Систему перевірено"
}

# Налаштування nftables
setup_nftables() {

    log_info "Налаштування nftables..."

    if ! command -v nft >/dev/null 2>&1; then
        log_info "nft не знайдений. Встановлення nftables..."
        pacman -S --noconfirm nftables || {
            log_error "Не вдалося встановити nftables"
            exit 1
        }
    fi
    log_success "nftables встановлено..."

    cat > /etc/nftables.conf << 'EOF'

#!/usr/sbin/nft -f

flush ruleset

table inet filter {

    # IP, заблоковані Fail2ban
    set f2b-sshd {
        type ipv4_addr
        flags dynamic, timeout
        timeout 10m
    }

    chain input {
        type filter hook input priority filter; policy drop;

        # Уже встановлені з'єднання
        ct state established,related accept

        # Некоректні пакети
        ct state invalid drop

        # Loopback
        iifname "lo" accept

        # Fail2ban
        ip saddr @f2b-sshd drop

        # SSH
        tcp dport 2241 ct state new accept

        # HTTP / HTTPS
        tcp dport { 80, 443 } ct state new accept

        # ICMP
        icmp type echo-request accept

        # Логування тільки відхилених пакетів
        limit rate 5/second burst 10 packets \
            log prefix "nftables-drop: " level warning
    }

    chain forward {
        type filter hook forward priority filter;
        policy drop;
    }

    chain output {
        type filter hook output priority filter;
        policy accept;
    }
}
EOF
    
    # Застосування правил
    nft -f /etc/nftables.conf

    systemctl enable --now nftables
    systemctl is-active --quiet nftables || {
        log_warning "nftables не запущений"
        exit 1
    }
    
    log_success "nftables налаштовано"
}

# Налаштування Fail2ban
setup_fail2ban() {
    log_info "Налаштування Fail2ban..."

    # Встановлення fail2ban
    if ! command -v fail2ban-client >/dev/null 2>&1; then
        log_info "fail2ban не знайдений. Встановлення fail2ban..."
        pacman -S --noconfirm fail2ban || {
            log_error "Не вдалося встановити fail2ban"
            exit 1
        }
    fi
    log_success "Fail2ban встановлено..."
    
    # Створення конфігурації для WordPress
    cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
# Початковий час блокування IP
bantime = 1h
# Період, протягом якого рахуються невдалі спроби
findtime = 10m
# Кількість невдалих спроб до блокування
maxretry = 3
# Увімкнути поступове збільшення часу блокування
bantime.increment = true
# Множник збільшення часу блокування
bantime.factor = 2
# Максимальний час блокування IP
bantime.maxtime = 1w
# Використовувати systemd journal для аналізу логів
backend = systemd
# IP-адреси, які ніколи не блокувати
ignoreip = 127.0.0.1/8 ::1
# Використовувати nftables для блокування IP
banaction = nftables-multiport
# Використовувати nftables для блокування IP на всіх портах
banaction_allports = nftables-allports

[sshd]
# Увімкнути захист SSH
enabled = true
# Порт SSH
port = 2241
# Кількість невдалих спроб до блокування SSH
maxretry = 3
# Період підрахунку невдалих спроб SSH
findtime = 10m

[wordpress-auth]
enabled = true
port = http,https
filter = wordpress-auth
logpath = /var/log/nginx/access.log
maxretry = 5
bantime = 7200
EOF

    # Створення фільтру для WordPress
    cat > /etc/fail2ban/filter.d/wordpress-auth.conf << 'EOF'
[Definition]
failregex = ^<HOST> .* "POST /wp-login\.php.* HTTP/.*" (4\d\d|5\d\d) .*$
            ^<HOST> .* "POST /wp-admin/admin-ajax\.php.* HTTP/.*" 403 .*$
ignoreregex =
EOF

    systemctl enable --now fail2ban
    fail2ban-client status
    systemctl is-active --quiet fail2ban-client || {
        log_warning "fail2ban не запущений"
        exit 1
    }

    log_success "Fail2ban налаштовано"
}

# Створення структури проєкту
create_project_structure() {
    log_info "Створення структури проєкту в $INSTALL_DIR..."
    
    create_secure_dir "$INSTALL_DIR" 750 root:root
    cd "$INSTALL_DIR"
    
    # Створення всіх необхідних директорій
    local dirs=(
        "traefik/dynamic"
        "nginx"
        "php"
        "scripts"
        "data/mysql"
        "data/wordpress"
        "letsencrypt"
        "backups"
    )
    
    for dir in "${dirs[@]}"; do
        create_secure_dir "$dir" 750 root:root
    done
    
    # Спеціальні права для let's encrypt
    chmod 700 "$INSTALL_DIR/letsencrypt"
    
    log_success "Структуру проєкту створено"
}

# Створення .env файлу
create_env_file() {
    log_info "Створення .env файлу..."
    
    # Генерація паролів
    local mysql_root_pass=$(generate_password)
    local mysql_user_pass=$(generate_password)
    local wp_admin_pass=$(generate_password)
    
    cat > .env << EOF
# ============================================
# WORDPRESS PRODUCTION ENVIRONMENT
# ============================================

# ---------- Доменні налаштування ----------
DEPLOY_MODE=${DEPLOY_MODE}
DOMAIN=${DOMAIN:-localhost}
EMAIL=${EMAIL:-admin@localhost}

# ---------- База даних ----------
MYSQL_ROOT_PASSWORD=${mysql_root_pass}
MYSQL_DATABASE=wordpress
MYSQL_USER=wp_user
MYSQL_PASSWORD=${mysql_user_pass}

# ---------- WordPress ----------
WORDPRESS_DB_HOST=db:3306
WORDPRESS_DB_USER=\${MYSQL_USER}
WORDPRESS_DB_PASSWORD=\${MYSQL_PASSWORD}
WORDPRESS_DB_NAME=\${MYSQL_DATABASE}

# ---------- WordPress Admin ----------
WORDPRESS_ADMIN_USER=admin
WORDPRESS_ADMIN_PASSWORD=${wp_admin_pass}
WORDPRESS_ADMIN_EMAIL=${EMAIL:-admin@example.com}
WORDPRESS_TITLE="My WordPress Site"

# ---------- Версії образів ----------
TRAEFIK_VERSION=3.3.6
WORDPRESS_VERSION=php8.3-fpm-alpine
MYSQL_VERSION=8.4
NGINX_VERSION=1.29-alpine

# ---------- Шляхи ----------
DB_DATA_PATH=./data/mysql
WP_DATA_PATH=./data/wordpress

# ---------- Налаштування PHP ----------
MEMORY_LIMIT=512M
UPLOAD_MAX_FILESIZE=128M
POST_MAX_SIZE=128M
MAX_EXECUTION_TIME=300
MAX_INPUT_VARS=3000

# ---------- Безпека ----------
SECURE_COOKIE=true
DISABLE_FILE_EDIT=true
DISABLE_XMLRPC=true
EOF
    
    # Встановлення прав доступу
    chmod 600 .env
    chown root:root .env
    
    log_success ".env файл створено (chmod 600)"
}

# Створення docker-compose.yml
create_docker_compose() {
    log_info "Створення docker-compose.yml..."
    
    cat > docker-compose.yml << 'EOF'
services:
  # ==================== TRAEFIK ====================
  traefik:
    image: traefik:${TRAEFIK_VERSION:-3.3.6}
    container_name: traefik
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    command:
      - "--log.level=WARN"
      - "--api.dashboard=false"
      - "--api.insecure=false"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./letsencrypt:/letsencrypt
      - ./traefik/dynamic:/dynamic:ro
    networks:
      - public
    restart_policy:
      condition: on-failure
      delay: 5s
      max_attempts: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ==================== NGINX ====================
  nginx:
    image: nginx:${NGINX_VERSION:-1.29-alpine}
    container_name: wordpress-nginx
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /var/run
      - /var/cache/nginx
    volumes:
      - ${WP_DATA_PATH:-./data/wordpress}:/var/www/html:ro
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
      - ./nginx/security-headers.conf:/etc/nginx/conf.d/security-headers.conf:ro
      - nginx-cache:/var/cache/nginx
    networks:
      - public
      - internal
    depends_on:
      - wordpress
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nginx.rule=Host(`${DOMAIN:-localhost}`)"
      - "traefik.http.routers.nginx.entrypoints=websecure"
      - "traefik.http.routers.nginx.tls=true"
      - "traefik.http.routers.nginx.tls.certresolver=letsencrypt"
      - "traefik.http.services.nginx.loadbalancer.server.port=80"
      - "traefik.http.routers.nginx.middlewares=secHeaders@docker"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ==================== WORDPRESS PHP-FPM ====================
  wordpress:
    image: wordpress:${WORDPRESS_VERSION:-php8.3-fpm-alpine}
    container_name: wordpress-app
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    env_file:
      - .env
    environment:
      WORDPRESS_DB_HOST: ${WORDPRESS_DB_HOST:-db:3306}
      WORDPRESS_DB_USER: ${MYSQL_USER}
      WORDPRESS_DB_PASSWORD: ${MYSQL_PASSWORD}
      WORDPRESS_DB_NAME: ${MYSQL_DATABASE}
    volumes:
      - ${WP_DATA_PATH:-./data/wordpress}:/var/www/html
      - ./php/custom.ini:/usr/local/etc/php/conf.d/zz-custom.ini:ro
    networks:
      - internal
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "php", "-r", "exit(0);"]
      interval: 30s
      timeout: 10s
      retries: 3
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ==================== MYSQL ====================
  db:
    image: mysql:${MYSQL_VERSION:-8.4}
    container_name: wordpress-db
    restart: unless-stopped
    security_opt:
      - no-new-privileges:true
    env_file:
      - .env
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE:-wordpress}
      MYSQL_USER: ${MYSQL_USER:-wp_user}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    volumes:
      - ${DB_DATA_PATH:-./data/mysql}:/var/lib/mysql
    networks:
      - internal
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}"]
      interval: 10s
      timeout: 5s
      retries: 5
    command:
      - "--character-set-server=utf8mb4"
      - "--collation-server=utf8mb4_unicode_ci"
      - "--default-authentication-plugin=mysql_native_password"
      - "--max_connections=100"
      - "--innodb_log_file_size=256M"
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

  # ==================== WP-CLI ====================
  wpcli:
    image: wordpress:cli
    container_name: wp-cli-tool
    restart: unless-stopped
    user: "33:33"
    env_file:
      - .env
    environment:
      WORDPRESS_DB_HOST: ${WORDPRESS_DB_HOST:-db:3306}
      WORDPRESS_DB_USER: ${MYSQL_USER}
      WORDPRESS_DB_PASSWORD: ${MYSQL_PASSWORD}
      WORDPRESS_DB_NAME: ${MYSQL_DATABASE}
    volumes:
      - ${WP_DATA_PATH:-./data/wordpress}:/var/www/html
      - ./scripts:/scripts:ro
    networks:
      - internal
    depends_on:
      db:
        condition: service_healthy
      wordpress:
        condition: service_started
    command: tail -f /dev/null
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

volumes:
  nginx-cache:
    name: wordpress_nginx_cache

networks:
  public:
    name: traefik_public
    driver: bridge
  internal:
    name: wordpress_internal
    driver: bridge
    internal: true
EOF

    # Додавання Traefik конфігурації для режиму LAN
    if [ "$DEPLOY_MODE" = "lan" ]; then
        cat >> docker-compose.yml << 'EOF'
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nginx.rule=Host(`localhost`) || Host(`wp.local`)"
      - "traefik.http.routers.nginx.entrypoints=web"
      - "traefik.http.routers.nginx.middlewares=secHeaders@docker"
EOF
    fi
    
    log_success "docker-compose.yml створено"
}

# Створення конфігурації Nginx
create_nginx_config() {
    log_info "Створення конфігурації Nginx..."
    
    # Основний конфіг
    cat > nginx/default.conf << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    root /var/www/html;
    index index.php index.html index.htm;
    
    client_max_body_size 128M;
    
    # Безпека
    include /etc/nginx/conf.d/security-headers.conf;
    
    # Заборона доступу до системних файлів
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    location ~* (wp-config\.php|xmlrpc\.php|wp-config-sample\.php|readme\.html|license\.txt|wp-links-opml\.php) {
        deny all;
        return 404;
    }
    
    # Заборона виконання PHP у uploads
    location ~* /(?:uploads|files)/.*\.php$ {
        deny all;
        return 403;
    }
    
    # Основний локація
    location / {
        try_files $uri $uri/ /index.php?$args;
    }
    
    # Обробка PHP
    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass wordpress:9000;
        fastcgi_index index.php;
        include fastcgi_params;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        
        # Оптимізація
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
        fastcgi_read_timeout 300s;
        fastcgi_send_timeout 300s;
    }
    
    # Кешування статики
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot|webp|avif)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
        add_header X-Content-Type-Options nosniff;
        access_log off;
    }
    
    # Головна сторінка - без кешу
    location = / {
        expires -1;
        add_header Cache-Control "no-cache, no-store, must-revalidate";
    }
    
    # Стиснення
    gzip on;
    gzip_vary on;
    gzip_comp_level 6;
    gzip_min_length 256;
    gzip_proxied any;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/javascript
        application/xml+rss
        application/json
        application/x-javascript
        application/xml
        image/svg+xml;
}
EOF

    # Security headers
    cat > nginx/security-headers.conf << 'EOF'
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-Content-Type-Options "nosniff" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;
EOF

    log_success "Конфігурація Nginx створена"
}

# Створення конфігурації PHP
create_php_config() {
    log_info "Створення конфігурації PHP..."
    
    cat > php/custom.ini << 'EOF'
; Налаштування PHP для WordPress
file_uploads = On
memory_limit = 512M
upload_max_filesize = 128M
post_max_size = 128M
max_execution_time = 300
max_input_vars = 3000
max_input_time = 300
default_charset = UTF-8

; Безпека
expose_php = Off
disable_functions = exec,shell_exec,system,passthru,phpinfo
allow_url_fopen = Off

; Налаштування сесій
session.cookie_httponly = 1
session.use_only_cookies = 1
session.cookie_secure = 1

; Оптимізація
opcache.enable = 1
opcache.memory_consumption = 256
opcache.max_accelerated_files = 4000
opcache.revalidate_freq = 60
opcache.fast_shutdown = 1

; Логування
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
display_errors = Off
log_errors = On
error_log = /proc/self/fd/2
EOF

    log_success "Конфігурація PHP створена"
}

# Створення скриптів
create_scripts() {
    log_info "Створення скриптів управління..."
    
    # WP Install Script
    cat > scripts/wp-install.sh << 'EOF'
#!/usr/bin/env bash

set -e

echo "=== WordPress Installation ==="

# Wait for WordPress to be ready
echo "Waiting for WordPress..."
until wp core is-installed --allow-root 2>/dev/null; do
    sleep 2
done

# Install if not installed
if ! wp core is-installed --allow-root 2>/dev/null; then
    echo "Installing WordPress..."
    
    wp core install \
        --url="http://${DOMAIN:-localhost}" \
        --title="${WORDPRESS_TITLE:-My WordPress Site}" \
        --admin_user="${WORDPRESS_ADMIN_USER:-admin}" \
        --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
        --admin_email="${WORDPRESS_ADMIN_EMAIL:-admin@example.com}" \
        --skip-email \
        --allow-root
    
    echo "Configuring permalinks..."
    wp rewrite structure '/%postname%/' --allow-root
    wp rewrite flush --allow-root
    
    echo "Removing default plugins..."
    wp plugin delete hello akismet --allow-root 2>/dev/null || true
    wp theme delete twentytwentyfour twentytwentyfive --allow-root 2>/dev/null || true
    
    echo "Configuring WordPress..."
    wp option update timezone_string "Europe/Kiev" --allow-root
    wp option update date_format "d.m.Y" --allow-root
    wp option update time_format "H:i" --allow-root
    
    echo "WordPress installed successfully!"
fi
EOF

    # Backup Script
    cat > scripts/backup.sh << 'EOF'
#!/usr/bin/env bash

set -e

BACKUP_DIR="${BACKUP_DIR:-/opt/wordpress/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/backup_${TIMESTAMP}"

echo "=== Creating Backup ==="
mkdir -p "$BACKUP_PATH"

echo "[1/2] Backing up database..."
docker-compose exec -T db mysqldump \
    --no-tablespaces \
    -u"${MYSQL_USER}" \
    -p"${MYSQL_PASSWORD}" \
    "${MYSQL_DATABASE}" \
    | gzip > "${BACKUP_PATH}/database.sql.gz"

echo "[2/2] Backing up files..."
tar -czf "${BACKUP_PATH}/wordpress.tar.gz" \
    -C ./data \
    wordpress

echo "Backup completed: ${BACKUP_PATH}"

# Rotate old backups (keep last 7)
find "$BACKUP_DIR" -type d -name "backup_*" -mtime +7 -exec rm -rf {} \;
echo "Old backups rotated"
EOF

    # Healthcheck Script
    cat > scripts/healthcheck.sh << 'EOF'
#!/usr/bin/env bash

set -e

echo "=== Healthcheck ==="

# Check Docker services
echo "Checking Docker services..."
docker-compose ps --format json | jq -r '.[] | "\(.Service): \(.State)"'

# Check WordPress
echo "Checking WordPress..."
if curl -s -o /dev/null -w "%{http_code}" "http://nginx" | grep -q "200"; then
    echo "WordPress: OK"
else
    echo "WordPress: ERROR"
    exit 1
fi

# Check database
echo "Checking database..."
docker-compose exec -T db mysqladmin ping -h localhost -u root -p"${MYSQL_ROOT_PASSWORD}" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Database: OK"
else
    echo "Database: ERROR"
    exit 1
fi

echo "All checks passed!"
EOF

    chmod +x scripts/*.sh
    log_success "Скрипти створено"
}

# Створення Makefile
create_makefile() {
    log_info "Створення Makefile..."
    
    cat > Makefile << 'EOF'
.PHONY: help up down restart logs status shell wp-cli install backup restore healthcheck clean

include .env
export

help: ## Показати команди
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

up: ## Запустити всі сервіси
	docker-compose up -d
	@echo "✅ Сервіси запущено"
	@echo "WordPress: http://$${DOMAIN:-localhost}"

down: ## Зупинити всі сервіси
	docker-compose down

restart: down up ## Перезапуск

logs: ## Логи всіх сервісів
	docker-compose logs -f

logs-nginx: ## Логи Nginx
	docker-compose logs -f nginx

logs-wordpress: ## Логи WordPress
	docker-compose logs -f wordpress

logs-db: ## Логи MySQL
	docker-compose logs -f db

status: ## Статус сервісів
	docker-compose ps

shell: ## Shell в WordPress
	docker-compose exec wordpress bash

wp-cli: ## WP-CLI (make wp-cli CMD="plugin list")
	docker-compose exec wpcli wp $(CMD) --allow-root

install: ## Встановити WordPress
	docker-compose exec wpcli bash /scripts/wp-install.sh

backup: ## Створити backup
	@bash scripts/backup.sh

restore: ## Відновити backup (make restore BACKUP=backup_20240101_120000)
	@if [ -z "$(BACKUP)" ]; then \
		echo "Usage: make restore BACKUP=backup_YYYYMMDD_HHMMSS"; \
		echo "Available backups:"; \
		ls -1 backups/ 2>/dev/null || echo "None"; \
		exit 1; \
	fi
	@bash scripts/restore.sh $(BACKUP)

healthcheck: ## Перевірка стану системи
	@bash scripts/healthcheck.sh

clean: ## ⚠️ Видалити всі дані (з підтвердженням)
	@read -p "⚠️ Видалити всі дані? [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker-compose down -v; \
		rm -rf data/; \
		echo "✅ Дані видалено"; \
	else \
		echo "❌ Скасовано"; \
	fi
EOF

    log_success "Makefile створено"
}

# Створення README
create_readme() {
    log_info "Створення README.md..."
    
    cat > README.md << EOF
# WordPress Production Stack

Production-готовий WordPress стек з Traefik, Nginx, PHP-FPM та MySQL.

## 🚀 Швидкий старт

### Запуск
\`\`\`bash
cd ${INSTALL_DIR}
make up
make install
\`\`\`

### Доступ
- **WordPress**: http://${DOMAIN:-localhost}
- **WP-Admin**: http://${DOMAIN:-localhost}/wp-admin
- **Адміністратор**: admin (пароль у .env)

## 📋 Команди

\`\`\`bash
make help          # Показати всі команди
make up            # Запустити сервіси
make down          # Зупинити сервіси
make logs          # Перегляд логів
make status        # Статус сервісів
make install       # Встановити WordPress
make backup        # Створити backup
make healthcheck   # Перевірка стану
\`\`\`

## 🔒 Безпека

- Traefik з Let's Encrypt (автоматичний HTTPS)
- nftables firewall
- Fail2ban захист
- MySQL тільки у внутрішній мережі
- PHP-FPM не доступний ззовні
- Security headers
- Заборона виконання PHP у uploads
- .env з паролями (chmod 600)

## 📦 Структура

\`\`\`
${INSTALL_DIR}/
├── docker-compose.yml
├── .env              # Змінні оточення (паролі)
├── Makefile
├── README.md
├── traefik/          # Конфігурація Traefik
├── nginx/            # Конфігурація Nginx
├── php/              # Конфігурація PHP
├── scripts/          # Скрипти управління
├── data/             # Дані (MySQL + WordPress)
├── letsencrypt/      # Сертифікати Let's Encrypt
└── backups/          # Резервні копії
\`\`\`

## 🔄 Backup/Restore

\`\`\`bash
# Створити backup
make backup

# Відновити backup
make restore BACKUP=backup_20240101_120000
\`\`\`
EOF

    log_success "README.md створено"
}

# Налаштування Traefik для режиму Internet
setup_traefik_internet() {
    log_info "Налаштування Traefik для режиму Internet..."
    
    cat > traefik/dynamic/letsencrypt.yml << EOF
tls:
  certificatesResolvers:
    letsencrypt:
      acme:
        email: ${EMAIL}
        storage: /letsencrypt/acme.json
        httpChallenge:
          entryPoint: web
EOF

    log_success "Traefik налаштовано для Let's Encrypt"
}

# Налаштування Traefik для режиму LAN
setup_traefik_lan() {
    log_info "Налаштування Traefik для режиму LAN..."
    
    cat > traefik/dynamic/letsencrypt.yml << 'EOF'
tls:
  certificatesResolvers:
    default:
      acme:
        storage: /letsencrypt/acme.json
EOF

    log_success "Traefik налаштовано для LAN режиму"
}

# Запуск сервісів
start_services() {
    log_info "Запуск Docker сервісів..."
    
    cd "$INSTALL_DIR"
    docker-compose up -d
    
    # Очікування готовності
    log_info "Очікування готовності сервісів..."
    sleep 10
    
    # Перевірка статусу
    if docker-compose ps | grep -q "Up"; then
        log_success "Сервіси успішно запущено"
    else
        log_error "Помилка запуску сервісів. Перевірте логи: docker-compose logs"
    fi
}

# Встановлення WordPress
install_wordpress() {
    log_info "Встановлення WordPress..."
    
    cd "$INSTALL_DIR"
    docker-compose exec -T wpcli bash /scripts/wp-install.sh
    
    log_success "WordPress встановлено"
}

# Фінальна інформація
show_final_info() {
    echo ""
    echo "============================================================"
    echo "  🎉 WORDPRESS STACK УСПІШНО ВСТАНОВЛЕНО!"
    echo "============================================================"
    echo ""
    echo -e "${GREEN}📱 Доступ:${NC}"
    if [ "$DEPLOY_MODE" = "internet" ]; then
        echo -e "   WordPress: ${BLUE}https://${DOMAIN}${NC}"
        echo -e "   WP-Admin:  ${BLUE}https://${DOMAIN}/wp-admin${NC}"
        echo -e "   🔒 HTTPS автоматично налаштовано через Let's Encrypt"
    else
        IP=$(ip route get 1 | awk '{print $7;exit}')
        echo -e "   WordPress: ${BLUE}http://${IP}${NC}"
        echo -e "   Або:       ${BLUE}http://wp.local${NC}"
        if ! grep -q "wp.local" /etc/hosts; then
            echo -e "   ${YELLOW}Додайте в /etc/hosts:${NC} ${IP} wp.local"
        fi
    fi
    echo ""
    echo -e "${GREEN}🔑 Дані для входу:${NC}"
    echo -e "   Користувач: ${YELLOW}admin${NC}"
    echo -e "   Пароль:     ${YELLOW}$(grep WORDPRESS_ADMIN_PASSWORD ${INSTALL_DIR}/.env | cut -d'=' -f2)${NC}"
    echo ""
    echo -e "${GREEN}🛠️ Управління:${NC}"
    echo -e "   cd ${INSTALL_DIR}"
    echo -e "   make help     - Показати всі команди"
    echo -e "   make logs     - Перегляд логів"
    echo -e "   make backup   - Створити backup"
    echo -e "   make down     - Зупинити сервіси"
    echo ""
    echo -e "${RED}⚠️  ВАЖЛИВО:${NC}"
    echo -e "   - Паролі збережено у: ${INSTALL_DIR}/.env"
    echo -e "   - Ніколи не комітьте .env у репозиторій!"
    echo -e "   - Регулярно створюйте backup: make backup"
    echo ""
    
    if [ "$DEPLOY_MODE" = "internet" ]; then
        echo -e "${GREEN}🔒 Додаткові заходи безпеки:${NC}"
        echo -e "   - Налаштовано nftables firewall"
        echo -e "   - Налаштовано Fail2ban"
        echo -e "   - Автоматичне оновлення сертифікатів Let's Encrypt"
        echo ""
    fi
    
    echo "============================================================"
}

# Головна функція
main() {
    echo "============================================================"
    echo "  PRODUCTION WORDPRESS STACK INSTALLER"
    echo "  Traefik + Nginx + WordPress + MySQL + Security"
    echo "============================================================"
    echo ""
    
    # Парсинг аргументів
    parse_args "$@"
    
    # Перевірка системи
    check_system
    
    # Налаштування безпеки
    setup_nftables
    setup_fail2ban
    
    # Створення структури
    create_project_structure
    
    # Створення конфігурацій
    create_env_file
    create_docker_compose
    create_nginx_config
    create_php_config
    create_scripts
    create_makefile
    create_readme
    
    # Налаштування Traefik залежно від режиму
    if [ "$DEPLOY_MODE" = "internet" ]; then
        setup_traefik_internet
    else
        setup_traefik_lan
    fi
    
    # Запуск та встановлення
    start_services
    install_wordpress
    
    # Фінальна інформація
    show_final_info
}

# Запуск
main "$@"
