# Сценарий 01: наивный контейнер (только chroot) — побег на хост

## Симптом
«Контейнер», собранный из одного `chroot` (как на этапе 01), дырявый: процесс
внутри выходит на корень хоста через `/proc/1/root`.
```bash
sudo ./broken/scenario-01/make-broken.sh
# hostname ХОСТА: DESKTOP-2NEPKQQ
# внутри naive chroot hostname: DESKTOP-2NEPKQQ
# побег chroot /proc/1/root → hostname: DESKTOP-2NEPKQQ     <- вышли на ХОСТ!
```

## Подсказки
1. Какой mount-namespace у наивного chroot — свой или общий с хостом?
2. На что указывает `/proc/1/root`, если mount-ns общий?
3. Что `mycontainer` делает после overlay-mount, чего нет в наивном chroot?

## Диагностика
Наивный контейнер = `chroot rootfs` без нового mount-namespace. Поэтому
`/proc/1/root` (корень PID 1 в его mnt-ns) указывает на корень **хоста** — и
`chroot /proc/1/root` выводит наружу (повтор побега из этапа 01). hostname тоже
хостовый (UTS не изолирован). Это не контейнер, а песочница с дырой.

## Решение
Настоящий контейнер делает `unshare --mount` + `pivot_root` + `umount old_root`
(этап 03) — что и есть в `mycontainer.sh`. Тогда старый корень удалён из дерева, и
`/proc/1/root` ведёт в корень контейнера (см. `solutions/01-pivot-root/fix.sh`):
```bash
sudo ./solutions/01-pivot-root/fix.sh
# mycontainer (pivot_root): побег /proc/1/root →
#   hostname: mycontainer
#   /proc/1/root ls /: bin dev etc ... (корень alpine, НЕ хоста)
```

## Профилактика
- Контейнер ≠ chroot. Минимум для изоляции ФС-периметра: новый **mount-namespace**
  + `pivot_root` + `umount` старого корня (этапы 02–03).
- Никогда не полагайся на chroot как на границу безопасности — это исторически
  дырявый механизм (этап 01).
- Настоящие рантаймы (`runc`, этап 13) делают ровно эту последовательность.
