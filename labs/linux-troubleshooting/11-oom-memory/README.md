# Урок 11: OOM-killer и давление по памяти

## Цель
Поймать момент, когда ядро Linux убивает процесс из-за нехватки памяти,
и научиться разбирать постфактум: кого, почему, что было до этого.

## Основные команды
- `dmesg -T | grep -iE 'oom|killed process'` — ядро всегда логирует факт OOM-kill в кольцевой буфер.
- `journalctl -k --since "1 hour ago" | grep -i oom` — то же самое из systemd journal.
- `cat /proc/pressure/memory` — PSI: процент времени, когда процессы ждут память (`some avg10`, `full avg10`). Лучший индикатор «системе плохо».
- `cat /proc/<PID>/oom_score` — текущая «привлекательность» процесса для убийства (0..1000).
- `cat /proc/<PID>/oom_score_adj` — корректор: `-1000` = «никогда не убивать», `+1000` = «убей в первую очередь».
- `grep -E 'AnonPages|Shmem|MemAvailable' /proc/meminfo` — кто реально съел RAM.
- `ps -eo pid,user,rss,comm --sort=-rss | head` — топ процессов по физической памяти.

## Как работает OOM-killer
Когда `MemAvailable` падает близко к нулю и swap кончился (или его нет), ядро
выбирает процесс с **наивысшим `oom_score`** и шлёт ему SIGKILL.
Скор считается по формуле: процент памяти процесса + `oom_score_adj`.

Подкрутить шанс выжить для критичного сервиса:
```
echo -1000 | sudo tee /proc/$(pidof postgres)/oom_score_adj
```
Или через systemd: в unit-файл `OOMScoreAdjust=-1000`.

## Задание
1. Запустите `./simulate.sh`. Скрипт запустит «жадный» процесс, который
   быстро съест всю свободную память.
2. В другом терминале наблюдайте: `watch -n 1 'free -h; cat /proc/pressure/memory'`.
3. Через 10-30 секунд ядро убьёт процесс. В первом терминале увидите `Killed`.
4. Найдите событие:
   - `dmesg -T | grep -iE 'oom|killed process' | tail`
   - В выводе ядра увидите PID жертвы, имя процесса, его `total-vm`, `anon-rss` и кто его выбрал.
5. Откройте `/proc/<PID-другого-критичного-процесса>/oom_score` и `oom_score_adj`.
   Поэкспериментируйте: запустите скрипт повторно, но сначала
   `echo -1000 | sudo tee /proc/<PID-нагрузки>/oom_score_adj` — ядро убьёт уже что-то другое.

## Очистка
```bash
sudo killall python3 stress-ng 2>/dev/null
```
