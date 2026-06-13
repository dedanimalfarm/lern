# 01 — Собрать rootfs и войти в chroot

## Задача
Собрать минимальный rootfs из статического `busybox` и войти в него через
`chroot`. Убедиться, что внутри видна СВОЯ файловая система (свой `/etc`, свой
набор каталогов), а не хостовая.

## Проверка
```bash
sudo ./verify/prepare.sh            # соберёт /lab/01-chroot/rootfs
sudo chroot /lab/01-chroot/rootfs /bin/sh -c 'ls / ; cat /etc/hostname'
```

## Ожидаемый результат
```
bin
dev
etc
proc
root
sys
tmp
chroot-jail            <- наш /etc/hostname из rootfs, а не хостовый
```
Внутри виден ровно тот корень, что мы собрали — `chroot` сменил точку отсчёта
путей. Файл, созданный внутри (`/lab/01-chroot/rootfs/...`), на хосте лежит
именно в каталоге rootfs.
