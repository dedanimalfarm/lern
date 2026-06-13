# 02 — seccomp без кода через systemd-run

## Задача
Применить seccomp-фильтр к разовой команде через `systemd-run
-p SystemCallFilter=`, не написав ни строки BPF. Запретить один syscall и целый
класс.

## Проверка
```bash
# запретить один syscall (тильда = blocklist)
systemd-run --wait -p SystemCallFilter=~uname uname -a
# запретить целый класс привилегированных вызовов
systemd-run --wait -p SystemCallFilter=~@privileged ip link add fake type dummy
```

## Ожидаемый результат
```
Finished with result: signal
Main processes terminated with: code=killed, status=31/SYS   # SIGSYS(31) — тот же seccomp
```
`~uname` блокирует один вызов; `~@privileged` — ~50 admin-syscalls разом (mount,
ptrace, …). Это удобная обёртка над тем же seccomp; в unit-файлах задаётся как
`SystemCallFilter=`. У Docker аналог — `--security-opt seccomp=profile.json`.
