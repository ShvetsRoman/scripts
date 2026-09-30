#!/usr/bin/env bash
set -e

KEEP=3

function color() {
  case "$1" in
    red)
      echo -e "\n\033[31m$2\033[0m"
    ;;
    yellow)
      echo -e "\n\033[33m$2\033[0m"
    ;;
    green)
      echo -e "\n\033[32m$2\033[0m"
    ;;
  esac
}

color green "======================================"
color green "  BTRFS + SNAPPER HEALTH CHECK TOOL"
color green "======================================"

color green ""
color green "[1] Disk usage (df):"
df -h /

color green ""
color green "[2] Btrfs filesystem usage:"
sudo btrfs filesystem usage /

color green ""
color green "[3] Snapper list (root):"
sudo snapper -c root list || color green "Snapper not available"

color green ""
color green "[3.1] Cleaning old snapshots (keeping last $KEEP)..."

IDS=$(sudo snapper -c root list | awk 'NR>2 {print $1}' | grep -E '^[0-9]+$' | head -n -$KEEP || true)

if [ -n "$IDS" ]; then
  for id in $IDS; do
    color red "Deleting snapshot: $id"
    sudo snapper -c root delete "$id" || true
  done
else
  color red "Nothing to delete."
fi

color green ""
color green "[4] Snapper list (home):"
sudo snapper -c home list || color green "Snapper not available"

color green ""
color green "[4.1] Cleaning old snapshots (keeping last $KEEP)..."

IDSH=$(sudo snapper -c home list | awk 'NR>2 {print $1}' | grep -E '^[0-9]+$' | head -n -$KEEP || true)

if [ -n "$IDSH" ]; then
  for id in $IDSH; do
    color red "Deleting snapshot: $id"
    sudo snapper -c home delete "$id" || true
  done
else
  color red "Nothing to delete."
fi

color green ""
color green "[5] Running Btrfs balance (safe mode)..."
sudo btrfs balance start -dusage=75 -musage=75 / || true

color green ""
color green "[6] Checking grub-btrfsd service..."
systemctl status grub-btrfsd.service --no-pager || color red "grub-btrfsd not active"

color green ""
color green "[7] Final disk state:"
df -h /

color green ""
color green "======================================"
color green " DONE - system optimized like openSUSE"
color green "======================================"
