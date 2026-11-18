# install-wordpress V2.0.9

Модульний WordPress stack:

- Traefik
- Nginx
- WordPress PHP-FPM
- MySQL 8.4 LTS
- WP-CLI
- Let's Encrypt
- optional Fail2ban
- optional nftables
- backup / restore
- layered healthcheck

## LAN

```bash
./wordpress-stack.sh \
  --mode lan \
  --admin-email admin@example.com
```

Default LAN hostname:

```text
wp.home.arpa
```

На самому сервері WordPress доступний через:

```text
http://wp.home.arpa
http://localhost
http://127.0.0.1
```

Для `wp.home.arpa` на сервері healthcheck використовує локальний DNS override,
тому запис у `/etc/hosts` сервера не потрібен.

Для доступу з іншого LAN-компʼютера додай:

```text
SERVER_IP wp.home.arpa
```

у `/etc/hosts` цього клієнта або створи запис у локальному DNS.

`localhost` та `127.0.0.1` на іншому компʼютері означають сам той компʼютер,
а не WordPress-сервер.

## Чому не .local

`.local` використовується mDNS/Bonjour, тому default LAN hostname у V2.0.9:

```text
wp.home.arpa
```

## LAN WordPress URL behavior

У LAN mode WordPress дозволяє лише ці HTTP Host values:

- configured `${DOMAIN}`;
- `localhost`;
- `127.0.0.1`.

Для них `WP_HOME` та `WP_SITEURL` визначаються динамічно після whitelist-перевірки,
тому WordPress не перекидає `localhost` або `127.0.0.1` назад на primary hostname.

## Internet

```bash
./wordpress-stack.sh \
  --mode internet \
  --domain example.com \
  --email letsencrypt@example.com \
  --admin-email admin@example.com
```

Internet mode не дозволяє localhost aliases через public Traefik router.

## Root-only hardening

```bash
sudo ./wordpress-stack.sh \
  --mode internet \
  --domain example.com \
  --email letsencrypt@example.com \
  --admin-email admin@example.com \
  --dir /srv/wordpress \
  --enable-fail2ban \
  --enable-cron \
  --manage-firewall
```

## Кілька сайтів на одному сервері

Один сервер — один центральний proxy (80/443), сайти — окремі стеки:

```bash
# 1. Разово: центральний proxy (директорія окрема від сайтів!)
sudo ./wordpress-stack.sh --init-proxy \
  --email letsencrypt@example.com \
  --dir /srv/proxy \
  --manage-firewall

# 2. Кожен сайт:
sudo ./wordpress-stack.sh \
  --mode internet \
  --domain site1.example.com \
  --email letsencrypt@example.com \
  --admin-email admin@example.com \
  --dir /srv/wordpress-site1 \
  --no-traefik \
  --enable-cron
```

- `--init-proxy` створює Traefik-стек (ACME, ротація сертифікатів, мережа `wp_proxy`)
- `--no-traefik` — сайт без власного Traefik; nginx приєднується до `wp_proxy`,
  центральний proxy роутить за доменом через docker-лейбли
- Режим `--init-proxy` не підтримує `--enable-fail2ban`, `--enable-cron`, `--enable-redis`,
  `--staging` застосовується до ACME proxy
- `make down` у proxy-стеку перечеплює всі сайти — для оновлення використовуй
  `make restart` або `make pull && make up`
- LAN-режим з `--no-traefik` публікує nginx напряму на `:80` (без центрального proxy)

## Операційні речі (продакшн)

- `--enable-cron` — інсталер встановлює `/etc/cron.d/wordpress-stack`:
  щоденний `backup.sh` о 03:00 та `logrotate-nginx.sh` о 03:30
  (логи: `backups/backup.cron.log`, `logs/logrotate.cron.log`);
- Бекапи зберігаються лише локально (`backups/`) — для продакшну
  налаштуй копіювання поза сервером (rclone/rsync на S3 або інший хост);
- Fail2ban (`--enable-fail2ban`) захищає SSH та `POST /wp-login.php`
  (лог: `logs/nginx/access.log`, maxretry=5 за 10м, бан 1г з ескалацією);
- Ліміти Redis: `REDIS_MEM_LIMIT` має бути більшим за `REDIS_MAXMEMORY`;
- Оновлення: `make update` (backup + pull + recreate), тільки вручну.

## V2.0.9

Додано:

- `server_tokens off` у Nginx (версія не віддається);
- FastCGI `/fpm-ping` endpoint — healthcheck nginx→PHP-FPM через реальний ping, а не тільки `php-fpm -t`;
- `--staging` — Let's Encrypt staging CA для тестування (сертифікати не довірені; для переходу на prod видали `letsencrypt/acme.json`);
- DNS preflight перед Let's Encrypt у internet mode — A-запис має вказувати на сервер (skip через `--force`);
- `nginx/real-ip.conf` — X-Forwarded-For довіряється лише frontend-підмережі `FRONTEND_SUBNET` (фіксована `subnet` у compose), а не всім приватним range;
- `wait_for_services` через `docker inspect` — стійкість до змін формату JSON у Docker Compose;
- Resource limits: `mem_limit` + `pids_limit` для кожного сервісу;
- Ротація nginx логів: `make logs-rotate` (підходить для cron), ретеншн = `BACKUP_RETENTION_DAYS`;
- `VERSION` має єдине джерело — `config/defaults.conf`;
- Smoke-тест installer (`--no-start` у tmp dir) у `tests/run-tests.sh`.

## V2.0.8

Додано:

- default LAN domain `wp.home.arpa`;
- LAN Traefik router для primary hostname + `localhost` + `127.0.0.1`;
- dynamic LAN `WP_HOME/WP_SITEURL` з whitelist;
- healthcheck усіх трьох LAN entry points;
- збережена explicit Traefik `frontend` network з V2.0.7.
