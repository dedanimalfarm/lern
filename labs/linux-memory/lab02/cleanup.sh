#!/usr/bin/env bash
# Очистка ресурсов лабораторной работы по cgroups v2
set -uo pipefail

ROOT=0; [ "$(id -u)" -eq 0 ] && ROOT=1

if [ "$ROOT" -ne 1 ]; then
  echo "Запустите очистку через sudo/root"
  exit 1
fi

CG_PATH="/sys/fs/cgroup/mem-test-lab"
if [ -d "$CG_PATH" ]; then
  echo "Удаление cgroup $CG_PATH..."
  if [ -f "$CG_PATH/cgroup.procs" ]; then
    while read -r pid; do
      echo "Завершение процесса $pid..."
      kill -9 "$pid" 2>/dev/null || true
    done < "$CG_PATH/cgroup.procs"
  fi
  rmdir "$CG_PATH" 2>/dev/null && echo "cgroup успешно удалена" || echo "Ошибка удаления cgroup"
fi

echo "Очистка завершена."
