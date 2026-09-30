SHELL := /bin/bash

COMPOSE := docker compose -f compose.yml -f compose.override.yml

.PHONY: help config up down restart status logs logs-nginx logs-wordpress logs-db \
        shell wp install backup restore healthcheck pull update clean

help: ## Показати список команд
	@awk 'BEGIN {FS = ":.*## "; printf "\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\n"

config: ## Перевірити Docker Compose configuration
	$(COMPOSE) config

up: ## Запустити stack
	$(COMPOSE) up -d --remove-orphans

down: ## Зупинити stack
	$(COMPOSE) down

restart: ## Перезапустити stack
	$(COMPOSE) restart

status: ## Статус контейнерів
	$(COMPOSE) ps

logs: ## Логи всього stack
	$(COMPOSE) logs -f --tail=200

logs-nginx: ## Логи Nginx
	$(COMPOSE) logs -f --tail=200 nginx

logs-wordpress: ## Логи PHP-FPM
	$(COMPOSE) logs -f --tail=200 wordpress

logs-db: ## Логи MySQL
	$(COMPOSE) logs -f --tail=200 db

shell: ## Shell WordPress container
	$(COMPOSE) exec wordpress sh

wp: ## WP-CLI: make wp CMD="plugin list"
	$(COMPOSE) exec wpcli wp $(CMD)

install: ## Встановити WordPress
	$(COMPOSE) exec wpcli /scripts/wp-install.sh

backup: ## Створити backup
	./scripts/backup.sh

restore: ## Restore: make restore BACKUP=2026-09-30_20-00-00
	@test -n "$(BACKUP)" || (echo "Вкажи BACKUP=<name>" && exit 1)
	./scripts/restore.sh "$(BACKUP)"

healthcheck: ## Перевірити stack
	./scripts/healthcheck.sh

pull: ## Завантажити нові Docker images
	$(COMPOSE) pull

update: backup pull ## Backup + pull + recreate
	$(COMPOSE) up -d --remove-orphans
	$(COMPOSE) ps

clean: ## Зупинити stack і видалити orphan containers
	$(COMPOSE) down --remove-orphans
