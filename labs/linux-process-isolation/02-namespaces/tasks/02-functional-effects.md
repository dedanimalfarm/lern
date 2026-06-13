# 02 — Увидеть эффект каждого namespace

## Задача
Не просто создать namespace, а наблюдать, ЧТО он меняет: hostname (UTS), PID 1
(PID), приватный mount (MNT), пустой стек (NET), uid 0 (USER), свою таблицу IPC.

## Проверка
```bash
sudo unshare --uts /bin/bash -c 'hostname c1; echo внутри=$(hostname)'; echo снаружи=$(hostname)
sudo unshare --pid --fork --mount-proc /bin/bash -c 'echo PID=$$; ps -ef | head -3'
sudo unshare --mount /bin/bash -c 'mount --make-rprivate /; mount -t tmpfs none /mnt; echo s>/mnt/x; ls /mnt'; ls /mnt
sudo unshare --net /bin/bash -c 'ip -o link'
sudo unshare --user --map-root-user /bin/bash -c 'id'
```

## Ожидаемый результат
- UTS: `внутри=c1`, `снаружи=DESKTOP-2NEPKQQ` (хост не изменился).
- PID: `PID=1`, в `ps` только свои процессы (PID 1 = bash, 2 = ps).
- MNT: внутри `/mnt` содержит `x`; на хосте `/mnt` — свой (файла `x` нет).
- NET: единственная строка `1: lo: <LOOPBACK> … state DOWN` — связности нет.
- USER: `uid=0(root) gid=0(root)` — внутри ты root, снаружи остался своим uid.
