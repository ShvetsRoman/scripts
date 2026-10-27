# RouterOS CHR у VirtualBox — профіль `test`

## Схема

- `ether1` — VirtualBox NAT, DHCP (`10.0.2.15/24` до очищення, після нього адреса динамічна).
- `ether2` — VirtualBox Host-Only `vboxnet0`, частина LAN bridge.
- `ether3`–`ether5` — LAN, входять до bridge.
- Linux-host `vboxnet0` — `192.168.56.1/24`.
- CHR (IP LAN bridge після чистої установки) — `192.168.56.2/24`.
- SSH і WinBox — TCP 22/8291, обмежені LAN (`limit_to_lan=true`).
- DHCP-пул LAN — `192.168.56.100–192.168.56.200`.

**Важливо:** перед RESET RouterOS CHR має лише NAT-адресу, тому спочатку через консоль VirtualBox треба надати адресу `192.168.56.2/24` інтерфейсу `ether2` (тільки якщо другий адаптер ВМ дійсно під'єднано до `vboxnet0`):

```routeros
/ip address add address=192.168.56.2/24 interface=ether2 comment="Temporary Host-Only for initial SSH"
/ip service print detail where name=ssh
```

Це тимчасова адреса до RESET. Після чистої установки RSC створить `bridge-lan` з цією самою IP-адресою.

Перевірка з Linux:

```bash
ssh -p 22 admin@192.168.56.2
scp -O -P 22 routers/test/build/2.rsc admin@192.168.56.2:2.rsc
```

Не запускайте `--reset` до успішної SSH/SCP-перевірки та збереження резервної копії. Прапорець `--reset` змінює конфігурацію й перезавантажує CHR.
