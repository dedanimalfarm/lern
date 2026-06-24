# Лабораторная работа 14: eBPF — наблюдаемость изоляции

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Перехватить openat (IDS-стиль)](#-1--openat-ids-)
  - [Теория для изучения перед частью](#----)
  - [1.1 Слежка за открытием файла](#11----)
- [Часть 2: Агрегаты — кто сколько syscalls делает](#-2-----syscalls-)
  - [Теория для изучения перед частью](#----)
  - [2.1 Сколько syscalls у каждого процесса](#21--syscalls---)
- [Часть 3: eBPF в контейнерном мире](#-3-ebpf---)
  - [Теория для изучения перед частью](#----)
  - [3.1 Привязка события к процессу](#31----)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: `bpftrace ... only supports running as the root user`](#-1-bpftrace--only-supports-running-as-the-root-user)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~30 мин · сложность 4/5 · пререквизиты: 02-namespaces, 06-seccomp

Цель: посмотреть на изоляцию **снаружи** — видеть, какие системные вызовы, файлы и
события делает процесс/контейнер, не вмешиваясь в него. **eBPF** запускает
безопасные мини-программы прямо в ядре (без модулей и перекомпиляции); **bpftrace**
— высокоуровневый язык к нему (как awk для ядра). Это надстройка над всем курсом:
мы изолировали процесс примитивами 01–13, а теперь **наблюдаем** за ним с
минимальным оверхедом — основа Falco, Tetragon, Cilium.

> ⚠️ **Host-only модуль.** На WSL2 нет `bpftrace` (и часто нет BTF) — `verify/`
> печатает `[WARN]` и проходит (skip). Все «ожидаемые выводы» сняты на реальном
> Ubuntu-хосте (GCP, ядро 6.8, `bpftrace` 0.14, BTF в `/sys/kernel/btf/vmlinux`).
> Развитие `06-seccomp`: там мы syscalls **фильтровали**, здесь — **наблюдаем**.

---

## Предварительные требования

```bash
sudo ./00-setup/check.sh                 # bpftrace (модуль 14)
sudo apt-get install -y bpftrace         # на хосте (не WSL2)
ls /sys/kernel/btf/vmlinux               # BTF есть → bpftrace заработает без headers
bpftrace --version | head -1             # bpftrace v0.1x
```

---

## Стартовая проверка

```bash
sudo bpftrace -e 'BEGIN { printf("ebpf ok\n"); exit(); }'
# ebpf ok
```

---

## Часть 1: Перехватить openat (IDS-стиль)

### Теория для изучения перед частью

- **bpftrace -e '<probe> /фильтр/ { действие }'** прикрепляет eBPF-программу к
  точке ядра. **`tracepoint:syscalls:sys_enter_openat`** срабатывает на каждом
  `openat(2)` (открытие файла); `str(args->filename)` читает имя файла.
- Так делают IDS (Falco/Tetragon): мгновенно видят, что контейнер открыл
  `/etc/shadow` или `/run/secrets/`, **не вмешиваясь** в его ФС.

---

### 1.1 Слежка за открытием файла

```bash
echo secret > /tmp/secret.txt
( while :; do cat /tmp/secret.txt >/dev/null; sleep 0.1; done ) &      # «контейнер» читает файл

sudo bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("OPEN %s\n", str(args->filename)); }'
# OPEN /tmp/secret.txt
# OPEN /tmp/secret.txt
# ... (Ctrl-C для выхода)
kill %1; rm -f /tmp/secret.txt
```

**Контрольные вопросы:**
1. Что такое eBPF и чем он лучше модуля ядра/перекомпиляции?
2. Что делает `tracepoint:syscalls:sys_enter_openat` и зачем `str(args->filename)`?
3. Как на этом построить детектор чтения `/etc/shadow` контейнером?

---

## Часть 2: Агрегаты — кто сколько syscalls делает

### Теория для изучения перед частью

- eBPF умеет **агрегировать в ядре** (maps): `@[ключ] = count()` копит счётчики без
  передачи каждого события в userspace — отсюда низкий оверхед. По выходу bpftrace
  печатает map.
- `tracepoint:raw_syscalls:sys_enter` ловит ВСЕ syscalls; `@[comm] = count()`
  считает их по имени процесса.

---

### 2.1 Сколько syscalls у каждого процесса

```bash
sudo bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @sys[comm] = count(); }'
# ^C через пару секунд:
# @sys[timeout]: 9
# @sys[bpftrace]: 22
# @sys[postgres]: 239        <- самый «болтливый» процесс по syscalls
```

**Контрольные вопросы:**
1. Почему агрегация в ядре (maps) даёт низкий оверхед?
2. Что считает `@[comm] = count()` и чем `raw_syscalls` отличается от конкретного syscall?
3. Как этим найти процесс, который «забивает» ядро вызовами?

---

## Часть 3: eBPF в контейнерном мире

### Теория для изучения перед частью

- **Наблюдаемость/безопасность:** Falco, Tetragon перехватывают события контейнеров
  (exec, открытие файлов, сеть) для рантайм-детекта атак — альтернатива/дополнение
  seccomp (этап 06): seccomp **блокирует**, eBPF **наблюдает** (и новые версии могут
  блокировать).
- **Сеть:** Cilium заменяет iptables (этап 09) на eBPF — маршрутизация/политики
  пакетов в ядре, быстрее.
- **device cgroup v2** (доступ к устройствам в контейнере) уже реализован через eBPF.
- Привязка к этапам: eBPF видит ровно те namespaces/cgroups/syscalls, что мы строили
  руками — `comm`, `pid`, `cgroup`, имена файлов доступны прямо в probe.

---

### 3.1 Привязка события к процессу

```bash
sudo bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("%s[%d] -> %s\n", comm, pid, str(args->filename)); }' | head -5
# bash[12345] -> /tmp/secret.txt        <- кто (comm/pid) и что открыл
```

**Контрольные вопросы:**
1. Чем eBPF-наблюдение (Falco/Tetragon) дополняет seccomp (этап 06)?
2. Что Cilium заменяет из этапа 09 и зачем?
3. Какие поля (`comm`/`pid`/имя файла) доступны прямо в eBPF-probe?

---

## Часть 4: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ bpftrace: only supports running as the root user ──────────► запускай через sudo
│     (нужен CAP_BPF/CAP_SYS_ADMIN) (Сценарий 01)
├─ ERROR: Unable to find BTF / kernel headers ────────────────► нет BTF и нет
│     linux-headers-$(uname -r). Поставь headers или ядро с CONFIG_DEBUG_INFO_BTF
├─ bpftrace на WSL2: не работает ─────────────────────────────► часто нет bpftrace/
│     BTF/трейспоинтов. Это host-only — запускай на полноценном Ubuntu
└─ str(args->filename) пустой/мусор ──────────────────────────► читаешь не тот
      аргумент или указатель уже освобождён; сверься с форматом tracepoint (/sys/.../format)
```

### Инцидент 1: `bpftrace ... only supports running as the root user`
Разобран в `broken/scenario-01/` (запуск без root). Воспроизвести и починить:
```bash
sudo ./broken/scenario-01/make-broken.sh        # от nobody → ошибка про root
sudo ./solutions/01-run-as-root/fix.sh            # от root → bpftrace работает
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 14-ebpf
# --- module: 14-ebpf ---
# prepare...
# [OK] bpftrace на месте (BTF: есть)
# verify...
# [OK] eBPF: bpftrace перехватил openat файла /tmp/lpi-ebpf-secret.txt (N раз)
# [OK] module 14-ebpf verified
```

На хосте без `bpftrace` (WSL2) `verify/` печатает `[WARN]` и проходит (skip).

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| `bpftrace -e '<probe>{...}'` | eBPF-программа из CLI | трассировку ядра без модулей |
| `tracepoint:syscalls:sys_enter_openat` | точка на openat | перехват доступа к файлам (IDS) |
| `@[comm] = count()` | агрегация в ядре (map) | низкий оверхед наблюдения |
| `comm`/`pid`/`str(args->filename)` | контекст события | привязку к процессу/контейнеру |
| BTF (`/sys/kernel/btf/vmlinux`) | типы ядра | работу bpftrace без headers |

---

## Теоретические вопросы (итоговые)
1. Что такое eBPF и почему он безопаснее модуля ядра?
2. Чем eBPF-наблюдение (Falco/Tetragon) дополняет seccomp (фильтрация, этап 06)?
3. Зачем агрегация в ядре (maps) и как она снижает оверхед?
4. Почему bpftrace требует root и BTF/headers?
5. Что из курса (этапы 06, 09) eBPF-инструменты заменяют/дополняют в проде?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-trace-openat.md`** — перехватить открытие файла через bpftrace.
2. **`tasks/02-count-syscalls.md`** — посчитать syscalls по процессам (агрегат).
3. **`tasks/03-attach-to-process.md`** — привязать событие к `comm`/`pid`.

Дополнительно:
4. Напиши однострочник, который печатает только чтение `/etc/shadow` (фильтр по имени файла).
5. Посчитай гистограмму размеров `read()` через `@ = hist(args->count)`.

---

## Шпаргалка

```bash
# открытия файлов (кто что открыл):
bpftrace -e 'tracepoint:syscalls:sys_enter_openat { printf("%s %s\n", comm, str(args->filename)); }'
# счётчик syscalls по процессам:
bpftrace -e 'tracepoint:raw_syscalls:sys_enter { @[comm]=count(); }'
# запуски процессов (execve):
bpftrace -e 'tracepoint:syscalls:sys_enter_execve { printf("EXEC %s\n", str(args->filename)); }'
# гистограмма размеров чтения:
bpftrace -e 'tracepoint:syscalls:sys_enter_read { @=hist(args->count); }'
# готовые инструменты: bpftrace, bcc-tools (opensnoop, execsnoop, tcpconnect)
```

---

## Чему вы научились
- Понимать eBPF/bpftrace и запускать трассировку ядра без модулей/перекомпиляции.
- Перехватывать syscalls контейнера снаружи (openat → IDS-детект чтения секретов).
- Агрегировать события в ядре (maps) с низким оверхедом.
- Видеть место eBPF в проде: Falco/Tetragon (наблюдение vs seccomp), Cilium (vs iptables).

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 14-ebpf
```

> Это последний этап курса. Ты прошёл путь от голого `chroot` (01) до настоящего
> рантайма `runc` (13) и наблюдаемости через eBPF (14) — и теперь знаешь, что
> контейнер это не магия, а композиция примитивов ядра. 🎉
