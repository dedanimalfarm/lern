#!/usr/bin/env bash
# Проверка решения лабы 12-time-sync
set -uo pipefail

ok()   { printf "  [OK]   %s\n" "$1"; }
fail() { printf "  [FAIL] %s\n" "$1"; FAILED=1; }
FAILED=0

# 1. Проверяем, что NTP включён и часы синхронизируются
NTP_ENABLED=$(timedatectl show 2>/dev/null | grep '^NTP=' | cut -d= -f2)
if [ "$NTP_ENABLED" = "yes" ]; then
  ok "NTP синхронизация включена (NTP=yes)"
else
  fail "NTP синхронизация выключена (NTP=$NTP_ENABLED). Включи: sudo timedatectl set-ntp true"
fi

# 2. Проверяем расхождение системного времени с реальным (через RTC)
SYS_EPOCH=$(date +%s)
RTC_STR=$(hwclock --utc -r 2>/dev/null | head -1)
RTC_EPOCH=$(date -d "$RTC_STR" +%s 2>/dev/null || echo 0)

if [ "$RTC_EPOCH" -gt 0 ]; then
  DIFF=$(( SYS_EPOCH - RTC_EPOCH ))
  ABS_DIFF=${DIFF#-}  # абсолютное значение
  if [ "$ABS_DIFF" -lt 300 ]; then
    ok "Системное время близко к RTC (отклонение ${DIFF}с) — синхронизация прошла"
  else
    fail "Системное время далеко от RTC (отклонение ${DIFF}с). Часы всё ещё смещены?"
  fi
else
  # Если RTC недоступен — проверяем статус синхронизации по timedatectl
  SYNCED=$(timedatectl show 2>/dev/null | grep '^NTPSynchronized=' | cut -d= -f2)
  if [ "$SYNCED" = "yes" ]; then
    ok "Часы синхронизированы по NTP (NTPSynchronized=yes)"
  else
    fail "Часы не синхронизированы (NTPSynchronized=${SYNCED:-unknown}) — дождись синхронизации или запусти chronyc makestep"
  fi
fi

echo
if [ "$FAILED" -eq 0 ]; then
  echo "verify: ok"
  exit 0
else
  echo "Есть невыполненные условия."
  exit 1
fi
