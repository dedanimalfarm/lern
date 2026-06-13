# 01 — Выполнить pivot_root в новом mount-namespace

## Задача
Создать новый mount-namespace, сделать `new_root` отдельной точкой монтирования
(tmpfs), наполнить минимальным rootfs и сменить корень через `pivot_root`.

## Проверка
```bash
sudo unshare --mount --pid --uts --fork --mount-proc /bin/bash <<'INNER'
set -e
NEW=/lab/03-pivot-root/newroot
mount --make-rprivate /
mount -t tmpfs none "$NEW"
install -d "$NEW"/{bin,etc,proc,dev,old_root}
cp /bin/busybox "$NEW/bin/"
for a in sh ls cat hostname mount umount; do ln -sf busybox "$NEW/bin/$a"; done
mount -t proc proc "$NEW/proc"; mount --rbind /dev "$NEW/dev"
cd "$NEW"; pivot_root . old_root
hostname pivoted-container
echo "hostname=$(hostname)"; echo "корень:"; ls /
INNER
```

## Ожидаемый результат
```
hostname=pivoted-container
корень:
bin  dev  etc  old_root  proc
```
Мы в новом корне (tmpfs). Старый (хостовый) корень пока виден в `/old_root` —
убираем его в задании 02/03.
