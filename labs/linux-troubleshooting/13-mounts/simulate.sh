#!/usr/bin/env bash
set -e

IMG=/tmp/lab-mount.img
MP=/mnt/lab-mount

echo "Готовим loop-устройство 64M и монтируем в $MP ..."
sudo mkdir -p "$MP"

# Создаём файл-образ и форматируем в ext4
if [ ! -f "$IMG" ]; then
    sudo dd if=/dev/zero of="$IMG" bs=1M count=64 status=none
    sudo mkfs.ext4 -q "$IMG"
fi

# Найдём свободный loop и смонтируем
LOOP=$(sudo losetup -f --show "$IMG")
sudo mount "$LOOP" "$MP"

echo "Смонтировано: $(findmnt -n -o SOURCE,TARGET,FSTYPE $MP)"

# Запускаем в этой ФС фоновый процесс, который держит файл открытым
sudo bash -c "cd $MP && sleep 9999 < $MP/.holder 2>/dev/null" &
sudo touch "$MP/.holder"
sudo bash -c "tail -f $MP/.holder >/dev/null 2>&1 &"

sleep 1
echo
echo "Пробуем размонтировать ..."
sudo umount "$MP" 2>&1 || true
echo
echo "Не получилось — кто-то держит ФС. Найди виновника:"
echo "  sudo fuser -mv $MP"
echo "  sudo lsof   $MP"
echo
echo "Когда разберёшься — запусти ./cleanup.sh для полной очистки."
