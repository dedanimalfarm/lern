# Урок 13: Точки монтирования — busy, readonly, stale

## Цель
Разобраться с тремя классическими ситуациями:
- `umount` падает с `target is busy` — кто держит?
- ФС внезапно стала readonly — что случилось и как восстановить?
- Stale mount (особенно NFS) — висит, но не работает.

## Основные команды
- `mount | column -t` — что куда смонтировано (с опциями).
- `findmnt` / `findmnt --target /path` — современный способ смотреть mount-таблицу, удобно фильтровать.
- `df -hT` — место + тип ФС.
- `fuser -mv /mountpoint` — кто использует точку монтирования (PID, USER, COMMAND, ACCESS).
- `lsof /mountpoint` — детальнее: какие файлы открыты, какими процессами.
- `umount /mp` / `umount -l /mp` (lazy) / `umount -f /mp` (force, NFS).
- `mount -o remount,rw /path` — перевести ФС обратно в read-write.
- `dmesg -T | grep -iE 'ext4|xfs|btrfs|i/o error|remount'` — почему ядро перевело ФС в readonly.

## Три кейса в одной лабе

### Кейс A: «target is busy»
Кто-то (cd в директорию, открытый файл, демон) держит точку монтирования открытой.
`fuser -mv /mp` или `lsof /mp` — найти и закрыть. Крайняя мера — `umount -l` (lazy):
ядро спрячет mountpoint от новых обращений, реальное размонтирование произойдёт
после закрытия последнего дескриптора.

### Кейс B: ФС внезапно readonly
Ext4/xfs автоматически переводят себя в RO при I/O-ошибке на диске —
защита от porчи данных. Сигнатура в `dmesg`:
```
EXT4-fs error (device sda1): ext4_journal_check_start:83: ... Remounting filesystem read-only
```
Лечение: чинить диск или временный workaround `mount -o remount,rw`
(при условии, что причина устранена; иначе зациклитесь).

### Кейс C: Stale NFS
NFS-сервер недоступен — `df`, `ls`, `mount` могут зависнуть навсегда (hard mount).
Подсказки:
- mount с опциями `soft,timeo=...` падает с ошибкой, а не висит — рекомендуется для не-критичных монтов.
- `umount -f -l /mp` — единственный способ освободить, если сервер мёртв.

## Задание
1. Запустите `./simulate.sh`. Скрипт создаст loop-устройство, смонтирует его в `/mnt/lab-mount`, запустит в нём фоновый процесс и попробует размонтировать.
2. `umount /mnt/lab-mount` упадёт с `target is busy`.
3. Найдите виновника:
   - `fuser -mv /mnt/lab-mount` — увидите PID и команду.
   - `lsof /mnt/lab-mount` — детальнее.
4. Убейте процесс или ещё лучше — попробуйте `umount -l /mnt/lab-mount` и посмотрите разницу.
5. Бонус: посмотрите в `dmesg` сообщения о smousnted/unmounted ФС.

## Очистка
```bash
sudo ./cleanup.sh
```
