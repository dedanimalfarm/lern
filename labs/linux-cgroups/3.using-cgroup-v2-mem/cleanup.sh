#!/bin/bash
set -euo pipefail

CGROUP_PATH="/sys/fs/cgroup/memory_limit_group"

echo "Очистка ресурсов..."

# Kill any stress processes globally just in case
sudo pkill -9 stress || true

if [ -d "$CGROUP_PATH" ]; then
    echo "Очистка процессов в $CGROUP_PATH..."
    if [ -f "$CGROUP_PATH/cgroup.procs" ]; then
        while read -r pid; do
            if [ -n "$pid" ]; then
                sudo kill -9 "$pid" 2>/dev/null || true
            fi
        done < "$CGROUP_PATH/cgroup.procs"
    fi
    
    sleep 1

    echo "Удаление cgroup $CGROUP_PATH..."
    sudo rmdir "$CGROUP_PATH" || {
        echo "❌ Не удалось удалить $CGROUP_PATH, возможно группа все еще содержит процессы."
        exit 1
    }
    echo "✅ Cgroup удален."
else
    echo "✅ Cgroup $CGROUP_PATH не существует, очистка не требуется."
fi

echo "🧹 Очистка завершена."
