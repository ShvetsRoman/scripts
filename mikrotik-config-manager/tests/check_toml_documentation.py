#!/usr/bin/env python3
"""Перевірка TOML без прив'язки до версії, імен профілів чи значень конфігурації."""

import sys
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    paths = sorted(ROOT.glob("routers/*/*.toml"))
    paths += [ROOT / "Cargo.toml", ROOT / "config/manager.toml"]
    if not any(ROOT.glob("routers/*/*.toml")):
        print("FAIL: жодного TOML-профілю")
        return 1

    for path in paths:
        name = str(path.relative_to(ROOT))
        try:
            content = path.read_text(encoding="utf-8")
            data = tomllib.loads(content)
        except (OSError, UnicodeError, tomllib.TOMLDecodeError) as exc:
            print(f"FAIL {name}: {exc}")
            return 1
        if not isinstance(data, dict) or not data:
            print(f"FAIL {name}: порожня конфігурація")
            return 1
        if path.name == "services.toml":
            for service in ("ssh", "winbox"):
                settings = data.get("services", {}).get(service)
                if settings is not None and not isinstance(settings.get("limit_to_lan"), bool):
                    print(f"FAIL {name}: services.{service}.limit_to_lan повинен бути bool")
                    return 1
        comments = [line for line in content.splitlines() if line.lstrip().startswith("#")]
        if len(comments) < 5 or not any("ПРИКЛАД" in line for line in comments):
            print(f"FAIL {name}: недостатньо коментарів/прикладів")
            return 1
        print(f"PASS {name}")

    print(f"PASS: {len(paths)} TOML, значення кожного профілю незалежні")
    return 0


if __name__ == "__main__":
    sys.exit(main())
