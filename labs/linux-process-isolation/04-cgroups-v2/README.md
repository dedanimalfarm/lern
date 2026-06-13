# Лабораторная работа 04: cgroups v2 — лимиты CPU, памяти, PIDs

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Устройство cgroup v2 и размещение процесса](#-1--cgroup-v2---)
  - [Теория для изучения перед частью](#----)
  - [1.1 Создать cgroup и включить контроллеры](#11--cgroup---)
- [Часть 2: Лимит CPU (cpu.max → throttling)](#-2--cpu-cpumax--throttling)
  - [Теория для изучения перед частью](#----)
  - [2.1 Ограничить busy-loop 20% ядра](#21--busy-loop-20-)
- [Часть 3: Лимит памяти (memory.max → OOM-kill)](#-3---memorymax--oom-kill)
  - [Теория для изучения перед частью](#----)
  - [3.1 Поймать OOM в лимите 50M](#31--oom---50m)
- [Часть 4: Лимит PIDs (pids.max → отказ fork)](#-4--pids-pidsmax---fork)
  - [Теория для изучения перед частью](#----)
  - [4.1 Упереться в pids.max=5](#41---pidsmax5)
- [Часть 5: Troubleshooting](#-5-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: в дочерней cgroup нет `cpu.max`](#-1---cgroup--cpumax)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~40 мин · сложность 3/5 · пререквизиты: 02-namespaces, базовый /proc и /sys

Цель: к **изоляции** (что процесс ВИДИТ — namespaces) добавить **лимиты** (сколько
процесс может ПОТРЕБИТЬ). Это вторая половина контейнера: namespaces дают свой мир,
cgroups не дают этому миру съесть весь хост. Разберём единую иерархию cgroup v2,
правило включения контроллеров «сверху вниз» (`cgroup.subtree_control`) и на живых
выводах увидим три жёстких лимита: CPU (троттлинг), память (OOM-kill), PIDs
(отказ `fork`). Это то, что Docker делает флагами `--cpus`, `--memory`, `--pids-limit`.

> Развитие `02-namespaces`. Все «ожидаемые выводы» сняты на реальном Ubuntu-хосте
> (GCP, ядро 6.8, `stress-ng` 0.13.12) — на WSL2 cgroup v2 тоже есть, но числа и
> наличие `stress-ng` могут отличаться; `verify/` намеренно работает без `stress-ng`
> (busy-loop / `tail /dev/zero` / fork-цикл).

---

## Предварительные требования

```bash
sudo ./00-setup/check.sh             # cgroup v2 — CORE; stress-ng — для демо (модуль 04)
stat -fc %T /sys/fs/cgroup           # cgroup2fs
cat /sys/fs/cgroup/cgroup.controllers
# cpuset cpu io memory hugetlb pids rdma misc
```

`stress-ng` нужен для демонстраций в README; если его нет — `sudo apt-get install -y stress-ng`
(или используй переносимые аналоги из шпаргалки). `verify/` обходится без него.

---

## Стартовая проверка

```bash
cat /sys/fs/cgroup/cgroup.subtree_control   # какие контроллеры делегированы детям
# cpuset cpu io memory pids                 # (на systemd-хосте обычно уже включены)
```

---

## Часть 1: Устройство cgroup v2 и размещение процесса

### Теория для изучения перед частью

- **cgroup v2 = единая иерархия.** В отличие от v1 (отдельная иерархия на каждый
  контроллер) здесь одно дерево под `/sys/fs/cgroup`, и процесс находится
  **ровно в одной** cgroup. Контроллеры (`cpu`, `memory`, `io`, `pids`, …)
  включаются на узле через `cgroup.subtree_control`.
- **Правило «сверху вниз».** Чтобы у дочерней cgroup появился файл лимита
  (`cpu.max`, `memory.max`…), контроллер должен быть включён в
  `cgroup.subtree_control` **родителя**. Не включил — файла лимита просто не будет
  (Часть 5, Сценарий 01).
- **Правило «no internal processes».** Cgroup либо содержит процессы, либо
  делегирует контроллеры подгруппам — не одновременно (кроме корневой). Поэтому
  лимиты вешают на **листовые** cgroup, а контроллеры включают на узлах-родителях.
- **Размещение процесса** — записью его PID в `cgroup.procs`. Идиома, гарантирующая
  попадание в группу ещё до старта нагрузки: `sh -c 'echo $$ > .../cgroup.procs; exec <нагрузка>'`.

---

**Цель:** создать cgroup, включить контроллеры, поместить туда процесс.

---

### 1.1 Создать cgroup и включить контроллеры

```bash
CG=/sys/fs/cgroup
sudo mkdir -p $CG/lab
# делегируем контроллеры дочерним группам (на узле lab, не в корень)
echo '+cpu +memory +pids' | sudo tee $CG/lab/cgroup.subtree_control
sudo mkdir -p $CG/lab/demo
ls $CG/lab/demo | grep -E 'cpu.max|memory.max|pids.max'
# cpu.max
# memory.max
# pids.max          <- файлы лимитов появились, т.к. контроллеры делегированы
```

**Контрольные вопросы:**
1. Чем единая иерархия v2 отличается от параллельных иерархий v1?
2. Почему у дочерней cgroup может не быть файла `cpu.max`?
3. Что такое правило «no internal processes»?

---

## Часть 2: Лимит CPU (cpu.max → throttling)

### Теория для изучения перед частью

- **`cpu.max` = "<квота> <период>"** в микросекундах. `20000 100000` = 20 мс
  процессорного времени каждые 100 мс = **20% одного ядра**. Когда квота на период
  исчерпана, ядро **тормозит** (throttle) процесс до конца периода.
- Доказательство — **`cpu.stat`**: `nr_throttled` (сколько периодов тормозили),
  `throttled_usec` (суммарно мкс простоя), `usage_usec` (реально использовано).
- Это `--cpus=0.2` у Docker. Мягкий аналог — `cpu.weight` (доля при конкуренции,
  это `--cpu-shares`), он НЕ ставит потолок.

---

### 2.1 Ограничить busy-loop 20% ядра

```bash
CG=/sys/fs/cgroup; sudo mkdir -p $CG/lab/cpu
echo "20000 100000" | sudo tee $CG/lab/cpu/cpu.max        # 20% одного ядра
# один воркер stress-ng на 5 секунд, помещённый в cgroup
sudo sh -c 'echo $$ > '$CG'/lab/cpu/cgroup.procs; exec stress-ng --cpu 1 --timeout 5s' >/dev/null 2>&1
cat $CG/lab/cpu/cpu.stat
# usage_usec 1013841          <- за 5с реально потрачено ~1.01с CPU = ~20% ✔
# user_usec 1000411
# system_usec 13429
# nr_periods 51
# nr_throttled 50             <- тормозили почти каждый период
# throttled_usec 3990012      <- суммарно ~3.99с простоя «по тормозам»
```

Воркер хотел 100% ядра, но `cpu.max` удержал его на 20%: `usage ≈ 1.01с` из 5с,
а ~3.99с он простоял в throttle.

**Контрольные вопросы:**
1. Что означает `cpu.max = "20000 100000"` в процентах ядра?
2. Какие поля `cpu.stat` доказывают, что лимит сработал?
3. Чем `cpu.max` отличается от `cpu.weight` (жёсткий потолок vs доля)?

---

## Часть 3: Лимит памяти (memory.max → OOM-kill)

### Теория для изучения перед частью

- **`memory.max`** — жёсткий потолок памяти cgroup. При попытке выйти за него ядро
  сначала освобождает page cache и свопит (если своп не запрещён
  `memory.swap.max=0`); если не помогло — **OOM-killer** убивает процесс(ы) группы.
- **`memory.events`** считает события: `oom` (срабатывания), `oom_kill` (убийства),
  `max` (сколько раз упёрлись в потолок). Это `--memory=` у Docker.

---

### 3.1 Поймать OOM в лимите 50M

```bash
CG=/sys/fs/cgroup; sudo mkdir -p $CG/lab/mem
echo 50M | sudo tee $CG/lab/mem/memory.max
echo 0   | sudo tee $CG/lab/mem/memory.swap.max          # без swap — OOM быстрый
# просим занять 200M в лимите 50M
sudo sh -c 'echo $$ > '$CG'/lab/mem/cgroup.procs; exec stress-ng --vm 1 --vm-bytes 200M --vm-keep --timeout 6s' 2>&1 | tail -2
# ... stress-ng перезапускает воркеры, каждого убивает OOM
grep -E '^(oom|oom_kill|max) ' $CG/lab/mem/memory.events
# max 2400          <- 2400 раз упёрлись в потолок
# oom 62
# oom_kill 62       <- 62 OOM-убийства воркеров

# Переносимый аналог без stress-ng — tail /dev/zero (читает нули в память):
sudo sh -c 'echo $$ > '$CG'/lab/mem/cgroup.procs; exec tail /dev/zero'
# Killed                                  <- процесс убит OOM-killer'ом
# (код возврата 137 = 128 + SIGKILL(9))
```

**Контрольные вопросы:**
1. Что ядро делает ДО OOM-kill при достижении `memory.max`?
2. Зачем в демо `memory.swap.max=0`?
3. Какой код возврата у процесса, убитого OOM (SIGKILL)?

---

## Часть 4: Лимит PIDs (pids.max → отказ fork)

### Теория для изучения перед частью

- **`pids.max`** ограничивает число процессов/потоков в cgroup. При попытке
  превысить — `fork()`/`clone()` возвращает `EAGAIN` («Resource temporarily
  unavailable»). Защита от fork-бомб; это `--pids-limit` у Docker.
- `pids.current` — текущее число, `pids.events.max` — сколько раз упёрлись.

---

### 4.1 Упереться в pids.max=5

```bash
CG=/sys/fs/cgroup; sudo mkdir -p $CG/lab/pids
echo 5 | sudo tee $CG/lab/pids/pids.max
sudo sh -c 'echo $$ > '$CG'/lab/pids/cgroup.procs; for i in $(seq 1 10); do sleep 20 & done; wait'
# bash: fork: retry: Resource temporarily unavailable
# bash: fork: retry: Resource temporarily unavailable
# bash: fork: retry: Resource temporarily unavailable
# bash: fork: retry: Resource temporarily unavailable
# bash: fork: Resource temporarily unavailable     <- больше 5 процессов не создать
```

> На жёстком лимите даже `$(cat pids.current)` внутри группы может не выполниться
> (для подстановки тоже нужен `fork`). Читай `pids.current`/`pids.events` **снаружи**:
> `cat /sys/fs/cgroup/lab/pids/pids.current` → `5`.

**Контрольные вопросы:**
1. Какую ошибку возвращает `fork()` при достижении `pids.max`?
2. От какой атаки/аварии защищает `pids.max`?
3. Почему `pids.current` лучше читать снаружи cgroup?

---

## Часть 5: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ в дочерней cgroup НЕТ cpu.max/memory.max ─────► контроллер не включён в
│     cgroup.subtree_control РОДИТЕЛЯ. echo +cpu > parent/cgroup.subtree_control
│     (Сценарий 01)
├─ echo +cpu > X/cgroup.subtree_control → EBUSY ─► в X есть процессы («no internal
│     processes»). Вынеси процессы в листовую подгруппу, на X оставь только контроллеры
├─ записал PID в cgroup.procs, а лимит «не действует» ─► процесс попал в группу ПОСЛЕ
│     старта нагрузки. Идиома: sh -c 'echo $$ > .../cgroup.procs; exec <нагрузка>'
└─ rmdir cgroup → Device or resource busy ───────► в группе ещё есть процессы;
      вынеси их (echo PID > /sys/fs/cgroup/cgroup.procs) и повтори rmdir
```

### Инцидент 1: в дочерней cgroup нет `cpu.max`
Разобран в `broken/scenario-01/` (контроллер не делегирован через `subtree_control`).
Воспроизвести и починить:
```bash
sudo ./broken/scenario-01/make-broken.sh         # нет cpu.max → запись отказывает
sudo ./solutions/01-enable-subtree-control/fix.sh # +cpu в subtree_control → cpu.max появился
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 04-cgroups-v2
# --- module: 04-cgroups-v2 ---
# prepare...
# [OK] cgroup v2 на месте, контроллеры делегированы (cpu/memory/pids)
# verify...
# [OK] CPU: cpu.max=10% → throttling (nr_throttled>=1)
# [OK] MEM: memory.max=32M → OOM-kill (oom_kill>=1)
# [OK] PIDS: pids.max=3 → fork отклонён (EAGAIN)
# [OK] module 04-cgroups-v2 verified
```

`verify/` использует переносимые генераторы нагрузки (busy-loop, `tail /dev/zero`,
fork-цикл) — без `stress-ng`. Демо с `stress-ng` — `sudo ./run.sh`.

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| `cgroup.subtree_control` | делегирование контроллеров | правило «сверху вниз» |
| `cpu.max` + `cpu.stat` | лимит CPU и счётчики throttle | `--cpus` Docker |
| `memory.max` + `memory.events` | потолок памяти и OOM | `--memory` Docker |
| `pids.max` | лимит числа процессов | `--pids-limit` Docker |
| `io.max` (теория) | лимит дискового IO (wbps/rbps) | `--device-write-bps` Docker |

---

## Теоретические вопросы (итоговые)
1. Чем cgroup v2 (единая иерархия) отличается от v1?
2. Почему контроллеры включаются «сверху вниз» через `subtree_control`?
3. Что такое «no internal processes» и как из-за него строить дерево cgroup?
4. Как `cpu.max`/`memory.max`/`pids.max` соответствуют флагам `docker run`?
5. Что делает ядро при достижении `memory.max` до OOM-kill?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-cpu-limit.md`** — `cpu.max`, поймать throttling в `cpu.stat`.
2. **`tasks/02-memory-oom.md`** — `memory.max`, поймать OOM-kill.
3. **`tasks/03-pids-limit.md`** — `pids.max`, поймать отказ `fork`.

Дополнительно:
4. Поставь `cpu.weight=50` вместо `cpu.max` и при конкуренции сравни доли двух групп.
5. Ограничь IO: `echo "$(lsblk -no MAJ:MIN /dev/<диск>) wbps=1048576" > io.max`, проверь `dd`.

---

## Шпаргалка

```bash
CG=/sys/fs/cgroup
mkdir -p $CG/lab && echo '+cpu +memory +pids +io' > $CG/lab/cgroup.subtree_control
mkdir -p $CG/lab/g

echo "20000 100000" > $CG/lab/g/cpu.max          # CPU 20% ядра  (cpu.stat: nr_throttled)
echo 64M            > $CG/lab/g/memory.max        # память; + echo 0 > memory.swap.max
echo 100            > $CG/lab/g/pids.max          # лимит PIDs
echo "8:0 wbps=1048576" > $CG/lab/g/io.max        # IO: 1MB/s записи на устройство 8:0

# поместить процесс В группу до старта нагрузки:
sh -c 'echo $$ > '$CG'/lab/g/cgroup.procs; exec <нагрузка>'

# уборка: вынести процессы и снести
for p in $(cat $CG/lab/g/cgroup.procs); do echo $p > $CG/cgroup.procs; done
rmdir $CG/lab/g $CG/lab
```

---

## Чему вы научились
- Понимать единую иерархию cgroup v2 и правило делегирования контроллеров «сверху вниз».
- Ставить и проверять три жёстких лимита: CPU (`cpu.max`/`cpu.stat`), память
  (`memory.max`/OOM/`memory.events`), процессы (`pids.max`/`EAGAIN`).
- Корректно помещать процесс в cgroup (`echo $$ > cgroup.procs; exec …`).
- Сопоставлять это с флагами `docker run --cpus/--memory/--pids-limit`.

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 04-cgroups-v2
```

> Дальше — `05-capabilities`: дробим всемогущего root на отдельные права
> (CAP_NET_BIND_SERVICE, CAP_SYS_ADMIN …) — `--cap-drop`/`--cap-add` у Docker.
