#!/usr/bin/env bash
set -Eeuo pipefail
repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf -- "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/home"
export HOME="$tmp/home" SETUP_LOG_FILE='' SETUP_ASSUME_YES=true
[[ "$(bash "$repo/backup-install_manager.sh" packages --list)" == *snapper* ]]
# Snapper is available only through Installer, not as a top-level CLI command.
if bash "$repo/backup-install_manager.sh" snapper check >"$tmp/invalid-command" 2>&1; then
    printf '[FAIL] snapper must not be top-level CLI command\n' >&2
    exit 1
fi
if grep -q './backup-install_manager.sh snapper check' "$tmp/invalid-command"; then
    printf '[FAIL] obsolete Snapper help text\n' >&2
    exit 1
fi
cat > "$tmp/bin/findmnt" <<'STUB'
#!/usr/bin/env bash
printf 'btrfs\n'
STUB
for cmd in snapper systemctl pacman; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$cmd"
done
cat > "$tmp/bin/sudo" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == -- ]] && shift
printf '%s\n' "$*" >> "$SNAPPER_TEST_CALLS"
if [[ "${1:-}" == test && "${2:-}" == -f ]]; then
    [[ "${3:-}" == /etc/snapper/configs/root ]] && exit 0
    exit 1
fi
exit 0
STUB
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH" SNAPPER_TEST_CALLS="$tmp/calls"
# No home config: standalone hook must skip without writes.
result="$(SETUP_ROOT="$repo" SETUP_DRY_RUN=false bash "$repo/src/hooks/hook_runtime.sh" "$repo/hooks/snapper.sh")"
[[ "$result" == *'[SKIP]'* ]]
! grep -Eq '^(cp|install|snapper|systemctl|tee) ' "$SNAPPER_TEST_CALLS" 2>/dev/null
printf '[PASS] test-snapper\n'
