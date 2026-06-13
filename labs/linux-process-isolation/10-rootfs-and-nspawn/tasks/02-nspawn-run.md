# 02 — Запустить rootfs через systemd-nspawn

## Задача
Запустить alpine-rootfs через `systemd-nspawn` и убедиться, что внутри изолированы
PID (наш процесс = PID 1) и UTS (свой hostname) — namespaces создаёт сам nspawn.

## Проверка
```bash
A=/lab/10/alpine
systemd-nspawn -q -D "$A" --pipe -- /bin/sh -c '
  echo "PID 1:  $(p=$(cat /proc/1/comm); echo $p)"
  echo "host:   $(hostname)"
  echo "os:     $(grep ^ID= /etc/os-release)"
'
hostname    # для сравнения — хостовый
```

## Ожидаемый результат
```
PID 1:  sh           # PID-ns изолирован: наш sh — это PID 1
host:   alpine       # UTS-ns изолирован: hostname ≠ хостового
os:     ID=alpine
```
`systemd-nspawn` сам сделал UTS/PID/MNT/IPC namespaces, смонтировал `/proc`/`/sys`/
`/dev` — то, что мы 9 этапов собирали руками. Это `docker run -it alpine sh`.
