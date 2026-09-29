#!/bin/bash

# ============================================================
# СКРИПТ АВТОМАТИЧНОГО РОЗГОРТАННЯ WORDPRESS СТЕКУ
# ============================================================
# Цей скрипт створює повне оточення WordPress з:
# - Traefik (реверс-проксі)
# - Nginx (веб-сервер)
# - PHP-FPM (обробка PHP)
# - MySQL (база даних)
# - WP-CLI (керування через командний рядок)
# ============================================================

set -e  # Зупиняємо виконання при помилці

# Кольори для виводу
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функції для логування
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}
log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Функція перевірки наявності команд
check_command() {
    if ! command -v $1 &> /dev/null; then
        log_error "$1 не встановлено. Будь ласка, встановіть $1"
        exit 1
    fi
}

# Функція перевірки та створення директорії
create_dir() {
    if [ ! -d "$1" ]; then
        mkdir -p "$1"
        log_success "Створено директорію: $1"
    else
        log_info "Директорія вже існує: $1"
    fi
}

# Функція створення файлу з вмістом
create_file() {
    local file_path="$1"
    local content="$2"
    
    if [ -f "$file_path" ]; then
        log_warning "Файл $file_path вже існує. Створюємо резервну копію."
        cp "$file_path" "${file_path}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    echo "$content" > "$file_path"
    log_success "Створено файл: $file_path"
}

# Перевірка прав доступу
check_root() {
    if [ "$EUID" -eq 0 ]; then 
        log_warning "Запуск від root. Рекомендується запускати від звичайного користувача."
    fi
}

# Отримання IP-адреси сервера
get_server_ip() {
    local ip=""
    
    # Спробуємо отримати IP з параметра або визначити автоматично
    if [ ! -z "$1" ]; then
        ip="$1"
    else
        # Отримуємо основну IP-адресу
        ip=$(ip route get 1 | awk '{print $7;exit}' 2>/dev/null || echo "")
        
        if [ -z "$ip" ]; then
            ip=$(hostname -I | awk '{print $1}')
        fi
    fi
    
    if [ -z "$ip" ]; then
        log_error "Не вдалося визначити IP-адресу сервера"
        log_info "Будь ласка, вкажіть IP-адресу вручну: ./install_wp.sh 192.168.88.7"
        exit 1
    fi
    
    echo "$ip"
}

# Генерація випадкового пароля
generate_password() {
    openssl rand -base64 16 | tr -d '/+=' | cut -c1-20
}

# ФУНКЦІЯ ЗАВАНТАЖЕННЯ .env ФАЙЛУ
load_env() {
    local env_file="${1:-.env}"
    
    if [ ! -f "$env_file" ]; then
        log_warning "Файл $env_file не знайдено. Створюємо стандартний .env файл..."
        create_default_env
    fi
    
    log_info "Завантаження конфігурації з $env_file..."
    
    # Читаємо .env файл рядок за рядком
    while IFS='=' read -r key value; do
        # Пропускаємо коментарі та порожні рядки
        [[ $key =~ ^#.*$ ]] && continue
        [[ -z $key ]] && continue
        
        # Видаляємо пробіли навколо ключа
        key=$(echo "$key" | xargs)
        
        # Видаляємо лапки з значення (якщо є)
        value=$(echo "$value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        
        # Експортуємо змінну
        export "$key=$value"
    done < "$env_file"
    
    log_success "Конфігурацію завантажено"
}

create_default_env() {
    # ============================================================
    # СТВОРЕННЯ .env ФАЙЛУ
    # ============================================================
    log_info "Створення файлу конфігурації .env..."
    
    cat > .env << 'EOF'
# ================== МЕРЕЖЕВІ НАЛАШТУВАННЯ ==================
HOST=db
SERVER_IP=${SERVER_IP}
WORDPRESS_HOST=wp.${SERVER_IP}.nip.io
TRAEFIK_HOST=traefik.${SERVER_IP}.nip.io

# ================== БАЗА ДАНИХ ==================
MYSQL_DATABASE=db-wp-site
MYSQL_USER=sql_roman
MYSQL_PASSWORD=${MYSQL_PASSWORD}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}

# ================== WORDPRESS НАЛАШТУВАННЯ ==================
WORDPRESS_TITLE="Мій WordPress Сайт"
WORDPRESS_ADMIN_USER=roman
WORDPRESS_ADMIN_PASSWORD=${WORDPRESS_ADMIN_PASSWORD}
WORDPRESS_ADMIN_EMAIL=admin@example.com

# ================== ШЛЯХИ ДЛЯ ЗБЕРІГАННЯ ДАНИХ ==================
DB_DATA_P=data/mysql
WP_DATA_P=data/wordpress
WP_DATA_CONFIG_P=data/wp_config
WP_DATA_CONTENT_P=data/wp_content
WP_DATA_THEMES_P=data/wp_themes
WP_DATA_PLUGINS_P=data/wp_plugins

DB_DATA_PATH=./data/mysql
WP_DATA_PATH=./data/wordpress
WP_DATA_CONFIG_PATH=./data/wp_config
WP_DATA_CONTENT_PATH=./data/wp_content
WP_DATA_THEMES_PATH=./data/wp_themes
WP_DATA_PLUGINS_PATH=./data/wp_plugins

NGINX_CONFIG_PATH=./nginx/default.conf

# ================== ВЕРСІЇ ОБРАЗІВ ==================
TRAEFIK_VERSION=3.6.14
WORDPRESS_VERSION=php8.3-fpm-alpine
MYSQL_VERSION=8.0
NGINX_VERSION=alpine
EOF

    # Заміна змінних у .env файлі
    sed -i "s/\${SERVER_IP}/$SERVER_IP/g" .env
    sed -i "s/\${MYSQL_PASSWORD}/$MYSQL_PASSWORD/g" .env
    sed -i "s/\${MYSQL_ROOT_PASSWORD}/$MYSQL_ROOT_PASSWORD/g" .env
    sed -i "s/\${WORDPRESS_ADMIN_PASSWORD}/$WORDPRESS_ADMIN_PASSWORD/g" .env
    
    log_success ".env файл створено"
    log_warning "Запустіть скрипт ще раз після редагування .env"
    exit 0
}

# ФУНКЦІЯ ВАЛІДАЦІЇ ЗМІННИХ
validate_env() {
    local required_vars=(
        "SERVER_IP"
        "WORDPRESS_HOST" 
        "TRAEFIK_HOST"
        "MYSQL_DATABASE"
        "MYSQL_USER"
        "MYSQL_PASSWORD"
        "MYSQL_ROOT_PASSWORD"
    )
    
    local missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Відсутні обов'язкові змінні в .env:"
        printf '%s\n' "${missing_vars[@]}"
        exit 1
    fi
    
    log_success "Всі обов'язкові змінні присутні"
}

# ============================================================
# ГОЛОВНА ФУНКЦІЯ ВСТАНОВЛЕННЯ
# ============================================================
main() {
    
    echo "============================================================"
    echo "  WORDPRESS STACK INSTALLER"
    echo "  Traefik + Nginx + WordPress + MySQL + WP-CLI"
    echo "============================================================"
    echo ""

    # Перевірка необхідних команд
    log_info "Перевірка необхідних компонентів..."
    check_command docker
    check_command docker compose
    check_command openssl
    
    # Отримання IP-адреси
    SERVER_IP=$(get_server_ip "$1")
    log_success "Використовуємо IP-адресу: $SERVER_IP"
    
    # Генерація паролів
    MYSQL_ROOT_PASSWORD=$(generate_password)
    MYSQL_PASSWORD=$(generate_password)
    WORDPRESS_ADMIN_PASSWORD=$(generate_password)
    
    # Завантажуємо .env файл
    load_env ".env"
    
    # Валідуємо змінні
    validate_env
    
    # Виводимо завантажені налаштування
    log_info "Завантажені налаштування:"
    echo "  SERVER_IP:              ${SERVER_IP}"
    echo "  WORDPRESS_TITLE:        ${WORDPRESS_TITLE}"
    echo "  WORDPRESS_HOST:         ${WORDPRESS_HOST}"
    echo "  WORDPRESS_ADMIN_USER:   ${WORDPRESS_ADMIN_USER}"
    echo "  TRAEFIK_HOST:           ${TRAEFIK_HOST}"
    echo "  MYSQL_DATABASE:         ${MYSQL_DATABASE}"
    echo "  MYSQL_USER:             ${MYSQL_USER}"
    echo "  DB_DATA_P:              ${DB_DATA_P}"
    echo "  WP_DATA_P:              ${WP_DATA_P}"
    echo "  DB_DATA_PATH:           ${DB_DATA_PATH}"
    echo "  WP_DATA_PATH:           ${WP_DATA_PATH}"
    echo ""
    
    # Створення структури проєкту
    PROJECT_DIR="./"
    log_info "Створення структури проєкту в директорії: $PROJECT_DIR"
    
    create_dir "$PROJECT_DIR"
    cd "$PROJECT_DIR"
    
    # Створення піддиректорій
    create_dir "nginx"
    create_dir "scripts"
    create_dir "${DB_DATA_P}"
    create_dir "${WP_DATA_P}"
    create_dir "${WP_DATA_CONFIG_P}"
    create_dir "${WP_DATA_CONTENT_P}"
    create_dir "${WP_DATA_THEMES_P}"
    create_dir "${WP_DATA_PLUGINS_P}"
    
    
    # ============================================================
    # СТВОРЕННЯ docker-compose.yml
    # ============================================================
    log_info "Створення docker-compose.yml..."
    
    cat > docker-compose.yml << 'EOF'
services:
  # ================== TRAEFIK ==================
  traefik:
    image: traefik:${TRAEFIK_VERSION:-3.6.6}
    container_name: traefik
    restart: always
    command:
      - "--api.dashboard=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--log.level=INFO"
    ports:
      - "80:80"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - web
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.dashboard.rule=Host(`${TRAEFIK_HOST}`)"
      - "traefik.http.routers.dashboard.service=api@internal"

  # ================== WORDPRESS (PHP-FPM) ==================
  wordpress:
    image: wordpress:${WORDPRESS_VERSION:-php8.3-fpm-alpine}
    container_name: wordpress-app
    restart: always
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: ${MYSQL_USER}
      WORDPRESS_DB_PASSWORD: ${MYSQL_PASSWORD}
      WORDPRESS_DB_NAME: ${MYSQL_DATABASE}
      WORDPRESS_CONFIG_EXTRA: |
        define('WP_HOME','http://${WORDPRESS_HOST}');
        define('WP_SITEURL','http://${WORDPRESS_HOST}');
        define('WP_DEBUG', false);
        define('FS_METHOD', 'direct');
    volumes:
      - ${WP_DATA_PATH:-wp_data}:/var/www/html
      - ${WP_DATA_CONFIG_PATH}:/usr/local/etc/php/conf.d/uploads.ini
      - ${WP_DATA_CONTENT_PATH}:/var/www/html/wp-content/uploads
      - ${WP_DATA_THEMES_PATH}:/var/www/html/wp-content/themes
      - ${WP_DATA_PLUGINS_PATH}:/var/www/html/wp-content/plugins
    networks:
      - web
      - internal
    depends_on:
      db:
        condition: service_healthy

  # ================== NGINX ==================
  nginx:
    image: nginx:${NGINX_VERSION:-alpine}
    container_name: wordpress-nginx
    restart: always
    volumes:
      - ${WP_DATA_PATH:-wp_data}:/var/www/html:ro
      - ${NGINX_CONFIG_PATH:-./nginx/default.conf}:/etc/nginx/conf.d/default.conf:ro
    networks:
      - web
    depends_on:
      - wordpress
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.nginx.rule=Host(`${WORDPRESS_HOST}`)"
      - "traefik.http.services.nginx.loadbalancer.server.port=80"

  # ================== MySQL ==================
  db:
    image: mysql:${MYSQL_VERSION:-8.0}
    container_name: wordpress-db
    restart: always
    environment:
      MYSQL_ROOT_PASSWORD: ${MYSQL_ROOT_PASSWORD}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      MYSQL_PASSWORD: ${MYSQL_PASSWORD}
    volumes:
      - ${DB_DATA_PATH:-db_data}:/var/lib/mysql
    networks:
      - internal
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "root", "-p${MYSQL_ROOT_PASSWORD}"]
      timeout: 10s
      retries: 10
      interval: 10s
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
      - --default-authentication-plugin=mysql_native_password

  # ================== WP-CLI ==================
  wpcli:
    image: wordpress:cli
    container_name: wp-cli-tool
    user: "33:33"
    env_file:
      - .env
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: ${MYSQL_USER}
      WORDPRESS_DB_PASSWORD: ${MYSQL_PASSWORD}
      WORDPRESS_DB_NAME: ${MYSQL_DATABASE}
    volumes:
      - ${WP_DATA_PATH:-wp_data}:/var/www/html
      - ./scripts/wp-setup.sh:/usr/local/bin/wp-setup.sh:ro
    networks:
      - internal
    depends_on:
      db:
        condition: service_healthy
      wordpress:
        condition: service_started
    command: tail -f /dev/null

volumes:
  db_data:
    name: wordpress_db_data
  wp_data:
    name: wordpress_wp_data

networks:
  web:
    name: traefik_network
    driver: bridge
  internal:
    name: wordpress_internal
    driver: bridge
EOF
    
    log_success "docker-compose.yml створено"
    
    # ============================================================
    # СТВОРЕННЯ КОНФІГУРАЦІЇ NGINX
    # ============================================================
    log_info "Створення конфігурації Nginx..."
    
    cat > nginx/default.conf << 'EOF'
server {
    listen 80;
    listen [::]:80;
    server_name _;
    
    root /var/www/html;
    index index.php index.html index.htm;
    
    # Збільшуємо ліміт завантаження файлів
    client_max_body_size 64M;
    
    # Основний локейшн для WordPress
    location / {
        try_files $uri $uri/ /index.php?$args;
    }
    
    # Передача PHP-запитів у PHP-FPM
    location ~ \.php$ {
        try_files $uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        fastcgi_pass wordpress:9000;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO $fastcgi_path_info;
        fastcgi_param HTTP_HOST $host;
        include fastcgi_params;
        
        # Збільшуємо таймаути для довгих операцій
        fastcgi_read_timeout 300;
        fastcgi_send_timeout 300;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
    }
    
    # Заборона доступу до прихованих файлів
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    # Заборона доступу до чутливих файлів WordPress
    location ~* (wp-config\.php|xmlrpc\.php|wp-config-sample\.php|readme\.html|license\.txt) {
        deny all;
        return 404;
    }
    
    # Кешування статичних файлів
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|svg|woff|woff2|ttf|eot|webp|avif)$ {
        expires max;
        add_header Cache-Control "public, immutable";
        add_header X-Content-Type-Options nosniff;
        access_log off;
    }
    
    # Стиснення контенту
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
    
    # Безпека
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
}
EOF
    
    log_success "Конфігурація Nginx створена"
    
    # ============================================================
    # СТВОРЕННЯ СКРИПТА АВТОМАТИЧНОГО НАЛАШТУВАННЯ WORDPRESS
    # ============================================================
    log_info "Створення скрипта налаштування WordPress..."
    
    cat > scripts/wp-setup.sh << 'EOF'
#!/usr/bin/env bash

set -e

echo "=== Автоматичне налаштування WordPress через WP-CLI ==="

# Чекаємо на готовність WordPress
echo "Очікування готовності WordPress..."
until wp core is-installed --allow-root 2>/dev/null; do
    if [ $? -eq 1 ]; then
        echo "WordPress ще не встановлено, продовжуємо..."
        break
    fi
    echo "Очікування..."
    sleep 5
done

# Встановлюємо WordPress якщо потрібно
if ! wp core is-installed --allow-root 2>/dev/null; then
    echo "Встановлення WordPress..."
    
    # Отримуємо змінні оточення
    SITE_URL="http://${WORDPRESS_HOST:-localhost}"
    SITE_TITLE="${WORDPRESS_TITLE:-Мій WordPress Сайт}"
    ADMIN_USER="${WORDPRESS_ADMIN_USER:-admin}"
    ADMIN_PASS="${WORDPRESS_ADMIN_PASSWORD:-admin123}"
    ADMIN_EMAIL="${WORDPRESS_ADMIN_EMAIL:-admin@example.com}"
    
    wp core install \
        --url="$SITE_URL" \
        --title="$SITE_TITLE" \
        --admin_user="$ADMIN_USER" \
        --admin_password="$ADMIN_PASS" \
        --admin_email="$ADMIN_EMAIL" \
        --skip-email \
        --allow-root
    
    echo "Налаштування постійних посилань..."
    wp rewrite structure '/%postname%/' --allow-root
    wp rewrite flush --allow-root
    
    echo "Видалення стандартних плагінів та тим..."
    wp plugin delete hello akismet --allow-root 2>/dev/null || true
    wp theme delete twentytwentythree twentytwentytwo --allow-root 2>/dev/null || true
    
    echo "Встановлення української локалізації..."
    wp language core install uk --allow-root 2>/dev/null || true
    wp site switch-language uk --allow-root 2>/dev/null || true
    
    echo "Налаштування параметрів сайту..."
    wp option update timezone_string "Europe/Kiev" --allow-root
    wp option update date_format "d.m.Y" --allow-root
    wp option update time_format "H:i" --allow-root
    wp option update blogdescription "Створено за допомогою Docker Stack" --allow-root
    
    echo "Оновлення WordPress та компонентів..."
    wp core update --allow-root --quiet 2>/dev/null || true
    wp plugin update --all --allow-root --quiet 2>/dev/null || true
    wp theme update --all --allow-root --quiet 2>/dev/null || true
    
    echo "=== Налаштування WordPress завершено успішно! ==="
else
    echo "WordPress вже встановлено. Пропускаємо встановлення."
    echo "Поточні налаштування сайту:"
    wp option get siteurl --allow-root
fi
EOF
    
    chmod +x scripts/wp-setup.sh
    log_success "Скрипт налаштування WordPress створено"
    
    # ============================================================
    # СТВОРЕННЯ MAKEFILE
    # ============================================================
    log_info "Створення Makefile..."
    
    cat > Makefile << 'EOF'
.PHONY: help up down restart logs shell wp-cli clean install backup restore status clean-backups

# Підключаємо .env
include .env
export

# -------------------- HELP --------------------
help: ## Показати список команд
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
	awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

# -------------------- DOCKER --------------------
up: ## Запустити всі сервіси
	docker compose up -d
	@echo "================================================"
	@echo "Сервіси запущено!"
	@echo "WordPress: http://wp.$(SERVER_IP).nip.io"
	@echo "Traefik:   http://traefik.$(SERVER_IP).nip.io"
	@echo "================================================"

down: ## Зупинити всі сервіси
	docker compose down

restart: down up ## Перезапуск

logs: ## Логи всіх сервісів
	docker compose logs -f

logs-nginx: ## Логи nginx
	docker compose logs -f nginx

logs-wordpress: ## Логи wordpress
	docker compose logs -f wordpress

logs-db: ## Логи MySQL
	docker compose logs -f db

status: ## Статус сервісів
	docker compose ps

# -------------------- SHELL --------------------
shell: ## Увійти в wordpress контейнер
	docker compose exec wordpress bash

shell-nginx: ## Увійти в nginx контейнер
	docker compose exec nginx sh

wp-cli: ## WP CLI (make wp-cli CMD="plugin list")
	docker compose exec wpcli wp $(CMD) --allow-root

# -------------------- INSTALL --------------------
install: ## Авто-інсталяція WordPress
	@echo "Запуск установки..."
	docker compose exec wpcli bash /usr/local/bin/wp-setup.sh

# -------------------- CLEAN --------------------
clean: ## ⚠️ Видалити всі дані
	@read -p "Ви впевнені? Це видалить ВСЕ! [y/N] " -n 1 -r; \
	echo ""; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		docker compose down -v; \
		rm -rf data/; \
		rm -rf backups/; \
		echo "Дані видалено"; \
	else \
		echo "Скасовано"; \
	fi

# -------------------- BACKUP --------------------
backup: ## Створити backup (DB + файли)
	@set -e; \
	BACKUP_DIR=backups/$$(date +%Y%m%d_%H%M%S); \
	mkdir -p $$BACKUP_DIR; \
	echo "📦 Backup: $$BACKUP_DIR"; \
	\
	echo "[1/2] Dump БД..."; \
	docker compose exec -T db mysqldump \
		--no-tablespaces \
		-u$$MYSQL_USER \
		-p$$MYSQL_PASSWORD \
		$$MYSQL_DATABASE \
	| gzip > $$BACKUP_DIR/database.sql.gz; \
	\
	echo "[2/2] Архівація файлів..."; \
	tar -czf $$BACKUP_DIR/wordpress.tar.gz -C data \
		wordpress \
		wp_config \
		wp_content \
		wp_plugins \
		wp_themes; \
	\
	echo "✅ Backup створено: $$BACKUP_DIR"

# -------------------- RESTORE --------------------
restore: ## Відновлення (make restore DATE=YYYYMMDD_HHMMSS)
	@if [ -z "$(DATE)" ]; then \
		echo "Використання: make restore DATE=YYYYMMDD_HHMMSS"; \
		echo "Доступні backup:"; \
		ls -1 backups/ 2>/dev/null || echo "Немає"; \
		exit 1; \
	fi
	@set -e; \
	BACKUP_DIR=backups/$(DATE); \
	\
	if [ ! -d "$$BACKUP_DIR" ]; then \
		echo "❌ $$BACKUP_DIR не знайдено"; \
		exit 1; \
	fi; \
	\
	echo "[1/3] Restore БД..."; \
	gunzip < $$BACKUP_DIR/database.sql.gz | docker compose exec -T db mysql \
		-u$$MYSQL_USER \
		-p$$MYSQL_PASSWORD \
		$$MYSQL_DATABASE; \
	\
	echo "[2/3] Backup старих файлів..."; \
	mv data/wordpress data/wordpress_old_$$(date +%s) 2>/dev/null || true; \
	\
	echo "[3/3] Розпакування..."; \
	mkdir -p data; \
	tar -xzf $$BACKUP_DIR/wordpress.tar.gz -C data; \
	\
	echo "✅ Restore завершено"

# -------------------- ROTATION --------------------
clean-backups: ## Видалити backup старше 7 днів
	find backups/ -mindepth 1 -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;
	@echo "Старі backup очищено"
EOF
    
    log_success "Makefile створено"
    
    # ============================================================
    # СТВОРЕННЯ .gitignore
    # ============================================================
    log_info "Створення .gitignore..."
    
    cat > .gitignore << 'EOF'
# Змінні оточення з паролями
.env
.env.*

# Дані
data/
backups/

# Резервні копії
*.backup.*

# Системні файли
.DS_Store
Thumbs.db

# Логи
*.log

# Тимчасові файли
tmp/
temp/
EOF
    
    log_success ".gitignore створено"
    
    # ============================================================
    # СТВОРЕННЯ README.md
    # ============================================================
    log_info "Створення README.md..."
    
    cat > README.md << EOF
# WordPress Docker Stack

Автоматично розгорнутий WordPress стек із використанням Docker Compose.

## 🚀 Швидкий старт

### Доступ до сервісів:
- **WordPress**: http://${WORDPRESS_HOST}
- **Панель Traefik**: http://${TRAEFIK_HOST}
- **WP-Admin**: http://${WORDPRESS_HOST}/wp-admin

### Дані для входу:
- **Користувач**: ${WORDPRESS_ADMIN_USER}
- **Пароль**: ${WORDPRESS_ADMIN_PASSWORD}

### Дані MySQL:
- **Користувач**: ${MYSQL_USER}
- **Пароль**: ${MYSQL_PASSWORD}
- **База даних**: ${MYSQL_DATABASE}

## 📋 Керування

\`\`\`bash
# Запуск сервісів
docker compose up -d

# Зупинка сервісів
docker compose down

# Перегляд логів
docker compose logs -f

# Використання WP-CLI
docker compose exec wpcli wp plugin list --allow-root

# Або використовуйте Makefile
make help
make up
make install
make backup
\`\`\`

## 🔒 Безпека

Паролі збережено у файлі \`.env\`. Ніколи не комітьте цей файл у репозиторій!

## 📦 Структура проєкту

\`\`\`
.
├── docker-compose.yml    # Конфігурація сервісів
├── .env                  # Змінні оточення (паролі)
├── Makefile              # Команди для керування
├── nginx/
│   └── default.conf      # Конфігурація Nginx
├── scripts/
│   └── wp-setup.sh       # Скрипт автоналаштування WP
└── data/
    ├── mysql/            # Дані MySQL
    └── wordpress/        # Файли WordPress
\`\`\`
EOF
    
    log_success "README.md створено"
    
    # ============================================================
    # ЗАПУСК СЕРВІСІВ
    # ============================================================
    echo ""
    echo "============================================================"
    echo "  СТРУКТУРУ ПРОЄКТУ СТВОРЕНО УСПІШНО!"
    echo "============================================================"
    echo ""
    
    log_info "Запуск Docker сервісів..."
    docker compose up -d
    
    echo ""
    log_info "Очікування запуску всіх сервісів (приблизно 30 секунд)..."
    
    # Чекаємо на готовність MySQL
    log_info "Очікування готовності MySQL..."
    sleep 15
    
    # Чекаємо на готовність WordPress
    log_info "Очікування готовності WordPress..."
    sleep 15
    
    # Встановлюємо WordPress
    log_info "Автоматичне встановлення та налаштування WordPress..."
    docker compose exec -T wpcli bash /usr/local/bin/wp-setup.sh || {
        log_warning "Не вдалося автоматично налаштувати WordPress"
        log_info "Ви можете зробити це пізніше командою: make install"
    }
    
    # ============================================================
    # СТВОРЕННЯ CONFIG WORDPRESS
    # ============================================================
    log_info "Створення uploads.ini..."
    
    cat > ${WP_DATA_CONFIG_PATH}/uploads.ini << 'EOF'
file_uploads = On
memory_limit = 1024M
upload_max_filesize = 1024M
post_max_size = 1024M
max_executation_time = 1200
max_input_vars = 2000
EOF
    
    log_success "uploads.ini створено"

    # ============================================================
    # ВИВЕДЕННЯ ІНФОРМАЦІЇ
    # ============================================================
    echo ""
    echo "============================================================"
    echo "  🎉 WORDPRESS УСПІШНО ВСТАНОВЛЕНО!"
    echo "============================================================"
    echo ""
    echo -e "${GREEN}📱 Доступ до сайтів:${NC}"
    echo -e "   WordPress: ${BLUE}http://${WORDPRESS_HOST}${NC}"
    echo -e "   WP-Admin:  ${BLUE}http://${WORDPRESS_HOST}/wp-admin${NC}"
    echo -e "   Traefik:   ${BLUE}http://${TRAEFIK_HOST}${NC}"
    echo ""
    echo -e "${GREEN}🔑 Дані для входу в WordPress:${NC}"
    echo -e "   Користувач: ${YELLOW}${WORDPRESS_ADMIN_USER}${NC}"
    echo -e "   Пароль:     ${YELLOW}${WORDPRESS_ADMIN_PASSWORD}${NC}"
    echo ""
    echo -e "${GREEN}🗄️ Дані для підключення до MySQL:${NC}"
    echo -e "   Хост:       ${YELLOW}${HOST}${NC}"
    echo -e "   База даних: ${YELLOW}${MYSQL_DATABASE}${NC}"
    echo -e "   Користувач: ${YELLOW}${MYSQL_USER}${NC}"
    echo -e "   Пароль:     ${YELLOW}${MYSQL_PASSWORD}${NC}"
    echo -e "   Root пароль: ${YELLOW}${MYSQL_ROOT_PASSWORD}${NC}"
    echo ""
    echo -e "${GREEN}💾 Розташування файлів:${NC}"
    echo -e "   Директорія проєкту: ${YELLOW}$(pwd)${NC}"
    echo -e "   Файли WordPress:    ${YELLOW}$(pwd)/${WP_DATA_P}${NC}"
    echo -e "   Config WordPress:   ${YELLOW}$(pwd)/${WP_DATA_CONFIG_P}${NC}"
    echo -e "   База даних:         ${YELLOW}$(pwd)/${DB_DATA_P}${NC}"
    echo ""
    echo -e "${GREEN}🛠️ Корисні команди:${NC}"
    echo -e "   Перегляд логів:     ${YELLOW}make logs${NC}"
    echo -e "   WP-CLI команди:     ${YELLOW}make wp-cli CMD=\"plugin list\"${NC}"
    echo -e "   Резервна копія:     ${YELLOW}make backup${NC}"
    echo -e "   Зупинка сервісів:   ${YELLOW}make down${NC}"
    echo ""
    echo -e "${RED}⚠️  ВАЖЛИВО: Збережіть паролі в безпечному місці!${NC}"
    echo -e "${RED}   Вони знаходяться у файлі: $(pwd)/.env${NC}"
    echo ""
    echo "============================================================"
    
    # Зберігаємо паролі в окремий файл
    cat > passwords.txt << EOF
============================================
ПАРОЛІ WORDPRESS СТЕКУ
Дата встановлення: $(date)
Сервер: ${SERVER_IP}
============================================

WordPress Admin:
  URL: http://${WORDPRESS_HOST}/wp-admin
  Користувач: ${WORDPRESS_ADMIN_USER}
  Пароль: ${WORDPRESS_ADMIN_PASSWORD}

MySQL:
  База даних: ${MYSQL_DATABASE}
  Користувач: ${MYSQL_USER}
  Пароль: ${MYSQL_PASSWORD}
  Root пароль: ${MYSQL_ROOT_PASSWORD}

УВАГА: Збережіть цей файл у безпечному місці!
============================================
EOF
    
    log_success "Паролі збережено у файлі: passwords.txt"
    log_warning "Рекомендуємо видалити файл passwords.txt після збереження паролів!"
}

# ============================================================
# ЗАПУСК ГОЛОВНОЇ ФУНКЦІЇ
# ============================================================

# Перевіряємо аргументи командного рядка
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "Використання: $0 [IP-адреса]"
    echo ""
    echo "Скрипт для автоматичного розгортання WordPress стеку"
    echo ""
    echo "Аргументи:"
    echo "  IP-адреса    IP-адреса сервера (опціонально)"
    echo "               Якщо не вказано, визначається автоматично"
    echo ""
    echo "Приклад:"
    echo "  $0 192.168.88.7"
    exit 0
fi

# Запускаємо головну функцію
main "$@"
