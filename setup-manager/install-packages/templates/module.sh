#!/usr/bin/env bash
# Змінні цього файла читаються іншими модулями через source.
# shellcheck disable=SC2034
# Шаблон єдиного файла модуля (скопіюйте до modules/mytools.sh).
# Файл виконується через source: додавайте тільки перевірений Bash-код.
MODULE_ID="mytools"                # Збігається з назвою файла
MODULE_TITLE="Мої інструменти"       # Назва в меню
MODULE_ORDER=200                    # Порядок у меню
MODULE_DEPENDS=""                   # Наприклад: "base cli"
MODULE_SERVICES_LIST=""             # Наприклад: "docker"
MODULE_POST_HOOK=""                 # Необов'язкова назва функції нижче

PACMAN_PACKAGES=(jq)
AUR_PACKAGES=()
GITHUB_ITEMS=()
CONFIG_ITEMS=(
    # "mytools|home|.config/mytools|.config/mytools"
)

# Приклад спеціальних дій після встановлення:
# MODULE_POST_HOOK="configure_mytools"
# configure_mytools() {
#     log_info "Налаштування mytools"
#     # Використовуйте run_cmd для команд, що змінюють систему,
#     # аби коректно працював режим --dry-run.
# }
