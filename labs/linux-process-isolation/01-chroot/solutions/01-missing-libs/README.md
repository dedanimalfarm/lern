# Решение scenario-01: докопировать библиотеки по `ldd`

Динамический бинарь в rootfs не запускается без своего загрузчика и `.so`.
`fix.sh` берёт список из `ldd /bin/bash` и копирует каждую библиотеку по тому
же абсолютному пути внутрь rootfs.

```bash
sudo 01-chroot/broken/scenario-01/make-broken.sh   # воспроизвести
sudo 01-chroot/solutions/01-missing-libs/fix.sh     # починить
```

Ожидаемый итог: `inside-OK`.

Альтернатива (и предпочтительный путь для учебного rootfs) — статический
бинарь без зависимостей: ровно так `verify/prepare.sh` собирает rootfs из
`busybox-static`, и проблема не возникает в принципе.
