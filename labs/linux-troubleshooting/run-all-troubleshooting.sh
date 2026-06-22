#!/usr/bin/env bash
# =============================================================================
# run-all-troubleshooting.sh — Автоматический тест всех лаб курса linux-troubleshooting
# Запуск: sudo ./run-all-troubleshooting.sh
# =============================================================================
set -uo pipefail

PASS=0
FAIL=0
SKIP=0
FAILED_LABS=()

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

green()  { printf "\033[32m%s\033[0m\n" "$*"; }
red()    { printf "\033[31m%s\033[0m\n" "$*"; }
yellow() { printf "\033[33m%s\033[0m\n" "$*"; }
bold()   { printf "\033[1m%s\033[0m\n" "$*"; }
sep()    { printf "\n%s\n" "────────────────────────────────────────────────"; }

run_lab() {
  local NUM="$1"
  local NAME="$2"
  local SETUP_FN="$3"   # функция подготовки (решения) — запускается после simulate.sh
  local LAB_DIR="$BASE_DIR/$NUM-$NAME"

  sep
  bold "[ LAB $NUM ] $NAME"

  if [ ! -f "$LAB_DIR/simulate.sh" ]; then
    yellow "  SKIP  — simulate.sh не найден"
    (( SKIP++ )) || true
    return
  fi
  if [ ! -f "$LAB_DIR/verify.sh" ]; then
    yellow "  SKIP  — verify.sh не найден"
    (( SKIP++ )) || true
    return
  fi

  # Очистка перед стартом (на случай грязного состояния)
  if [ -f "$LAB_DIR/cleanup.sh" ]; then
    bash "$LAB_DIR/cleanup.sh" >/dev/null 2>&1 || true
  fi

  # Запуск симуляции
  echo "  → Запускаем simulate.sh ..."
  bash "$LAB_DIR/simulate.sh" >/dev/null 2>&1 || true

  # Применяем решение студента (автоматическое)
  echo "  → Применяем решение ..."
  $SETUP_FN "$LAB_DIR"

  # Запускаем верификатор
  echo "  → Запускаем verify.sh ..."
  if bash "$LAB_DIR/verify.sh"; then
    green "  ✓  PASS"
    (( PASS++ )) || true
  else
    red "  ✗  FAIL"
    (( FAIL++ )) || true
    FAILED_LABS+=("$NUM-$NAME")
  fi

  # Очистка после теста
  if [ -f "$LAB_DIR/cleanup.sh" ]; then
    bash "$LAB_DIR/cleanup.sh" >/dev/null 2>&1 || true
  fi
}

# ─── Функции решений для каждой лабы ────────────────────────────────────────

solve_system_cpu_ram() {
  pkill -f 'stress-ng --cpu 2 --vm 1' 2>/dev/null || true
  sleep 1
}

solve_disk_io() {
  pkill -f 'tail -f /dev/urandom' 2>/dev/null || true
  pkill -f 'dd if=/dev/urandom' 2>/dev/null || true
  # Освобождаем дескрипторы удалённых файлов
  lsof 2>/dev/null | awk '/deleted/ && /\/tmp\// {print $2}' | sort -u | xargs -r kill 2>/dev/null || true
}

solve_networking() {
  # Удаляем DROP-правило на порт 8888
  iptables -D INPUT -p tcp --dport 8888 -j DROP 2>/dev/null || true
}

solve_logs_services() {
  # Создаём magic_config.ini для broken-app.service
  echo "[app]" > /etc/magic_config.ini
  echo "enabled=true" >> /etc/magic_config.ini
  systemctl restart broken-app.service 2>/dev/null || true
}

solve_certificates() {
  # Проверяем наличие valid.crt/valid.key (уже созданы симуляцией)
  true
}

solve_advanced_tracing() {
  # Создаём конфиг для stuck_app.py
  echo "run=true" > /tmp/stuck_app_config.cfg
}

solve_network_traffic() {
  # Убиваем фоновый curl-генератор и сохраняем IP в файл
  pkill -f 'curl.*93.184.216.34' 2>/dev/null || true
  echo "93.184.216.34" > /tmp/suspicious_ip.txt
}

solve_audit_users() {
  # Создаём отчёт с правильными ответами
  echo "SSH_USER=hacker"          > /tmp/audit_report.txt
  echo "SECRET_MODIFIER_UID=65534" >> /tmp/audit_report.txt
}

solve_kernel_tuning() {
  # Повышаем лимит inotify и записываем в конфиг
  sysctl -w fs.inotify.max_user_watches=524288 >/dev/null
  mkdir -p /etc/sysctl.d
  echo "fs.inotify.max_user_watches=524288" > /etc/sysctl.d/99-tuning.conf
}

solve_dns() {
  # Удаляем подложную запись из /etc/hosts и сбрасываем кеш
  sed -i '/192\.0\.2\.1[[:space:]]\+github\.com/d' /etc/hosts 2>/dev/null || true
  resolvectl flush-caches 2>/dev/null || true
}

solve_oom_memory() {
  # Убиваем жадный процесс (OOM уже должен был произойти, но на всякий случай)
  pkill -f 'stress-ng.*--vm-keep' 2>/dev/null || true
  pkill -f 'bytearray.*50.*1024' 2>/dev/null || true
  sleep 1
}

solve_time_sync() {
  # Включаем NTP и синхронизируем с RTC
  timedatectl set-ntp true 2>/dev/null || true
  hwclock --hctosys --utc 2>/dev/null || true
  sleep 3
}

solve_mounts() {
  local LAB_DIR="$1"
  MP=/mnt/lab-mount
  IMG=/tmp/lab-mount.img
  # Убиваем процессы и размонтируем
  fuser -km "$MP" 2>/dev/null || true
  sleep 1
  umount -l "$MP" 2>/dev/null || true
  losetup -j "$IMG" 2>/dev/null | cut -d: -f1 | xargs -r losetup -d
}

solve_ulimits_fd() {
  # Повышаем мягкий лимит fd в текущем процессе (subshell наследует)
  ulimit -Sn 8192
}

# ─── Запуск лаб ──────────────────────────────────────────────────────────────

sep
bold "🔍  linux-troubleshooting — автопрогон всех лаб"

run_lab "01" "system-cpu-ram"   "solve_system_cpu_ram"
run_lab "02" "disk-io"          "solve_disk_io"
run_lab "03" "networking"       "solve_networking"
run_lab "04" "logs-services"    "solve_logs_services"
run_lab "05" "certificates"     "solve_certificates"
run_lab "06" "advanced-tracing" "solve_advanced_tracing"
run_lab "07" "network-traffic"  "solve_network_traffic"
run_lab "08" "audit-users"      "solve_audit_users"
run_lab "09" "kernel-tuning"    "solve_kernel_tuning"
run_lab "10" "dns"              "solve_dns"
run_lab "11" "oom-memory"       "solve_oom_memory"
run_lab "12" "time-sync"        "solve_time_sync"
run_lab "13" "mounts"           "solve_mounts"
run_lab "14" "ulimits-fd"       "solve_ulimits_fd"

# ─── Итоговый отчёт ──────────────────────────────────────────────────────────

sep
bold "📊  Итоговый результат"
green "  PASS: $PASS"
if [ "$FAIL" -gt 0 ]; then
  red "  FAIL: $FAIL  →  ${FAILED_LABS[*]}"
else
  echo "  FAIL: 0"
fi
yellow "  SKIP: $SKIP"

if [ "$FAIL" -eq 0 ] && [ "$SKIP" -eq 0 ]; then
  sep
  green "🎉  Все лабы пройдены успешно!"
  exit 0
elif [ "$FAIL" -eq 0 ]; then
  sep
  yellow "⚠️   Некоторые лабы пропущены (нет verify.sh/simulate.sh)"
  exit 0
else
  sep
  red "❌  Есть провалы. Проверьте логи выше."
  exit 1
fi
