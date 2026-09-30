# install-wordpress V2.0.8

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

`.local` використовується mDNS/Bonjour, тому default LAN hostname у V2.0.8:

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
  --manage-firewall
```

## V2.0.8

Додано:

- default LAN domain `wp.home.arpa`;
- LAN Traefik router для primary hostname + `localhost` + `127.0.0.1`;
- dynamic LAN `WP_HOME/WP_SITEURL` з whitelist;
- healthcheck усіх трьох LAN entry points;
- збережена explicit Traefik `frontend` network з V2.0.7.
