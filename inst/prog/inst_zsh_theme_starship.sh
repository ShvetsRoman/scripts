#!/usr/bin/env bash

set -Eeuo pipefail

# Визначити абсолютний шлях до директорії, де лежить цей скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR_CONF="${SCRIPT_DIR}/conf"

# HOME .config
HOME_DIR_CONF="${HOME}/.config"

function color() {
  case "$1" in
    red)
      echo -e "\n\033[31m$2\033[0m"
    ;;
    yellow)
      echo -e "\n\033[33m$2\033[0m"
    ;;
    green)
      echo -e "\n\033[32m$2\033[0m"
    ;;
  esac
}

# Встановлення ZSH
color green "[***] Installing ZSH..."
sudo pacman -S --noconfirm --needed zsh zsh-completions zsh-syntax-highlighting zsh-autocomplete zsh-autosuggestions
# Встановлення Starship
color green "[***] Installing Starship..."
sudo pacman -S --noconfirm --needed starship
# Додаткове ПО
color green "[***] Installing PO..."
sudo pacman -S --noconfirm --needed eza grc bat television
 
# Delete .bashrc
color green "[***] Delete .bashrc & .bash*..."
if [[ -f "${HOME}"/.bashrc ]]; then
rm -r "${HOME}"/.bash*
fi

# Backup .zshrc
color green "[*] Installing Backup .zshrc..."
if [[ -n "${HOME}"/.zsh*(N) ]]; then
    mkdir "${HOME}/zsh.backup"
    mv "${HOME}/".zsh* "${HOME}/zsh.backup/"
fi
if [[ -n "${HOME}"/.p10k*(N) ]]; then
    mkdir "${HOME}/zsh.backup"
    mv "${HOME}"/.p10k* "${HOME}/zsh.backup/"
fi

# Copy config
color green "[***] Copy config ZSH..."
cp -rfv "${SCRIPT_DIR_CONF}"/zsh/. "${HOME}/"
color green "[***] Copy config Starship..."
cp -rfv "${SCRIPT_DIR_CONF}/starship" "${HOME_DIR_CONF}/"

# Install configs ROOT
color green "[***] Install configs ROOT ZSH..."
if [[ -d /root/.config ]]; then
  color green "[***] /root/.config існює..."
else
  sudo mkdir -p /root/.config/
fi
color green "[***] Copy config ROOT ZSH..."
sudo cp -rfv "${SCRIPT_DIR_CONF}"/zsh/. /root/
color green "[***] Copy config ROOT Starship..."
sudo cp -rfv "${SCRIPT_DIR_CONF}/starship" /root/.config/

# Встановленн Zsh в якості оболонки за вмочуванням
color green "[***] ROOT & USER ZSH..."
sudo chsh -s $(which zsh) "${USER}"
sudo chsh -s $(which zsh) root
