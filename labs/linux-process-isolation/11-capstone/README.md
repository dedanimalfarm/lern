# Лабораторная работа 11: Capstone — «свой docker run» из ~150 строк bash

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Что делает mycontainer](#-1---mycontainer)
  - [Теория для изучения перед частью](#----)
  - [1.1 Запустить контейнер](#11--)
- [Часть 2: Главный тезис — pivot_root делает контейнер контейнером](#-2----pivot_root---)
  - [Теория для изучения перед частью](#----)
  - [2.1 Побег закрыт (сравните с этапом 01)](#21------01)
- [Часть 3: Лимиты ресурсов и честные ограничения](#-3-----)
  - [Теория для изучения перед частью](#----)
  - [3.1 Лимит памяти защищает хост](#31----)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: наивный chroot-контейнер дырявый (побег на хост)](#-1--chroot-----)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~30 мин · сложность 4/5 · пререквизиты: 01–10 (весь курс)

Цель: склеить всё пройденное в один скрипт `mycontainer.sh`, который делает примерно
`docker run --rm alpine sh` — но на голых примитивах ядра. Это не замена Docker, а
**доказательство, что Docker не магия**: ~150 строк bash и десяток системных
вызовов дают изолированный процесс с лимитами ресурсов. Главный вывод курса виден
здесь: разница между «игрушечным» chroot (этап 01, побег работает) и настоящим
контейнером — это `pivot_root` в новом mount-namespace.

> Финал курса. `mycontainer.sh` собирает: rootfs (01,10) + overlay (08) + cgroups
> (04) + namespaces (02) + pivot_root (03) + caps/seccomp (05,06, best-effort).
> Выводы сняты на WSL2 (все примитивы работают); нужен alpine rootfs (интернет).

---

## Предварительные требования

```bash
sudo ./00-setup/check.sh                 # unshare, ip, mount, curl, tar
# alpine rootfs скачается автоматически при первом запуске (нужен интернет)
```

---

## Стартовая проверка

```bash
sed -n '1,9p' ./11-capstone/mycontainer.sh   # шапка: что собирает скрипт
```

---

## Часть 1: Что делает mycontainer

### Теория для изучения перед частью

`mycontainer.sh run [-m MEM] [-c CPU] [-p PIDS] IMAGE -- CMD` по шагам собирает
контейнер из примитивов, каждый — из своего этапа:

| Шаг | Этап | Примитив |
|-----|------|----------|
| overlay (lower=image, upper=rw-слой) | 08 | `mount -t overlay` |
| cgroup v2 с лимитами mem/cpu/pids | 04 | `cgroup.subtree_control` + `*.max` |
| namespaces uts/pid/mnt/ipc | 02 | `unshare --uts --pid --mount --ipc --fork` |
| смена корня в overlay merged | 03 | `pivot_root` + `umount old_root` |
| дроп capabilities (если есть capsh) | 05 | `capsh --drop=all` |
| seccomp-bpf (если есть helper) | 06 | `prctl(PR_SET_SECCOMP)` |
| `exec` команды | — | — |
| уборка: umount overlay, rmdir cgroup | — | — |

---

### 1.1 Запустить контейнер

```bash
sudo ./11-capstone/mycontainer.sh run alpine -- sh -c '
  echo "PID 1:   $(cat /proc/1/comm)"
  echo "hostname:$(hostname)"
  echo "uid:     $(id -u)"
  echo "os:      $(grep ^ID= /etc/os-release)"
  echo "procs:   $(ls -d /proc/[0-9]* | wc -l)"
'
# overlay смонтирован: /var/lib/mycontainer/myc-.../merged
# cgroup создан: /sys/fs/cgroup/mycontainer-myc-...  (mem=128M cpu=50000 100000 pids=64)
# PID 1:   sh             <- PID-ns: наш процесс это PID 1
# hostname:mycontainer    <- UTS-ns: свой hostname
# uid:     0              <- root внутри
# os:      ID=alpine      <- overlay из alpine rootfs
# procs:   4              <- PID-ns изолирован (всего пара процессов)
```

**Контрольные вопросы:**
1. Какие примитивы (и из каких этапов) склеивает `mycontainer.sh`?
2. Почему `procs` внутри = единицы, а не сотни (как на хосте)?
3. Что делает `pivot_root` после overlay-mount?

---

## Часть 2: Главный тезис — pivot_root делает контейнер контейнером

### Теория для изучения перед частью

- В этапе 01 «контейнер» из одного `chroot` дырявый: побег `chroot /proc/1/root`
  выводит на корень хоста (mount-ns общий). `mycontainer` использует `unshare
  --mount` + `pivot_root` + `umount old_root` (этап 03) — старый корень удалён из
  дерева монтирования, и `/proc/1/root` ведёт уже в корень **контейнера**.
- Поэтому тот же побег внутри `mycontainer` остаётся внутри. Это и есть разница
  между chroot-«песочницей» и настоящим контейнером.

---

### 2.1 Побег закрыт (сравните с этапом 01)

```bash
sudo ./11-capstone/mycontainer.sh run alpine -- sh -c '
  echo "мой hostname: $(hostname)"
  echo "chroot /proc/1/root ls /: $(chroot /proc/1/root /bin/sh -c "ls /" | tr "\n" " ")"
'
# мой hostname: mycontainer
# chroot /proc/1/root ls /: bin dev etc home lib ... usr var   <- корень КОНТЕЙНЕРА (alpine), не хоста!
```

Сравните: наивный chroot из этапа 01 на тот же `/proc/1/root` показал бы корень
хоста (`hostname` хоста). Здесь — alpine-корень контейнера: побег закрыт
`pivot_root`. Это разбирается в `broken/scenario-01/`.

**Контрольные вопросы:**
1. Почему в `mycontainer` побег `/proc/1/root` не выводит на хост, а в chroot (01) — выводит?
2. Какие два шага закрывают побег (mount-ns + что ещё)?
3. Что бы вывел `chroot /proc/1/root` в наивном chroot-контейнере?

---

## Часть 3: Лимиты ресурсов и честные ограничения

### Теория для изучения перед частью

- Флаги `-m` (memory.max), `-c` (cpu.max), `-p` (pids.max) вешают cgroup-лимиты
  (этап 04). Процесс помещается в cgroup до `exec` — поэтому хог получает OOM
  **внутри** контейнера, не затрагивая хост.
- **Честно про ограничения** (это не замена Docker): сеть НЕ изолирована (нет
  `--net` → netns хоста); capabilities дропаются только если в rootfs есть `capsh`
  (в alpine-minirootfs его нет → контейнер от full-cap root); нет registry,
  multi-image, journald. Настоящий рантайм (этап 13, `runc`) делает это правильно
  через syscalls, не полагаясь на утилиты в rootfs.

---

### 3.1 Лимит памяти защищает хост

```bash
sudo ./11-capstone/mycontainer.sh run -m 32M alpine -- sh -c 'echo до; tail /dev/zero; echo после'
# до
# Killed              <- хог tail /dev/zero съел 32M → OOM-killer убил ЕГО (не хост)
# после               <- shell пережил (OOM убил самый большой процесс в cgroup)
```

**Контрольные вопросы:**
1. Почему хог получает OOM внутри контейнера, а не роняет хост?
2. Какие изоляции `mycontainer` НЕ делает (сеть, caps) и почему?
3. Чем настоящий `runc` (этап 13) делает дроп caps правильнее, чем наш скрипт?

---

## Часть 4: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ побег /proc/1/root выводит на ХОСТ ──────────► «контейнер» только из chroot, без
│     pivot_root + new mnt-ns. Нужен unshare --mount + pivot_root (Сценарий 01)
├─ остался overlay-mount/cgroup после контейнера ─► процесс упал до уборки (напр.
│     fork-бомба исчерпала pids). Чистка: umount -l /var/lib/mycontainer/*/merged
├─ «не нашёл rootfs» ───────────────────────────► нет alpine (нет интернета при
│     первом запуске) или неверный путь к IMAGE
└─ внутри видны интерфейсы/процессы хоста ───────► не подняли net-ns (mycontainer без
      --net использует netns хоста — это сознательное упрощение)
```

### Инцидент 1: наивный chroot-контейнер дырявый (побег на хост)
Разобран в `broken/scenario-01/` (chroot без pivot_root → escape). Воспроизвести и сравнить:
```bash
sudo ./broken/scenario-01/make-broken.sh        # наивный chroot → побег на ХОСТ
sudo ./solutions/01-pivot-root/fix.sh             # mycontainer (pivot_root) → побег закрыт
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 11-capstone
# --- module: 11-capstone ---
# prepare...
# [OK] alpine rootfs готов; mycontainer.sh на месте
# verify...
# [OK] контейнер запущен: PID 1=sh, hostname=mycontainer, uid=0, os=alpine
# [OK] PID-ns изолирован: внутри мало процессов (4)
# [OK] pivot_root закрыл побег: /proc/1/root → корень контейнера (alpine), не хост
# [OK] уборка чистая: нет overlay-mount и cgroup mycontainer-*
# [OK] module 11-capstone verified
```

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| `mycontainer.sh` | «docker run» из ~150 строк | весь стек 01–10 вместе |
| overlay + cgroup + ns + pivot_root | склейка примитивов | анатомию контейнера |
| побег `/proc/1/root` → alpine | confined | роль pivot_root (vs chroot 01) |
| `-m`/`-c`/`-p` лимиты | cgroup v2 | защиту хоста от контейнера |

---

## Теоретические вопросы (итоговые)
1. Из каких ~8 примитивов (и этапов) состоит `mycontainer.sh`?
2. Почему `pivot_root` + new mnt-ns делают контейнер настоящим, а chroot — нет?
3. Что `mycontainer` НЕ изолирует и почему (сеть, caps в alpine)?
4. Как cgroup-лимит защищает хост от утечки памяти в контейнере?
5. Чем `mycontainer` принципиально отличается от Docker (и в чём совпадает)?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-run-and-inspect.md`** — запустить контейнер, увидеть все изоляции.
2. **`tasks/02-resource-limits.md`** — `-m`/`-p` лимиты, поймать OOM/отказ fork.
3. **`tasks/03-escape-confined.md`** — побег `/proc/1/root` закрыт (vs chroot 01).

Дополнительно:
4. Сравни вывод `mycontainer run alpine sh` и `docker run --rm -it alpine sh` (если есть Docker).
5. Добавь в `mycontainer.sh` поддержку `--net` (veth+bridge из этапа 09) для сетевой изоляции.

---

## Шпаргалка

```bash
# запустить контейнер с лимитами
sudo ./mycontainer.sh run -m 128M -c "50000 100000" -p 64 alpine -- sh

# что внутри (изоляции):
#   cat /proc/1/comm   → sh        (PID-ns)
#   hostname           → mycontainer (UTS-ns)
#   chroot /proc/1/root ls /  → корень alpine, НЕ хост (pivot_root)

# уборка зависшего контейнера (если процесс упал до cleanup):
umount -l /var/lib/mycontainer/*/merged 2>/dev/null; rm -rf /var/lib/mycontainer/*
rmdir /sys/fs/cgroup/mycontainer-* 2>/dev/null
```

---

## Чему вы научились
- Собирать «контейнер» из примитивов ядра одним скриптом — Docker перестаёт быть магией.
- Видеть, что `pivot_root` + mount-ns отличают настоящий контейнер от дырявого chroot.
- Применять cgroup-лимиты, защищающие хост от контейнера (OOM внутри, не снаружи).
- Честно понимать, чего `mycontainer` НЕ делает (сеть, caps) и почему рантаймы сложнее.

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 11-capstone
```

> Дальше — `12-rootless`: контейнер БЕЗ root (user namespace + uid-mapping) — то,
> что делают `podman` и rootless Docker.
