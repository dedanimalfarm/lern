#!/usr/bin/env bash
# Очистка ресурсов лабораторной работы по THP
set -uo pipefail

ROOT=0; [ "$(id -u)" -eq 0 ] && ROOT=1

if [ "$ROOT" -eq 1 ]; then
  # Восстанавливаем стандартное значение для Ubuntu/Debian
  echo "madvise" > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || true
  echo "madvise" > /sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null || true
  echo "THP сброшены в состояние madvise"
fi

echo "Очистка завершена."
