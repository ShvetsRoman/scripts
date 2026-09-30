# WordPress Production Stack V2.0

Модульний production stack:

- Traefik
- Let's Encrypt у Internet mode
- Nginx
- WordPress PHP-FPM
- MySQL 8.4
- WP-CLI
- Fail2ban для SSH
- optional nftables integration
- backup / restore
- healthcheck

## Основні команди

```bash
make help
make up
make down
make status
make logs
make backup
make healthcheck
```

WP-CLI:

```bash
make wp CMD="plugin list"
```

Restore:

```bash
make restore BACKUP=2026-09-30_20-00-00
```

## HTTPS

У `internet` mode Traefik автоматично отримує та поновлює
Let's Encrypt certificate.

`letsencrypt/acme.json` зберігається у persistent bind mount.

## LAN

LAN mode працює через HTTP і не вмикає HSTS/FORCE_SSL_ADMIN.

## Secrets

`.env` має mode `0600` і внесений у `.gitignore`.

Не коміть `.env`.

## Firewall

`--manage-firewall` не виконує `flush ruleset` і не переписує
Docker forwarding rules. Installer додає окрему таблицю
`inet wordpress_stack`.

Загальну host policy DROP потрібно налаштовувати окремо після
перевірки всіх сервісів сервера, щоб не заблокувати SSH/VPN.
