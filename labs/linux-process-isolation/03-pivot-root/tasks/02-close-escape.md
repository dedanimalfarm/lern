# 02 — Доказать, что побег из модуля 01 закрыт

## Задача
После `pivot_root` + `umount old_root` повторить классический побег
`chroot /proc/1/root` (тот, что в модуле 01 выводил на корень хоста) и убедиться,
что теперь он остаётся внутри нашего корня — `escape=CONFINED`.

## Проверка
```bash
sudo unshare --mount --pid --uts --fork --mount-proc /bin/bash <<'INNER'
set -e
NEW=/lab/03-pivot-root/newroot
mount --make-rprivate /; mount -t tmpfs none "$NEW"
install -d "$NEW"/{bin,etc,proc,old_root}; cp /bin/busybox "$NEW/bin/"
for a in sh ls cat hostname chroot mount umount; do ln -sf busybox "$NEW/bin/$a"; done
mount -t proc proc "$NEW/proc"
cd "$NEW"; pivot_root . old_root
/bin/busybox umount -l /old_root
export PATH=/bin
echo "побег chroot /proc/1/root ведёт в:"; chroot /proc/1/root /bin/sh -c 'ls /'
INNER
```

## Ожидаемый результат
```
побег chroot /proc/1/root ведёт в:
bin  etc  old_root  proc        <- наш минимальный корень, НЕ /home,/usr,/var хоста
```
Сравните с модулем 01: там та же команда выводила корень хоста. Здесь периметр
закрыт, потому что хостовый корень удалён из дерева монтирования (`umount old_root`).
