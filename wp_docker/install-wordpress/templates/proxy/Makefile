SHELL := /bin/bash

COMPOSE := docker compose -f compose.yml

.PHONY: help config up down restart status logs healthcheck pull

help: ## Показати список команд
	@awk 'BEGIN {FS = ":.*## "; printf "\n"} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf "\n"

config: ## Перевірити Docker Compose configuration
	$(COMPOSE) config

up: ## Запустити proxy
	$(COMPOSE) up -d --remove-orphans

down: ## Зупинити proxy
	$(COMPOSE) down

restart: ## Перезапустити proxy
	$(COMPOSE) restart

status: ## Стан proxy
	$(COMPOSE) ps

logs: ## Логи Traefik
	$(COMPOSE) logs -f --tail=200 traefik

healthcheck: ## Перевірити Traefik ping
	$(COMPOSE) exec traefik traefik healthcheck --ping

pull: ## Завантажити нові Docker images
	$(COMPOSE) pull
