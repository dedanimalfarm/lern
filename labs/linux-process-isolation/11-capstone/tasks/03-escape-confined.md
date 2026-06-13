# 03 — Побег /proc/1/root закрыт (главный тезис курса)

## Задача
Повторить побег из этапа 01 (`chroot /proc/1/root`) внутри `mycontainer` и увидеть,
что он остаётся ВНУТРИ контейнера — `pivot_root` + mount-ns закрыли дыру.

## Проверка
```bash
sudo ./11-capstone/mycontainer.sh run alpine -- sh -c '
  echo "мой hostname: $(hostname)"
  echo "chroot /proc/1/root ls /: $(chroot /proc/1/root /bin/sh -c "ls /" | tr "\n" " ")"
'
```

## Ожидаемый результат
```
мой hostname: mycontainer
chroot /proc/1/root ls /: bin dev etc home lib media mnt opt proc root run sbin srv sys tmp usr var
```
Это корень **alpine-контейнера**, а НЕ хоста. Сравните с этапом 01: там тот же
`chroot /proc/1/root` показал бы корень хоста (его `hostname`). Разница — `unshare
--mount` + `pivot_root` + `umount old_root`: старый корень удалён из дерева
монтирования. Это и отличает настоящий контейнер от дырявого chroot.
