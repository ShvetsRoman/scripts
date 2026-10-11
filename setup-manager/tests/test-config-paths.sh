#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf -- "$TMP"' EXIT
mkdir -p "$TMP/dotfiles/.config/fzf" "$TMP/home/.config/fzf" "$TMP/bin"
printf 'source\n' > "$TMP/dotfiles/.config/fzf/settings"
printf 'target\n' > "$TMP/home/.config/fzf/settings"
cat > "$TMP/bin/rsync" <<'MOCK'
#!/usr/bin/env bash
printf '[MOCK RSYNC] %s\n' "$*"
MOCK
chmod +x "$TMP/bin/rsync"
export PATH="$TMP/bin:$PATH" HOME="$TMP/home" TEST_ROOT="$ROOT" TEST_TMP="$TMP"
for dry in true false; do
  export TEST_DRY="$dry"
  bash -c '
    set -Eeuo pipefail
    ROOT_DIR="$TEST_ROOT/install-packages"
    DOTFILES_DIR="$TEST_TMP/dotfiles"
    BACKUP_ROOT="$TEST_TMP/backups"
    DRY_RUN="$TEST_DRY" CONFIG_BACKUP=true SYNC_DELETE=false STRICT_CONFIGS=false INSTALL_CONFIGS=true
    BLUE="" GREEN="" YELLOW="" RED="" MAGENTA="" NC=""
    source "$TEST_ROOT/lib/ui.sh"
    source "$ROOT_DIR/lib/common.sh"
    source "$TEST_ROOT/lib/core.sh"
    source "$ROOT_DIR/lib/configs.sh"
    copy_config_path home .config/fzf .config/fzf fzf
    copy_config_path home .config/absent .config/absent superfile
  ' > "$TMP/output-$dry"
  grep -Fq "Звідки: $TMP/home/.config/fzf" "$TMP/output-$dry"
  grep -Fq "Звідки: $TMP/dotfiles/.config/fzf" "$TMP/output-$dry"
  grep -Fq "Куди:   $TMP/home/.config/fzf" "$TMP/output-$dry"
  grep -Fq "Конфіг superfile не знайдено, пропускаю: $TMP/dotfiles/.config/absent" "$TMP/output-$dry"
  if [[ "$dry" == true ]]; then
    grep -Fq '[DRY-RUN] Захисний backup: fzf буде виконано.' "$TMP/output-$dry"
    grep -Fq '[DRY-RUN] Конфіг: fzf буде скопійовано.' "$TMP/output-$dry"
    [[ ! -d "$TMP/backups" ]]
  else
    grep -Fq '[OK] Захисний backup: fzf виконано.' "$TMP/output-$dry"
    grep -Fq '[OK] Конфіг: fzf скопійовано.' "$TMP/output-$dry"
    compgen -G "$TMP/backups/*/home/.config/fzf/settings" >/dev/null
  fi
done
printf '[PASS] Шляхи backup/copy, коректні OK/dry-run, назви відсутніх конфігів\n'
