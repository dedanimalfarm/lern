# Лабораторная работа 10: сборка rootfs и systemd-nspawn (нативный runtime)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Собрать rootfs](#-1--rootfs)
  - [Теория для изучения перед частью](#----)
  - [1.1 Скачать alpine minirootfs](#11--alpine-minirootfs)
- [Часть 2: Запустить через systemd-nspawn](#-2---systemd-nspawn)
  - [Теория для изучения перед частью](#----)
  - [2.1 Запуск alpine](#21--alpine)
- [Часть 3: Что nspawn делает за тебя + debootstrap](#-3--nspawn-----debootstrap)
  - [Теория для изучения перед частью](#----)
  - [3.1 (опц.) Собрать Ubuntu-rootfs через debootstrap](#31---ubuntu-rootfs--debootstrap)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: nspawn отказывается — «doesn't look like an OS tree»](#-1-nspawn---doesnt-look-like-an-os-tree)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~40 мин · сложность 3/5 · пререквизиты: 01–09 (весь стек примитивов)

Цель: собрать **настоящий** rootfs (не busybox из этапа 01, а полноценный
дистрибутив) и запустить его через `systemd-nspawn` — нативный «container runtime»
из systemd. nspawn автоматически делает то, что мы 9 этапов собирали руками:
namespaces (UTS/PID/MNT/IPC), монтирование `/proc`/`/sys`/`/dev`, cgroup,
интеграцию с journald. Это «третий путь» между ручным `unshare` и Docker, на тех же
примитивах ядра.

> ⚠️ **Host-only модуль.** На WSL2 нет `systemd-nspawn`/`debootstrap` — `verify/`
> там печатает `[WARN]` и проходит (skip). Все «ожидаемые выводы» сняты на реальном
> Ubuntu-хосте (GCP, systemd PID 1, `systemd-container` + `debootstrap` доставлены).
> Это capstone примитивов 01–09: rootfs (01) + namespaces (02) + pivot_root (03).

---

## Предварительные требования

```bash
sudo ./00-setup/check.sh
ps -p 1 -o comm=                       # systemd — иначе nspawn не запустится
sudo apt-get install -y systemd-container debootstrap   # на хосте (не WSL2)
command -v systemd-nspawn curl tar >/dev/null && echo "инструменты на месте"
```

---

## Стартовая проверка

```bash
systemd-nspawn --version | head -1     # systemd 2xx
```

---

## Часть 1: Собрать rootfs

### Теория для изучения перед частью

- **Готовый minirootfs (быстро):** Alpine публикует tarball ~3 МБ. `curl | tar -xz`
  — и согласованный rootfs готов (musl + busybox + apk, без systemd/локалей —
  отсюда компактность).
- **`debootstrap` (с нуля):** скачивает официальные `.deb`, разрешает зависимости,
  выполняет post-install (локали, dpkg-база) → согласованная Debian/Ubuntu ОС.
  Ручной `cp` дал бы битый mish-mash. Это аналог слоя `FROM debian` в Dockerfile.

---

### 1.1 Скачать alpine minirootfs

```bash
A=/lab/10/alpine; mkdir -p "$A"
URL="https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz"
curl -fsSL "$URL" | tar -xz -C "$A"
du -sh "$A"; find "$A" -type f | wc -l
# 7.7M
# 90
cat "$A/etc/os-release" | grep PRETTY_NAME
# PRETTY_NAME="Alpine Linux v3.19"
```

**Контрольные вопросы:**
1. Чем `debootstrap` лучше ручного `cp -r` для сборки rootfs?
2. Почему alpine minirootfs такой маленький (~3–8 МБ)?
3. Что внутри `.deb`-пакета (data/control)?

---

## Часть 2: Запустить через systemd-nspawn

### Теория для изучения перед частью

- `systemd-nspawn -D <rootfs> -- <cmd>` запускает команду в rootfs, **сам** создавая
  UTS/PID/MNT/IPC namespaces, монтируя `/proc`/`/sys`/`/dev` и настраивая cgroup.
  Внутри процесс — `PID 1`, свой hostname, свой `/etc/os-release`.
- **Важно про сеть:** по умолчанию nspawn **НЕ** изолирует сеть — контейнер видит
  интерфейсы хоста (общий net-ns). Для своей сети добавь `--private-network`
  (пустой стек) или `--network-veth`/`--network-bridge=<br>` (veth в мост, как
  этап 09). Это сознательный дефолт nspawn.

---

### 2.1 Запуск alpine

```bash
systemd-nspawn -q -D "$A" --pipe -- /bin/sh -c '
  echo "os:     $(grep ^PRETTY_NAME= /etc/os-release)"
  echo "PID 1:  $(p=$(cat /proc/1/comm); echo $p)"
  echo "host:   $(hostname)"
  echo "ifaces: $(ip -o link 2>/dev/null | wc -l)"
'
# os:     PRETTY_NAME="Alpine Linux v3.19"
# PID 1:  sh                 <- PID-ns изолирован (наш процесс = PID 1)
# host:   alpine             <- UTS-ns изолирован (≠ hostname хоста)
# ifaces: 7                  <- сеть НЕ изолирована: видим интерфейсы хоста!
```

Сравните `host:` с хостовым `hostname` — отличается (UTS-ns). А `ifaces: 7` — это
интерфейсы ХОСТА: net-ns по умолчанию общий. Добавьте `--private-network` —
останется только `lo`.

**Контрольные вопросы:**
1. Что `systemd-nspawn` делает за тебя из этапов 01–09?
2. Почему `hostname` внутри отличается, а интерфейсов видно 7 (а не 1)?
3. Каким флагом дать контейнеру свою изолированную сеть?

---

## Часть 3: Что nspawn делает за тебя + debootstrap

### Теория для изучения перед частью

- `systemd-nspawn` ≈ `docker run`, но не Docker-совместимый: тот же набор ядерных
  примитивов (namespaces + cgroup + pivot_root), плюс интеграция с journald и
  `machinectl` (`machinectl list`, `--boot` для полноценной загрузки с systemd
  внутри).
- `debootstrap --variant=minbase <suite> <dir> <mirror>` собирает Debian/Ubuntu
  rootfs, в котором работает `apt` — это и есть базовый слой образа.

---

### 3.1 (опц.) Собрать Ubuntu-rootfs через debootstrap

```bash
debootstrap --variant=minbase jammy /lab/10/ubuntu http://archive.ubuntu.com/ubuntu/
systemd-nspawn -q -D /lab/10/ubuntu --pipe -- /bin/sh -c 'grep PRETTY_NAME /etc/os-release; which apt'
# PRETTY_NAME="Ubuntu 22.04 LTS"
# /usr/bin/apt
```

**Контрольные вопросы:**
1. Чем `systemd-nspawn` отличается от связки `unshare … chroot …`?
2. Что добавляет `--boot` (загрузка systemd внутри контейнера)?
3. Почему `debootstrap` даёт рабочий `apt`, а ручной `cp` — нет?

---

## Часть 4: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ «Directory … doesn't look like it has an OS tree. Refusing.» ─► rootfs пустой/
│     неполный (нет /usr/lib/os-release, /etc/os-release, /bin). Собери настоящий
│     rootfs (alpine/debootstrap) (Сценарий 01)
├─ «Failed to … No such file or directory» на /bin/sh ──────────► rootfs без шелла
│     или не та арка. Проверь ls <rootfs>/bin
├─ внутри nspawn видны интерфейсы хоста ────────────────────────► это НЕ баг: net-ns
│     общий по умолчанию. Добавь --private-network для изоляции
└─ «Failed to register machine: … already exists» ─────────────► прошлый контейнер
      ещё зарегистрирован: machinectl terminate <name>, или запускай с --register=no
```

### Инцидент 1: nspawn отказывается — «doesn't look like an OS tree»
Разобран в `broken/scenario-01/` (запуск на пустом каталоге). Воспроизвести и починить:
```bash
sudo ./broken/scenario-01/make-broken.sh        # пустой каталог → Refusing
sudo ./solutions/01-proper-rootfs/fix.sh          # настоящий rootfs → запускается
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 10-rootfs-and-nspawn
# --- module: 10-rootfs-and-nspawn ---
# prepare...
# [OK] alpine minirootfs готов: /lab/10-nspawn/alpine
# verify...
# [OK] rootfs запущен через systemd-nspawn: ID=alpine
# [OK] PID-ns изолирован: PID 1 внутри = sh
# [OK] UTS-ns изолирован: hostname внутри = 'alpine' (host = '...')
# [OK] module 10-rootfs-and-nspawn verified
```

На хосте без `systemd-nspawn` (WSL2) `verify/` печатает `[WARN]` и проходит (skip).
Полное демо (alpine + опц. debootstrap) — `sudo ./run.sh` / `WITH_DEBOOTSTRAP=1 sudo ./run.sh`.

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| alpine minirootfs | готовый rootfs (~8 МБ) | `docker pull alpine` |
| `debootstrap` | сборка Debian/Ubuntu rootfs | слой `FROM debian` |
| `systemd-nspawn -D` | нативный runtime | `docker run -it alpine sh` |
| PID 1 = sh, своя hostname | авто-namespaces | работа этапов 02–03 «из коробки» |
| `--private-network` | изоляция сети (опц.) | `--network=none`/veth (этап 09) |

---

## Теоретические вопросы (итоговые)
1. Чем `systemd-nspawn` отличается от ручного `unshare … pivot_root … chroot`?
2. Почему сеть в nspawn по умолчанию НЕ изолирована и как это изменить?
3. Чем `debootstrap` лучше ручного копирования для сборки rootfs?
4. Что значит «doesn't look like an OS tree» и как это чинится?
5. Как `systemd-nspawn --boot` соотносится с «настоящим» контейнером с systemd внутри?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-build-rootfs.md`** — скачать alpine minirootfs, проверить целостность.
2. **`tasks/02-nspawn-run.md`** — запустить через nspawn, увидеть изоляцию PID/UTS.
3. **`tasks/03-private-network.md`** — `--private-network`: пустой сетевой стек внутри.

Дополнительно:
4. `WITH_DEBOOTSTRAP=1 sudo ./run.sh` — собери Ubuntu-rootfs и запусти `apt` внутри.
5. `systemd-nspawn --boot -D <rootfs>` на debootstrap-rootfs с systemd — загрузи «полную» ОС.

---

## Шпаргалка

```bash
# === rootfs ===
A=/lab/10/alpine; mkdir -p "$A"
curl -fsSL https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-minirootfs-3.19.1-x86_64.tar.gz | tar -xz -C "$A"
debootstrap --variant=minbase jammy /lab/10/ubuntu http://archive.ubuntu.com/ubuntu/   # Debian/Ubuntu

# === запуск ===
systemd-nspawn -q -D "$A" --pipe -- /bin/sh -c '<cmd>'    # команда в rootfs
systemd-nspawn --private-network -D "$A" -- /bin/sh       # + изоляция сети
systemd-nspawn --network-veth -D "$A" -- /bin/sh          # veth наружу
systemd-nspawn --boot -D <rootfs>                          # загрузить systemd внутри
machinectl list                                            # запущенные контейнеры
```

---

## Чему вы научились
- Собирать настоящий rootfs: готовый alpine minirootfs и `debootstrap` (Debian/Ubuntu).
- Запускать его через `systemd-nspawn`, который сам делает namespaces/mounts/cgroup.
- Понимать, что nspawn по умолчанию НЕ изолирует сеть (`--private-network` для этого).
- Видеть `systemd-nspawn` как «третий путь» между ручным `unshare` и Docker.

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 10-rootfs-and-nspawn
```

> Дальше — `11-capstone`: собираем «свой Docker» из ~150 строк bash, склеивая всё,
> что прошли (rootfs + namespaces + pivot_root + cgroups + caps + seccomp + veth).
