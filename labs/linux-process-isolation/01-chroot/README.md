# Лабораторная работа 01: chroot — первая (и дырявая) изоляция файловой системы

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Минимальный rootfs и вход в chroot](#-1--rootfs----chroot)
  - [Теория для изучения перед частью](#----)
  - [1.1 Собрать rootfs и войти](#11--rootfs--)
- [Часть 2: Что chroot НЕ изолирует](#-2--chroot--)
  - [Теория для изучения перед частью](#----)
  - [2.1 PID, UTS, сеть, mount-ns — всё хостовое](#21-pid-uts--mount-ns---)
- [Часть 3: Классический побег через /proc/1/root](#-3----proc1root)
  - [Теория для изучения перед частью](#----)
  - [3.1 Сбежать в корень хоста](#31----)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: «No such file or directory» на существующем бинаре](#-1-no-such-file-or-directory---)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~25 мин · сложность 2/5 · пререквизиты: 00-setup, базовый bash/mount

Цель: понять самый старый механизм изоляции в Unix — `chroot(2)` (1979). Собрать
минимальный rootfs **руками** из статического `busybox`, войти в него и на числах
увидеть две вещи сразу: что `chroot` изолирует (видимый корень файловой системы) и
что он НЕ изолирует (PID, UTS, сеть, mount-namespace), а главное — что он **не
держит периметр**: классический побег через `/proc/1/root` выводит root наружу.

> Это первый слой «контейнера». Docker не использует чистый `chroot` — он
> распаковывает слои образа и делает `pivot_root` в новом mount-namespace (этап
> `03-pivot-root`), именно потому что побег ниже слишком тривиален. Все
> «ожидаемые выводы» сняты на этом хосте (WSL2, ядро 6.6, `busybox` 1.37,
> hostname `DESKTOP-2NEPKQQ`) — у вас имена/числа будут свои, важна **структура**
> вывода, а не конкретные значения.

---

## Предварительные требования

```bash
# нужен НАСТОЯЩИЙ root и статический busybox (ставит 00-setup)
sudo ./00-setup/check.sh          # busybox, util-linux, chroot — на месте?
id -u                             # 0 — иначе ничего не смонтируется

busybox 2>&1 | head -1            # BusyBox v1.37.0 ... (версия у вас своя)
```

Если чего-то нет — `sudo ./00-setup/install.sh` (Ubuntu/Debian).

---

## Стартовая проверка

```bash
command -v busybox chroot unshare >/dev/null && echo "инструменты на месте"
# инструменты на месте
```

---

## Часть 1: Минимальный rootfs и вход в chroot

### Теория для изучения перед частью

- **`chroot(2)`** меняет видимый **корневой каталог** процесса (и его потомков):
  после вызова путь `/` указывает на заданный каталог, а не на корень хоста. Это
  изолирует **только файловую систему** — точку отсчёта путей. Больше ничего.
- **Почему статический `busybox`.** Это один бинарь-«швейцарский нож» (multi-call):
  по имени, под которым его позвали (`sh`, `ls`, `cat` — через симлинки), он
  выполняет нужный апплет. Статический — значит без внешних `.so`, поэтому внутри
  голого rootfs он работает сразу, без копирования библиотек (ловушку с
  динамическим бинарём разбираем в Части 4).
- **Зачем монтировать `/proc`, `/sys`, `/dev`.** `chroot` не наполняет rootfs —
  без `/dev/null` многие программы падают на старте, без `/proc` не работают `ps`
  и чтение `/proc/self/*`, `/sys` нужен для cgroup/hardware-инфы. Это ровно то,
  что рантайм контейнера прокидывает в каждый контейнер.

---

**Цель:** собрать rootfs и войти; убедиться, что внутри виден свой корень.

**Скрипт:** `verify/prepare.sh` собирает rootfs в `/lab/01-chroot/rootfs`
(busybox + симлинки-апплеты + примонтированные `/proc`,`/sys`,`/dev`).

---

### 1.1 Собрать rootfs и войти

```bash
sudo ./verify/prepare.sh
# [OK] rootfs готов: /lab/01-chroot/rootfs (busybox + /proc,/sys,/dev)

sudo chroot /lab/01-chroot/rootfs /bin/sh -c 'ls / ; echo "---"; cat /etc/hostname'
# bin
# dev
# etc
# proc
# root
# sys
# tmp
# ---
# chroot-jail        <- наш /etc/hostname из rootfs, не хостовый
```

Корень сменился: внутри виден ровно тот каталог, что мы собрали. Файловая
система изолирована — это и есть весь эффект `chroot`.

**Контрольные вопросы:**
1. Что именно меняет `chroot(2)` для процесса — и что остаётся прежним?
2. Почему для учебного rootfs берут *статический* busybox, а не `/bin/bash`?
3. Зачем внутрь rootfs монтируют `/proc`, `/dev`, `/sys`?

---

## Часть 2: Что chroot НЕ изолирует

### Теория для изучения перед частью

- `chroot` НЕ создаёт ни одного нового **namespace**. Значит PID, UTS (hostname),
  сеть, IPC, пользователи и **mount-namespace** у процесса остаются **хостовыми**.
- Самое честное доказательство — **inode kernel-namespace**. У каждого namespace
  есть свой inode под `/proc/<pid>/ns/<тип>`. Ядро гарантирует: процессы в РАЗНЫХ
  namespace имеют РАЗНЫЕ inode, в одном — одинаковые. Сравним inode внутри chroot
  и на хосте: если совпадают — изоляции нет.

---

**Цель:** на числах показать, что PID/UTS/NET/mount-ns — общие с хостом.

---

### 2.1 PID, UTS, сеть, mount-ns — всё хостовое

```bash
# UTS: hostname внутри == хостовому (UTS-namespace общий)
hostname
# DESKTOP-2NEPKQQ
sudo chroot /lab/01-chroot/rootfs /bin/hostname
# DESKTOP-2NEPKQQ            <- тот же

# Namespace-inode внутри и снаружи — совпадают ⇒ это ОДИН namespace
for ns in mnt pid net; do
  printf "%-4s host=%s  chroot=%s\n" "$ns" \
    "$(stat -L -c %i /proc/self/ns/$ns)" \
    "$(sudo chroot /lab/01-chroot/rootfs /bin/stat -L -c %i /proc/self/ns/$ns)"
done
# mnt  host=4026532219  chroot=4026532219     <- РАВНЫ
# pid  host=4026532221  chroot=4026532221     <- РАВНЫ
# net  host=4026531840  chroot=4026531840     <- РАВНЫ
```

```bash
# Процессы и сеть — тоже хостовые
sudo chroot /lab/01-chroot/rootfs /bin/ps | head -3
# PID   USER     COMMAND
#     1 root     {systemd} /sbin/init      <- видим init хоста, не «свой» PID 1
#     2 root     {init-systemd} /init
sudo chroot /lab/01-chroot/rootfs /bin/sh -c 'ls /sys/class/net'
# br-35074dfe6a0c  docker0  eth0  lo        <- хостовые интерфейсы
```

Вывод: чтобы изолировать PID/UTS/NET, `chroot` мало — нужны **namespaces**
(этап `02-namespaces`).

**Контрольные вопросы:**
1. Почему равенство inode `/proc/self/ns/mnt` доказывает отсутствие изоляции маунтов?
2. Какой PID видит процесс внутри chroot для системного `init` — 1 или хостовый?
3. Что нужно добавить к chroot, чтобы внутри был свой hostname и свой PID 1?

---

## Часть 3: Классический побег через /proc/1/root

### Теория для изучения перед частью

- `/proc/<pid>/root` — это **magic-symlink** ядра на корневой каталог процесса
  `<pid>` в его mount-namespace. Для PID 1 это корень `init`.
- Так как `chroot` **не** создал новый mount-namespace (Часть 2), `/proc/1/root`
  указывает на корень **хоста**. Имея root внутри chroot и доступ к `/proc`,
  достаточно одного `chroot /proc/1/root` — и ты в корне хоста.
- Поэтому `chroot` — НЕ граница безопасности. Это исторический факт, из-за
  которого появились namespaces и `pivot_root`.

---

**Цель:** выйти из «тюрьмы» в корень хоста и прочитать хостовый файл.

---

### 3.1 Сбежать в корень хоста

```bash
ls -l /proc/1/root
# lrwxrwxrwx 1 root root 0 ... /proc/1/root -> /     <- симлинк на корень PID 1 (хост)

sudo chroot /lab/01-chroot/rootfs /bin/sh -c '
  echo "я в chroot, мой /etc/hostname: $(cat /etc/hostname)"
  chroot /proc/1/root /bin/sh -c "echo сбежал; hostname; head -1 /etc/os-release"
'
# я в chroot, мой /etc/hostname: chroot-jail
# сбежал
# DESKTOP-2NEPKQQ                      <- hostname ХОСТА
# PRETTY_NAME="Ubuntu ..."             <- читаем хостовый /etc/os-release
```

> Защита приходит на этапе `03-pivot-root`: после `pivot_root` в новом
> mount-namespace `/proc/1/root` ведёт уже в новый корень, и побег закрывается.
> До тех пор любой root в chroot = root на хосте.

**Контрольные вопросы:**
1. На что указывает `/proc/1/root` и почему именно на корень хоста?
2. Какие три условия делают побег возможным (права, /proc, mount-ns)?
3. Как `pivot_root` в новом mount-ns закрывает эту дыру?

---

## Часть 4: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ «chroot: failed to run command … No such file or directory»,
│   хотя бинарь ВИДЕН в rootfs ─────► динамический бинарь без своих .so/загрузчика
│      Проверь: ldd <бинарь> — все ли пути есть ВНУТРИ rootfs? (Сценарий 01)
├─ внутри chroot «command not found» на ls/ps ──► нет симлинка-апплета на busybox
│      или не примонтирован /proc (для ps). Проверь bin/ и mount | grep rootfs
├─ программа падает «cannot open /dev/null» ─────► не примонтирован /dev в rootfs
└─ процесс из chroot читает хостовые файлы ──────► это НЕ баг: chroot не песочница
       (Часть 3). Лечится сменой на pivot_root + new mnt-ns (этап 03)
```

### Инцидент 1: «No such file or directory» на существующем бинаре
Разобран в `broken/scenario-01/` (динамический `bash` в rootfs без библиотек →
обманчивый `ENOENT`). Воспроизвести и починить:
```bash
sudo ./broken/scenario-01/make-broken.sh     # ловушка: bash без .so → ошибка
sudo ./solutions/01-missing-libs/fix.sh       # фикс: докопировать .so по ldd → inside-OK
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 01-chroot
# --- module: 01-chroot ---
# prepare...
# [OK] rootfs готов: /lab/01-chroot/rootfs (busybox + /proc,/sys,/dev)
# verify...
# [OK] ФС изолирована: /etc/hostname внутри = 'chroot-jail'
# [OK] UTS общий: hostname внутри = host = 'DESKTOP-2NEPKQQ'
# [OK] mnt-ns общий: inode внутри = host = 4026532219
# [OK] побег /proc/1/root работает — chroot это НЕ песочница (защита — этап 03)
# [OK] module 01-chroot verified
# [OK] cleanup 01-chroot
```

`run-module.sh` сам делает `prepare → verify → cleanup` (cleanup — через trap,
отрабатывает даже при падении). Хочешь посмотреть пошаговую демонстрацию с
пояснениями — `sudo ./run.sh`.

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| `/lab/01-chroot/rootfs` | минимальный rootfs (busybox + /etc) | изоляцию **видимого корня** ФС |
| `/proc`,`/sys`,`/dev` в rootfs | примонтированные псевдо-ФС | что rootfs нужно наполнять руками |
| inode `/proc/self/ns/*` | mnt/pid/net namespace | что chroot НЕ создаёт namespace (общие с хостом) |
| `/proc/1/root` | magic-symlink на корень PID 1 | классический побег из chroot |

---

## Теоретические вопросы (итоговые)
1. В чём разница между `chroot` и mount-namespace по тому, *что* изолируется?
2. Почему через `/proc/1/root` можно сбежать, и какие три условия для этого нужны?
3. Три способа защититься от побега (права, /proc, pivot_root) — как работает каждый?
4. Зачем в rootfs монтируют `/proc`, `/dev`, `/sys` и что сломается без каждого?
5. Почему «No such file or directory» на заведомо существующем бинаре — это про библиотеки?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-build-rootfs.md`** — собрать rootfs и войти, увидеть свой корень.
2. **`tasks/02-prove-shared.md`** — доказать на inode, что PID/UTS/NET/mnt-ns общие.
3. **`tasks/03-escape.md`** — выполнить побег через `/proc/1/root`.

Дополнительно:
4. Запусти chroot с `--userspec=nobody:nogroup` и повтори побег — почему теперь не выходит?
5. Не монтируй `/proc` в rootfs и попробуй сбежать — что сломалось у атакующего?

---

## Шпаргалка

```bash
# === Собрать rootfs из статического busybox ===
ROOT=/lab/01-chroot/rootfs
install -d "$ROOT"/{bin,etc,proc,sys,dev}
cp "$(command -v busybox)" "$ROOT/bin/"
for a in sh ls cat ps stat hostname; do ln -sf busybox "$ROOT/bin/$a"; done
mount --rbind /dev "$ROOT/dev"; mount -t proc proc "$ROOT/proc"; mount -t sysfs sys "$ROOT/sys"
chroot "$ROOT" /bin/sh

# === Доказать (не)изоляцию ===
stat -L -c %i /proc/self/ns/mnt            # inode host
chroot "$ROOT" /bin/stat -L -c %i /proc/self/ns/mnt   # совпал ⇒ тот же mnt-ns

# === Классический побег ===
chroot "$ROOT" /bin/sh -c 'chroot /proc/1/root /bin/sh'   # вышли в корень хоста

# === Диагностика «No such file or directory» ===
ldd /path/to/binary                        # все ли .so есть внутри rootfs?

# === Уборка ===
umount -R "$ROOT"/{proc,sys,dev}; rm -rf /lab/01-chroot
```

---

## Чему вы научились
- Собирать минимальный rootfs из статического `busybox` и входить в него `chroot`.
- Понимать, что `chroot` изолирует **только** видимый корень ФС, а PID/UTS/NET/
  mount-ns остаются хостовыми — и доказывать это через inode `/proc/self/ns/*`.
- Выполнять классический chroot-escape через `/proc/1/root` и объяснять, почему
  `chroot` — не граница безопасности.
- Диагностировать ловушку динамического бинаря без библиотек (`ldd`).

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 01-chroot
```

> Дальше — `02-namespaces`: добавляем недостающую изоляцию (UTS/PID/MNT/NET/USER/
> IPC), а затем `03-pivot-root` закрывает побег из этого модуля.
