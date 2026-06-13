# Сценарий 01: «chroot: failed to run command … No such file or directory» — хотя бинарь на месте

## Симптом
Собрали rootfs, положили в него `/bin/bash`, заходим — и получаем ошибку, будто
файла нет. Хотя `ls` показывает, что он есть.
```bash
sudo ./broken/scenario-01/make-broken.sh
# rootfs собран, bash на месте:
# -rwxr-xr-x 1 root root 1298416 ... /lab/01-chroot-broken/bin/bash
# пытаемся войти → ожидаем обманчивую ошибку:
chroot: failed to run command ‘/bin/bash’: No such file or directory   # exit=127
```

## Подсказки
1. Ошибка врёт: «No such file or directory» здесь про **не найденный загрузчик/
   библиотеки**, а не про сам `bash`. Файл-то на месте.
2. Что показывает `ldd /bin/bash`? Куда указывают эти пути ВНУТРИ rootfs?
3. Почему статический `busybox` (этап 01) такой проблемы не имеет?

## Диагностика
```bash
ldd /bin/bash
#   linux-vdso.so.1
#   libtinfo.so.6 => /lib/x86_64-linux-gnu/libtinfo.so.6
#   libc.so.6     => /lib/x86_64-linux-gnu/libc.so.6
#   /lib64/ld-linux-x86-64.so.2                        <- динамический загрузчик
```
`bash` — динамический бинарь. При запуске ядро зовёт `ld-linux`, тот ищет
`libc.so.6`, `libtinfo.so.6` по абсолютным путям. Внутри rootfs этих путей нет —
`execve` возвращает `ENOENT`, который `chroot` печатает как «No such file or
directory». Файл есть, а его зависимостей — нет.

## Решение
Вариант А — докопировать `.so` по тем же путям (см. `solutions/01-missing-libs/fix.sh`):
```bash
sudo ./solutions/01-missing-libs/fix.sh
# + /lib/x86_64-linux-gnu/libtinfo.so.6
# + /lib/x86_64-linux-gnu/libc.so.6
# + /lib64/ld-linux-x86-64.so.2
# повторный вход — теперь работает:
# inside-OK
```
Вариант Б (правильнее для учебного rootfs) — брать **статический** бинарь
(`busybox-static`): ему `.so` не нужны вовсе, что и делает `verify/prepare.sh`.

## Профилактика
- Для rootfs руками — статические бинари (`busybox`, `*-static`) либо честная
  сборка из образа (`debootstrap`, распаковка alpine — этап `10`).
- Перед «почему не запускается в chroot/контейнере» — первым делом `ldd <бинарь>`
  и проверка, что все зависимости попали в rootfs.
- Помни: «No such file or directory» на заведомо существующем бинаре =
  отсутствует его динамический загрузчик/библиотеки.
