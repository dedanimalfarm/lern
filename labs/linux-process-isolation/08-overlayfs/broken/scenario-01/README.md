# Сценарий 01: `mount overlay` падает — workdir и upperdir на разных ФС

## Симптом
Команда `mount -t overlay` отказывает с невнятным «wrong fs type, bad option…»,
хотя все каталоги существуют.
```bash
sudo ./broken/scenario-01/make-broken.sh
# mount overlay с workdir на tmpfs (upper на ext4 — разные ФС):
# mount: /lab/08-broken/merged: wrong fs type, bad option, bad superblock on overlay...
#   exit=32
# overlayfs: workdir and upperdir must reside under the same mount
```

## Подсказки
1. Само сообщение `mount` невнятное — где смотреть точную причину? (`dmesg | tail`)
2. На какой ФС лежит `upperdir`, а на какой `workdir` в этом сценарии?
3. Какое требование к `workdir` указано в теории Части 1?

## Диагностика
`dmesg` говорит прямо: **`overlayfs: workdir and upperdir must reside under the
same mount`**. Ядро делает CoW-операции через `workdir` атомарным `rename()` в
`upperdir`, а `rename(2)` между разными файловыми системами невозможен (`EXDEV`).
Поэтому overlay требует, чтобы `workdir` и `upperdir` были на ОДНОЙ ФС. В сценарии
`upperdir` на ext4 (`/lab`), а `workdir` — на смонтированном `tmpfs` → отказ.

## Решение
Положить `workdir` на ту же файловую систему, что `upperdir` (см.
`solutions/01-same-filesystem/fix.sh`):
```bash
sudo ./solutions/01-same-filesystem/fix.sh
# mount overlay с workdir на той же ФС, что upper:
#   OK, merged: f.txt
```

## Профилактика
- Держи `lowerdir`/`upperdir`/`workdir` под одним корнем на одной ФС (так делает и
  Docker: всё в `/var/lib/docker/overlay2/...`).
- `dmesg | tail` — первый инструмент при невнятной ошибке `mount` (overlay, как и
  многие ФС, пишет точную причину именно в kernel log).
- Проверь, что `workdir` пустой и существует; для read-only overlay (только
  `lowerdir`) `workdir`/`upperdir` не нужны вовсе.
