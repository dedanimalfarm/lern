# Лабораторная работа 02: namespaces — шесть видов изоляции ядра

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Шесть namespace по одному](#-1--namespace--)
  - [Теория для изучения перед частью](#----)
  - [1.1 Поднять каждый namespace и сравнить inode](#11---namespace---inode)
- [Часть 2: Эффект каждого namespace](#-2---namespace)
  - [Теория для изучения перед частью](#----)
  - [2.1 UTS, PID, MNT, NET, USER, IPC](#21-uts-pid-mnt-net-user-ipc)
- [Часть 3: Всё сразу — это и есть `docker run`](#-3-------docker-run)
  - [Теория для изучения перед частью](#----)
  - [3.1 Базовый контейнер одной командой](#31----)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: новый PID-namespace, но `ps` врёт / `$$` не 1](#-1--pid-namespace--ps-----1)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~35 мин · сложность 3/5 · пререквизиты: 01-chroot, базовый bash/процессы

Цель: понять **namespaces** — механизм, которым ядро даёт процессу «отдельный
экземпляр» глобального ресурса. На этапе 01 мы изолировали только файловую
систему (`chroot`) и увидели, что PID/UTS/NET/mount остаются хостовыми. Здесь
закрываем этот пробел: поднимаем каждый из шести ключевых namespace по одному,
доказываем изоляцию через inode `/proc/self/ns/*`, наблюдаем эффект — и в финале
одной командой собираем процесс, изолированный по всем шести. Это и есть ядро
`docker run`.

> Развитие `01-chroot`. Все «ожидаемые выводы» сняты на этом хосте (WSL2, ядро
> 6.6, hostname `DESKTOP-2NEPKQQ`). Числа inode и имена у вас будут свои — важна
> структура: «inode внутри ≠ inode хоста», «внутри свой hostname/PID 1/uid 0».

---

## Предварительные требования

```bash
sudo ./00-setup/check.sh          # unshare, nsenter, ip — должны быть
id -u                             # 0
unshare --version                 # unshare from util-linux 2.xx
```

---

## Стартовая проверка

```bash
# namespaces текущей оболочки — это «эталон хоста» для сравнения
for n in uts pid mnt net ipc user; do printf "%-5s %s\n" "$n" "$(readlink /proc/self/ns/$n)"; done
# uts   uts:[4026532220]
# pid   pid:[4026532221]
# mnt   mnt:[4026532219]
# net   net:[4026531840]
# ipc   ipc:[4026532208]
# user  user:[4026531837]
```

---

## Часть 1: Шесть namespace по одному

### Теория для изучения перед частью

- **Namespace** = изолированный экземпляр глобального ресурса ядра. Процесс
  «видит» только свой экземпляр. Linux поддерживает 8 типов; ключевых — 6:

  | Namespace | Что изолирует | Флаг `unshare` |
  |---|---|---|
  | **UTS** | hostname, domainname | `--uts` (`-u`) |
  | **PID** | таблицу PID, PID 1 | `--pid --fork` (`-p`) |
  | **MNT** | дерево mount | `--mount` (`-m`) |
  | **NET** | интерфейсы, маршруты, сокеты, iptables | `--net` (`-n`) |
  | **USER** | маппинг UID/GID | `--user` (`-U`) |
  | **IPC** | SysV IPC, POSIX-очереди | `--ipc` (`-i`) |

  Ещё два: **CGROUP** (вид иерархии cgroups, `-C`) и **TIME** (`CLOCK_MONOTONIC/
  BOOTTIME`, ядро ≥ 5.6, `-T`).
- **Доказательство изоляции — inode.** У каждого namespace есть inode под
  `/proc/<pid>/ns/<тип>` (`readlink` показывает `тип:[номер]`). Ядро гарантирует:
  процессы в РАЗНЫХ namespace имеют РАЗНЫЕ inode. Значит «inode внутри ≠ inode
  хоста» = мы действительно в новом namespace. Именно так рантайм определяет
  «принадлежит контейнеру».

---

**Цель:** создать каждый namespace и подтвердить по inode, что он новый.

---

### 1.1 Поднять каждый namespace и сравнить inode

```bash
# Соберём все шесть СРАЗУ в одном процессе и сверим с эталоном хоста выше
sudo unshare --uts --pid --mount --net --ipc --user --map-root-user --fork --mount-proc \
  /bin/bash -c 'for n in uts pid mnt net ipc user; do printf "%-5s %s\n" $n $(readlink /proc/self/ns/$n); done'
# uts   uts:[4026532301]     <- все шесть ОТЛИЧАЮТСЯ от хостовых
# pid   pid:[4026532303]
# mnt   mnt:[4026532300]
# net   net:[4026532304]
# ipc   ipc:[4026532302]
# user  user:[4026532299]
```

Все шесть inode — новые (сравните с эталоном из «Стартовой проверки»). Процесс
живёт в шести собственных namespace одновременно.

> Если поднимать namespace по одному в РАЗНЫХ командах (`unshare --uts …`,
> отдельно `unshare --mnt …`), номера inode могут совпасть между собой — ядро
> переиспользует освобождённый номер после завершения короткого процесса. Это не
> «один и тот же ns»: важно сравнение с **хостом**, а не команд между собой.

**Контрольные вопросы:**
1. Почему «inode внутри ≠ inode хоста» доказывает создание нового namespace?
2. Сколько всего типов namespace в Linux и какие из 8?
3. Как узнать, в каких namespace находится произвольный процесс по его PID?

---

## Часть 2: Эффект каждого namespace

### Теория для изучения перед частью

Inode доказывает «namespace новый», но интереснее увидеть, ЧТО меняется:
- **UTS** — свой `hostname`, смена внутри не видна хосту.
- **PID** — внутри ты `PID 1` (init namespace). **Нужна триада** `--pid --fork
  --mount-proc`: `--fork` (иначе PID 1 получит только потомок), `--mount-proc`
  (иначе `/proc` остаётся хостовым и `ps` врёт) — разбор в Части 4.
- **MNT** — свои монтирования; `tmpfs`, смонтированный внутри, хосту не виден.
- **NET** — пустой сетевой стек: только `lo`, и тот `DOWN`. Никаких `eth0`.
- **USER** — внутри ты `uid 0` (root), снаружи остаёшься своим uid. Основа rootless.
- **IPC** — своя таблица SysV-сегментов/очередей.

---

**Цель:** на живых выводах увидеть эффект каждого namespace.

---

### 2.1 UTS, PID, MNT, NET, USER, IPC

```bash
# UTS: меняем hostname внутри — хост не затронут
sudo unshare --uts /bin/bash -c 'hostname container-uts; echo "  внутри: $(hostname)"'
# внутри: container-uts
hostname
# DESKTOP-2NEPKQQ          <- хост не изменился
```

```bash
# PID: внутри $$ == 1, ps видит только свои процессы
sudo unshare --pid --fork --mount-proc /bin/bash -c 'echo "  \$\$=$$"; ps -ef | head -3'
#   $$=1
# UID  PID PPID C STIME TTY  TIME CMD
# root   1    0 0 ...        bash         <- наш процесс это PID 1
# root   2    1 0 ...        ps -ef
```

```bash
# MNT: tmpfs внутри не утекает на хост
sudo unshare --mount /bin/bash -c 'mount --make-rprivate /; mount -t tmpfs none /mnt; echo secret > /mnt/inside; echo "  внутри /mnt: $(ls /mnt)"'
#   внутри /mnt: inside
ls /mnt
# c  d  wsl  wslg          <- на хосте свой /mnt, файла inside нет
```

```bash
# NET: пустой стек — один loopback, и тот DOWN
sudo unshare --net /bin/bash -c 'ip -o link'
# 1: lo: <LOOPBACK> mtu 65536 qdisc noop state DOWN ...     <- ни eth0, ни связности

# USER: внутри root, снаружи — твой uid
sudo unshare --user --map-root-user /bin/bash -c 'id'
# uid=0(root) gid=0(root) groups=0(root)

# IPC: своя таблица SysV (сегмент, созданный внутри, снаружи не виден)
ipcs -m | grep -c '^0x'                       # снаружи: 0
sudo unshare --ipc /bin/bash -c 'ipcmk -M 1024 >/dev/null; echo "  внутри сегментов: $(ipcs -m | grep -c ^0x)"'
#   внутри сегментов: 1
ipcs -m | grep -c '^0x'                       # снаружи по-прежнему: 0
```

**Контрольные вопросы:**
1. Что произойдёт с остальными процессами PID-ns, если PID 1 завершится?
2. Почему `tmpfs`, смонтированный в mnt-ns, не виден хосту?
3. Зачем USER namespace нужен для rootless-контейнеров?

---

## Часть 3: Всё сразу — это и есть `docker run`

### Теория для изучения перед частью

`docker run --rm alpine sh` под капотом поднимает разом UTS, PID, MNT, NET, IPC
(и CGROUP), запуская процесс в свежем rootfs. На голых примитивах это:
```
unshare --uts --pid --mount --net --ipc --user --map-root-user --fork --mount-proc <rootfs>/bin/sh
```
Плюс (последующие этапы): veth в bridge (09), `pivot_root` в overlay (03+08),
лимиты cgroup (04). USER namespace в Docker по умолчанию выключен — компромисс
совместимости.

---

### 3.1 Базовый контейнер одной командой

```bash
sudo unshare --uts --pid --mount --net --ipc --user --map-root-user --fork --mount-proc \
  /bin/bash -c '
    hostname mini-container
    echo "  hostname: $(hostname)"
    echo "  uid:      $(id -u)"
    echo "  PID 1:    $(cat /proc/1/comm)"
    echo "  ifaces:   $(ip -o link | wc -l)"
  '
#   hostname: mini-container
#   uid:      0
#   PID 1:    bash
#   ifaces:   1
```

Свой hostname, свой PID 1, root внутри, пустая сеть — изолированный процесс на
одних примитивах ядра, без Docker.

**Контрольные вопросы:**
1. Какие namespace поднимает `docker run` по умолчанию, а какой — нет и почему?
2. Чего не хватает этому «контейнеру» до настоящего (сеть, корень, лимиты)?
3. Почему `--mount-proc` обязателен, если хочешь корректный `ps` внутри?

---

## Часть 4: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ внутри нового --pid: $$ НЕ равен 1 ───────► забыт --fork. unshare остаётся в
│     старом ns; новый ns получает только его ПОТОМОК (Сценарий 01, случай A)
├─ $$=1, но `ps` падает «fatal library error, lookup self» или показывает хост ─►
│     забыт --mount-proc: /proc остался хостовым (Сценарий 01, случай B)
├─ unshare: ... Operation not permitted ─────► нет root / userns запрещены
│     (проверь sudo и unshare --user --map-root-user true)
└─ внутри --net нет связности ───────────────► это норма: net-ns пустой, lo DOWN.
      Связность даёт veth+bridge (этап 09)
```

### Инцидент 1: новый PID-namespace, но `ps` врёт / `$$` не 1
Разобран в `broken/scenario-01/` (забыты `--fork` и/или `--mount-proc`).
Воспроизвести и починить:
```bash
sudo ./broken/scenario-01/make-broken.sh           # покажет оба случая поломки
sudo ./solutions/01-pid-fork-mountproc/fix.sh        # триада --pid --fork --mount-proc
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 02-namespaces
# --- module: 02-namespaces ---
# prepare...
# [OK] namespaces: инструменты на месте (unshare/ip/nsenter)
# verify...
# [OK] uts-ns создан: host=4026532220 new=...
# [OK] pid-ns создан: host=4026532221 new=...
# [OK] mnt-ns создан: host=4026532219 new=...
# [OK] net-ns создан: host=4026531840 new=...
# [OK] ipc-ns создан: host=4026532208 new=...
# [OK] user-ns создан: host=4026531837 new=...
# [OK] UTS: hostname хоста не изменился ('DESKTOP-2NEPKQQ')
# [OK] PID: внутри $$==1
# [OK] MNT: tmpfs из mnt-ns не виден на хосте
# [OK] NET: внутри интерфейсов = 1 (только lo)
# [OK] USER: внутри uid=0 (rootless mapping)
# [OK] module 02-namespaces verified
```

Хочешь пошаговую демонстрацию с пояснениями — `sudo ./run.sh`.

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| `/proc/self/ns/{uts,pid,mnt,net,ipc,user}` | inode 6 namespace | изоляцию (inode внутри ≠ host) |
| `unshare --uts` | свой hostname | UTS namespace |
| `unshare --pid --fork --mount-proc` | свой PID 1 и /proc | PID namespace + почему триада флагов |
| `unshare --mount` + tmpfs | приватный mount | MNT namespace (нет утечки) |
| `unshare --net` | пустой стек (lo DOWN) | NET namespace |
| `unshare --user --map-root-user` | uid 0 внутри | USER namespace (rootless) |

---

## Теоретические вопросы (итоговые)
1. Чем доказывается, что процесс в новом namespace — и почему именно inode?
2. Почему `unshare --pid` без `--fork` не даёт `$$ == 1`?
3. Почему без `--mount-proc` в новом PID-ns `ps` показывает хост / падает?
4. Зачем USER namespace для rootless и почему capabilities внутри не вредят хосту?
5. Какие namespace поднимает `docker run` по умолчанию, а USER — почему нет?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-each-namespace.md`** — поднять 6 namespace и подтвердить по inode.
2. **`tasks/02-functional-effects.md`** — увидеть эффект каждого (hostname/PID/mount/net/uid/ipc).
3. **`tasks/03-all-at-once.md`** — собрать «контейнер» одной командой.

Дополнительно:
4. Войди в namespace уже запущенного процесса через `nsenter --target <pid> --uts --net`.
5. Подними time namespace (`unshare --time`) и сдвинь `CLOCK_BOOTTIME` через `/proc/self/timens_offsets`.

---

## Шпаргалка

```bash
# === inode-доказательство ===
readlink /proc/self/ns/uts                       # uts:[N] на хосте
unshare --uts --fork readlink /proc/self/ns/uts  # другой N ⇒ новый ns

# === по одному ===
unshare --uts        bash   # свой hostname
unshare --pid --fork --mount-proc bash   # свой PID 1 + корректный ps  (триада!)
unshare --mount      bash   # приватные монтирования
unshare --net        bash   # пустой сетевой стек (lo DOWN)
unshare --user --map-root-user bash      # uid 0 внутри (rootless)
unshare --ipc        bash   # своя SysV-таблица

# === всё сразу = базовый docker run ===
unshare --uts --pid --mount --net --ipc --user --map-root-user --fork --mount-proc <rootfs>/bin/sh

# === войти в чужие namespace ===
nsenter --target <pid> --uts --net --pid
```

---

## Чему вы научились
- Создавать каждый из шести ключевых namespace через `unshare` и доказывать
  изоляцию через inode `/proc/self/ns/*`.
- Объяснять эффект каждого: hostname (UTS), PID 1 (PID), приватные монтирования
  (MNT), пустой стек (NET), uid 0 (USER), отдельная SysV-таблица (IPC).
- Понимать, зачем PID-ns нужна триада `--pid --fork --mount-proc`.
- Собирать процесс, изолированный по всем шести namespace, — ядро `docker run`.

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 02-namespaces (нет персистентных артефактов)
```

> Дальше — `03-pivot-root`: используем mount-namespace из этого модуля, чтобы
> безопасно сменить корень и закрыть побег `/proc/1/root` из этапа 01.
