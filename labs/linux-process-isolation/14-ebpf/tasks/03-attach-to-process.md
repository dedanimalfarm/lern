# 03 — Привязать событие к процессу (comm/pid)

## Задача
Показать, что в eBPF-probe доступен контекст события — имя процесса (`comm`), его
PID и аргументы syscall. Это позволяет связать действие с конкретным контейнером.

## Проверка
```bash
echo x > /tmp/secret.txt
( while :; do cat /tmp/secret.txt >/dev/null; sleep 0.2; done ) &
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("%s[%d] -> %s\n", comm, pid, str(args->filename)); }'
kill %1; rm -f /tmp/secret.txt
```

## Ожидаемый результат
```
cat[12345] -> /tmp/secret.txt        # кто (comm/pid) и что открыл
```
В probe сразу доступны `comm` (имя процесса), `pid`, `uid`, аргументы syscall.
Зная PID/cgroup процесса, инструмент привязывает событие к контейнеру — на этом
строятся Falco-правила («контейнер X открыл /etc/shadow → alert»).
