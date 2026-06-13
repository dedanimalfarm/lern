# Сценарий 01: systemd-nspawn отказывается — «doesn't look like an OS tree»

## Симптом
Запускаем nspawn на каталоге — а он отказывается, хотя каталог существует.
```bash
sudo ./broken/scenario-01/make-broken.sh
# nspawn на пустом каталоге (нет OS-дерева):
# Directory /lab/10-broken/empty doesn't look like it has an OS tree. Refusing.
```

> Host-only: нужен реальный хост с `systemd-nspawn` (на WSL2 скрипт сам сообщит).

## Подсказки
1. Что nspawn ожидает увидеть в каталоге, чтобы считать его rootfs?
2. Какие файлы есть в настоящем rootfs (alpine), которых нет в пустом каталоге?
3. Чем отличается «каталог» от «rootfs дистрибутива»?

## Диагностика
`systemd-nspawn` проверяет, что каталог похож на корень ОС: ищет `os-release`
(`/etc/os-release` или `/usr/lib/os-release`) и базовую структуру (`/usr`, `/bin`).
Пустой каталог их не содержит → nspawn отказывается запускаться, чтобы не загрузить
«пустоту» как контейнер. Это защита от запуска на случайной/неполной директории.

## Решение
Дать настоящий rootfs — распаковать дистрибутив (см. `solutions/01-proper-rootfs/fix.sh`):
```bash
sudo ./solutions/01-proper-rootfs/fix.sh
# распаковываем настоящий rootfs (alpine) и запускаем:
#   внутри: PRETTY_NAME="Alpine Linux v3.19"
```

## Профилактика
- Собирай rootfs целиком: `alpine minirootfs` (`curl | tar`) или `debootstrap` —
  они дают согласованную ОС с `os-release` и базовой структурой.
- Если нужно «почти пустой» контейнер — добавь хотя бы `/etc/os-release` и
  `/usr/lib`, либо используй `--directory` с готовым образом.
- Признак готовности: `cat <rootfs>/etc/os-release` отдаёт имя дистрибутива.
