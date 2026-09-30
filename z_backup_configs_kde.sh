#!/usr/bin/env bash

set -Eeuo pipefail

# Кольори
readonly RED='\033[31m'
readonly GREEN='\033[32m'
readonly YELLOW='\033[33m'
readonly BLUE='\033[34m'
readonly CYAN='\033[36m'
readonly NC='\033[0m'

# LOGGING
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }   # FIX: warnings → stderr
log_error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }        # FIX: errors → stderr

log_title() {
    echo
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}============================================================${NC}"
}

log_title_2() {
    echo -e "${CYAN}============================================================${NC}"
}

# Визначити абсолютний шлях до директорії, де лежить цей скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Основні шляхи
BACKUP_DIR="${SCRIPT_DIR}/back_kde"
TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
BACKUP_NAME="kde_settings_$TIMESTAMP.tar.gz"
BACKUP_PATH="$BACKUP_DIR/$BACKUP_NAME"

# Файли та папки, які копіюємо та перевіряємо
readonly CONFIG_ITEMS=(
  "$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
  "$HOME/.config/kdeglobals"
  "$HOME/.config/kwinrc"
  "$HOME/.config/kglobalshortcutsrc"
  "$HOME/.config/kscreenlockerrc"
  "$HOME/.config/krunnerrc"
  "$HOME/.config/dolphinrc"
  "$HOME/.config/konsole"
)

readonly LOCAL_SHARE_ITEMS=(
  "$HOME/.local/share/plasma"
  "$HOME/.local/share/kxmlgui5"
  "$HOME/.local/share/konsole"
)

# Резервне копіювання
backup_kde_settings() {
  log_title "📦 Створюю резервну копію KDE..."

  mkdir -p "$BACKUP_DIR"

  INCLUDE_ITEMS=()

  for item in "${CONFIG_ITEMS[@]}" "${LOCAL_SHARE_ITEMS[@]}"; do
    if [ -e "$item" ]; then
      REL_PATH="${item#$HOME/}"  # відносний шлях
      INCLUDE_ITEMS+=("--transform=s,^$HOME/,," -C "$HOME" "$REL_PATH")
    fi
  done

  if [ ${#INCLUDE_ITEMS[@]} -eq 0 ]; then
    log_warning "⚠️ Немає доступних файлів для резервного копіювання."
    exit 1
  fi

  tar czf "$BACKUP_PATH" "${INCLUDE_ITEMS[@]}"
  if [ $? -eq 0 ]; then
    echo
    log_success "✅ Бекап успішно створено: $BACKUP_PATH"
  else
    echo
    log_error "❌ Помилка під час архівації."
  fi
}

# Відновлення
restore_kde_settings() {
  read -e -p "📂 Вкажи шлях до архіву (.tar.gz): " ARCHIVE

  if [ ! -f "$ARCHIVE" ]; then
    log_error "❌ Архів не знайдено."
    exit 1
  fi

  log_info "🔁 Розпаковую архів..."
  tar xzf "$ARCHIVE" -C "$HOME"

  log_info "🔧 Встановлюю права..."
  chown -R "$USER:$USER" "$HOME/.config" "$HOME/.local/share"

  log_info "🔄 Перезапускаю Plasma..."
  kquitapp5 plasmashell && kstart5 plasmashell

  log_success "✅ Відновлення завершено."
}

# Меню
log_title " KDE Settings Backup Tool"
echo "1) 📥 Резервне копіювання"
echo "2) 🔁 Відновлення"
echo "3) ❌ Вихід"
log_title_2

read -p "Вибери дію (1-3): " choice

case "$choice" in
  1)
    backup_kde_settings
    ;;
  2)
    restore_kde_settings
    ;;
  3)
    log_success "👋 Вихід."
    exit 0
    ;;
  *)
    echo
    log_error "❌ Невірний вибір."
    exit 1
    ;;
esac
