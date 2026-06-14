# Лабораторная работа 13: OCI и runc — эталонный рантайм под капотом Docker

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: OCI-bundle и config.json](#-1-oci-bundle--configjson)
  - [Теория для изучения перед частью](#----)
  - [1.1 Собрать bundle и сгенерировать config.json](#11--bundle---configjson)
- [Часть 2: Запуск через runc run](#-2---runc-run)
  - [Теория для изучения перед частью](#----)
  - [2.1 Запустить контейнер](#21--)
- [Часть 3: Жизненный цикл и связь с Docker](#-3------docker)
  - [Теория для изучения перед частью](#----)
  - [3.1 Пошаговый запуск](#31--)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: `runc run failed: open /dev/tty` (terminal=true без tty)](#-1-runc-run-failed-open-devtty-terminaltrue--tty)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~35 мин · сложность 3/5 · пререквизиты: 01–12 (весь стек), 10 (rootfs)

Цель: запустить контейнер через **runc** — низкоуровневый OCI-совместимый рантайм,
который и стоит под Docker/containerd. После того как мы собирали контейнер руками
(этап 11), посмотрим, как это делает стандарт: контейнер = **OCI-bundle** (каталог
`rootfs/` + `config.json`), а `runc run` читает конфиг и поднимает namespaces,
cgroups, capabilities, seccomp — всё, что мы разбирали по этапам, описано декларативно.

> Финальная связка: то, что в этапе 11 было ~150 строк bash, здесь — один
> `config.json` + `runc`. runc есть и на WSL2, и на хосте — выводы сняты на WSL2
> (runc 1.2.5). Docker не запускает контейнеры сам: containerd → runc → ядро.

---

## Предварительные требования

```bash
sudo ./00-setup/check.sh            # runc, curl, tar, python3
runc --version | head -1            # runc version 1.x
```

---

## Стартовая проверка

```bash
command -v runc python3 >/dev/null && echo "runc на месте"
```

---

## Часть 1: OCI-bundle и config.json

### Теория для изучения перед частью

- **OCI-bundle** — это всё, что нужно рантайму: каталог `rootfs/` (файловая система
  контейнера) и **`config.json`** (OCI runtime spec) — декларативное описание
  процесса, namespaces, cgroups, capabilities, mounts, seccomp.
- `runc spec` генерирует дефолтный `config.json`. В нём по умолчанию 6 namespaces
  (как у Docker, БЕЗ user-ns), дроп capabilities, монтирование `/proc`/`/sys`/`/dev`.
- Стандарт OCI разделил «что такое контейнер» (image-spec, runtime-spec) от
  конкретного движка — поэтому Docker, podman, containerd работают одинаково.

---

### 1.1 Собрать bundle и сгенерировать config.json

```bash
B=/lab/13/bundle; mkdir -p "$B/rootfs"
# rootfs из alpine: static musl /bin/sh работает в минимальном контейнере
# (динамический busybox упал бы без загрузчика/libc — как в этапе 01)
URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz"
curl -fsSL "$URL" | tar -xz -C "$B/rootfs"
cd "$B" && runc spec                                  # создаёт config.json

python3 -c "import json;print(', '.join(n['type'] for n in json.load(open('config.json'))['linux']['namespaces']))"
# pid, network, ipc, uts, mount, cgroup      <- 6 namespaces (как docker, без user)
```

**Контрольные вопросы:**
1. Что такое OCI-bundle (из чего состоит)?
2. Что описывает `config.json` и кто его генерирует?
3. Какие namespaces включены по умолчанию и какого нет (в отличие от rootless)?

---

## Часть 2: Запуск через runc run

### Теория для изучения перед частью

- `runc run <id>` берёт bundle (cwd или `-b <dir>`), применяет `config.json` и
  запускает `process.args` как PID 1 контейнера. Это ровно то, что делает Docker
  при `docker run` — только без демона и образов.
- **Нюанс:** дефолтный `config.json` имеет `process.terminal: true` — для запуска
  без интерактивного tty его нужно выставить в `false` (Часть 4, Сценарий 01).

---

### 2.1 Запустить контейнер

```bash
# правим config.json: terminal=false и своя команда
python3 -c "
import json; d=json.load(open('config.json'))
d['process']['terminal']=False
d['process']['args']=['/bin/sh','-c','echo PID1=\$(cat /proc/1/comm); hostname; id -u']
json.dump(d, open('config.json','w'))
"
runc run demo
# PID1=sh        <- наш процесс это PID 1 (PID-ns из config)
# runc           <- hostname контейнера (UTS-ns)
# 0              <- uid 0 внутри
runc delete demo 2>/dev/null
```

**Контрольные вопросы:**
1. Что `runc run` делает с `config.json` и `rootfs`?
2. Почему PID 1 внутри — это наш процесс, а hostname отличается?
3. Чем `runc run` отличается от `docker run` (демон, образы)?

---

## Часть 3: Жизненный цикл и связь с Docker

### Теория для изучения перед частью

- runc умеет не только `run`, но и пошаговый жизненный цикл: `runc create <id>`
  (создать, процесс ждёт) → `runc start <id>` (запустить) → `runc state <id>`
  (статус/PID) → `runc list` (все контейнеры) → `runc kill`/`runc delete`.
- **Где это в Docker:** `docker run` → dockerd → **containerd** (управляет образами/
  жизненным циклом) → **containerd-shim** → **runc** (создаёт контейнер из bundle и
  выходит). runc — «исполнитель», containerd — «менеджер».

---

### 3.1 Пошаговый запуск

```bash
runc create demo2          # создан, процесс ждёт старта
runc state demo2 | python3 -c "import json,sys;d=json.load(sys.stdin);print('status:',d['status'],'pid:',d['pid'])"
# status: created pid: <N>
runc start demo2           # запустить
runc list                  # NAME demo2 STATUS ...
runc delete --force demo2
```

**Контрольные вопросы:**
1. Чем `runc create` + `runc start` отличается от `runc run`?
2. Где runc в цепочке `docker run` (containerd/shim)?
3. Что показывает `runc state` (статус и PID на хосте)?

---

## Часть 4: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ runc run failed: open /dev/tty: no such device or address ─► process.terminal=true
│     без интерактивного tty. Выставь terminal=false в config.json (Сценарий 01)
├─ exec "/bin/sh": no such file (хотя симлинк есть) ─────────► rootfs без рабочего
│     шелла: динамический busybox без libc/загрузчика. Бери static rootfs (alpine)
├─ container ... already exists ────────────────────────────► прошлый не удалён:
│     runc delete --force <id> (или runc list)
└─ writing to readonly / permission ────────────────────────► root.readonly=true в
      config.json; поставь false, если нужна запись в rootfs
```

### Инцидент 1: `runc run failed: open /dev/tty` (terminal=true без tty)
Разобран в `broken/scenario-01/` (дефолтный `terminal: true`). Воспроизвести и починить:
```bash
sudo ./broken/scenario-01/make-broken.sh        # terminal=true без tty → /dev/tty error
sudo ./solutions/01-terminal-false/fix.sh         # terminal=false → runc run работает
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 13-oci-runc
# --- module: 13-oci-runc ---
# prepare...
# [OK] OCI-bundle готов: /lab/13-runc/bundle (rootfs + config.json, terminal=false)
# verify...
# [OK] runc run: контейнер отработал из OCI-bundle
# [OK] изоляция: PID 1=sh, hostname=runc (namespaces из config.json)
# [OK] внутри uid=0 (root в контейнере)
# [OK] config.json описывает namespaces: pid network ipc uts mount cgroup
# [OK] module 13-oci-runc verified
```

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| OCI-bundle (`rootfs/` + `config.json`) | стандарт контейнера | image/runtime-spec OCI |
| `runc spec` | генерация config.json | декларативное описание изоляции |
| `runc run` | запуск контейнера | `docker run` под капотом |
| `runc create/start/state/list/delete` | жизненный цикл | управление контейнером |
| `config.json` namespaces | pid/net/ipc/uts/mount/cgroup | этапы 02–09 декларативно |

---

## Теоретические вопросы (итоговые)
1. Что такое OCI-bundle и зачем нужен стандарт OCI?
2. Что описывает `config.json` (namespaces/caps/mounts)?
3. Где runc в цепочке `docker run` (dockerd→containerd→shim→runc)?
4. Зачем `process.terminal=false` при неинтерактивном запуске?
5. Чем `runc` отличается от нашего `mycontainer.sh` (этап 11)?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-build-bundle.md`** — собрать bundle, сгенерировать `config.json`.
2. **`tasks/02-runc-run.md`** — запустить контейнер через `runc run`, увидеть изоляцию.
3. **`tasks/03-lifecycle.md`** — `runc create/start/state/list/delete`.

Дополнительно:
4. Поменяй в `config.json` `hostname` и добавь свой `mount` — проверь, что они применились.
5. Сравни список namespaces в `config.json` с тем, что делает `docker inspect` контейнера.

---

## Шпаргалка

```bash
# === bundle (rootfs со static /bin/sh — alpine) ===
mkdir -p bundle/rootfs
curl -fsSL <alpine-minirootfs-url> | tar -xz -C bundle/rootfs
cd bundle && runc spec                     # → config.json

# === правка config.json (terminal + команда) ===
# process.terminal=false; process.args=["/bin/sh","-c","..."]

# === запуск ===
runc run <id>                              # одной командой
runc create <id>; runc start <id>          # по шагам
runc state <id>; runc list                 # статус
runc delete --force <id>                   # удалить

# Docker под капотом: dockerd → containerd → shim → runc
```

---

## Чему вы научились
- Понимать OCI-bundle (`rootfs/` + `config.json`) и стандарт OCI runtime-spec.
- Запускать контейнер через эталонный `runc` без Docker-демона.
- Видеть в `config.json` те же namespaces/cgroups/caps, что собирали по этапам.
- Знать место runc в цепочке `docker run` (containerd → shim → runc).

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 13-oci-runc
```

> Дальше — `14-ebpf`: наблюдаемость изоляции через eBPF (трассировка syscalls/
> событий контейнера). Host-only: на WSL2 нет `bpftrace`.
