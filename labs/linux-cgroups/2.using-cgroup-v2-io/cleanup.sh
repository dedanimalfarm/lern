#!/bin/bash
set -euo pipefail

echo "==> Начинаем уборку стенда..."

# 1. Завершаем процесс dd, если он еще работает
if pgrep -f "dd if=/dev/zero of=/tmp/testfile" > /dev/null; then
    echo "Остановка запущенных процессов dd..."
    sudo pkill -f "dd if=/dev/zero of=/tmp/testfile" || true
    sleep 1 # даем процессу завершиться
fi

# 2. Удаляем тестовый файл
if [ -f /tmp/testfile ]; then
    echo "Удаление /tmp/testfile..."
    sudo rm -f /tmp/testfile
fi

# 3. Удаляем cgroup
CGROUP_DIR="/sys/fs/cgroup/io_limit_group"
if [ -d "$CGROUP_DIR" ]; then
    echo "Очистка процессов из cgroup $CGROUP_DIR..."
    # Перемещаем оставшиеся процессы в корневую группу, чтобы можно было удалить cgroup
    if [ -f "$CGROUP_DIR/cgroup.procs" ]; then
        for pid in $(cat "$CGROUP_DIR/cgroup.procs" 2>/dev/null || true); do
            echo "$pid" | sudo tee /sys/fs/cgroup/cgroup.procs >/dev/null || true
        done
    fi
    echo "Удаление cgroup $CGROUP_DIR..."
    sudo rmdir "$CGROUP_DIR"
fi

echo "✅ Уборка завершена. Среда восстановлена."
