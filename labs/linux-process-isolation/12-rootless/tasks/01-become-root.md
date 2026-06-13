# 01 — Стать root внутри user namespace

## Задача
От непривилегированного пользователя создать user namespace, отобразить себя в
uid 0 и убедиться, что внутри ты root и можешь выполнять root-операции (mount).

## Проверка
```bash
su -s /bin/sh nobody -c 'unshare --user --mount --map-root-user sh -c "id -u; mount -t tmpfs none /mnt && echo MOUNT_OK"'
```

## Ожидаемый результат
```
0           # внутри user-ns мы root (uid 0)
MOUNT_OK    # и можем монтировать в своём mount-ns
```
`--user` (`-U`) создал user namespace, `--map-root-user` (`-r`) отобразил твой uid
хоста в 0 внутри. Внутри ты получаешь полный набор capabilities (в пределах ns) —
поэтому mount работает. И всё это БЕЗ `sudo`. Это основа podman/rootless-Docker.
