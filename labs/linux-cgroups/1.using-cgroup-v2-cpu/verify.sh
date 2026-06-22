#!/bin/bash
set -euo pipefail

CGROUP_DIR="/sys/fs/cgroup/limited_cpu_group"

if [ ! -d "$CGROUP_DIR" ]; then
    echo "Ошибка: Директория cgroup $CGROUP_DIR не найдена."
    exit 1
fi

if [ ! -f "$CGROUP_DIR/cpu.max" ]; then
    echo "Ошибка: Файл $CGROUP_DIR/cpu.max не найден. Убедитесь, что вы создали правильную директорию и контроллер cpu включен."
    exit 1
fi

CPU_MAX=$(cat "$CGROUP_DIR/cpu.max")
if [[ "$CPU_MAX" != "50000 100000"* && "$CPU_MAX" != "50000 100000" ]]; then
    echo "Ошибка: Лимит CPU установлен неправильно. Ожидается: '50000 100000', Текущее значение: '$CPU_MAX'"
    exit 1
fi

echo "Проверка пройдена успешно! cgroup v2 для ограничения CPU настроена правильно."
