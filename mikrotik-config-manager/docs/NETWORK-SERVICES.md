# DHCP, DNS, NAT, IPv6 та WireGuard

Налаштування розділені між `dhcp.toml`, `dns.toml`, `nat.toml`, `firewall.toml`, `ipv6.toml` і `wireguard.toml`. Генератор перевіряє цілісність міжмодульних посилань і порядок виконання команд.

## DHCP та DNS

Пули, мережі, DHCP-сервер і статичні оренди повинні узгоджуватися з адресою LAN. При чистій установці з `no-defaults=yes` налаштовується новий стан; генератор WAN DHCP містить очищення попередніх IPv4 DHCP-клієнтів, тому він **не призначений для звичайного оновлення діючої конфігурації**.

## NAT / Firewall

NAT використовує налаштований WAN; правила INPUT/FORWARD з дозволами розташовуються перед підсумковими DROP. Перевіряйте port forwarding, hairpin NAT і призначення WAN/LAN в обох профілях.

## IPv6 / WireGuard

Параметри IPv6 і VPN управляються TOML, а WireGuard у стандартних профілях вимкнений. Для ввімкнення VPN перевіряйте CIDR, peer-адреси, дозвіл UDP у Firewall, маршрути та відсутність приватних ключів у відкритих виводах. Секрети потрібно зберігати лише приватно.

```bash
cargo run -- plan hap-ac dhcp
cargo run -- plan hap-ac dns
cargo run -- plan hap-ac nat
cargo run -- plan hap-ac firewall
cargo run -- plan hap-ac wireguard
```

Це перевірка плану, **не** виконання RouterOS-команд.
