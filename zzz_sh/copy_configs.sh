#!/usr/bin/env bash
set -Eeuo pipefail
 
# ШЛЯХИ
readonly DIR_HOME_CONF="${HOME}/.config"
readonly DIR_COPY_CONF="${HOME}/00_setup/scripts_bash/inst/prog/conf"
 
# СПИСОК КАТАЛОГІВ
# Формат: "шлях|опис"
readonly COPY_DIRS=(
    "alacritty|Alacritty"
    "eza|Eza"
    "helix|Helix"
    "kitty|Kitty"
    "Kvantum|Kvantum"
    "mc|MC"
    "nvim|NeoVim"
    "starship|Starship"
    "television|Television"
    "wezterm|Wezterm"
    "yazi|Yazi"
)
 
# СПИСОК ФАЙЛІВ
# Формат: "джерело|призначення|опис"
readonly COPY_FILES=(
    "${DIR_HOME_CONF}/pikaur.conf|pikaur/pikaur.conf|Pikaur"
    "/etc/environment|system/environment|System environment"
    "${HOME}/.zshrc|zsh/.zshrc|ZSH .zshrc"
    "${HOME}/.zsh_alias.zsh|zsh/.zsh_alias.zsh|ZSH aliases"
    "${HOME}/.zsh_path.zsh|zsh/.zsh_path.zsh|ZSH paths"
    "${HOME}/.p10k_my.zsh|zsh_p10k/.p10k_my.zsh|ZSH theme p10k_my"
    "${HOME}/.p10k_my_nordic_v1.zsh|zsh_p10k/.p10k_my_nordic_v1.zsh|ZSH theme p10k_my_nordic_v1"
)
 
# КОЛЬОРИ
readonly BLUE='\033[0;34m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'
 
# LOGGING
log_info() { echo -e "\n${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1\n"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1\n"; exit 1; }
 
# ЛІЧИЛЬНИКИ
COPIED=0
SKIPPED=0
 
# ОБРОБКА ПОМИЛОК
trap 'log_error "Помилка на рядку ${LINENO}. Скрипт завершено."' ERR
 
# ПЕРЕВІРКА КАТАЛОГУ ПРИЗНАЧЕННЯ
check_destination() {
    # Якщо каталогу немає — створюємо
    if [[ ! -d "${DIR_COPY_CONF}" ]]; then
        log_info "Каталог призначення відсутній. Створення..."
        mkdir -p "${DIR_COPY_CONF}"
        log_success "Каталог призначення створено"
    fi
    # Перевіряємо можливість запису
    if [[ ! -w "${DIR_COPY_CONF}" ]]; then
        log_error "Немає прав на запис: ${DIR_COPY_CONF}"
        exit 1
    fi
    log_success "Каталог призначення доступний для запису"
}
 
# КОПІЮВАННЯ КАТАЛОГУ
copy_dir() {
    local source="$1"
    local destination="$2"
    local description="$3"
    # Перевіряємо існування каталогу
    if [[ ! -d "${source}" ]]; then
        log_warning "${description}: каталог відсутній"
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi
    log_info "Копіювання: ${description}"
    # Створюємо батьківський каталог
    mkdir -p "${DIR_COPY_CONF}/$(dirname "${destination}")"
    # Видаляємо стару копію
    rm -rf "${DIR_COPY_CONF:?}/${destination}"
    # Створюємо каталог призначення
    mkdir -p "${DIR_COPY_CONF}/${destination}"
    # Копіюємо вміст каталогу
    cp -a "${source}/." "${DIR_COPY_CONF}/${destination}/"
    log_success "${description}: скопійовано в ${DIR_COPY_CONF}/${destination}"
    COPIED=$((COPIED + 1))
}
 
# КОПІЮВАННЯ ФАЙЛУ
copy_file() {
    local source="$1"
    local destination="$2"
    local description="$3"
    # Перевіряємо існування файлу
    if [[ ! -f "${source}" ]]; then
        log_warning "${description}: файл відсутній"
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi
    log_info "Копіювання: ${description}"
    # Створюємо батьківський каталог
    mkdir -p "${DIR_COPY_CONF}/$(dirname "${destination}")"
    # Копіюємо файл
    cp -a "${source}" "${DIR_COPY_CONF}/${destination}"
    log_success "${description}: скопійовано в ${DIR_COPY_CONF}/${destination}"
    COPIED=$((COPIED + 1))
}
 
# ПОЧАТОК
log_info "Початок копіювання конфігурації"
check_destination
 
# КОПІЮВАННЯ КАТАЛОГІВ
log_info "Обробка каталогів..."
for item in "${COPY_DIRS[@]}"; do
    IFS='|' read -r path description <<< "${item}"
    copy_dir \
        "${DIR_HOME_CONF}/${path}" \
        "${path}" \
        "${description}"
done
 
# КОПІЮВАННЯ ФАЙЛІВ
log_info "Обробка файлів..."
for item in "${COPY_FILES[@]}"; do
    IFS='|' read -r source destination description <<< "${item}"
    copy_file \
        "${source}" \
        "${destination}" \
        "${description}"
done
 
# ПІДСУМОК
echo
log_success "Копіювання завершено."
echo
echo "=========================================="
echo " Скопійовано : ${COPIED}"
echo " Пропущено   : ${SKIPPED}"
echo "=========================================="
echo
