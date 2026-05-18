#!/usr/bin/env bash
# Проверка готовности стенда для лабораторной "Управление памятью".
# Запускается ДО лабы: показывает, чего не хватает и что уже стоит.
# Никаких изменений в системе не делает.

set -u

ok()   { printf "  [OK]   %s\n" "$1"; }
warn() { printf "  [WARN] %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }

FAILED=0

echo "=== Утилиты ==="
for cmd in free vmstat pmap ps strace stress-ng ipcs ipcmk ipcrm lsipc \
           swapon swapoff mkswap fallocate dd python3 getconf sysctl; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "$cmd"
    else
        fail "$cmd  (нет в PATH)"
    fi
done

echo
echo "=== Память и swap ==="
TOTAL_KB=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
TOTAL_MB=$((TOTAL_KB / 1024))
if [ "$TOTAL_MB" -lt 1800 ]; then
    warn "MemTotal = ${TOTAL_MB} MB. Лаба расчитана на >= 2 ГБ — модуль 3 может вести себя нестабильно."
else
    ok "MemTotal = ${TOTAL_MB} MB"
fi

PAGESIZE=$(getconf PAGESIZE 2>/dev/null || echo "?")
ok "PAGESIZE = ${PAGESIZE}"

if swapon --show 2>/dev/null | grep -q .; then
    ok "swap уже активен (это нормально, в модуле 4 добавим свой)"
else
    warn "swap не активен — модуль 3 без swap вызовет OOM-killer при нагрузке"
fi

echo
echo "=== Диск под swap-файл ==="
ROOT_FREE_MB=$(df -Pm / | awk 'NR==2{print $4}')
if [ "$ROOT_FREE_MB" -lt 1500 ]; then
    fail "Свободного места на / меньше 1.5 ГБ (есть ${ROOT_FREE_MB} MB). В модуле 4 не получится создать swap-файл."
else
    ok "Свободного места на /: ${ROOT_FREE_MB} MB"
fi

echo
echo "=== Доступ ==="
if [ "$(id -u)" -eq 0 ]; then
    ok "Запущено от root"
elif sudo -n true 2>/dev/null; then
    ok "sudo доступен без пароля"
else
    warn "Не root. Модули 1.4, 3, 4, 5 потребуют sudo с паролем."
fi

echo
echo "=== Виртуальные ФС ==="
[ -d /proc ] && ok "/proc смонтирован"     || fail "/proc отсутствует"
[ -d /sys  ] && ok "/sys  смонтирован"     || fail "/sys отсутствует"
[ -d /dev/shm ] && ok "/dev/shm смонтирован (нужно для модуля 5)" \
                || fail "/dev/shm отсутствует"

if [ -r /proc/pressure/memory ]; then
    ok "/proc/pressure/memory доступен (PSI работает)"
else
    warn "/proc/pressure/memory нет — ядро без PSI. Модуль 3.3 не сработает (нужно CONFIG_PSI=y, ядро >= 4.20)."
fi

echo
if [ "$FAILED" -eq 0 ]; then
    echo "Стенд готов к лабораторной."
    exit 0
else
    echo "Есть проблемы — поправь FAIL-пункты выше перед началом лабы."
    exit 1
fi
