# MikroTik hAP ac — RouterOS 7 (базове налаштування + WireGuard SSH)

Конфігурація для **MikroTik hAP ac RB962UiGS-5HacT2HnT**, RouterOS 7 із встановленим пакетом **legacy `wireless`**. Включає LAN/WAN, Wi-Fi, DHCP, DNS, захист Firewall, підтримку пробросу портів (DST-NAT) і окремий WireGuard VPN для SSH до домашнього сервера.

> **Увага:** скрипти призначені для **чистої конфігурації** (після `no-defaults=yes`) і **не є ідемпотентними**. Не імпортуй повторно без перевірки: можуть виникнути дублікати правил та помилки. Виконуй налаштування локально, через Ethernet, за можливості в **Safe Mode** або з резервним доступом через MAC WinBox. Скрипт **не виконує скидання** самостійно.

## Файли

| Файл | Призначення |
|---|---|
| `01-base-hap-ac.rsc` | Основне налаштування маршрутизатора, Wi-Fi, DHCP, DNS, NAT, Firewall, FastTrack і служб |
| `02-wireguard-ssh.rsc` | WireGuard VPN сервер, Cloud DDNS і доступ VPN-клієнта до SSH сервера |
| `wireguard-client-example.conf` | Шаблон Linux WireGuard клієнта |
| `README.md` | Інструкція з установлення, перевірки й відновлення |

## Схема мережі

| Параметр | Значення |
|---|---|
| WAN | `00_WAN` (ether1), DHCP-клієнт |
| Bridge LAN | `00_LAN-Bridge` |
| LAN | `192.168.88.0/24` |
| MikroTik LAN IP | `192.168.88.1` |
| DHCP dynamic pool | `192.168.88.100–192.168.88.200` |
| Статичні DHCP lease | `192.168.88.5–192.168.88.20` (усі зі старого скрипта) |
| Wi-Fi SSID (2.4 та 5 ГГц) | `HOME_test` |
| DNS | `1.1.1.3`, `1.0.0.3` (Cloudflare Family: malware + adult content filtering) |
| Адміністратор | `roman`, пароль встановлюється в скрипті |
| Дозволений ПК адміністратора | `192.168.88.11` |
| MikroTik SSH | TCP `2240`, лише з `192.168.88.11` |
| MikroTik WinBox | TCP `48291`, лише з `192.168.88.11` за IP |
| Домашній сервер | `192.168.88.7` |
| SSH домашнього сервера | TCP `2241` |
| WireGuard | `wg-remote`, UDP `51820` |
| WireGuard MikroTik | `10.77.0.1/24` |
| WireGuard клієнт | `10.77.0.2/32` |
| Часовий пояс | `Europe/Kyiv` |

> **Не плутай:** TCP 2240 — SSH **самого MikroTik**, TCP 2241 — SSH **домашнього сервера**. З інтернету SSH сервера не відкривається напряму; доступ передбачено через VPN.

## 1. Перед початком

1. Підключи комп'ютер кабелем до LAN-порту та підготуй резервний спосіб доступу (MAC WinBox/консоль). Після скидання без стандартної конфігурації LAN IP може бути відсутній.
2. Переконайся, що встановлено **RouterOS 7** і пакет `wireless`, доступні `wlan1` та `wlan2`:

   ```routeros
   /system resource print
   /system package print
   /interface wireless print
   /interface print
   ```

3. Якщо роутер ще налаштований, збережи копії **до скидання**:

   ```routeros
   /system backup save name=before-hap-ac
   /export file=before-hap-ac
   ```

   Скопіюй обидва файли на комп'ютер. Binary backup містить чутливі дані — зберігай його захищено.
4. Врахуй, що команда нижче **видаляє поточні налаштування** та може обірвати доступ:

   ```routeros
   /system reset-configuration no-defaults=yes skip-backup=yes
   ```

   Застосовуй її **лише якщо свідомо хочеш скинути** маршрутизатор і вже маєш резервні копії.

## 2. Встановити базовий конфіг

Відкрий `01-base-hap-ac.rsc` у редакторі та **обов'язково** заміни:

```routeros
:local adminPass "CHANGE_ME_ADMIN_STRONG_PASSWORD"
:local wifiPass "CHANGE_ME_WIFI_STRONG_PASSWORD"
```

Вибери власні сильні паролі; початковий пароль Wi-Fi з попередньої конфігурації більше не використовуй. Зважай на екранування спеціальних символів у рядках RouterOS. За потреби зміни SSID `HOME_test` і перевір MAC-адреси статичних DHCP lease.

Завантаж файл через WinBox **Files** або іншим способом на MikroTik, потім у Terminal:

```routeros
/import file-name=01-base-hap-ac.rsc verbose=yes
```

**Перевір після імпорту:**

```routeros
/interface bridge port print
/interface wireless print
/ip dhcp-client print detail
/ip address print
/ip route print
/ip dhcp-server lease print
/ip firewall filter print stats
/ip dns print
/ip service print
```

Перевір отримання IP клієнтом, вихід в інтернет, DNS та обидва діапазони Wi-Fi. Увійди **новим** користувачем `roman`; **лише після успішного входу** вимкни стандартного `admin`:

```routeros
/user disable [find where name="admin"]
```

> **Увага до Firewall:** базова конфігурація застосовує default-deny для INPUT і FORWARD. Вона допускає керування SSH/WinBox через IP лише з `192.168.88.11`. Якщо ПК адміністратора отримав іншу IP-адресу, доступ за IP не працюватиме; перевір DHCP lease та MAC WinBox, перш ніж блокувати аварійний доступ. WAN з DHCP також слід перевірити на конкретній версії RouterOS; якщо DHCP не отримує адресу, діагностуй вхідні DHCP відповіді UDP 67→68 до правила `INPUT: Drop other`.

## 3. Налаштувати WireGuard для SSH

Цей сценарій працює, якщо WAN MikroTik має **доступну ззовні публічну IPv4** (вона може змінюватися), або є проброс UDP 51820 на вищому маршрутизаторі. **DDNS не обходить CGNAT.**

### 3.1 Згенерувати ключі на Linux

На Arch Linux:

```bash
sudo pacman -S --needed wireguard-tools
mkdir -p ~/.config/wireguard
chmod 700 ~/.config/wireguard
cd ~/.config/wireguard
umask 077
wg genkey > client.key
wg pubkey < client.key > client.pub
cat client.pub
```

`client.key` — **секретний** ключ, його не передавай на MikroTik та нікому не публікуй. На MikroTik використовується тільки **публічний** ключ `client.pub`.

### 3.2 Відредагувати та імпортувати серверний скрипт

У `02-wireguard-ssh.rsc` заміни:

```routeros
:local peerPublicKey "REPLACE_WITH_CLIENT_PUBLIC_KEY"
```

на значення з `client.pub`. Скрипт потрібно запускати **після** `01-base-hap-ac.rsc`, рівно один раз:

```routeros
/import file-name=02-wireguard-ssh.rsc verbose=yes
```

Скрипт активує MikroTik Cloud DDNS, створює `wg-remote` на UDP 51820 і додає **перед фінальними DROP** два правила: INPUT дозволяє WireGuard UDP з WAN; FORWARD дозволяє TCP 2241 від `10.77.0.2` до `192.168.88.7`.

Отримай публічний ключ роутера та DNS-ім'я:

```routeros
/interface wireguard print detail where name="wg-remote"
/ip cloud print
/ip firewall filter print stats
```

### 3.3 Налаштувати клієнт Linux

Скопіюй `wireguard-client-example.conf` у `/etc/wireguard/wg-home.conf` та підстав:

- `REPLACE_WITH_CLIENT_PRIVATE_KEY` → вміст `client.key`;
- `REPLACE_WITH_MIKROTIK_WIREGUARD_PUBLIC_KEY` → **public-key** інтерфейсу `wg-remote`;
- `REPLACE_WITH_MIKROTIK_CLOUD_DNS_NAME` → поле `dns-name` з `/ip cloud print`.

```bash
sudo install -m 600 wireguard-client-example.conf /etc/wireguard/wg-home.conf
sudoedit /etc/wireguard/wg-home.conf
sudo wg-quick up wg-home
sudo wg show
```

Для зупинки:

```bash
sudo wg-quick down wg-home
```

Це **split tunnel**: у `AllowedIPs` вказані тільки `10.77.0.1/32` та `192.168.88.7/32`, увесь інший інтернет-трафік клієнта йде напряму.

### 3.4 Перевірити доступ до SSH

Проводь перевірку **ззовні домашньої мережі** (наприклад, із мобільного інтернету):

```bash
sudo wg show
ping 10.77.0.1
ssh -p 2241 USER@192.168.88.7
```

`USER` заміни реальним користувачем сервера. SSH має слухати порт `2241` **на сервері**, а його власний firewall має дозволяти підключення від VPN клієнта `10.77.0.2` (пакети не маскарадуються в цьому сценарії). MikroTik VPN не гарантує, що SSH сервер уже налаштований.

### 3.5 Якщо зовнішня адреса змінюється або є CGNAT

Cloud DDNS оновлює домен виду `xxxx.sn.mynetname.net` при зміні публічної адреси:

```routeros
/ip cloud print
/ip dhcp-client print detail
```

Перевір WAN IPv4. Якщо вона з `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` або `100.64.0.0/10`, це ознака приватної/CGNAT-адресації. Порівняй її також із публічною адресою з `/ip cloud print`. Навіть якщо WAN виглядає публічною, провайдер може фільтрувати вхідний UDP.

**За CGNAT** потрібен інший дизайн: **VPS із публічною IP як центральний WireGuard вузол**, до якого MikroTik і клієнт ініціюють вихідні з'єднання. Поточний `02-wireguard-ssh.rsc` **не налаштовує VPS-топологію**.

## 4. Port Forwarding / DST-NAT

У `01-base-hap-ac.rsc` уже є правило FORWARD:

```routeros
add chain=forward action=accept connection-state=new connection-nat-state=dstnat in-interface-list=WAN comment="FORWARD: Allow WAN dstnat"
```

Усе інше нове з'єднання з WAN буде заблоковане кінцевим `FORWARD: Drop other`. Для публічного HTTPS сервера `192.168.88.7`, якщо свідомо хочеш опублікувати його:

```routeros
/ip firewall nat add chain=dstnat action=dst-nat \
    in-interface-list=WAN protocol=tcp dst-port=443 \
    to-addresses=192.168.88.7 to-ports=443 \
    comment="DST-NAT: HTTPS server-pc"
```

> Увага: цей FORWARD допускає **будь-який новий WAN-трафік, який збігся з DST-NAT**. Публікуй лише необхідні сервіси та захищай їх на самих серверах. За потреби обмежуй `src-address` / `src-address-list` безпосередньо в DST-NAT або додавай вузькі правила FORWARD. **Не відкривай SSH 2241 у публічний WAN**, якщо для нього вже є WireGuard.

Для доступу з LAN за зовнішньою IP/доменом може знадобитися **split DNS** або Hairpin NAT. Ці правила не входять до готового базового скрипта.

## 5. Безпека, обмеження та експлуатація

- Базовий скрипт **вимикає IPv6**. Якщо тобі потрібен IPv6, спочатку підготуй окремий IPv6 Firewall, а потім вмикай його.
- MikroTik SSH — TCP 2240, WinBox — TCP 48291; IP-доступ до них обмежено `192.168.88.11/32` і INPUT Firewall. MAC WinBox залишається доступним через LAN — це аварійний механізм, але його також слід захистити фізичним доступом до локальної мережі.
- Базовий конфіг **не запускає автоматичне встановлення оновлень**. Перевірити вручну: `/system package update check-for-updates`. Перед оновленням збережи backup.
- FastTrack увімкнено для звичайних established/related IPv4-з'єднань. Якщо пізніше додаватимеш QoS, черги, IPsec, складний policy routing або інші VPN-схеми, перевір сумісність FastTrack.
- Не публікуй приватні ключі WireGuard, реальні паролі, `.backup` та повні експорти з секретами у відкритих репозиторіях.
- Зміна зовнішньої IP за DDNS може вимагати часу на оновлення DNS і повторне встановлення тунелю клієнтом.

## 6. Діагностика

На MikroTik:

```routeros
/log print
/ip dhcp-client print detail
/ip route print
/ip dns print
/ip firewall filter print stats
/ip firewall nat print stats
/interface wireguard print detail
/interface wireguard peers print detail
/ip cloud print
```

На Linux:

```bash
sudo wg show
ip route get 192.168.88.7
ping -c 3 10.77.0.1
ssh -vv -p 2241 USER@192.168.88.7
```

**Якщо інтернет не працює:** перевір DHCP на WAN, default route `0.0.0.0/0`, DNS та NAT counters. **Якщо WireGuard не піднімається:** перевір, чи WAN справді доступний, UDP 51820, DDNS, ключі та `latest handshake`. **Якщо VPN є, але SSH не працює:** перевір `sshd`, порт і локальний firewall сервера, а також правило `FORWARD: WireGuard SSH to server-pc`.

## 7. Відновлення

Якщо налаштування зірвали доступ, спробуй зайти через MAC WinBox із локального Ethernet-порту. Якщо це неможливо, знадобиться фізичний доступ для recovery/reset. Для відкату можеш відновити раніше збережений MikroTik `.backup` **на тому самому пристрої**, враховуючи версію RouterOS і сумісність конфігурації. Не роби reset до того, як перевіриш наявність резервної копії.

---

**Порядок застосування:** `01-base-hap-ac.rsc` → перевірка LAN/WAN/входу → `02-wireguard-ssh.rsc` → налаштування клієнта → зовнішня перевірка SSH.
