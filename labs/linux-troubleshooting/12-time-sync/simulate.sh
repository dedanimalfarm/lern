#!/usr/bin/env bash
# Отключаем NTP и переводим часы на 2 дня вперёд.
echo "Останавливаем синхронизацию времени ..."
sudo timedatectl set-ntp false

# +400 дней гарантированно выходит за пределы 90-дневной валидности
# современных Let's Encrypt / GitHub-сертификатов — curl получит «certificate expired».
# 2-3 дня недостаточно: большинство сертов всё ещё валидны.
FUTURE=$(date -u -d '+400 days' '+%Y-%m-%d %H:%M:%S')
echo "Переводим часы вперёд на 400 дней: $FUTURE UTC"
sudo date -u -s "$FUTURE" >/dev/null

echo "Готово. timedatectl покажет 'System clock synchronized: no'."
echo "Проверь: curl -I https://github.com  — должен ругаться на просроченный сертификат."
echo "Чтобы починить: sudo timedatectl set-ntp true  (или ./cleanup.sh)"
