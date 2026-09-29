#!/bin/sh

color() {
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

color green "[***] START IPTABLES"
sudo systemctl start iptables
sudo systemctl enable iptables

color green "[***] Добавление правил для блокировки всех входящих пакетов, кроме SSH, HTTP, HTTPS и SAMBA"
sudo iptables -A INPUT -i lo -j ACCEPT
sudo iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT 
# sudo iptables -A INPUT -p tcp --dport 22 -j ACCEPT 
sudo iptables -A INPUT -p tcp --dport 2241 -j ACCEPT 
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT 
sudo iptables -A INPUT -p tcp --dport 443 -j ACCEPT 
sudo iptables -A INPUT -p udp -m udp --dport 137 -j ACCEPT
sudo iptables -A INPUT -p udp -m udp --dport 138 -j ACCEPT
sudo iptables -A INPUT -p tcp -m tcp --dport 139 -j ACCEPT
sudo iptables -A INPUT -p tcp -m tcp --dport 445 -j ACCEPT
sudo iptables -A INPUT -j DROP
# sudo iptables -P INPUT DROP

color green "[***] Добавление правил для разрешения исходящих пакетов"
sudo iptables -A OUTPUT -m state --state RELATED,ESTABLISHED -j ACCEPT 
sudo iptables -A OUTPUT -j ACCEPT
# sudo iptables -P OUTPUT DROP

color green "[***] Добавление правил для перенаправления пакетов (если требуется)"
sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT 
sudo iptables -A FORWARD -j DROP
# sudo iptables -P FORWARD DROP

color red "[***] После добавления правил посредством командной строки файл настроек не изменится автоматически — изменения необходимо сохранять командой"
sudo iptables-save -f /etc/iptables/iptables.rules
sudo iptables-restore /etc/iptables/iptables.rules

sudo systemctl restart iptables

color yellow "[***] Вывод текущих правил"
sudo iptables -L -nv
color yellow "[***] END ..."
