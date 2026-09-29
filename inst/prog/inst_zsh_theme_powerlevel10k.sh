#!/bin/bash

# Визначити абсолютний шлях до директорії, де лежить цей скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR_CONF="${SCRIPT_DIR}/conf"

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
color green "[*] Installing ZSH..."
sudo pacman -S --noconfirm --needed zsh zsh-completions zsh-syntax-highlighting zsh-autocomplete zsh-autosuggestions

# Додаткове ПО
sudo pacman -S --noconfirm --needed eza grc bat television
 
# Install Theme ZSH
color green "[*] Installing Theme ZSH..."
paru -S --noconfirm --skipreview --needed zsh-theme-powerlevel10k-git
 
# Install Font 
color green "[*] Installing Font ZSH..."
paru -S --noconfirm --skipreview --needed ttf-meslo-nerd-font-powerlevel10k
 
# Delete .bashrc
color green "[*] Delete .bashrc & .bash*..."
if [[ -f "${HOME}/.bashrc" ]]; then
  rm -r "${HOME}/.bash*"
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
color green "[*] Copy config ZSH..."
cp -rfv "${SCRIPT_DIR_CONF}/zsh/". "${HOME}/"
cp -rfv "${SCRIPT_DIR_CONF}/zsh_p10k/". "${HOME}/"

# Install configs ROOT
color green "[*] Install configs ROOT ZSH..."
sudo cp -rfv "${SCRIPT_DIR_CONF}/zsh/". /root/
sudo cp -rfv "${SCRIPT_DIR_CONF}/zsh_p10k/". /root/

# Встановленн Zsh в якості оболонки за вмочуванням
color green "[*] Встановленн Zsh в якості оболонки за вмочуванням..."
sudo chsh -s $(which zsh) "${USER}"
sudo chsh -s $(which zsh) root
