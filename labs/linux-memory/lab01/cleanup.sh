#!/usr/bin/env bash
# Уборка за лабой "Управление памятью в Linux".
# Трогает ТОЛЬКО ресурсы, созданные в лабе. Никаких killall и массового ipcrm.
set -uo pipefail
SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo"

# 1) Тестовый swap (системный/чужой swap не трогаем)
for f in /swapfile-lab /swapfile-lab2 /swapfile-verify; do
  $SUDO swapoff "$f" 2>/dev/null || true
  $SUDO sed -i "\\#^${f}[[:space:]]#d" /etc/fstab 2>/dev/null || true
  $SUDO rm -f "$f"
done

# 2) Временные файлы и POSIX shm из лабы
$SUDO rm -f /tmp/bigfile /tmp/mmap-shared /dev/shm/posix_demo

# 3) Свой sysctl-оверрайд swappiness (только если создавали)
if [ -f /etc/sysctl.d/99-swappiness.conf ]; then
  $SUDO rm -f /etc/sysctl.d/99-swappiness.conf
  $SUDO sysctl -w vm.swappiness=60 >/dev/null 2>&1 || true
fi

# 4) Фоновые процессы лабы — ТОЛЬКО по характерным маркерам, без killall.
#    Паттерны экранированы (круглые/звёздочки — спецсимволы ERE в pkill -f).
for pat in '1024\*1024\*1024' 'libc\.malloc' '1024 \* 50' '/tmp/mmap-shared'; do
  pkill -f -- "$pat" 2>/dev/null || true
done
pkill -f -- 'stress-ng --vm' 2>/dev/null || true

# 5) cgroup-scope из модулей 3/6 (если остался)
$SUDO systemctl stop memlab.slice 2>/dev/null || true

echo "Уборка завершена."
echo "Осиротевшие SysV shm (если создавали в модуле 5) удаляйте точечно по своему shmid:"
echo "  ipcs -m   # найдите свои сегменты с nattch=0, затем: ipcrm -m <shmid>"
echo
free -h
swapon --show 2>/dev/null || true
