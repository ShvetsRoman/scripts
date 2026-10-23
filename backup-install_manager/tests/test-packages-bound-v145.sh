#!/usr/bin/env bash
# Перевірка прив'язки hook до пакета та діагностики конфігурації.
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../src/packages/registry.sh
source "$ROOT_DIR/src/packages/registry.sh"
# shellcheck source=../src/hooks/hooks.sh
source "$ROOT_DIR/src/hooks/hooks.sh"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
log() { :; }
cat > "$tmp/packages.conf" <<'INI'
[demo]
title = Demo
pacman = alpha beta
aur =
configs =
hooks = common
hook.alpha = alpha_config
INI
packages_load "$tmp/packages.conf"
[[ "${PACKAGE_BOUND_HOOKS[demo|alpha]}" == alpha_config ]]
[[ "${PACKAGE_HOOKS[demo]}" == common ]]
cat > "$tmp/packages.conf" <<'INI'
[demo]
title = Demo
pacman = alpha
hook.beta = beta_config
INI
if packages_load "$tmp/packages.conf" 2>/dev/null; then exit 1; fi
cat > "$tmp/packages.conf" <<'INI'
[demo]
title = Demo
pacman = alpha
hooks = same
hook.alpha = same
INI
if packages_load "$tmp/packages.conf" 2>/dev/null; then exit 1; fi
cat > "$tmp/packages.conf" <<'INI'
[demo]
title = Demo
pacman = alpha
hook.alpha = ../invalid
INI
if packages_load "$tmp/packages.conf" 2>/dev/null; then exit 1; fi
printf '[PASS] test-packages-bound-v145\n'
