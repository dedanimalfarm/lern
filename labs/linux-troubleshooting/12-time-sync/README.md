# Урок 12: Рассинхрон времени — тихий убийца TLS и кластеров

## Цель
Понять, как уехавшие на минуты системные часы ломают TLS-хендшейк, JWT,
Kerberos и репликацию БД — и как это диагностируется.

## Основные команды
- `timedatectl` — текущее время, таймзона, статус NTP-синхронизации.
- `timedatectl show-timesync` — подробности про NTP-источник (Ubuntu 18.04+, systemd-timesyncd).
- `chronyc tracking` / `chronyc sources` — статус chrony (если установлен).
- `date` / `hwclock` — системное время vs аппаратные часы.
- `ntpdate -q pool.ntp.org` — спросить эталонное время без установки.

## Почему это критично
- **TLS:** сертификат валиден `notBefore..notAfter`. Если ваши часы убежали в будущее — сертификат «истёк». Если в прошлое — «ещё не вступил в силу». Ошибка `certificate is not yet valid`.
- **JWT / OAuth:** токены подписаны с `iat`/`exp` в секундах. Скос >30 сек — токен отвергается.
- **Kerberos / AD:** клиент и KDC должны быть синхронизованы в пределах 5 минут (по умолчанию). Иначе `Clock skew too great`.
- **БД-репликация (etcd, MongoDB, PostgreSQL streaming):** при отъезде времени лидер «теряет» followers, начинаются split-brain и rollback.
- **Логи в распределённой системе:** при разном времени логи невозможно сопоставить.

## Задание
1. Запустите `./simulate.sh`. Скрипт остановит синхронизацию времени и переведёт системные часы на 400 дней вперёд (этого хватает, чтобы выйти за валидность типичных Let's Encrypt / GitHub сертификатов, которые живут 90 дней).
2. Проверьте `timedatectl` — увидите `System clock synchronized: no` и неправильное время.
3. Попробуйте `curl -I https://github.com`:
   ```
   curl: (60) SSL certificate problem: certificate has expired
   ```
   Это та самая ошибка от рассинхрона.
4. Посмотрите детально: `openssl s_client -connect github.com:443 -servername github.com </dev/null 2>&1 | grep -E 'verify|notBefore|notAfter'`
5. Восстановите:
   ```bash
   sudo timedatectl set-ntp true
   # подождать 5-10 сек, проверить
   timedatectl
   ```
   Или для chrony: `sudo systemctl start chrony && sudo chronyc makestep`.
6. `curl -I https://github.com` снова работает.

## Очистка
`./cleanup.sh` или вручную:
```bash
sudo timedatectl set-ntp true
```
