# 01 — Собрать OCI-bundle и config.json

## Задача
Собрать минимальный OCI-bundle (rootfs из alpine + `config.json` через `runc spec`)
и посмотреть, какие namespaces описаны в конфиге по умолчанию.

> rootfs берём alpine (static musl `/bin/sh`), а не голый busybox: динамический
> busybox в минимальном rootfs не запустится (нет загрузчика/libc — как в этапе 01).

## Проверка
```bash
B=/lab/13/bundle; mkdir -p "$B/rootfs"
URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz"
curl -fsSL "$URL" | tar -xz -C "$B/rootfs"          # настоящий rootfs со static /bin/sh
cd "$B" && runc spec                                 # создаёт config.json
python3 -c "import json;print(', '.join(n['type'] for n in json.load(open('config.json'))['linux']['namespaces']))"
```

## Ожидаемый результат
```
pid, network, ipc, uts, mount, cgroup
```
`runc spec` создал `config.json` с 6 namespaces (как у Docker, БЕЗ user-ns),
дропом capabilities и монтированием `/proc`/`/sys`/`/dev`. Bundle = `rootfs/` +
`config.json` — это всё, что нужно OCI-рантайму.
