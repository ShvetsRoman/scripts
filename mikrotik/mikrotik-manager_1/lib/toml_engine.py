#!/usr/bin/env python3
"""Строгий TOML engine для MikroTik Manager Bash.

Використовує стандартний tomllib (Python 3.11+), не виконує вміст TOML.
"""
from __future__ import annotations
import ipaddress
import json
import re
import shlex
import sys
import tomllib
import unicodedata
from pathlib import Path
from typing import Any

# Єдине джерело правил валідації — lib/schema.json.
# Резервної вбудованої схеми немає: без актуального файлу перевірка заборонена.
SCHEMA_FILE = Path(__file__).resolve().parent / "schema.json"
if not SCHEMA_FILE.is_file():
    raise SystemExit(f"ERROR: TOML schema not found: {SCHEMA_FILE}")
try:
    _schema = json.loads(SCHEMA_FILE.read_text(encoding="utf-8"))
    ROOT_KEYS: dict[str, str] = _schema["root_keys"]
    TABLES: dict[str, dict[str, str]] = _schema["tables"]
    REQUIRED_TABLES: dict[str, set[str]] = {
        path: set(keys) for path, keys in _schema["required_tables"].items()
    }
    SCHEMA_CONSTRAINTS: dict[str, Any] = _schema.get("constraints", {})
except (OSError, json.JSONDecodeError, KeyError, TypeError) as exc:
    raise SystemExit(f"ERROR: invalid TOML schema {SCHEMA_FILE}: {exc}")
# Єдине джерело allowlist служб — schema.json; без нього перевірка заборонена.
try:
    SERVICE_ALLOWLIST: frozenset[str] = frozenset(_schema["service_allowlist"])
except (KeyError, TypeError) as exc:
    raise SystemExit(f"ERROR: invalid TOML schema {SCHEMA_FILE}: {exc}")
if not SERVICE_ALLOWLIST:
    raise SystemExit(f"ERROR: invalid TOML schema {SCHEMA_FILE}: service_allowlist порожній")

class ValidationError(Exception):
    pass

def fail(message: str) -> None:
    raise ValidationError(message)

def type_ok(value: Any, spec: str) -> bool:
    if spec == "str": return isinstance(value, str)
    if spec == "bool": return isinstance(value, bool)
    if spec == "int": return isinstance(value, int) and not isinstance(value, bool)
    if spec == "int_or_str": return (isinstance(value, int) and not isinstance(value, bool)) or isinstance(value, str)
    if spec == "str_list": return isinstance(value, list) and all(isinstance(v, str) for v in value)
    if spec == "table_list": return isinstance(value, list) and all(isinstance(v, dict) for v in value)
    if spec.startswith("enum:"): return isinstance(value, str) and value in spec[5:].split(",")
    return False

def flatten(data: dict[str, Any], prefix: str = "") -> tuple[dict[str, Any], list[str]]:
    values: dict[str, Any] = {}
    sections: list[str] = []
    for key, value in data.items():
        path = f"{prefix}.{key}" if prefix else key
        if isinstance(value, dict):
            sections.append(path)
            child, sub = flatten(value, path)
            values.update(child); sections.extend(sub)
        elif isinstance(value, list) and value and all(isinstance(x, dict) for x in value):
            for index, item in enumerate(value, 1):
                array_section = f"{path}.{index}"
                sections.append(array_section)
                child, sub = flatten(item, array_section)
                values.update(child); sections.extend(sub)
        elif isinstance(value, list):
            values[path] = value
        else:
            values[path] = value
    return values, sections

def table_paths(data: dict[str, Any], prefix: str = "") -> list[tuple[str, dict[str, Any]]]:
    result = []
    for key, value in data.items():
        path = f"{prefix}.{key}" if prefix else key
        if isinstance(value, dict):
            result.append((path, value)); result.extend(table_paths(value, path))
        elif isinstance(value, list) and value and all(isinstance(x, dict) for x in value):
            for item in value: result.append((path, item))
    return result

def pattern_matches(path: str, pattern: str) -> bool:
    """Перевірити відповідність шляху шаблону схеми."""
    actual, expected = path.split("."), pattern.split(".")
    return len(actual) == len(expected) and all(p == "*" or p == v for p, v in zip(expected, actual))

def matching_schema(path: str) -> dict[str, str] | None:
    if path == "leases.devices" or re.fullmatch(r"leases\.devices\.\d+", path):
        return TABLES["leases.devices"]
    for pattern, schema in TABLES.items():
        if pattern_matches(path, pattern):
            return schema
    return None

def validate_dynamic_table_keys(path: str, source: str) -> None:
    """Захистити ключі динамічних TOML-таблиць від команд RouterOS у назвах."""
    parts = path.split(".")
    for pattern in TABLES:
        expected = pattern.split(".")
        if len(parts) != len(expected):
            continue
        for token, actual in zip(expected, parts):
            if token == "*" and not re.fullmatch(r"[A-Za-z0-9_-]+", actual):
                fail(f"{source}: недопустиме ім’я таблиці '{actual}' у [{path}]; дозволено лише [A-Za-z0-9_-]")

def reference_rule(path: str) -> list[str] | None:
    for rule in SCHEMA_CONSTRAINTS.get("reference_types", []):
        if pattern_matches(path, rule["field"]):
            return rule["targets"]
    return None

def validate(data: dict[str, Any], source: str) -> tuple[dict[str, Any], list[str]]:
    # Керівні символи в будь-яких рядках небезпечні для генерації RouterOS CLI.
    # Відхиляємо їх до передачі значень у Bash/RouterOS, а не покладаємося лише на escaping.
    def reject_control_characters(value: Any, path: str = "") -> None:
        if isinstance(value, str):
            if any(unicodedata.category(char) == "Cc" for char in value):
                fail(f"{source}: {path or '<root>'}: рядок містить керівний символ")
        elif isinstance(value, dict):
            for key, child in value.items():
                child_path = f"{path}.{key}" if path else str(key)
                reject_control_characters(child, child_path)
        elif isinstance(value, list):
            for index, child in enumerate(value):
                reject_control_characters(child, f"{path}[{index}]")

    reject_control_characters(data)
    flat, sections = flatten(data)
    for key, value in data.items():
        if key in ROOT_KEYS:
            if not type_ok(value, ROOT_KEYS[key]): fail(f"{source}: {key}: очікується {ROOT_KEYS[key]}")
        elif not isinstance(value, dict) and not (isinstance(value, list) and all(isinstance(x, dict) for x in value)):
            fail(f"{source}: невідомий кореневий ключ '{key}'")
    for path, table in table_paths(data):
        validate_dynamic_table_keys(path, source)
        schema = matching_schema(path)
        if schema is None:
            # Неявні батьківські таблиці TOML (наприклад [interfaces] для [interfaces.ether1]).
            if table and all(isinstance(v, dict) or (isinstance(v, list) and all(isinstance(x, dict) for x in v)) for v in table.values()):
                continue
            fail(f"{source}: невідома секція [{path}]")
        for key, value in table.items():
            if key not in schema:
                if isinstance(value, dict) or (isinstance(value, list) and all(isinstance(x, dict) for x in value)):
                    continue
                fail(f"{source}: невідомий параметр {path}.{key}")
            if not type_ok(value, schema[key]):
                fail(f"{source}: {path}.{key}: очікується {schema[key]}, отримано {type(value).__name__}")
    for path, required in REQUIRED_TABLES.items():
        node: Any = data
        try:
            for part in path.split("."): node = node[part]
        except (KeyError, TypeError): fail(f"{source}: відсутня обов'язкова секція [{path}]")
        for key in required:
            if key not in node: fail(f"{source}: відсутній обов'язковий параметр {path}.{key}")
    paths_cfg = data.get("paths", {})
    # Типові каталоги профілю не потребують окремого TOML-блоку.
    for key, default in (("output_dir", "output"), ("backup_dir", "backups")):
        value = paths_cfg.get(key, default)
        # "~"-префікс не розгортається: інакше створився б літеральний каталог "~".
        if not value or value == "." or value.startswith("~") or Path(value).is_absolute() or ".." in Path(value).parts:
            fail(f"{source}: paths.{key} має бути непорожнім відносним каталогом усередині профілю")
    remote_dir = paths_cfg.get("remote_dir", "")
    if remote_dir and (remote_dir.startswith("/") or ".." in Path(remote_dir).parts or not re.fullmatch(r"[A-Za-z0-9_./-]+", remote_dir)):
        fail(f"{source}: paths.remote_dir має бути відносним шляхом без '..' і пробілів")
    if data.get("schema_version") != "1.0": fail(f"{source}: підтримується schema_version = \"1.0\"")
    # Посилання @section.path адресують секцію TOML без окремого ID.
    # Шлях секції є єдиним канонічним ідентифікатором конфігураційного об'єкта.
    tables = dict(table_paths(data))
    graph: dict[str, set[str]] = {path: set() for path in tables}
    for key, value in flat.items():
        items = value if isinstance(value, list) else [value]
        for item in items:
            if not (isinstance(item, str) and item.startswith("@")):
                continue
            allowed = reference_rule(key)
            if allowed is None:
                fail(f"{source}: {key}: посилання @section.path тут не дозволене схемою")
            ref = item[1:]
            target_path = ref
            if target_path not in tables:
                fail(f"{source}: {key}: невідоме посилання @{ref}")
            if not any(pattern_matches(target_path, target) for target in allowed):
                fail(f"{source}: {key}: @{ref} має тип [{target_path}], очікується один із типів {', '.join(allowed)}")
            owner = key.rsplit('.', 1)[0]
            if owner in graph:
                graph[owner].add(target_path)
    visiting: set[str] = set(); visited: set[str] = set()
    def visit(node: str, trail: list[str]) -> None:
        if node in visiting: fail(f"{source}: цикл посилань: {' -> '.join(trail + [node])}")
        if node in visited: return
        visiting.add(node)
        for target in graph.get(node, set()): visit(target, trail + [node])
        visiting.remove(node); visited.add(node)
    for section_path in graph: visit(section_path, [])
    routerboard = data.get("routerboard")
    if routerboard is not None:
        if "supported" not in routerboard:
            fail(f"{source}: [routerboard] потребує supported")
        if routerboard.get("supported") is False and routerboard.get("upgrade", False) is True:
            fail(f"{source}: routerboard.upgrade=true неможливий при supported=false")
    # Контракт користувачів RouterOS. Створення, активність, пароль і SSH-ключі незалежні.
    user_names: set[str] = set()
    for user_key, user in data.get("users", {}).items():
        for required in ("name", "enabled", "create", "group"):
            if required not in user:
                fail(f"{source}: users.{user_key} потребує параметр {required}")
        name = user.get("name", "")
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", name):
            fail(f"{source}: users.{user_key}.name: некоректне ім’я RouterOS")
        if name in user_names:
            fail(f"{source}: дубль імені користувача RouterOS: {name}")
        user_names.add(name)
        group = user.get("group", "")
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", group):
            fail(f"{source}: users.{user_key}.group: некоректна група RouterOS")
        has_file = "password_file" in user
        has_key = "password_key" in user
        if has_file != has_key:
            fail(f"{source}: users.{user_key}: password_file і password_key потрібно задавати разом")
        if has_file and (not user.get("password_file") or not user.get("password_key")):
            fail(f"{source}: users.{user_key}: password_file та password_key не можуть бути порожніми")
        if user.get("create") and not (has_file and user.get("password_file") and user.get("password_key")):
            fail(f"{source}: users.{user_key}.create=true потребує password_file та password_key незалежно від enabled")
        keys = user.get("ssh_keys", [])
        if any(not key.strip() for key in keys):
            fail(f"{source}: users.{user_key}.ssh_keys не може містити порожні шляхи")
        if len(keys) != len(set(keys)):
            fail(f"{source}: users.{user_key}.ssh_keys містить дубль шляхів")
    # connection.user має бути користувачем профілю, який залишиться активним:
    # у разі reset вимкнений користувач керування = повний lockout.
    conn_user = (data.get("connection") or {}).get("user")
    if conn_user:
        owner_key = next((k for k, u in data.get("users", {}).items() if u.get("name") == conn_user), None)
        if owner_key is None:
            fail(f"{source}: connection.user '{conn_user}' не належить жодному [users.*]")
        elif not data["users"][owner_key].get("enabled"):
            fail(f"{source}: connection.user '{conn_user}' збігається з вимкненим користувачем users.{owner_key}; після reset доступ буде втрачено (lockout)")
    # Міжсекційні залежності описані в schema.json і застосовуються до TOML.
    for relation in SCHEMA_CONSTRAINTS.get("matching_table_keys", []):
        source_table = data.get(relation["source"], {})
        target_table = data.get(relation["target"], {})
        for item_name in source_table:
            if item_name not in target_table:
                fail(f"{source}: {relation['source']}.{item_name}: {relation['message']}")
    # Перевірка IP/CIDR та унікальності DHCP leases.
    for path in ("network.lan.address", "management.address", "nat.hairpin_lan_subnet"):
        val = flat.get(path)
        if val and isinstance(val, str) and not val.startswith("@"):
            try: ipaddress.ip_interface(val) if path != "nat.hairpin_lan_subnet" else ipaddress.ip_network(val, strict=False)
            except ValueError: fail(f"{source}: {path}: некоректна адреса/CIDR '{val}'")
    lease_ips, lease_macs = set(), set()
    for item in data.get("leases", {}).get("devices", []):
        try: ipaddress.ip_address(item["address"])
        except (ValueError, KeyError): fail(f"{source}: leases.devices: некоректна IP-адреса")
        mac = item.get("mac", "").upper()
        if not re.fullmatch(r"([0-9A-F]{2}:){5}[0-9A-F]{2}", mac): fail(f"{source}: leases.devices: некоректна MAC '{mac}'")
        if item["address"] in lease_ips: fail(f"{source}: дубль DHCP IP {item['address']}")
        if mac in lease_macs: fail(f"{source}: дубль DHCP MAC {mac}")
        lease_ips.add(item["address"]); lease_macs.add(mac)
    # Перевірка сумісності ключових залежностей.
    # [forward.*] генерує dstnat-правила: без nat.enabled вони мовчки втрачаються.
    if not data.get("nat", {}).get("enabled", False) and data.get("forward"):
        fail(f"{source}: секції [forward.*] потребують nat.enabled=true: без NAT правила dstnat не генеруються")
    if data.get("nat", {}).get("enabled") and data.get("nat", {}).get("masquerade") and not data.get("lists", {}).get("wan", {}).get("name"):
        fail(f"{source}: NAT masquerade потребує [lists.wan]")
    if data.get("wan", {}).get("enabled") and not data.get("wan", {}).get("interface"):
        fail(f"{source}: wan.enabled=true потребує wan.interface")
    if data.get("ntp", {}).get("enabled"):
        if "servers" not in data.get("ntp", {}):
            fail(f"{source}: ntp.enabled=true потребує ntp.servers")
        max_servers = data["ntp"].get("max_servers", 4)
        if not isinstance(max_servers, int) or isinstance(max_servers, bool) or not 1 <= max_servers <= 16:
            fail(f"{source}: ntp.max_servers має бути 1..16")
    if data.get("updates", {}).get("auto_install"):
        updates = data["updates"]
        if not updates.get("auto_reboot"): fail(f"{source}: updates.auto_install=true потребує auto_reboot=true")
        if "auto_interval" not in updates or not re.fullmatch(r"[0-9]+[smhdw]", updates["auto_interval"]):
            fail(f"{source}: updates.auto_install=true потребує auto_interval у форматі 1d/6h")
    firewall = data.get("firewall", {})
    if firewall.get("brute_force_enabled"):
        for key in ("brute_force_ports", "brute_force_blacklist_timeout", "brute_force_stage_timeout"):
            if key not in firewall: fail(f"{source}: firewall.brute_force_enabled=true потребує firewall.{key}")
        for key in ("brute_force_blacklist_timeout", "brute_force_stage_timeout"):
            if not re.fullmatch(r"[0-9]+[smhdw]", firewall[key]): fail(f"{source}: firewall.{key} має бути тривалістю RouterOS")
        # Перевіряємо не лише формат, а й реальний діапазон RouterOS TCP/UDP-портів.
        ports = firewall["brute_force_ports"]
        if not re.fullmatch(r"[0-9]+(?:-[0-9]+)?(?:,[0-9]+(?:-[0-9]+)?)*", ports):
            fail(f"{source}: firewall.brute_force_ports має містити порти/діапазони через кому")
        for item in ports.split(","):
            bounds = item.split("-", 1)
            start = int(bounds[0])
            end = int(bounds[-1])
            if not 1 <= start <= 65535 or not 1 <= end <= 65535 or start > end:
                fail(f"{source}: firewall.brute_force_ports містить недопустимий порт/діапазон '{item}' (дозволено 1..65535, початок <= кінець)")
    if firewall.get("allow_icmp") and firewall.get("icmp_limit_per_second", 0) > 0:
        if "icmp_burst" not in firewall or not 1 <= firewall["icmp_burst"] <= 100:
            fail(f"{source}: firewall.allow_icmp з лімітом потребує icmp_burst 1..100")
    if firewall.get("fasttrack") and "fasttrack_hw_offload" not in firewall:
        fail(f"{source}: firewall.fasttrack=true потребує firewall.fasttrack_hw_offload")
    if data.get("nat", {}).get("hairpin_enabled") and "hairpin_lan_subnet" not in data.get("nat", {}):
        fail(f"{source}: nat.hairpin_enabled=true потребує nat.hairpin_lan_subnet")
    if data.get("server", {}).get("lan", {}).get("enabled", True):
        if "lan" not in data.get("pool", {}) or "lan" not in data.get("dhcp", {}).get("network", {}):
            fail(f"{source}: активний server.lan потребує pool.lan і dhcp.network.lan")
    lease_time = data.get("server", {}).get("lan", {}).get("lease_time")
    if lease_time is not None and not re.fullmatch(r"[0-9]+[smhdw]", str(lease_time)):
        fail(f"{source}: server.lan.lease_time має бути тривалістю RouterOS (напр. 12h)")
    if data.get("leases", {}).get("enabled") and not data.get("leases", {}).get("server"):
        fail(f"{source}: leases.enabled=true потребує leases.server")
    if data.get("dns", {}).get("enabled") and not data.get("dns", {}).get("servers"):
        fail(f"{source}: dns.enabled=true потребує принаймні один dns.servers")
    backup_cfg = data.get("backup", {})
    if backup_cfg.get("encrypt") and not all(backup_cfg.get(k) for k in ("password_file", "password_key")):
        fail(f"{source}: backup.encrypt=true потребує backup.password_file та backup.password_key")
    reset_cfg = data.get("reset", {})
    if reset_cfg and not reset_cfg.get("run_after_reset"):
        # Дозволяємо профіль для --build/--validate, але операція --upload --reset окремо перевіряє цей прапорець.
        pass
    connection = data.get("connection", {})
    if "host" in connection:
        host = connection["host"]
        try:
            ipaddress.ip_address(host)
            valid_host = True
        except ValueError:
            valid_host = bool(re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9_.:-]*[A-Za-z0-9])?", host))
        if not valid_host:
            fail(f"{source}: connection.host має починатися й закінчуватися літерою/цифрою та не містити опцій SSH")
    if "user" in connection and not re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*", connection["user"]):
        fail(f"{source}: connection.user має починатися з літери, цифри або '_' і не містити опцій SSH")
    if "port" in connection and not 1 <= connection["port"] <= 65535: fail(f"{source}: connection.port має бути 1..65535")
    if "timeout_seconds" in connection and not 1 <= connection["timeout_seconds"] <= 300: fail(f"{source}: connection.timeout_seconds має бути 1..300")
    if "transfer_settle_seconds" in connection and not 0 <= connection["transfer_settle_seconds"] <= 30: fail(f"{source}: connection.transfer_settle_seconds має бути 0..30")
    reset_cfg = data.get("reset", {})
    if data.get("nat", {}).get("enabled") and data.get("nat", {}).get("masquerade") and not data.get("wan", {}).get("enabled"):
        fail(f"{source}: NAT masquerade не можна вмикати без активного WAN")
    if data.get("management", {}).get("on_lan") is False and "management" not in data.get("lists", {}):
        fail(f"{source}: management.on_lan=false потребує [lists.management]")
    for service_name, service in data.get("services", {}).items():
        if not isinstance(service, dict):
            continue
        # Стандартний набір IP-служб RouterOS (CHANGELOG 2026-11-06);
        # без allowlist ім'я служби потрапляло б у RSC без лапок.
        if service_name not in SERVICE_ALLOWLIST:
            fail(f"{source}: services.{service_name} не входить у стандартний набір IP-служб RouterOS ({', '.join(sorted(SERVICE_ALLOWLIST))})")
        if service.get("enabled"):
            if "port" not in service: fail(f"{source}: services.{service_name}.port обов'язковий для активної служби")
            if "limit_to_lan" not in service: fail(f"{source}: services.{service_name}.limit_to_lan обов'язковий для активної служби")
            if not 1 <= service["port"] <= 65535: fail(f"{source}: services.{service_name}.port має бути 1..65535")
    # Контракт Wi-Fi driver: кожен стек має власний набір band/width/auth.
    wireless = data.get("wireless", {})
    driver = wireless.get("driver", "none")
    if driver not in {"none", "legacy", "wifi-qcom-ac", "wifi-qcom"}:
        fail(f"{source}: wireless.driver: очікується none, legacy, wifi-qcom-ac або wifi-qcom")
    if wireless.get("enabled") and driver == "none":
        active_radios = [name for name, value in wireless.items() if name != "guest" and isinstance(value, dict) and value.get("enabled", False)]
        if active_radios:
            fail(f"{source}: wireless.driver=none не може використовуватися з активними радіо: {', '.join(active_radios)}")
    if wireless.get("enabled") and driver != "none":
        legacy_bands = {
            "2ghz-b", "2ghz-b/g", "2ghz-b/g/n", "2ghz-g/n", "2ghz-onlyg", "2ghz-onlyn",
            "5ghz-a", "5ghz-a/n", "5ghz-onlyn", "5ghz-a/n/ac", "5ghz-onlyac", "5ghz-n/ac",
        }
        legacy_widths = {
            "20mhz", "10mhz", "5mhz", "40mhz-turbo", "20/40mhz-Ce", "20/40mhz-eC", "20/40mhz-XX",
            "20/40/80mhz-Ceee", "20/40/80mhz-eCee", "20/40/80mhz-eeCe", "20/40/80mhz-eeeC",
            "20/40/80mhz-XXXX", "20/40/80/160mhz-Ceeeeeee", "20/40/80/160mhz-XXXXXXXX",
            "20/40/80/160mhz-eCeeeeee", "20/40/80/160mhz-eeCeeeee", "20/40/80/160mhz-eeeCeeee",
            "20/40/80/160mhz-eeeeCeee", "20/40/80/160mhz-eeeeeCee", "20/40/80/160mhz-eeeeeeCe",
            "20/40/80/160mhz-eeeeeeeC",
        }
        wifi_bands = {"2ghz-g", "2ghz-n", "2ghz-ax", "5ghz-a", "5ghz-an", "5ghz-ac", "5ghz-ax", "6ghz-ax"}
        wifi_widths = {"20mhz", "20/40mhz", "20/40mhz-Ce", "20/40mhz-eC", "20/40/80mhz", "20/40/80+80mhz", "20/40/80/160mhz"}
        qcom_ac_bands = {"2ghz-g", "2ghz-n", "5ghz-a", "5ghz-an", "5ghz-ac"}
        for name, wlan in wireless.items():
            if not isinstance(wlan, dict) or name == "guest" or not wlan.get("enabled", False):
                continue
            path = f"wireless.{name}"
            for req in ("interface", "ssid", "band", "security"):
                if not wlan.get(req): fail(f"{source}: {path}.{req} обов'язковий для активного Wi-Fi")
            band = wlan["band"]
            width = wlan.get("channel_width", "20mhz")
            frequency = wlan.get("frequency", "auto")
            country = wlan.get("country", "")
            if not wlan["ssid"].strip() or len(wlan["ssid"].encode("utf-8")) > 32:
                fail(f"{source}: {path}.ssid має містити 1..32 байти UTF-8")
            if driver == "legacy":
                if band not in legacy_bands:
                    fail(f"{source}: {path}.band={band!r} не підтримується legacy (/interface wireless)")
                if width not in legacy_widths:
                    fail(f"{source}: {path}.channel_width={width!r} не підтримується legacy")
                if frequency != "auto" and not re.fullmatch(r"[0-9]{4,5}", str(frequency)):
                    fail(f"{source}: {path}.frequency для legacy має бути auto або частотою в MHz")
            else:
                allowed_bands = qcom_ac_bands if driver == "wifi-qcom-ac" else wifi_bands
                if band not in allowed_bands:
                    fail(f"{source}: {path}.band={band!r} не підтримується {driver}")
                if width not in wifi_widths:
                    fail(f"{source}: {path}.channel_width={width!r} не підтримується /interface wifi")
                if driver == "wifi-qcom-ac" and width in {"20/40/80+80mhz", "20/40/80/160mhz"}:
                    fail(f"{source}: {path}.channel_width={width!r} перевищує контракт wifi-qcom-ac (до 80 MHz)")
                if band.startswith("2ghz-") and width not in {"20mhz", "20/40mhz", "20/40mhz-Ce", "20/40mhz-eC"}:
                    fail(f"{source}: {path}.channel_width несумісна з діапазоном 2.4 GHz")
                if band.startswith("5ghz-") and width == "20/40/80/160mhz" and driver == "wifi-qcom-ac":
                    fail(f"{source}: wifi-qcom-ac не підтримує ширину 160 MHz")
                if band.startswith("6ghz-") and driver != "wifi-qcom":
                    fail(f"{source}: 6 GHz доступний лише через wifi-qcom")
                if frequency != "auto" and not re.fullmatch(r"[0-9]{4,5}(?:-[0-9]{4,5}(?::[0-9]+)?)?(?:,[0-9]{4,5}(?:-[0-9]{4,5}(?::[0-9]+)?)?)*", str(frequency)):
                    fail(f"{source}: {path}.frequency має бути auto або списком частот/діапазонів MHz без пробілів")
            if country and not re.fullmatch(r"[A-Za-z][A-Za-z -]{1,48}", country):
                fail(f"{source}: {path}.country має містити назву країни латиницею")
            if driver == "wifi-qcom-ac" and country.lower() == "superchannel":
                fail(f"{source}: {path}.country=Superchannel не підтримується wifi-qcom-ac")
            sec_ref = wlan.get("security", "")
            sec_path = sec_ref[1:] if isinstance(sec_ref, str) and sec_ref.startswith("@") else ""
            sec_table = dict(table_paths(data)).get(sec_path, {})
            auth = sec_table.get("authentication", "")
            if driver == "legacy":
                valid_auth = {"wpa-psk", "wpa2-psk", "wpa-psk,wpa2-psk", "wpa2-psk,wpa-psk"}
            else:
                valid_auth = {"wpa2-psk", "wpa3-psk", "wpa2-psk,wpa3-psk", "wpa3-psk,wpa2-psk"}
            if auth not in valid_auth:
                fail(f"{source}: {path}.security: authentication={auth!r} не підтримується драйвером {driver}; підтримуються PSK-режими {', '.join(sorted(valid_auth))}")
    # [wireless.guest] — окрема гостьова мережа: VAP на вказаних радіо + bridge + DHCP.
    guest = data.get("wireless", {}).get("guest", {})
    if isinstance(guest, dict) and guest.get("enabled"):
        # Ізоляція гостей (guest → LAN drop) генерується лише у firewall:
        # без нього таблиця filter порожня (політика accept) і гості мають
        # повний доступ до LAN — тому гостьова мережа вимагає firewall.
        if not data.get("firewall", {}).get("enabled", False):
            fail(f"{source}: wireless.guest.enabled=true потребує firewall.enabled=true: гостьова мережа без firewall не ізолюється від LAN")
        wire = data.get("wireless", {})
        guest_sec_ref = guest.get("security", "")
        guest_sec_path = guest_sec_ref[1:] if isinstance(guest_sec_ref, str) and guest_sec_ref.startswith("@") else ""
        guest_sec_table = dict(table_paths(data)).get(guest_sec_path, {})
        guest_auth = guest_sec_table.get("authentication", "")
        if wire.get("driver") == "legacy":
            guest_auth_values = {"wpa-psk", "wpa2-psk", "wpa-psk,wpa2-psk", "wpa2-psk,wpa-psk"}
        else:
            guest_auth_values = {"wpa2-psk", "wpa3-psk", "wpa2-psk,wpa3-psk", "wpa3-psk,wpa2-psk"}
        if guest_auth not in guest_auth_values:
            fail(f"{source}: wireless.guest.security.authentication={guest_auth!r} не підтримується драйвером {wire.get('driver', 'none')}")
        if not guest.get("masters"):
            fail(f"{source}: wireless.guest.masters має містити хоча б одне радіо")
        if len(guest["masters"]) != len(set(guest["masters"])):
            fail(f"{source}: wireless.guest.masters містить повторювані посилання")
        if not isinstance(guest, dict) or not wire.get("enabled") or wire.get("driver", "none") == "none":
            fail(f"{source}: wireless.guest.enabled=true потребує wireless.enabled=true з driver != none")
        for req in ("masters", "ssid", "security", "bridge", "address", "pool_start", "pool_end", "dns_servers"):
            if not guest.get(req):
                fail(f"{source}: wireless.guest.enabled=true потребує wireless.guest.{req}")
        masters = guest.get("masters") or []
        if any(not m.startswith("@") for m in masters):
            fail(f"{source}: wireless.guest.masters: очікується список посилань @interfaces.<name> на інтерфейси радіо")
        prefix = guest.get("name_prefix", "guest")
        if not isinstance(prefix, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", prefix):
            fail(f"{source}: wireless.guest.name_prefix має містити лише [A-Za-z0-9_-]")
        try:
            guest_net = ipaddress.ip_interface(guest.get("address", "")) if isinstance(guest.get("address"), str) and not str(guest.get("address")).startswith("@") else None
        except ValueError:
            guest_net = None
            fail(f"{source}: wireless.guest.address: некоректний CIDR")
        if guest_net is not None:
            lan_value = flat.get("network.lan.address")
            if isinstance(lan_value, str) and not lan_value.startswith("@"):
                lan_net = ipaddress.ip_interface(lan_value).network
                if guest_net.network.overlaps(lan_net):
                    fail(f"{source}: wireless.guest.address ({guest_net.network}) перетинається з основною LAN ({lan_net})")
            management_value = flat.get("management.address")
            if isinstance(management_value, str) and not management_value.startswith("@"):
                management_net = ipaddress.ip_interface(management_value).network
                if guest_net.network.overlaps(management_net):
                    fail(f"{source}: wireless.guest.address ({guest_net.network}) перетинається з management ({management_net})")
            for field in ("pool_start", "pool_end"):
                try:
                    addr = ipaddress.ip_address(guest.get(field))
                except (ValueError, TypeError):
                    fail(f"{source}: wireless.guest.{field}: некоректна IP-адреса '{guest.get(field)}'")
                if addr not in guest_net.network:
                    fail(f"{source}: wireless.guest.{field} ({guest.get(field)}) не належить {guest_net.network}")
                if addr in {guest_net.network.network_address, guest_net.network.broadcast_address, guest_net.ip}:
                    fail(f"{source}: wireless.guest.{field} ({addr}) не може бути адресою мережі, broadcast або самого маршрутизатора")
            if ipaddress.ip_address(guest["pool_start"]) > ipaddress.ip_address(guest["pool_end"]):
                fail(f"{source}: wireless.guest.pool_start має бути не більшою за wireless.guest.pool_end")
            guest_gateway = guest_net.ip
            guest_pool_start = ipaddress.ip_address(guest["pool_start"])
            guest_pool_end = ipaddress.ip_address(guest["pool_end"])
            if guest_pool_start <= guest_gateway <= guest_pool_end:
                fail(f"{source}: гостьовий DHCP pool не може містити адресу маршрутизатора {guest_gateway}")
        for srv_ip in guest.get("dns_servers") or []:
            try:
                ipaddress.ip_address(srv_ip)
            except ValueError:
                fail(f"{source}: wireless.guest.dns_servers: некоректна IP '{srv_ip}'")
        if guest_net is not None and str(guest_net.ip) in [str(x) for x in guest.get("dns_servers") or []]:
            if not data.get("dns", {}).get("allow_remote_requests", False):
                fail(f"{source}: wireless.guest.dns_servers містить адресу роутера, тому потрібен dns.allow_remote_requests=true")
        lease_time = guest.get("lease_time")
        if lease_time is not None and not re.fullmatch(r"[0-9]+[smhdw]", str(lease_time)):
            fail(f"{source}: wireless.guest.lease_time має бути тривалістю RouterOS (напр. 12h)")
    # [upnp] — UPnP-служби для домашніх консолей/інфраструктури.
    upnp = data.get("upnp", {})
    if isinstance(upnp, dict) and upnp.get("enabled"):
        for req in ("external", "internal"):
            if not upnp.get(req):
                fail(f"{source}: upnp.enabled=true потребує upnp.{req}")
        if upnp.get("external") and upnp["external"] == upnp["internal"]:
            fail(f"{source}: upnp.external та upnp.internal мають бути різними інтерфейсами")
    # LAN, DHCP pool та статичні leases: один прохід — pool не захоплює
    # зарезервовані адреси, leases лежать у LAN та поза pool/gateway.
    lan_value = flat.get("network.lan.address")
    if isinstance(lan_value, str) and not lan_value.startswith("@"):
        lan_if = ipaddress.ip_interface(lan_value)
        lan_net = lan_if.network
        for field in ("dhcp.network.lan.gateway", "pool.lan.start", "pool.lan.end"):
            candidate = flat.get(field)
            if candidate:
                try: addr = ipaddress.ip_address(candidate)
                except ValueError: fail(f"{source}: {field}: некоректна IP-адреса '{candidate}'")
                if addr not in lan_net: fail(f"{source}: {field} ({candidate}) не належить {lan_net}")
        reserved = {lan_if.ip, lan_net.network_address, lan_net.broadcast_address}
        gateway_value = flat.get("dhcp.network.lan.gateway")
        if gateway_value:
            reserved.add(ipaddress.ip_address(gateway_value))
        pool_start_ip = pool_end_ip = None
        if flat.get("pool.lan.start") and flat.get("pool.lan.end"):
            pool_start_ip = ipaddress.ip_address(flat["pool.lan.start"])
            pool_end_ip = ipaddress.ip_address(flat["pool.lan.end"])
            if pool_start_ip > pool_end_ip:
                fail(f"{source}: pool.lan.start має бути не більшою за pool.lan.end")
            if any(pool_start_ip <= address <= pool_end_ip for address in reserved):
                fail(f"{source}: DHCP pool {pool_start_ip}-{pool_end_ip} містить зарезервовану адресу маршрутизатора, gateway, network або broadcast")
        for item in data.get("leases", {}).get("devices", []):
            addr = ipaddress.ip_address(item["address"])
            if addr not in lan_net: fail(f"{source}: lease {addr} не належить LAN {lan_net}")
            if addr in reserved: fail(f"{source}: статична lease {addr} конфліктує з адресою маршрутизатора, gateway, network або broadcast")
            if pool_start_ip and pool_end_ip and pool_start_ip <= addr <= pool_end_ip:
                fail(f"{source}: статична lease {addr} перетинається з DHCP pool {pool_start_ip}-{pool_end_ip}")
    return {"values": flat, "sections": sections}, []

def load_files(paths: list[Path]) -> dict[str, Any]:
    merged: dict[str, Any] = {}
    for path in paths:
        try: current = tomllib.loads(path.read_text(encoding="utf-8"))
        except (OSError, tomllib.TOMLDecodeError) as exc: fail(f"{path}: TOML parse error: {exc}")
        # Файли профілю можуть доповнювати різні секції, але не перезаписувати ключі.
        def merge(dst: dict[str, Any], src: dict[str, Any], prefix: str = "") -> None:
            for key, value in src.items():
                if key in dst:
                    if isinstance(dst[key], dict) and isinstance(value, dict): merge(dst[key], value, f"{prefix}.{key}" if prefix else key)
                    elif isinstance(dst[key], list) and isinstance(value, list) and (not dst[key] or not isinstance(dst[key][0], dict)):
                        fail(f"{path}: повторне визначення ключа {prefix + '.' if prefix else ''}{key}")
                    else: fail(f"{path}: повторне визначення ключа/секції {prefix + '.' if prefix else ''}{key}")
                else: dst[key] = value
        merge(merged, current)
    return merged

def emit_bash(parsed: dict[str, Any]) -> None:
    values, sections = parsed["values"], parsed["sections"]
    # Усі значення екрануються shlex.quote; shell source не інтерпретує дані TOML як код.
    for section in sections:
        print(f"SECTIONS+=({shlex.quote(section)})")
        print(f"SEC_SEEN[{shlex.quote(section)}]=1")
    for key, value in values.items():
        if isinstance(value, list): value = "\n".join(str(x) for x in value)
        elif isinstance(value, bool): value = "true" if value else "false"
        else: value = str(value)
        print(f"CFG[{shlex.quote(key)}]={shlex.quote(value)}")

def main() -> int:
    if len(sys.argv) < 3 or sys.argv[1] not in {"validate", "export"}:
        print("usage: toml_engine.py validate|export FILE...", file=sys.stderr); return 2
    mode, names = sys.argv[1], sys.argv[2:]
    try:
        data = load_files([Path(x) for x in names])
        parsed, _ = validate(data, ", ".join(names))
        if mode == "validate":
            print(f"PASS: TOML parsed and schema validated ({len(parsed['sections'])} tables, {len(parsed['values'])} values; ID-free)")
        else: emit_bash(parsed)
        return 0
    except ValidationError as exc:
        print(f"FAIL: {exc}", file=sys.stderr); return 1

if __name__ == "__main__": raise SystemExit(main())
