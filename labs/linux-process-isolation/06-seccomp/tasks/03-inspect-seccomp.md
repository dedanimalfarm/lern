# 03 — Смотреть seccomp-статус и номера syscalls

## Задача
Научиться видеть, стоит ли на процессе seccomp-фильтр, и находить номер syscall
для своей архитектуры (номера разные на x86_64 и arm64).

## Проверка
```bash
grep Seccomp /proc/self/status                       # у обычного шелла
./06-seccomp/seccomp_bpf.py 63 cat /proc/self/status | grep '^Seccomp:'   # под фильтром
ausyscall x86_64 uname 2>/dev/null || grep -w __NR_uname /usr/include/asm/unistd_64.h
```

## Ожидаемый результат
```
Seccomp:	0       # обычный шелл — фильтра нет
Seccomp:	2       # под нашим фильтром — MODE_FILTER
# uname = 63 на x86_64  (на arm64 это 160 — фильтр должен учитывать арку)
```
- `Seccomp:` — `0` нет, `1` strict, `2` filter. Поле наследуется через `execve`.
- Номер syscall зависит от архитектуры; реальный фильтр сначала проверяет
  `seccomp_data.arch`, иначе на другой арке заблокирует «не тот» вызов.
