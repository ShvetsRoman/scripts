#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf '[FAIL] %s\n' "$*" >&2; exit 1; }
expected_version="$(bash -c 'source "$1/config/setup.conf"; printf "%s" "$SETUP_VERSION"' bash "$ROOT_DIR")"
[[ -n "$expected_version" && "$(bash "$ROOT_DIR/setup.sh" --version)" == "$expected_version" ]] || fail version
bash "$ROOT_DIR/setup.sh" archive list >/dev/null || fail archives
bash "$ROOT_DIR/setup.sh" recovery list >/dev/null || fail recovery
bash "$ROOT_DIR/setup.sh" maintenance disk >/dev/null || fail disk
bash "$ROOT_DIR/setup.sh" git invalid >/dev/null 2>&1 && fail git-invalid
bash "$ROOT_DIR/setup.sh" archive restore ../bad.tar.gz >/dev/null 2>&1 && fail path-traversal
bash "$ROOT_DIR/setup.sh" recovery restore ../bad >/dev/null 2>&1 && fail recovery-traversal
printf '[PASS] Archive, Recovery, Maintenance, Git routing\n'
# Інтеграційний сценарій на ізольованій копії, без зміни справжнього HOME.
fixture="$(mktemp -d)"
trap 'rm -rf -- "$fixture"' EXIT
mkdir -p "$fixture/project/dotfiles/.config/demo" "$fixture/home"
cp -a "$ROOT_DIR/setup.sh" "$ROOT_DIR/lib" "$ROOT_DIR/config" "$ROOT_DIR/modules" "$ROOT_DIR/tools" "$fixture/project/"
printf 'original\n' > "$fixture/project/dotfiles/.config/demo/config.toml"
(
    cd "$fixture/project"
    ./setup.sh archive create >/dev/null
    archive="$(./setup.sh archive list | head -n 1)"
    [[ -n "$archive" ]] || exit 1
    printf 'changed\n' > dotfiles/.config/demo/config.toml
    SETUP_ASSUME_YES=true ./setup.sh archive restore "$archive" >/dev/null || exit 1
    [[ "$(cat dotfiles/.config/demo/config.toml)" == original ]] || exit 1
) || fail 'Відновлення архіву'
printf '[PASS] Архів: створення та відновлення на тестових файлах\n'
