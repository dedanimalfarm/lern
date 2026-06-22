#!/bin/bash
set -euo pipefail

CGROUP_DIR="/sys/fs/cgroup/limited_cpu_group"

echo "Остановка процессов stress..."
pkill stress || echo "Процессы stress не найдены."

if [ -d "$CGROUP_DIR" ]; then
    echo "Удаление cgroup $CGROUP_DIR..."
    sleep 1
    
    if ! sudo rmdir "$CGROUP_DIR" 2>/dev/null; then
        echo "В cgroup остались процессы. Принудительное завершение..."
        if [ -f "$CGROUP_DIR/cgroup.procs" ]; then
            for pid in $(cat "$CGROUP_DIR/cgroup.procs"); do
                sudo kill -9 "$pid" 2>/dev/null || true
            done
        fi
        sleep 1
        sudo rmdir "$CGROUP_DIR"
    fi
    echo "Успешно удалено."
else
    echo "Директория cgroup $CGROUP_DIR не найдена, нечего удалять."
fi

echo "Очистка завершена."
