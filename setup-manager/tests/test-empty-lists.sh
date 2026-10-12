#!/usr/bin/env bash
set -Eeuo pipefail
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/archives" "$tmp/backups/recovery"
output="$(bash -c 'ROOT_DIR="$1"; source "$2/lib/ui.sh"; source "$2/lib/archive.sh"; archive_list' bash "$tmp" "$ROOT_DIR")"
[[ "$output" == *'Архівів немає'* ]] || exit 1
output="$(bash -c 'ROOT_DIR="$1"; source "$2/lib/ui.sh"; source "$2/lib/recovery.sh"; recovery_list' bash "$tmp" "$ROOT_DIR")"
[[ "$output" == *'Recovery-копій немає'* ]] || exit 1
printf '[PASS] Порожні списки Archive/Recovery\n'
