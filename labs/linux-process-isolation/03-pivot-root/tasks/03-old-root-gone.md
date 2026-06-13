# 03 — Старый корень исчезает после umount

## Задача
Увидеть переход: сразу после `pivot_root` старый (хостовый) корень ещё виден в
`/old_root`; после `umount -l /old_root` он полностью пропадает из дерева
монтирования и становится недостижим.

## Проверка
```bash
sudo unshare --mount --pid --uts --fork --mount-proc /bin/bash <<'INNER'
set -e
NEW=/lab/03-pivot-root/newroot
mount --make-rprivate /; mount -t tmpfs none "$NEW"
install -d "$NEW"/{bin,proc,old_root}; cp /bin/busybox "$NEW/bin/"
for a in sh ls umount; do ln -sf busybox "$NEW/bin/$a"; done
mount -t proc proc "$NEW/proc"
cd "$NEW"; pivot_root . old_root; export PATH=/bin
echo "ДО umount — в /old_root виден хост:"; ls /old_root | /bin/busybox head -4
/bin/busybox umount -l /old_root
echo "ПОСЛЕ umount — /old_root пуст:"; ls /old_root
INNER
```

## Ожидаемый результат
```
ДО umount — в /old_root виден хост:
bin
boot
dev
etc
ПОСЛЕ umount — /old_root пуст:
(пусто)
```
Именно `umount old_root` (а не сам `pivot_root`) закрывает побег: старый корень
больше не присутствует в дереве монтирования процесса.
