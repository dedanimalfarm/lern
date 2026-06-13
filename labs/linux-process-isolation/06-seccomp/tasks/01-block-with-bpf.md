# 01 — Заблокировать syscall своим seccomp-bpf

## Задача
С помощью `seccomp_bpf.py` поставить фильтр, убивающий процесс при вызове
`uname(2)` (syscall 63 на x86_64), и убедиться: `uname` падает по `SIGSYS`, а
не вызывающая `uname` команда (`date`) работает.

## Проверка
```bash
./06-seccomp/seccomp_bpf.py 63 uname -a       # запрещён
./06-seccomp/seccomp_bpf.py 63 date           # разрешён
./06-seccomp/seccomp_bpf.py 63 cat /proc/self/status | grep '^Seccomp:'
```

## Ожидаемый результат
```
Bad system call (core dumped)     # uname → SIGSYS(31), exit 159 = 128+31
Sat Jun 13 ... 2026               # date работает под тем же фильтром
Seccomp:	2                      # MODE_FILTER реально применён
```
Фильтр точечный: блокирует ровно `uname(2)`, остальное проходит. Это и делает
рантайм/Chrome/`runc` — только с большим white-list-фильтром.
