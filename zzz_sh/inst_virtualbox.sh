#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# ВСТАНОВЛЕННЯ VIRTUALBOX НА ARCH LINUX
# ============================================================

# Перевірка прав адміністратора
if [[ "$EUID" -eq 0 ]]; then
    echo "Не запускайте скрипт від root. Використовуйте звичайного користувача."
    exit 1
fi

# Перевірка sudo
sudo -v

# 1. Повне оновлення системи та встановлення пакетів
sudo pacman -Syu --needed \
    virtualbox \
    virtualbox-host-dkms \
    virtualbox-guest-iso \
    linux-headers \
    dkms

# 2. Перевірка групи USB
if ! id -nG "$USER" | grep -qw vboxusers; then
    sudo usermod -aG vboxusers "$USER"
    echo "Користувача додано до vboxusers."
fi

# 3. Перевірка відповідності ядра
if [[ ! -d "/usr/lib/modules/$(uname -r)/build" ]]; then
    echo "Не знайдено заголовків поточного ядра."
    echo "Потрібне перезавантаження після оновлення."
    sudo reboot
    exit 0
fi

# 4. Збірка модулів VirtualBox
sudo dkms autoinstall

# 5. Завантаження основного модуля
sudo modprobe vboxdrv

# 6. Завантаження мережевих модулів
sudo modprobe vboxnetadp
sudo modprobe vboxnetflt

# 7. Перевірка модулів
if ! lsmod | grep -q '^vboxdrv'; then
    echo "ПОМИЛКА: vboxdrv не завантажений."
    exit 1
fi

# 8. Підсумок
echo
echo "======================================"
echo "VirtualBox успішно встановлено!"
echo "======================================"

VBoxManage --version
dkms status
lsmod | grep '^vbox'

echo
echo "Для USB та нової групи vboxusers"
echo "потрібно повторно увійти в систему."

echo
read -r -p "Перезавантажити комп'ютер зараз? [y/N] " answer

if [[ "$answer" =~ ^[Yy]$ ]]; then
    sudo reboot
fi
