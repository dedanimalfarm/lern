#!/bin/bash
set -euo pipefail

CGROUP_PATH="/sys/fs/cgroup/memory_limit_group"

echo "Проверка конфигурации cgroup..."

if [ ! -d "$CGROUP_PATH" ]; then
    echo "❌ Ошибка: Группа cgroup $CGROUP_PATH не существует."
    exit 1
fi
echo "✅ Группа cgroup $CGROUP_PATH создана."

if [ ! -f "$CGROUP_PATH/memory.max" ]; then
    echo "❌ Ошибка: Файл memory.max не найден."
    exit 1
fi

MEM_MAX=$(cat "$CGROUP_PATH/memory.max")
if [ "$MEM_MAX" = "max" ]; then
    echo "❌ Ошибка: Лимит памяти не установлен (memory.max = max)."
    exit 1
fi

echo "✅ Лимит памяти установлен (memory.max = $MEM_MAX)."
echo "🎉 Проверка пройдена успешно!"
