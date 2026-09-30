#!/bin/bash
# Оголошення змінних
FW="sudo iptables"
# Інтерфейс, підключений до Інтернету
WAN="enp0s25"
# Інтерфейс, підключений до локальної мережі
LAN="enp16s0"
# Діапазон адрес локальної мережі
LAN_NET="192.168.88.0/24"

# Очищення всіх ланцюжків та видалення правил
$FW -F
$FW -F -t nat
$FW -F -t mangle
$FW-X
$FW -t nat -X
$FW -t mangle -X

# Дозволити вхідний трафік до інтерфейсу локальної петлі,
# це необхідно для коректної роботи деяких сервісів
$FW -A INPUT -i lo -j ACCEPT

# Дозволити на внутрішньому інтерфейсі весь трафік з локальної мережі
$FW -A INPUT -i $LAN -s $LAN_NET -j ACCEPT

# Дозволяємо два, найбільш безпечні типи пінгу
$FW -A INPUT -p icmp --icmp-type 0 -j ACCEPT
$FW -A INPUT -p icmp --icmp-type 8 -j ACCEPT

# Дозволити вхідні з'єднання, які були дозволені в рамках інших з'єднань
$FW -A INPUT -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Дозволити SSH, HTTP, HTTPS 
$FW -A INPUT -p tcp --dport 2241 -j ACCEPT 
$FW -A INPUT -p tcp --dport 80 -j ACCEPT 
$FW -A INPUT -p tcp --dport 443 -j ACCEPT 

# Дозволити перенаправлення трафіку з внутрішньої мережі назовні, як для нових,так і вже наявних з'єднань у системі
$FW -A FORWARD -i $LAN -o $WAN -m conntrack --ctstate NEW,RELATED,ESTABLISHED -j ACCEPT

# Дозволити перенаправлення лише тих пакетів із зовнішньої мережі всередину, які вже є частиною наявних сполук
$FW -A FORWARD -i $WAN -o $LAN -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

# Виконуємо трансляцію мережевих адрес, що належать локальній мережі
$FW -t nat -A POSTROUTING -o $WAN -s $LAN_NET -j MASQUERADE

# Встановлюємо стандартні політики:
# Вхідний трафік - скидати; Трафік, що проходить - скидати; Вихідний - дозволяти
$FW -P INPUT DROP
$FW -P FORWARD DROP
$FW -P OUTPUT ACCEPT

# Після додавання правил за допомогою командного рядка файл налаштувань не зміниться автоматично – зміни необхідно зберігати командою"
sudo iptables-save -f /etc/iptables/iptables.rules
sudo iptables-restore /etc/iptables/iptables.rules

sudo systemctl restart iptables

# Виведення поточних правил"
sudo iptables -L -nv
