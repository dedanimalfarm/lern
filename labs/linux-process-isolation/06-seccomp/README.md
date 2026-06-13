# Лабораторная работа 06: seccomp — фильтрация системных вызовов

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Что такое seccomp](#-1---seccomp)
  - [Теория для изучения перед частью](#----)
  - [1.1 Посмотреть seccomp-статус процесса](#11--seccomp--)
- [Часть 2: Свой seccomp-bpf руками (prctl)](#-2--seccomp-bpf--prctl)
  - [Теория для изучения перед частью](#----)
  - [2.1 Заблокировать uname (syscall 63) и убедиться в SIGSYS](#21--uname-syscall-63----sigsys)
- [Часть 3: Быстрый путь — systemd-run](#-3----systemd-run)
  - [Теория для изучения перед частью](#----)
  - [3.1 Запретить syscall и класс через systemd-run](#31--syscall----systemd-run)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: не-root не может поставить фильтр без `PR_SET_NO_NEW_PRIVS`](#-1--root------pr_set_no_new_privs)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~35 мин · сложность 4/5 · пререквизиты: 05-capabilities, представление о syscalls

Цель: ограничить процесс не по привилегиям (как capabilities), а по **множеству
системных вызовов**, которые он вообще может сделать. `seccomp` (secure computing)
с режимом **filter** запускает на каждый syscall маленькую BPF-программу, которая
решает: разрешить, вернуть `errno` или **убить** процесс (`SIGSYS`). Соберём такой
фильтр руками (через `prctl`, без libseccomp), увидим `SIGSYS` на запрещённом
вызове, и сделаем то же быстро через `systemd-run`. Это `--security-opt seccomp`
у Docker (его дефолтный профиль — белый список ~310 из ~440 syscalls).

> Развитие `05-capabilities` (там — какие привилегии; здесь — какие syscalls).
> Оба пути работают и на WSL2 (ядро 6.6, systemd как PID 1), и на реальном хосте —
> выводы сняты на WSL2. Ключевой инструмент — `seccomp_bpf.py` (raw BPF через
> ctypes, без зависимостей).

---

## Предварительные требования

```bash
sudo ./00-setup/check.sh          # python3 (CORE); systemd-run — для Части 3
grep Seccomp /proc/self/status    # Seccomp: 0  (фильтра пока нет)
```

---

## Стартовая проверка

```bash
ps -p 1 -o comm=                  # systemd  → systemd-run доступен (Часть 3)
command -v python3 >/dev/null && echo "python3 на месте"   # для raw-bpf (Часть 2)
```

---

## Часть 1: Что такое seccomp

### Теория для изучения перед частью

- **Два режима.** `SECCOMP_MODE_STRICT` разрешает ровно 4 syscalls
  (`read`/`write`/`_exit`/`sigreturn`) — для реальных программ бесполезен.
  `SECCOMP_MODE_FILTER` («seccomp-bpf») — BPF-программа, которая для каждого
  syscall видит его номер и аргументы и решает действие.
- **Действия фильтра.** `SECCOMP_RET_ALLOW` (пропустить), `..._ERRNO` (вернуть
  ошибку, процесс живёт), `..._KILL_PROCESS`/`KILL_THREAD` (убить — процесс
  получает **`SIGSYS`**, сигнал 31). По умолчанию запрещённый вызов = смерть.
- **Где видно.** `/proc/<pid>/status` поле `Seccomp:` — `0` нет, `1` strict,
  `2` filter. Поле наследуется через `execve` (фильтр «прилипает» к процессу).
- **Предусловие для не-root:** `PR_SET_NO_NEW_PRIVS` (иначе не-root не имеет
  права ставить фильтр — Часть 4). Под root хватает `CAP_SYS_ADMIN`.

---

### 1.1 Посмотреть seccomp-статус процесса

```bash
grep Seccomp /proc/self/status
# Seccomp:	0            <- у обычного шелла фильтра нет
# Seccomp_filters:	0
```

**Контрольные вопросы:**
1. Чем `SECCOMP_MODE_FILTER` отличается от strict?
2. Какой сигнал получает процесс при `SECCOMP_RET_KILL` и какой у него номер?
3. Где в `/proc` видно, что на процессе стоит seccomp-фильтр?

---

## Часть 2: Свой seccomp-bpf руками (prctl)

### Теория для изучения перед частью

- Фильтр — это массив BPF-инструкций (`struct sock_filter`): загрузить номер
  syscall (`seccomp_data.nr`, offset 0), сравнить с целевым, при совпадении
  вернуть `KILL_PROCESS`, иначе `ALLOW`. Ставится двумя `prctl`:
  `PR_SET_NO_NEW_PRIVS`, затем `PR_SET_SECCOMP, MODE_FILTER`.
- Номера syscalls **зависят от архитектуры** (`uname` = 63 на x86_64, 160 на
  arm64) — реальный фильтр сначала проверяет `seccomp_data.arch`.
- `seccomp_bpf.py <nr> <cmd...>` делает ровно это: ставит фильтр на текущий
  процесс и `exec`-ает команду (фильтр наследуется).

---

### 2.1 Заблокировать uname (syscall 63) и убедиться в SIGSYS

```bash
# uname(2) под фильтром → процесс убит SIGSYS
./06-seccomp/seccomp_bpf.py 63 uname -a
# Bad system call (core dumped)        <- SIGSYS (31); exit code 159 = 128+31

# та же программа, но date не зовёт uname(2) → работает
./06-seccomp/seccomp_bpf.py 63 date
# Sat Jun 13 ... 2026

# доказательство, что фильтр реально стоит: Seccomp=2 (MODE_FILTER)
./06-seccomp/seccomp_bpf.py 63 cat /proc/self/status | grep '^Seccomp:'
# Seccomp:	2
```

Фильтр точечный: блокирует только `uname(2)`, всё остальное (`date`, `cat`) идёт.

**Контрольные вопросы:**
1. Что делает BPF-программа фильтра по шагам (load nr → сравнить → действие)?
2. Почему `date` работает под фильтром, а `uname -a` — нет?
3. Почему номер syscall в фильтре зависит от архитектуры?

---

## Часть 3: Быстрый путь — systemd-run

### Теория для изучения перед частью

- `systemd-run -p SystemCallFilter=...` ставит seccomp на разовый transient-сервис
  без написания BPF. `~uname` — «запретить uname» (тильда = blocklist), без тильды
  — allowlist. Можно блокировать целые **классы**: `~@privileged`, `~@mount`,
  `~@clock` (см. `man systemd.exec`).
- Это тот же seccomp под капотом; удобно для ad-hoc и unit-файлов.

---

### 3.1 Запретить syscall и класс через systemd-run

```bash
systemd-run --wait -p SystemCallFilter=~uname uname -a
# Finished with result: signal
# Main processes terminated with: code=killed, status=31/SYS    <- тот же SIGSYS(31)

# запретить целый класс привилегированных вызовов
systemd-run --wait -p SystemCallFilter=~@privileged ip link add fake type dummy
# ... убит на одном из ~50 syscalls класса @privileged
```

**Контрольные вопросы:**
1. Что означает тильда `~` в `SystemCallFilter=~uname`?
2. Чем удобны классы (`@privileged`, `@mount`) против перечисления syscalls?
3. `systemd-run`-фильтр и наш `prctl`-фильтр — это разные механизмы?

---

## Часть 4: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ не-root: PR_SET_SECCOMP → errno 13 (Permission denied) ─► забыт
│     PR_SET_NO_NEW_PRIVS. Не-root обязан выставить его ДО фильтра (Сценарий 01)
├─ программа падает «Bad system call» сразу на старте ─────► фильтр блокирует
│     syscall, нужный загрузчику/libc (mmap, openat…). Блокируй точечно
├─ фильтр «не срабатывает» (вызов проходит) ───────────────► неверный номер syscall
│     для арки (uname 63 на x86_64 vs 160 на arm64). Проверь seccomp_data.arch
└─ хотел errno, а процесс умирает ─────────────────────────► действие KILL вместо
      RET_ERRNO. Для «мягкого» отказа верни SECCOMP_RET_ERRNO|errno
```

### Инцидент 1: не-root не может поставить фильтр без `PR_SET_NO_NEW_PRIVS`
Разобран в `broken/scenario-01/` (errno 13). Воспроизвести и починить:
```bash
sudo ./broken/scenario-01/make-broken.sh        # nobody без no_new_privs → errno 13
sudo ./solutions/01-no-new-privs/fix.sh           # с no_new_privs → фильтр ставится
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 06-seccomp
# --- module: 06-seccomp ---
# prepare...
# [OK] python3 и seccomp_bpf.py на месте
# verify...
# [OK] блокировка uname (syscall 63) → процесс убит SIGSYS (rc=159)
# [OK] незатронутая команда (date) под тем же фильтром работает
# [OK] после prctl: /proc/self/status Seccomp=2 (MODE_FILTER)
# [OK] module 06-seccomp verified
```

`verify/` использует raw seccomp-bpf (`seccomp_bpf.py`) — без systemd, переносим.
Полное демо (вкл. `systemd-run`) — `sudo ./run.sh`.

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| `seccomp_bpf.py <nr> <cmd>` | raw seccomp-bpf через prctl | механику фильтра «изнутри» |
| `/proc/<pid>/status` `Seccomp:` | режим seccomp (0/1/2) | что фильтр применён |
| `SIGSYS` (31) | сигнал на запрещённый syscall | `SECCOMP_RET_KILL` |
| `systemd-run -p SystemCallFilter=` | seccomp без кода | `--security-opt seccomp` Docker |
| `PR_SET_NO_NEW_PRIVS` | предусловие для не-root | почему фильтр ставится без root |

---

## Теоретические вопросы (итоговые)
1. Чем seccomp отличается от capabilities по тому, ЧТО ограничивает?
2. Три действия фильтра (ALLOW/ERRNO/KILL) и что получает процесс при KILL?
3. Зачем нужен `PR_SET_NO_NEW_PRIVS` и кому (root/не-root)?
4. Можно ли фильтровать по аргументам syscall и почему нельзя по строке-указателю?
5. Что использует Docker по умолчанию и какой профиль (сколько syscalls в allowlist)?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-block-with-bpf.md`** — заблокировать syscall через `seccomp_bpf.py`, поймать SIGSYS.
2. **`tasks/02-systemd-run.md`** — `SystemCallFilter=~uname` и `~@privileged`.
3. **`tasks/03-inspect-seccomp.md`** — поле `Seccomp` в `/proc/status`, номера syscalls.

Дополнительно:
4. Перепиши `seccomp_bpf.py` на `SECCOMP_RET_ERRNO` — uname должен возвращать ошибку, а не падать.
5. Заблокируй класс `~@clock` через systemd-run и поймай `date -s` (settimeofday).

---

## Шпаргалка

```bash
# === raw seccomp-bpf (наш helper) ===
./seccomp_bpf.py 63 uname -a        # блок uname(63 x86_64) → SIGSYS
./seccomp_bpf.py 63 date            # незатронутая команда работает
grep Seccomp /proc/self/status      # Seccomp: 2 = MODE_FILTER

# === systemd-run (без кода) ===
systemd-run --wait -p SystemCallFilter=~uname uname -a        # запретить один
systemd-run --wait -p SystemCallFilter=~@privileged <cmd>     # запретить класс

# === номера syscalls ===
ausyscall x86_64 uname              # → 63  (если установлен auditd)
grep -w __NR_uname /usr/include/asm/unistd_64.h

# === Docker ===
# --security-opt seccomp=profile.json   (дефолт: allowlist ~310 syscalls)
# --security-opt seccomp=unconfined     (снять фильтр — плохая идея)
```

---

## Чему вы научились
- Понимать seccomp filter (BPF на каждый syscall) и его действия (ALLOW/ERRNO/KILL).
- Собирать минимальный seccomp-bpf руками через `prctl` и видеть `SIGSYS` на запрете.
- Применять seccomp быстро через `systemd-run -p SystemCallFilter=`.
- Знать предусловие `PR_SET_NO_NEW_PRIVS` для не-root и зависимость номеров от арки.

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 06-seccomp
```

> Дальше — `07-apparmor`: мандатный контроль доступа (MAC) — профили на пути/
> возможности; `--security-opt apparmor=…` у Docker. (На WSL2 AppArmor выключен —
> модуль снимается на реальном хосте.)
