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

sudo pacman -S --noconfirm --needed rsync cron

sudo cat << 'back_up' > /usr/local/bin/backup_pc-serv
#!/bin/bash

HOST=192.168.88.7

# Parse arguments:
TARGET=$1
BACKUP=$2
COUNT=$3
QUIET=$4

if ping -c 3 ${HOST} | grep -e "mdev" >/dev/null; then
    echo "[***] Резервне копіювання 00_setup..."
    rsync -a --quiet -e "ssh -p 2241 -i /home/roman/.ssh/id_serv" /home/roman/00_setup serv@${HOST}:/run/media/serv/media

    echo "[***] Резервне копіювання 01_project..."
    rsync -a --quiet -e "ssh -p 2241 -i /home/roman/.ssh/id_serv" /home/roman/01_project serv@${HOST}:/run/media/serv/media

    echo "[***] Резервне копіювання 03_work..."
    rsync -a --quiet -e "ssh -p 2241 -i /home/roman/.ssh/id_serv" /home/roman/03_work serv@${HOST}:/run/media/serv/media

    echo "[***] Резервне копіювання Documents..."
    rsync -a --quiet -e "ssh -p 2241 -i /home/roman/.ssh/id_serv" /home/roman/Documents serv@${HOST}:/run/media/serv/media

    echo "[***] Резервне копіювання Music..."
    rsync -a --quiet -e "ssh -p 2241 -i /home/roman/.ssh/id_serv" /home/roman/Music serv@${HOST}:/run/media/serv/media

    echo "[***] Резервне копіювання Pictures..."
    rsync -a --quiet -e "ssh -p 2241 -i /home/roman/.ssh/id_serv" /home/roman/Pictures serv@${HOST}:/run/media/serv/media

    echo "[***] Резервне копіювання Videos..."
    rsync -a --quiet -e "ssh -p 2241 -i /home/roman/.ssh/id_serv" /home/roman/Videos serv@${HOST}:/run/media/serv/media
else
    echo "[***] ERROR ping server!!!!!"
    exit 0
fi

# Basic argument checks:
if [ -z "$COUNT" ] ; then
  echo "[***] COUNT не вказано."
fi
if [ ! -z "$5" ] ; then
  echo "[***] Надто багато варіантів."
fi
if [ -n "$QUIET" ] && [ "x$QUIET" != "x-q"	] ; then
  echo "[***] Option 3 is either -q or empty. Given: \"$QUIET\""
fi

# $max_snap це найбільша кількість log файлів, які зберігатимуться $BACKUP
max_log=$COUNT

# Прибирати старші log файли:
for i in $(find "$TARGET" -maxdepth 1|sort |grep "${BACKUP}" |head -n -${max_log}); do
  cmd="rm -r $i"
  if [ -z "$QUIET" ]; then
    echo "[***] ВИДАЛЕННЯ ЛОГ ФАЙЛІВ!!!"
    echo "$cmd"
    $cmd
  else
    $cmd >/dev/null
  fi
done

echo "[***] END..."
back_up

sudo chmod +x /usr/local/bin/backup_pc-serv
sudo chown -R roman:roman /usr/local/bin/backup_pc-serv

crontab -l > ${HOME}/foocron
echo "" >>${HOME}/foocron
echo "# Планувати завдання за допомогою anacron від імені непривилегованих користувачів" >>${HOME}/foocron
echo "0 * * * *  /usr/sbin/anacron -s -t ${HOME}/.local/etc/anacrontab -S ${HOME}/.local/var/spool/anacron" >>${HOME}/foocron
crontab ${HOME}/foocron
rm ${HOME}/foocron

mkdir -p ${HOME}/Documents/log_anacrontab
mkdir -p ${HOME}/.local/var/spool/anacron
mkdir -p ${HOME}/.local/etc && touch ${HOME}/.local/etc/anacrontab

sudo cat << 'anacron' >> ~/.local/etc/anacrontab
SHELL=/bin/sh
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
MAILTO=${USER}
# the maximal random delay added to the base delay of the jobs
RANDOM_DELAY=15
# the jobs will be started during the following hours only
START_HOURS_RANGE=1-24

# Backup_pc-serv
1   10  backup_daily     /usr/local/bin/backup_pc-serv >~/Documents/log_anacrontab/backup-daily_$(date +%Y-%m-%d_%H:%M:%S).log ~/Documents/log_anacrontab/ backup-daily 3
7   20  backup_weekly     /usr/local/bin/backup_pc-serv >~/Documents/log_anacrontab/backup-weekly_$(date +%Y-%m-%d_%H:%M:%S).log ~/Documents/log_anacrontab/ backup-weekly 3
anacron

# sudo sed -i 's/^PATH=.*/PATH=\/sbin\:\/bin\:\/usr\/sbin\:\/usr\/bin\:\/usr\/local\/bin/g' /etc/anacrontab

sudo systemctl start cronie.service
sudo systemctl enable cronie.service

colors yellow "############"
colors green "[***] END..."
colors yellow "############"
