#!/usr/bin/env bash
# Порожній список AUR не повинен створювати етап встановлення.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/packages/registry.sh
source "$ROOT_DIR/src/packages/registry.sh"
# shellcheck source=../src/packages/packages.sh
source "$ROOT_DIR/src/packages/packages.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
cat > "$tmp/packages.conf" <<'INI'
[demo]
title = Demo
pacman = alpha
INI
packages_load "$tmp/packages.conf"
log() { :; }
header() { :; }
stage() { printf '%s\n' "$1"; }
hooks_validate() { return 0; }
pkgs_install() { :; }
configs_apply() { :; }
hooks_run_bound() { :; }
hooks_run() { :; }
pkg_run_module demo > "$tmp/output"
grep -Fq 'INFO встановлюються пакети pacman' "$tmp/output"
if grep -Fq 'INFO встановлюються пакети aur' "$tmp/output"; then
    printf '[FAIL] Порожній AUR показує заголовок\n' >&2
    exit 1
fi
cat > "$tmp/packages.conf" <<'INI'
[demo]
title = Demo
pacman = alpha
aur = beta
INI
packages_load "$tmp/packages.conf"
pkg_run_module demo > "$tmp/output"
grep -Fq 'INFO встановлюються пакети aur' "$tmp/output"
printf '[PASS] test-packages-empty-stage-v201\n'
