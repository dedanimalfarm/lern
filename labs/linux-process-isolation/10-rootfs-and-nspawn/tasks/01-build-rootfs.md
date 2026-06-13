# 01 — Скачать настоящий rootfs (alpine minirootfs)

## Задача
Получить полноценный (не busybox-ручной) rootfs дистрибутива одной командой —
готовый Alpine minirootfs.

> Host-only: нужен реальный Linux-хост с интернетом (на WSL2 пропусти).

## Проверка
```bash
A=/lab/10/alpine; mkdir -p "$A"
URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz"
curl -fsSL "$URL" | tar -xz -C "$A"
du -sh "$A"; find "$A" -type f | wc -l
grep PRETTY_NAME "$A/etc/os-release"
ls "$A/bin/sh"
```

## Ожидаемый результат
```
7.7M
90
PRETTY_NAME="Alpine Linux v3.19"
/lab/10/alpine/bin/sh
```
Согласованный rootfs ~8 МБ: musl + busybox + apk. Это аналог `docker pull alpine`.
Для Debian/Ubuntu есть `debootstrap` (Часть 3) — он собирает rootfs с рабочим `apt`.
