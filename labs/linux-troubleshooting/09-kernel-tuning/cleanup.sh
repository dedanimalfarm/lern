#!/usr/bin/env bash
# Очистка для лабы 09-kernel-tuning
set -uo pipefail

if [ -f /tmp/inotify_orig_limit.txt ]; then
  ORIG_LIMIT=$(cat /tmp/inotify_orig_limit.txt)
  echo "Восстанавливаем оригинальный лимит: $ORIG_LIMIT"
  sysctl -w fs.inotify.max_user_watches="$ORIG_LIMIT" >/dev/null
  rm -f /tmp/inotify_orig_limit.txt
fi

echo "Очищаем файлы конфигурации sysctl..."
rm -f /etc/sysctl.d/99-tuning.conf

if [ -f /etc/sysctl.conf ]; then
  # Удаляем строчку из /etc/sysctl.conf, если она была туда записана
  sed -i '/fs.inotify.max_user_watches/d' /etc/sysctl.conf
fi

# Убедимся, что удалены временные файлы тестов
rm -rf /tmp/inotify_test /tmp/test_inotify.py

echo "Очистка завершена!"
