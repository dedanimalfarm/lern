#!/usr/bin/env bash
# Проверка усвоенных навыков лабы "Ограничение ресурсов с помощью cgroup v2".
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

ROOT=0; [ "$(id -u)" -eq 0 ] && ROOT=1

if [ "$ROOT" -ne 1 ]; then
  fail "Этот скрипт должен быть запущен с правами root"
  exit 1
fi

# 1. Проверка cgroup v2
if mount | grep -q cgroup2; then
  ok "cgroup v2 смонтирована"
else
  fail "cgroup v2 не смонтирована"
fi

# 2. Проверка доступности контроллера memory
if grep -q "memory" /sys/fs/cgroup/cgroup.controllers; then
  ok "Контроллер memory доступен в cgroup v2"
else
  fail "Контроллер memory не найден в cgroup.controllers"
fi

# 3. Проверка жесткого лимита memory.max и OOM-killer
CG_PATH="/sys/fs/cgroup/verify-mem-limit"
if [ -e "$CG_PATH" ]; then
  # Убиваем процессы в cgroup, если она осталась с прошлого раза
  if [ -f "$CG_PATH/cgroup.procs" ]; then
    while read -r pid; do
      kill -9 "$pid" 2>/dev/null || true
    done < "$CG_PATH/cgroup.procs"
  fi
  rmdir "$CG_PATH" 2>/dev/null || true
fi

if mkdir "$CG_PATH" 2>/dev/null; then
  echo "20M" > "$CG_PATH/memory.max"
  # Запускаем stress-ng внутри cgroup и ожидаем OOM-kill (exit code 137 или SIGKILL)
  (
    echo "$BASHPID" > "$CG_PATH/cgroup.procs"
    exec stress-ng --vm 1 --vm-bytes 50M --vm-hang 5 -t 10 >/dev/null 2>&1
  ) &
  SPID=$!
  wait "$SPID" 2>/dev/null || true
  
  # Проверим, был ли OOM-kill
  OOM_COUNT=$(grep -oP 'oom_kill \K\d+' "$CG_PATH/memory.events" 2>/dev/null || echo "0")
  if [ "$OOM_COUNT" -gt 0 ]; then
    ok "Процесс превысил memory.max=20M и был успешно OOM-killed (oom_kill count=$OOM_COUNT)"
  else
    if dmesg | tail -n 50 | grep -qi "killed process"; then
      ok "Процесс превысил memory.max=20M и был OOM-killed (обнаружено в dmesg)"
    else
      fail "Процесс выделил больше лимита, но не был убит OOM-killer'ом"
    fi
  fi
  
  rmdir "$CG_PATH" 2>/dev/null || true
else
  fail "Не удалось создать группу cgroup по пути $CG_PATH"
fi

# 4. Проверка oom_score_adj
TEST_PID=$$
OLD_ADJ=$(cat "/proc/$TEST_PID/oom_score_adj")
NEW_ADJ=500
if echo "$NEW_ADJ" > "/proc/$TEST_PID/oom_score_adj" 2>/dev/null; then
  CURRENT_ADJ=$(cat "/proc/$TEST_PID/oom_score_adj")
  if [ "$CURRENT_ADJ" -eq "$NEW_ADJ" ]; then
    ok "oom_score_adj успешно изменяется (было: $OLD_ADJ, стало: $CURRENT_ADJ)"
  else
    fail "oom_score_adj не применился (ожидали $NEW_ADJ, получили $CURRENT_ADJ)"
  fi
  echo "$OLD_ADJ" > "/proc/$TEST_PID/oom_score_adj" 2>/dev/null || true
else
  fail "Не удалось записать в /proc/$TEST_PID/oom_score_adj"
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть проваленные проверки."
  exit 1
fi
