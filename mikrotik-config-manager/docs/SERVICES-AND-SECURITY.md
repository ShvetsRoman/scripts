# Services, Management та Firewall

`services.toml` визначає стани служб, порти SSH/WinBox та область допустимих адрес. LAN-підмережа для `address=` обчислюється з `network.toml`.

```toml
[services.ssh]
enabled = true
port = 22
limit_to_lan = true

[services.winbox]
enabled = true
port = 8291
limit_to_lan = true
```

- `limit_to_lan = true`: `/ip service address=` обмежений LAN CIDR (наприклад `192.168.88.0/24`).
- `limit_to_lan = false`: `address=0.0.0.0/0`; це **не відкриває доступ автоматично**, але знімає захист саме на рівні сервісу, тому генерується WARNING.
- `enabled = false`: служба вимкнена незалежно від address.

Firewall INPUT — незалежна перевірка доступу. SSH і WinBox повинні залишатися доступними з керівної LAN-мережі й обмеженими правилами Firewall. Management визначається `network.toml` за `@bridge.lan`, без перевірок назв `test` чи `hap-ac`. Не відкривайте WAN-Management без свідомої зміни політики.

```bash
cargo run -- plan hap-ac services
cargo run -- plan hap-ac firewall
cargo run -- plan test services
```

`services.toml` також вимикає зайві протоколи; параметри конкретних меню залежать від RouterOS 7. Перед установкою звірте версію RouterOS на пристрої.

## Firewall: залежності та WAN-захист

`firewall.enabled = true` обов'язковий для активних політик `input_default_drop`,
`forward_default_drop`, `drop_new_wan` і `brute_force_enabled`. Якщо Firewall
вимкнений, але запитано DROP-політику, PLAN повертає типізовану помилку
`module_firewall_drop_requires_enabled` замість мовчазного ігнорування.
Для `brute_force_enabled` застосовується окремий типізований код помилки.

У прикладі домашнього `routers/hap-ac/firewall.toml` увімкнено
`brute_force_enabled = true` та `icmp_limit_per_second = 10`. Це лише
поточні значення профілю: їх можна змінювати незалежно від назви пристрою.
Захист перебору працює для **нових TCP-з’єднань з WAN** до налаштованих портів,
не аналізує фактичну правильність паролів. LAN-адреси не додаються до
списків блокування цими правилами. Правило blacklist передує переходам
між етапами, а ICMP LAN приймається до WAN-ліміту. Ліміт ICMP можна
вимкнути значенням `0`, якщо потрібна діагностика без обмежень.
Порядок INPUT/FORWARD зберігається генератором; ці параметри не відкривають
доступ до SSH/WinBox з WAN.
