# 03 — Собрать «контейнер» одной командой

## Задача
Объединить все шесть namespace в одном `unshare` — получить процесс, изолированный
по UTS/PID/MNT/NET/IPC/USER. Это ядро того, что делает `docker run`.

## Проверка
```bash
sudo unshare --uts --pid --mount --net --ipc --user --map-root-user --fork --mount-proc \
  /bin/bash -c '
    hostname mini-container
    echo "hostname: $(hostname)"
    echo "uid:      $(id -u)"
    echo "PID 1:    $(cat /proc/1/comm)"
    echo "ifaces:   $(ip -o link | wc -l)"
  '
```

## Ожидаемый результат
```
hostname: mini-container
uid:      0
PID 1:    bash
ifaces:   1
```
Свой hostname, свой PID 1, root внутри, пустая сеть — изолированный процесс на
одних примитивах ядра. До настоящего контейнера не хватает: своего корня
(`pivot_root`, этап 03), сети (veth+bridge, этап 09) и лимитов (cgroup, этап 04).
