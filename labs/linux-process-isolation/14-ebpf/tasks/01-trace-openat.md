# 01 — Перехватить openat через bpftrace

## Задача
С помощью eBPF (bpftrace) перехватить системный вызов `openat` и увидеть, какие
файлы открывает процесс — извне, не вмешиваясь в него.

> Host-only: нужен `bpftrace` и BTF (на WSL2 пропусти).

## Проверка
```bash
echo secret > /tmp/secret.txt
( while :; do cat /tmp/secret.txt >/dev/null; sleep 0.1; done ) &
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("OPEN %s\n", str(args->filename)); }'
# Ctrl-C через пару секунд
kill %1; rm -f /tmp/secret.txt
```

## Ожидаемый результат
```
OPEN /tmp/secret.txt
OPEN /tmp/secret.txt
...
```
bpftrace прикрепил eBPF-программу к точке ядра `sys_enter_openat` и печатает имя
каждого открываемого файла. Так IDS (Falco/Tetragon) мгновенно видят, что процесс
открыл `/etc/shadow` или `/run/secrets/` — без модулей ядра и вмешательства в ФС.
