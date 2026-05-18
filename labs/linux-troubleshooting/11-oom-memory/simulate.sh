#!/usr/bin/env bash
# Запускаем процесс, который сожрёт всю свободную RAM
echo "Запускаем процесс, который будет жадно жрать память до OOM ..."

# stress-ng даёт самый понятный лог в dmesg. Если его нет — fallback на python
if command -v stress-ng >/dev/null 2>&1; then
    # 90% общей памяти — почти гарантированно вызовет OOM, если swap маленький/нет
    BYTES=$(awk '/MemTotal/ {printf "%d", $2*1024*0.9}' /proc/meminfo)
    stress-ng --vm 1 --vm-bytes "$BYTES" --vm-keep -t 120 &
else
    python3 -c '
import time
data = []
while True:
    data.append(bytearray(50 * 1024 * 1024))   # 50 МБ за итерацию
    time.sleep(0.1)
' &
fi

PID=$!
echo "Жадный процесс PID=$PID. Жди убийства через 10-60 секунд."
echo "Параллельно наблюдай: watch -n 1 'free -h; cat /proc/pressure/memory'"
echo "После: dmesg -T | grep -iE 'oom|killed process' | tail"
