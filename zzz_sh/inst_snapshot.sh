#!/bin/bash

colors() {
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

sudo pacman -S --noconfirm --needed grub-btrfs cron

sudo cat << 'snap-shot' > /usr/local/bin/btrfs-snapshot
#!/bin/bash

# Parse arguments:
SOURCE=$1
TARGET=$2
SNAP=$3
COUNT=$4
QUIET=$5

# Basic argument checks:
if [ -z "$COUNT" ] ; then
  echo "COUNT не вказано."
fi
if [ ! -z "$6" ] ; then
  echo "Надто багато варіантів."
fi
if [ -n "$QUIET" ] && [ "x$QUIET" != "x-q"	] ; then
  echo "Option 4 is either -q or empty. Given: \"$QUIET\""
fi

# $max_snap це найбільша кількість знімків, які зберігатимуться $SNAP.
max_snap=$COUNT

# Створити новий snapshot:
cmd="btrfs subvolume snapshot $SOURCE $TARGET/$(date --iso-8601=seconds)-@${SNAP}"
if [ -z "$QUIET" ]; then
  echo "$cmd"
  $cmd
else
  $cmd >/dev/null
fi

# Прибирати старше snapshots:
for i in $(find "$TARGET" -maxdepth 1|sort |grep @"${SNAP}"\$|head -n -${max_snap}); do
  cmd="btrfs subvolume delete $i"
  if [ -z "$QUIET" ]; then
    echo "$cmd"
    $cmd
  else
    $cmd >/dev/null
  fi
done

snap-shot
sudo chmod +x /usr/local/bin/btrfs-snapshot
sudo chown -R roman:roman /usr/local/bin/btrfs-snapshot

mkdir ~/Documents/log_anacrontab

sudo cat << 'anacron-tab' >> /etc/anacrontab

# Snapshots btrfs
1    5  daily_snap      /usr/local/bin/btrfs-snapshot / /.snapshots daily 8 >~/Documents/log_anacrontab/daily-snap_$(date +%Y-%m-%d_%H:%M:%S).log
7   10  weekly_snap     /usr/local/bin/btrfs-snapshot / /.snapshots weekly 5 >~/Documents/log_anacrontab/weekly-snap_$(date +%Y-%m-%d_%H:%M:%S).log
30  15  monthly_snap    /usr/local/bin/btrfs-snapshot / /.snapshots monthly 3 >~/Documents/log_anacrontab/monthly-snap_$(date +%Y-%m-%d_%H:%M:%S).log
1   20  grub_mkconfig   grub-mkconfig
anacron-tab

sudo sed -i 's/^PATH=.*/PATH=\/sbin\:\/bin\:\/usr\/sbin\:\/usr\/bin\:\/usr\/local\/bin/g' /etc/anacrontab

sudo systemctl start cronie.service
sudo systemctl enable cronie.service

colors yellow "######################################################################################"
colors yellow "######################################################################################"
