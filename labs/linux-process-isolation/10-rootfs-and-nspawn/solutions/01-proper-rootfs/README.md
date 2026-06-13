# Решение scenario-01: дать настоящий rootfs

`systemd-nspawn` отказывается запускаться на каталоге без признаков ОС (`os-release`
+ базовая структура). Нужен полноценный rootfs:

```bash
A=/lab/rootfs; mkdir -p "$A"
curl -fsSL https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz | tar -xz -C "$A"
systemd-nspawn -q -D "$A" --pipe -- /bin/sh -c 'cat /etc/os-release'
```

```bash
sudo 10-rootfs-and-nspawn/broken/scenario-01/make-broken.sh    # пустой каталог → Refusing
sudo 10-rootfs-and-nspawn/solutions/01-proper-rootfs/fix.sh      # alpine rootfs → запускается
```

Альтернатива — `debootstrap --variant=minbase <suite> <dir> <mirror>` для
Debian/Ubuntu rootfs с рабочим `apt`. Признак готовности: `cat <rootfs>/etc/os-release`
отдаёт имя дистрибутива.
