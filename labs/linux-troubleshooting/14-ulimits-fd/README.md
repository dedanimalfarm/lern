# Урок 14: Too many open files — лимиты на файловые дескрипторы

## Цель
Понять, откуда в логах появляется «Too many open files» при том, что
файлов как бы нет, и где крутить лимиты для сервиса/пользователя/системы.

## Основные команды
- `ulimit -a` — все мягкие лимиты текущей сессии. Интересует `open files` (`-n`).
- `ulimit -Hn` / `ulimit -Sn` — жёсткий и мягкий лимит на fd.
- `prlimit --pid <PID>` — лимиты ЖИВОГО процесса (актуальнее, чем `ulimit` в шелле).
- `cat /proc/<PID>/limits` — то же самое сыро.
- `ls /proc/<PID>/fd | wc -l` — сколько fd у процесса открыто прямо сейчас.
- `lsof -p <PID> | wc -l` — то же через lsof (учитывает memory-mapped файлы, цифра больше).
- `cat /proc/sys/fs/file-max` — общесистемный лимит fd (обычно очень большой).
- `cat /proc/sys/fs/file-nr` — сколько fd выделено / свободно / max.

## Три уровня лимитов
1. **Жёсткие пределы ядра:** `/proc/sys/fs/file-max`, `/proc/sys/fs/nr_open`.
2. **Пользовательские лимиты:** `/etc/security/limits.conf` или `/etc/security/limits.d/*.conf`. Применяются при логине через PAM. Формат:
   ```
   *           soft    nofile  65535
   *           hard    nofile  65535
   appuser     soft    nofile  100000
   ```
3. **Лимиты сервиса (systemd):** `LimitNOFILE=65535` в unit-файле. **Это самый частый случай для серверов** — пользовательский `limits.conf` не действует на systemd-юниты.
   ```
   [Service]
   LimitNOFILE=65535
   ```

## Задание
1. Текущие лимиты: `ulimit -n` и `cat /proc/$$/limits | grep 'open files'`.
2. Запустите `./simulate.sh`. Скрипт стартует процесс, который пытается открыть 5000 файлов.
3. Скрипт упадёт с `OSError: [Errno 24] Too many open files`.
4. Посмотрите лимит этого процесса:
   ```bash
   ps -ef | grep open_many
   prlimit --pid <PID> --nofile
   ```
5. Поднимите мягкий лимит в текущей сессии и перезапустите тест с флагом, чтобы скрипт не понизил лимит обратно:
   ```bash
   ulimit -n 8192
   KEEP_LIMIT=1 ./simulate.sh
   ```
   Теперь увидите `Открыто 5000 файлов — лимит не достигнут`.
6. Для **systemd-сервиса** того же не достичь через `ulimit` — нужно править unit:
   ```
   sudo systemctl edit --full myservice
   # добавить LimitNOFILE=65535 в [Service]
   sudo systemctl daemon-reload
   sudo systemctl restart myservice
   ```
7. Проверка для живого сервиса: `cat /proc/$(pidof myservice)/limits | grep 'open files'`.

## Очистка
```bash
killall python3 2>/dev/null
```
