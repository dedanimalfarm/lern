# Сценарий 01: `pivot_root: ... Device or resource busy` — new_root не точка монтирования

## Симптом
Делаем `pivot_root` на обычном каталоге — и получаем `EBUSY`, хотя каталог
существует и `put_old` внутри него создан.
```bash
sudo ./broken/scenario-01/make-broken.sh
# newroot — обычный каталог на той же ФС, что и /:
# pivot_root: failed to change root from `.' to `old_root': Device or resource busy
#   exit=1
```

## Подсказки
1. Какое первое требование к `new_root` у `pivot_root` (см. теорию Части 1)?
2. Чем «каталог» отличается от «точки монтирования»? Что показывает `mountpoint -q new`?
3. Как быстро сделать каталог точкой монтирования, ничего не копируя на отдельный диск?

## Диагностика
`pivot_root` требует, чтобы `new_root` был **отдельной точкой монтирования**, а не
просто каталогом на той же файловой системе, что и текущий корень. Наш `newroot` —
обычный `mkdir` внутри `/`, то есть та же ФС, что и `/`. Ядро отказывает: `new_root`
и текущий корень принадлежат одному mount → `EBUSY` («Device or resource busy»).
(Если вдобавок корень — *shared* mount, получите `EINVAL` «Invalid argument».)

## Решение
Сделать `new_root` точкой монтирования — двумя способами (см.
`solutions/01-make-mountpoint/fix.sh`):
```bash
mount -t tmpfs none /path/newroot        # вариант А: tmpfs (ещё и «чистая» ФС)
# ИЛИ
mount --bind /path/newroot /path/newroot  # вариант Б: bind сам на себя
```
После этого `pivot_root . old_root` проходит:
```bash
sudo ./solutions/01-make-mountpoint/fix.sh
# pivot_root OK (newroot стал /)
# old_root отмонтирован — побег закрыт
```

## Профилактика
- Перед `pivot_root` всегда делай `new_root` маунтом (`tmpfs` или `mount --bind`).
  Именно поэтому `runc` сначала `mount(merged, merged, MS_BIND)`, и только потом
  `pivot_root`.
- Заодно делай `mount --make-rprivate /` в новом mnt-ns, чтобы корень не был
  shared (иначе `EINVAL`).
- Проверка готовности: `mountpoint -q new_root` должно возвращать 0.
