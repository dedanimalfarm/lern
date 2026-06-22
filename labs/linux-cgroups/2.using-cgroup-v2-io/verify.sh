#!/bin/bash
set -euo pipefail

echo "==> Проверка выполнения лабораторной работы..."

if [ ! -d "/sys/fs/cgroup/io_limit_group" ]; then
  echo "❌ Ошибка: cgroup '/sys/fs/cgroup/io_limit_group' не найдена. Создайте её с помощью mkdir."
  exit 1
fi

if [ ! -f "/sys/fs/cgroup/io_limit_group/io.max" ]; then
  echo "❌ Ошибка: Файл '/sys/fs/cgroup/io_limit_group/io.max' не найден."
  echo "Убедитесь, что контроллер 'io' включен в родительской cgroup (cgroup.subtree_control)."
  exit 1
fi

IO_MAX=$(cat /sys/fs/cgroup/io_limit_group/io.max)
if ! echo "$IO_MAX" | grep -q "wbps="; then
  echo "❌ Ошибка: В файле io.max не задано ограничение записи (wbps)."
  echo "Текущее содержимое io.max:"
  echo "$IO_MAX"
  exit 1
fi

echo "✅ Cgroup '/sys/fs/cgroup/io_limit_group' успешно создана!"
echo "✅ Ограничение на запись (io.max) установлено корректно."
echo "🎉 Поздравляем с успешным выполнением задания!"
