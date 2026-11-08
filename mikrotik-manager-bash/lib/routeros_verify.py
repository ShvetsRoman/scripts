#!/usr/bin/env python3
"""Виводить локальний перелік read-only команд RouterOS 7 у stdout."""

from __future__ import annotations

import argparse
import sys


DRIVER_COMMANDS = {
    "legacy": [
        ("Wi-Fi interfaces", "/interface wireless print detail without-paging"),
        ("Wi-Fi security profiles", "/interface wireless security-profiles print detail without-paging"),
    ],
    "wifi-qcom-ac": [
        ("Wi-Fi interfaces", "/interface wifi print detail without-paging"),
        ("Wi-Fi security", "/interface wifi security print detail without-paging"),
        ("Wi-Fi configurations", "/interface wifi configuration print detail without-paging"),
        ("Wi-Fi datapaths", "/interface wifi datapath print detail without-paging"),
        ("Wi-Fi channels", "/interface wifi channel print detail without-paging"),
    ],
    "wifi-qcom": [
        ("Wi-Fi interfaces", "/interface wifi print detail without-paging"),
        ("Wi-Fi security", "/interface wifi security print detail without-paging"),
        ("Wi-Fi configurations", "/interface wifi configuration print detail without-paging"),
        ("Wi-Fi datapaths", "/interface wifi datapath print detail without-paging"),
        ("Wi-Fi channels", "/interface wifi channel print detail without-paging"),
    ],
    "none": [],
}

BASE_SECTIONS = [
    ("Interfaces", [
        ("All interfaces", "/interface print detail without-paging"),
        ("Ethernet interfaces", "/interface ethernet print detail without-paging"),
        ("Interface lists", "/interface list print detail without-paging"),
        ("Interface list members", "/interface list member print detail without-paging"),
    ]),
    ("Bridge", [
        ("Bridge instances", "/interface bridge print detail without-paging"),
        ("Bridge ports", "/interface bridge port print detail without-paging"),
        ("Bridge VLANs", "/interface bridge vlan print detail without-paging"),
    ]),
    ("DHCP", [
        ("DHCP servers", "/ip dhcp-server print detail without-paging"),
        ("DHCP networks", "/ip dhcp-server network print detail without-paging"),
        ("IP pools", "/ip pool print detail without-paging"),
        ("DHCP leases", "/ip dhcp-server lease print detail without-paging"),
    ]),
    ("DNS", [
        ("DNS settings", "/ip dns print detail without-paging"),
        ("Static DNS records", "/ip dns static print detail without-paging"),
    ]),
    ("Firewall", [
        ("Filter rules", "/ip firewall filter print detail without-paging"),
        ("Raw rules", "/ip firewall raw print detail without-paging"),
        ("Mangle rules", "/ip firewall mangle print detail without-paging"),
        ("Address lists", "/ip firewall address-list print detail without-paging"),
    ]),
    ("NAT", [
        ("NAT rules", "/ip firewall nat print detail without-paging"),
    ]),
    ("Users", [
        ("RouterOS users", "/user print detail without-paging"),
        ("User groups", "/user group print detail without-paging"),
        ("SSH public keys", "/user ssh-keys print detail without-paging"),
    ]),
]


def render(profile: str, driver: str) -> str:
    if not profile or any(ch not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-" for ch in profile):
        raise ValueError("Некоректна назва профілю")
    if driver not in DRIVER_COMMANDS:
        raise ValueError(f"Непідтримуваний Wi-Fi driver у профілі: {driver}")

    lines = [
        "# MikroTik Manager Bash — RouterOS read-only verification",
        f"# Profile: {profile}",
        "# RouterOS 7; generated locally; not executed by the manager.",
        "# Усі команди нижче лише читають стан через print; змін конфігурації немає.",
        "# Вивід може містити приватні IP, MAC, імена користувачів та SSH key-owner.",
        "# Не публікуйте повний вивід без попереднього приховування чутливих даних.",
        "",
    ]
    for title, commands in BASE_SECTIONS:
        lines.append(f':put "=== {title} ==="')
        for label, command in commands:
            lines.append(f"# {label}")
            lines.append(command)
        lines.append("")

    lines.append(':put "=== Wi-Fi ==="')
    wifi_commands = DRIVER_COMMANDS[driver]
    if wifi_commands:
        lines.append(f"# Driver: {driver}")
        for label, command in wifi_commands:
            lines.append(f"# {label}")
            lines.append(command)
    else:
        lines.append("# SKIP: wireless.driver=none — профіль не використовує Wi-Fi.")
    lines.extend(("", ':put "=== Read-only verification finished ==="', ""))
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile", help="назва локального профілю")
    parser.add_argument("driver", help="wireless.driver із TOML")
    args = parser.parse_args()
    try:
        content = render(args.profile, args.driver)
    except ValueError as exc:
        print(f"ПОМИЛКА: {exc}", file=sys.stderr)
        return 1
    # Команди лише показуються в терміналі; файли не створюються.
    sys.stdout.write(content)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
