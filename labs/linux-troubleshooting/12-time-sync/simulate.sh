#!/usr/bin/env bash
# Отключаем NTP и переводим часы на 2 дня вперёд.
echo "Останавливаем синхронизацию времени ..."
sudo timedatectl set-ntp false

FUTURE=$(date -u -d '+2 days' '+%Y-%m-%d %H:%M:%S')
echo "Переводим часы вперёд: $FUTURE UTC"
sudo date -u -s "$FUTURE" >/dev/null

echo "Готово. timedatectl покажет 'System clock synchronized: no'."
echo "Проверь: curl -I https://github.com  — должен ругаться на сертификат."
echo "Чтобы починить: sudo timedatectl set-ntp true  (или ./cleanup.sh)"
