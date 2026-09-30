# Для інтернет-сервера з HTTPS
sudo ./install-wordpress.sh --mode internet --domain example.com --email admin@example.com

# Для локальної мережі
sudo ./install-wordpress.sh --mode lan

# З власною директорією
sudo ./install-wordpress.sh --mode internet --domain example.com --email admin@example.com --dir /srv/wordpress
