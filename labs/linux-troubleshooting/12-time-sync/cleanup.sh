#!/usr/bin/env bash
set -u
echo "Возвращаем NTP-синхронизацию ..."

# Пробуем оба распространённых демона: systemd-timesyncd и chrony.
sudo timedatectl set-ntp true 2>/dev/null

if systemctl list-unit-files | grep -q '^chrony\.service'; then
    sudo systemctl start chrony 2>/dev/null || true
    # chrony при большом отрыве часов отказывается шагать — заставляем явно.
    sudo chronyc -a makestep 2>/dev/null || sudo chronyc makestep 2>/dev/null || true
fi

if systemctl list-unit-files | grep -q '^systemd-timesyncd\.service'; then
    sudo systemctl start systemd-timesyncd 2>/dev/null || true
fi

sleep 2

# Если за это время демон не дотянул часы (часто chrony отказывается шагать
# на сотни дней — он только медленно слевает), читаем железо: RTC мы не трогали.
NOW=$(date -u +%s)
RTC=$(sudo hwclock --utc -r 2>/dev/null | head -1)
RTC_EPOCH=$(sudo date -u -d "$RTC" +%s 2>/dev/null || echo 0)
if [ "$RTC_EPOCH" -gt 0 ] && [ "$((NOW - RTC_EPOCH))" -gt 600 ]; then
    echo "Системные часы всё ещё в будущем — копирую время из RTC ..."
    sudo hwclock --hctosys --utc
fi

timedatectl
echo "Если время всё ещё убежало, вручную: sudo date -u -s \"\$(curl -sI https://www.google.com | grep -i ^date | cut -d' ' -f2-)\""
