#!/usr/bin/env bash
MP=/mnt/lab-mount
IMG=/tmp/lab-mount.img

echo "Убиваем процессы внутри $MP ..."
sudo fuser -km "$MP" 2>/dev/null || true
sleep 1

echo "Размонтируем (lazy, на случай если ещё кто-то держит) ..."
sudo umount -l "$MP" 2>/dev/null || true

echo "Отключаем loop-устройства ..."
sudo losetup -j "$IMG" 2>/dev/null | cut -d: -f1 | xargs -r sudo losetup -d

echo "Удаляем файл-образ и точку ..."
sudo rm -f "$IMG"
sudo rmdir "$MP" 2>/dev/null || true

echo "Готово."
