# Лабораторная работа: **chroot** и изоляция процессов

> Цель: на практике показать, **что именно изолирует `chroot`** (только файловую
> систему), и как дополнять его **namespaces** (PID/UTS/MNT) и **cgroups v2**
> для получения контейнероподобной среды. Все шаги линейные, без альтернатив.
> Каждый шаг снабжён теоретическим обоснованием «почему так» и проверками.

---

## Где проводилось тестирование

Лабораторная работа полностью прогнана на:

- **Облако:** AWS,
- **Инстанс:** тип `t3.micro` (2 vCPU, 1 GiB RAM, 8 GiB gp3).
- - **ОС:** **Amazon Linux 2023**, ядро 6.1.x.

- **Облако:** Azure, регион **northeurope**.
- **Инстанс:** `lab-chroot-vm`, тип `Standard_D2s_v3` (2 vCPU, 8 GiB RAM).
- **ОС:** **Ubuntu 22.04.5 LTS**, ядро 5.15.x.

> **Внимание:** изначально лаба была написана для Debian/Ubuntu и пакетного
> менеджера `apt`. На Amazon Linux 2023 потребовались адаптации:
> 1. В репозиториях AL2023 **нет** пакета `busybox` / `busybox-static` —
>    качаем upstream-бинарник с `busybox.net` (статический, musl).
> 2. На хосте `/proc/sys/fs/binfmt_misc` смонтирован `autofs` от `systemd-1`
>    поверх `/proc` с `shared`-пропагацией. Это ломает `unshare --mount-proc=…` —
>    запускаем `unshare … --propagation=private` и монтируем `proc` вручную
>    уже **внутри** chroot.
> 3. Лимиты cgroup внутри chroot **не видны** при обычном `mount -t sysfs …`:
>    sysfs пустой, а cgroup2 хоста туда не «просачивается». Нужен явный
>    `mount --rbind /sys/fs/cgroup $ROOT/sys/fs/cgroup` с хоста.
> 4. У `systemctl show` свойство называется **`CPUQuotaPerSecUSec`**, а не
>    `CPUQuota` — последнее в выводе всегда пустое.
>
> В шагах ниже жёлтым выделены AL2023-варианты команд; для Debian/Ubuntu
> остаются исходные. Всё, что не выделено, работает одинаково на обоих
> семействах.

---

## 0. Среда, риски и подготовка

**Зачем:** `chroot` не является границей безопасности. С root‑правами и доступом к `/proc` можно выйти к корню хоста через `/proc/1/root`. Делайте работу **на тестовой ВМ**.

**Требования (Debian/Ubuntu):**

```bash
sudo apt update && sudo apt install -y busybox-static procps util-linux strace vim
```

**Требования (Amazon Linux 2023 / RHEL-like):**

```bash
sudo dnf install -y procps-ng util-linux strace vim-enhanced
# busybox в репах нет — берём upstream-статик-бинарник:
curl -fsSL -o /tmp/busybox \
  https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox
chmod +x /tmp/busybox
sudo install -m 0755 /tmp/busybox /usr/local/bin/busybox
# проверка: должно быть "statically linked"
/usr/local/bin/busybox sh -c 'echo busybox-ok'
```

* `busybox-static` — статически слинкованный бинарник, позволит собрать минимальный rootfs без зависимостей.
* `procps` / `procps-ng` — `ps` и др. утилиты для наблюдения процессов.
* `util-linux` — `unshare`, `mount` и прочие базовые инструменты.
* `strace` — наблюдение системных вызовов (`chroot(2)`).
* `vim` — правка конфигов (по требованию: **используем `vim`, не `nano`**).

**Переменные окружения и каталоги:**

```bash
export ROOT=/lab/chroot/rootfs
sudo mkdir -p "$ROOT"
```

---

## 1. Теория: что делает `chroot`

* `chroot(2)` меняет **root directory** процесса — точку, откуда VFS начинает путь `/`. После этого все абсолютные пути резолвятся относительно нового корня.
* `chroot` **не изолирует** PID‑пространство, сеть, IPC, hostname (UTS), пользователей и cgroups. Это **операционная изоляция файловой системы**, а не sandbox.
* Типичный приём — после `chroot` выполнить `chdir("/")` (инструменты `chroot(1)` делают это за нас).
* В отличие от `pivot_root(2)` `chroot` не меняет само дерево монтирования процесса — только точку отсчёта путей.

Практические последствия: внутри простого `chroot` вы видите процессы/hostname/сеть хоста.

---

## 2. Сборка минимального rootfs (BusyBox static)

**Почему так:** статический BusyBox работает без динамических либ; минимальный и надёжный старт.

Создадим структуру каталогов и откроем `tmp` как общедоступный:

```bash
sudo install -d -m 0755 "$ROOT"/{bin,sbin,etc,proc,sys,dev,usr/bin,usr/sbin,root,tmp,var/{log,run,lib},home}
sudo chmod 1777 "$ROOT"/tmp
```

Скопируем BusyBox и создадим аплеты‑ссылки.

**Debian/Ubuntu:**

```bash
sudo cp /bin/busybox "$ROOT"/bin/
```

**Amazon Linux 2023:**

```bash
sudo cp /usr/local/bin/busybox "$ROOT"/bin/
```

```bash
cd "$ROOT"/bin
for app in sh ash ls cat echo ps mount umount uname vi readlink id hostname \
           grep cut head sleep mkdir rm chroot tr find printf od; do
    sudo ln -sf busybox "$app"
done
```

> **Важно:** в исходной версии лабы список аплетов был короче. На практике
> внутри chroot вызываются `tr`, `find`, `printf` (диагностические
> скрипты в §8) — без симлинков получите `tr: not found`. Список выше
> покрывает все шаги.

Базовые файлы в `/etc`:

```bash
sudo vim "$ROOT"/etc/passwd
```

Вставьте:

```
root:x:0:0:root:/root:/bin/sh
nobody:x:65534:65534:nobody:/:/bin/sh
```

```bash
sudo vim "$ROOT"/etc/group
```

```
root:x:0:
nogroup:x:65534:
```

```bash
sudo vim "$ROOT"/etc/hostname
```

```
chroot-lab
```

```bash
sudo vim "$ROOT"/etc/hosts
```

```
127.0.0.1   localhost
127.0.1.1   chroot-lab
```

*(Опционально для DNS внутри chroot — если нужны сетевые утилиты):*

```bash
sudo cp /etc/resolv.conf "$ROOT"/etc/resolv.conf
```

**Обоснование:** многие программы ожидают базовые записи о пользователях/группах и hostname; `resolv.conf` нужен для резолвинга имён.

---

## 3. Подключаем псевдо‑ФС внутрь rootfs (dev/proc/sys)

**Почему так:**

* `/dev` — устройства (`/dev/null`, tty и др.) — без них часть программ не стартует.
* `/proc`, `/sys` — интерфейсы ядра, нужны, чтобы `ps`, `mount`, `ip` и пр. корректно работали.

Монтируем с безопасной пропагацией:

```bash
sudo mount --rbind /dev  "$ROOT"/dev
sudo mount --make-rslave "$ROOT"/dev
sudo mount -t proc  proc  "$ROOT"/proc
sudo mount -t sysfs sys   "$ROOT"/sys
```

**Дополнительно для AL2023 (нужно в §8 для cgroups v2):**

```bash
sudo mount --rbind /sys/fs/cgroup "$ROOT"/sys/fs/cgroup
sudo mount --make-rslave           "$ROOT"/sys/fs/cgroup
```

**Почему `--make-rslave`:** события монтирования с хоста видны внутри, но обратной пропагации из chroot наружу не будет — безопаснее для эксперимента.

Проверка:

```bash
mount | egrep "$ROOT/(dev|proc|sys)"
```

---

## 4. Вход в `chroot` и проверка границ изоляции

```bash
sudo chroot "$ROOT" /bin/sh
```

Проверим и интерпретируем:

```sh
echo "Inside PID: $$"      # PID процесса внутри хоста (не 1) — PID общий
ps                           # Видны процессы хоста — нет PID‑изоляции
cat /etc/hostname            # chroot-lab (файл в новом корне)
hostname                     # hostname хоста — UTS общий
cat /proc/self/mountinfo | head -n 10  # дерево монтирования хоста с подмонтированными /dev,/proc,/sys
cat /proc/net/dev            # те же сетевые интерфейсы — NET общий
```

Проверка связи с FS:

```sh
mkdir -p /root && echo "hello from chroot" > /root/inside
exit
sudo cat "$ROOT"/root/inside  # файл действительно в каталоге rootfs на хосте
```

**Зафиксированный результат прогона (AL2023):**

```
Inside PID:  1023114
--- /etc/hostname (файл из rootfs):
chroot-lab
--- hostname (системный — UTS хоста):
ip-172-31-18-113.eu-north-1.compute.internal
--- /proc/net/dev (сеть хоста):
ens5: 22793313489 28560236 …
```

`Inside PID ≠ 1` и `hostname ≠ chroot-lab` подтверждают: PID/UTS/NET-неймспейсы — общие с хостом, изолирована только ФС.

---

## 5. Почему `chroot` не безопасен (демонстрация побега)

**Идея:** обладая root‑правами и доступом к `/proc`, процесс внутри простого `chroot` может переключить корень файловой системы на корень процесса PID 1 (инит системы хоста), доступный по пути `/proc/1/root`. Это возможно, потому что `chroot` не меняет **mount‑namespace**: путь `/proc/1/root` по‑прежнему ссылается на **реальный корень хоста**.

### Предпосылки (что должно быть верно прежде)

* Вы находитесь **внутри** `chroot` из предыдущих шагов и обладаете **реальными** root‑правами (UID 0, без user‑namespace).

Если нет введите:

```bash
sudo chroot "$ROOT" /bin/sh
```

* Внутри смонтирован `/proc` (мы монтировали его на шаге 3).

### Шаги демонстрации

1. Убедимся, что `/proc/1/root` указывает на корень хоста:

```sh
readlink -f /proc/1/root   # ожидаемо: /
ls -ld / /proc/1/root       # должны выглядеть как два корня одной FS
```

2. Посмотрим содержимое корня PID 1 (то есть корня хоста), не покидая chroot:

```sh
ls /proc/1/root | head
```

3. Выполним «побег»: сменим корень процесса на корень PID 1 и откроем оболочку.

   **Debian/Ubuntu:**

```bash
chroot /proc/1/root /bin/sh
```

   **Amazon Linux 2023:** в корне хоста `/bin/sh` существует (это симлинк на `bash`), но во избежание неоднозначностей надёжнее указать абсолютный путь интерпретатора:

```bash
chroot /proc/1/root /usr/bin/sh
```

4. Проверим, что мы теперь действительно в окружении хоста:

```sh
pwd                        # /
hostname                   # вернёт hostname хоста, а не chroot-lab
cat /etc/hostname          # совпадает с выводом hostname
cat /proc/self/mountinfo | head -n 5  # дерево маунтов хоста
```

**Зафиксированный результат прогона (AL2023):**

```
до побега:  hostname=ip-172-31-18-113…, /etc/hostname=chroot-lab
после побега: pwd=/, hostname=ip-172-31-18-113…
--- /etc/os-release:
NAME="Amazon Linux"
VERSION="2023"
ls /proc/1/root | head: bin boot dev etc home lab lib lib64 …
```

### Почему это работает

* `/proc/<pid>/root` — это «магическая» символическая ссылка на **корневой каталог процесса `<pid>`** в его mount‑namespace.
* Так как обычный `chroot` **не создаёт новый mount‑namespace**, ссылка `/proc/1/root` ведёт в корень **хостовой** FS.
* Команда `chroot /proc/1/root /bin/sh` (требует `CAP_SYS_CHROOT`) просто меняет root directory текущего процесса на корень хоста и исполняет `/bin/sh` уже **в корне хоста**.

### Как сделать, чтобы «побег» не сработал (контр‑эксперименты)

1. **Лишить доступа к `/proc`** внутри chroot (нет пути к `/proc/1/root`):

```sh
umount /proc || true
chroot /proc/1/root /bin/sh || echo "no /proc → нет побега"
```

2. **Запустить chroot под непривилегранным пользователем** (нет `CAP_SYS_CHROOT`):

```sh
exit  # если вы в сессии из шага 3
sudo chroot --userspec=65534:65534 "$ROOT" /bin/sh -c 'chroot /proc/1/root /bin/sh' || echo "EPERM: нет прав на chroot"
```

3. **Создать user‑namespace** с `unshare --user --map-root-user` (root станет «поддельным», capabilities будут namespaced и не действуют на хост): попытка `chroot /proc/1/root` также не даст доступа к корню хоста.

### Наблюдение через `strace`

Посмотрим сам системный вызов `chroot(2)` во время «побега»:

```bash
sudo strace -e chroot chroot "$ROOT" /bin/sh -c 'chroot /proc/1/root /bin/sh -c "echo HOST:\ $(hostname)"'
# В выводе увидите: chroot("/proc/1/root") = 0
```

**Вывод:** простой `chroot` не обеспечивает безопасности. При наличии root‑прав и `/proc` корень хоста остаётся достижимым через `/proc/1/root`. Именно поэтому «чистый» `chroot` применяют только как операционный приём, а для изоляции используют **namespaces** и **cgroups**.

---

## 6. Запуск внутри chroot под непривилегированным пользователем

**Зачем:** уменьшить последствия ошибок/экспериментов.

```bash
sudo chroot --userspec=65534:65534 "$ROOT" /bin/sh
id                        # uid=65534(nobody)
hostname chroot-lab-2     # EPERM — прав на смену hostname нет
exit
```

**Зафиксированный результат прогона:**

```
uid=65534(nobody) gid=65534(nogroup) groups=65534(nogroup)
hostname: sethostname: Operation not permitted
```

---

## 7. Добавляем namespaces: PID/UTS/MNT через `unshare`

**Теория:** `unshare` создаёт новые пространства имён. Нам нужны PID (своё дерево процессов), UTS (свой hostname), MNT (своё дерево монтирования). Чтобы `ps` видел только процессы внутри, нужно подмонтировать **новый** `proc`.

**Команда (Debian/Ubuntu):**

```bash
sudo unshare --pid --uts --mount --fork \
  --mount-proc="$ROOT/proc" \
  chroot "$ROOT" /bin/sh
```

**Команда (Amazon Linux 2023):**

На AL2023 запуск с `--mount-proc=…` падает с ошибкой:

```
unshare: cannot change /lab/chroot/rootfs/proc filesystem propagation: Invalid argument
```

Причина — `autofs` для `binfmt_misc` поверх `/proc` с `shared`-пропагацией. Обход:

```bash
sudo umount "$ROOT"/proc 2>/dev/null || true
sudo unshare --pid --uts --mount --fork --propagation=private \
  chroot "$ROOT" /bin/sh -c '
mount -t proc proc /proc
exec /bin/sh
'
```

Проверим эффект:

```sh
echo "PID inside: $$"   # 1 — вы init нового PID‑namespace
hostname chroot-ns
hostname                # chroot-ns — теперь UTS изолирован
ps                      # видны только процессы внутри ns
cat /proc/1/cgroup      # проверим привязку процесса к cgroup
```

**Зафиксированный результат прогона (AL2023):**

```
PID inside: 1
hostname после смены: chroot-ns
PID   USER     TIME  COMMAND
    1 root      0:00 /bin/sh -c …
    5 root      0:00 ps
/proc/1/cgroup: 0::/user.slice/user-1000.slice/session-221.scope
```

С хоста `hostname` остаётся неизменным — UTS реально изолирован.

---

## 8. Лимиты ресурсов через cgroups v2 (через `systemd-run`)

**Теория:** cgroups v2 управляет лимитами CPU/памяти/IO. `systemd-run` создаёт временный unit и помещает наш процесс в отдельный cgroup with заданными лимитами.

**Запуск с лимитами 256МБ RAM и 25% CPU.**

**Debian/Ubuntu (интерактивный):**

```bash
sudo systemd-run -p MemoryMax=256M -p CPUQuota=25% -t \
  chroot "$ROOT" /bin/sh
```

**Amazon Linux 2023 (неинтерактивный по ssh — флаг `-t` требует TTY):**

```bash
sudo systemd-run --pipe --wait \
  -p MemoryMax=256M -p CPUQuota=25% \
  --unit chroot-lab \
  chroot "$ROOT" /bin/sh -c '
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
CG=$(cut -d: -f3 /proc/self/cgroup)
echo "cgroup: $CG"
cat /sys/fs/cgroup/system.slice/chroot-lab.service/memory.max
cat /sys/fs/cgroup/system.slice/chroot-lab.service/cpu.max
'
```

**Почему далее нужен маунт cgroup2 внутри chroot:** мы смонтировали `sysfs`, но не отдельную FS cgroup2. Чтобы прочитать лимиты, её надо примонтировать.

На **Debian/Ubuntu** это работает из коробки:

```sh
mount -t cgroup2 none /sys/fs/cgroup
grep ' cgroup2 ' /proc/self/mountinfo | grep '/sys/fs/cgroup'
CG=$(cut -d: -f3 /proc/self/cgroup)
cat "/sys/fs/cgroup${CG}/memory.max"   # ~268435456
cat "/sys/fs/cgroup${CG}/cpu.max"      # формат: quota period, напр. 25000 100000
```

На **Amazon Linux 2023** свежий `mount -t cgroup2 none /sys/fs/cgroup` падает с `Resource busy` или показывает пустой root cgroup без вложенных юнитов. Решение — сделанный в §3 `mount --rbind /sys/fs/cgroup "$ROOT"/sys/fs/cgroup`. Тогда внутри chroot полная иерархия видна как есть.

**Интерпретация:** `memory.max` — байты или `max`; `cpu.max` — квота и период (`25000/100000` ≈ 25%).

**Проверка с хоста:**

```bash
# Debian/Ubuntu:
systemctl show run-uXX.service -p MemoryMax -p CPUQuota -p CPUWeight

# Amazon Linux 2023 — свойство называется CPUQuotaPerSecUSec:
systemctl show chroot-lab.service \
  -p MemoryMax -p CPUQuotaPerSecUSec -p CPUQuotaPeriodUSec
```

**Зафиксированный результат прогона (AL2023):**

```
MemoryMax=268435456           # = 256 MiB ✓
CPUQuotaPerSecUSec=250ms      # 250ms / 1000ms = 25% ✓
CPUQuotaPeriodUSec=infinity   # default period
memory.max: 268435456
cpu.max:    25000 100000
```

---

## 9. Наблюдение системных вызовов `chroot`

**Зачем:** увидеть реальный вызов `chroot(2)` в действии.

```bash
sudo strace -e chroot chroot "$ROOT" /bin/sh -c 'echo ok'
# ожидаем в выводе: chroot("$ROOT") = 0
```

И во время побега (видны два `chroot(2)` подряд):

```bash
sudo strace -f -e chroot chroot "$ROOT" /bin/sh -c 'chroot /proc/1/root /usr/bin/sh -c "echo HOST"' 2>&1 | grep chroot
# chroot("/lab/chroot/rootfs") = 0
# chroot("/proc/1/root")       = 0
```

---

## 10. Приборка

```bash
# Выйдите из всех шеллов/chroot.
# Размонтировать всё в обратном порядке (rbind-маунты раньше своих родителей):
mount | awk -v p="$ROOT/" '$3 ~ p {print $3}' | tac | while read m; do
  sudo umount -lR "$m" || true
done
sudo rm -rf  "${ROOT%/rootfs}"

# Убрать failed/dead-юниты от systemd-run:
sudo systemctl reset-failed 'chroot-lab*' 2>/dev/null || true
```

**Почему порядок важен:** занятые маунты не снимутся; `-l` выполнит «ленивое» размонтирование после освобождения дескрипторов. На AL2023 рекурсивный rbind `/sys/fs/cgroup` нужно разбирать ДО `/sys` — иначе `rm -rf` упрётся в активный `/proc/sys/kernel/*` с `Permission denied`.

---

## 11. Частые ошибки и их причины

1. `ps` в `unshare` видит процессы хоста — вы читаете старый `/proc`. На Debian/Ubuntu используйте `--mount-proc="$ROOT/proc"` при запуске; на AL2023 — `--propagation=private` и `mount -t proc proc /proc` уже внутри chroot.
2. `hostname` не меняется в простом `chroot` — нужен UTS‑namespace (делаем через `unshare`).
3. `Operation not permitted` на действиях с сетью/монтированиями — не хватает capabilities; внутри user‑ns они ограничены.
4. `chroot: failed to run '/bin/sh': No such file or directory` — отсутствует интерпретатор/либы. Решение: статический BusyBox (как здесь).
5. Нет `/dev/null` и др. устройств — пропущен bind‑mount `/dev`.
6. **AL2023:** `unshare: cannot change …/proc filesystem propagation: Invalid argument` — на хосте есть autofs `binfmt_misc` поверх `/proc`. Решение: `--propagation=private` без `--mount-proc=…`.
7. **AL2023:** `cat /sys/fs/cgroup/<unit>/memory.max: No such file or directory` внутри chroot, хотя с хоста файл есть. Причина: cgroup2 не примонтирован внутри. Решение: `mount --rbind /sys/fs/cgroup "$ROOT"/sys/fs/cgroup` с хоста.
8. **AL2023:** `systemctl show -p CPUQuota` возвращает пусто. Используйте `CPUQuotaPerSecUSec` (`250ms` = 25%).
9. **AL2023:** внутри busybox `tr/find/od/printf not found` — добавьте симлинки в `$ROOT/bin/` (см. список в §2).

---

## 12. Итог

* `chroot` изолирует **только файловую систему**.
* Для контейнероподобной изоляции добавляйте namespaces (`unshare --pid --uts --mount --fork [--mount-proc=… | --propagation=private]`).
* Для лимитов ресурсов используйте cgroups v2 (в примере через `systemd-run`).
* Root внутри `chroot` не даёт безопасности; доступ к `/proc` открывает путь к корню хоста.

---

## 13. Верификация (Ubuntu 22.04 LTS)

Данная лабораторная работа была успешно протестирована на **Ubuntu 22.04 LTS (Jammy Jellyfish)** в облаке Azure. 

**Основные выводы:**
* Пакет `busybox-static` полностью решает проблему зависимостей для создания rootfs.
* Механизмы `unshare` и `cgroups v2` (через `systemd-run`) работают согласно инструкции.
* Путь к `busybox` в Ubuntu: `/bin/busybox`.
* Демонстрация «побега» через `/proc/1/root` подтверждена.

Для автоматической проверки шагов можно использовать скрипт `verify_chroot_ubuntu.sh`, добавленный в этот же репозиторий.

---

## Теоретические вопросы (итоговые)

### Блок 1: chroot(2) и VFS

1. Что именно делает системный вызов `chroot(2)` с точки зрения структуры `task_struct` и mount-namespace процесса? Почему после вызова всё ещё доступны открытые ранее файловые дескрипторы вне нового корня?
2. Чем `chroot(2)` принципиально отличается от `pivot_root(2)`? Какой из них использует runc/Docker и почему?
3. Почему чистый `chroot` без `chdir("/")` после вызова считается ошибкой? Что произойдёт если новый корень — `/srv/jail`, а текущий каталог процесса оставался `/tmp`?
4. Какая capability нужна для вызова `chroot(2)`? Если её отозвать у root — что увидит вызывающий?
5. Почему в `chroot` не изолируется hostname, PID, сеть и IPC? Какой механизм ядра отвечает за каждую из этих изоляций?

### Блок 2: Побег из chroot

6. Подробно опишите шаги побега `chroot /proc/1/root /bin/sh`. Какая магическая семантика стоит за символической ссылкой `/proc/<pid>/root`?
7. Почему демонстрационный побег **не работает** под `--userspec=65534`? Какие конкретно проверки делает ядро при `chroot(2)` и где они описаны в исходниках?
8. Кроме `/proc/1/root`, назовите ещё минимум два способа выйти из chroot, если у атакующего есть root и `CAP_SYS_CHROOT`.
9. Что произойдёт если внутри chroot открыть `chdir("/")` и потом ещё раз вызвать `chroot(".")`? Это используется в одном из классических побегов — опишите его.
10. Защитит ли SELinux/AppArmor от побега `chroot /proc/1/root`? Если да — какие правила должны быть включены?

### Блок 3: Namespaces

11. Перечислите все 8 типов namespaces в Linux 6.x. Какой из них создаётся **последним** при старте контейнера и почему порядок имеет значение?
12. Зачем `unshare --pid` требует `--fork`? Что произойдёт без `--fork`?
13. Объясните разницу между `unshare(2)` и `setns(2)`. Какая из утилит — `unshare(1)` или `nsenter(1)` — соответствует каждой?
14. Что такое «propagation type» для mount-point (`shared`, `private`, `slave`, `unbindable`)? Почему на Amazon Linux 2023 `unshare --mount-proc` падает с `Invalid argument`?
15. PID namespace «init» (`PID=1`) — какое у него особенное поведение по обработке сигналов? Почему `kill 1` из контейнера не убивает контейнер сразу?
16. Что произойдёт если процесс с PID=1 в новом PID-ns умрёт? Что увидят его дочерние процессы?

### Блок 4: User namespace

17. Что такое `/proc/<pid>/uid_map` и `/proc/<pid>/gid_map`? Покажите вид этих файлов для rootless-контейнера с маппингом `0:100000:65536`.
18. Почему «root внутри user-namespace» не является root хоста? Какие capabilities у такого root и где их граница?
19. CVE-2022-0185 (FUSE/user-ns) — кратко: где была уязвимость и почему user-namespace расширяют поверхность атаки?
20. Зачем нужен `setgroups: deny` в `/proc/<pid>/setgroups` перед записью `gid_map` без CAP_SETGID?

### Блок 5: Cgroups v2

21. Чем cgroups v2 отличаются от v1 на уровне иерархии? Почему в v2 нельзя одновременно использовать controllers для одного процесса в разных деревьях?
22. Опишите взаимосвязь `cgroup.subtree_control`, `cgroup.controllers` и `MemoryMax=`. Что означает «delegation»?
23. Что произойдёт если процесс пробьёт `memory.max`? Что такое OOM-killer на уровне cgroup и чем он отличается от системного OOM?
24. Как `cpu.max = 25000 100000` транслируется в реальное расписание? Связано ли это с количеством vCPU?
25. Почему `systemctl show -p CPUQuota` пустой, но `CPUQuotaPerSecUSec` показывает `250ms`? Где у systemd хранятся «оригинальные» строки лимитов и где — производные?

### Блок 6: Безопасность и операции

26. Перечислите 5 capabilities, которые Docker сбрасывает по умолчанию. Какая из них самая «опасная» если её оставить?
27. Что такое seccomp-bpf? Назовите минимум 3 системных вызова, которые блокируются seccomp-профилем Docker по умолчанию.
28. Чем `pivot_root` + новый mount-ns безопаснее обычного `chroot`? Что произойдёт если в пайплайне runc забыть `pivot_root`?
29. AL2023 + Docker — что использует Docker под капотом для изоляции ФС: chroot, pivot_root или overlayfs+pivot_root? Покажите как это проверить через `nsenter` в живой контейнер.
30. Какие три уровня защиты должен пройти злоумышленник чтобы из контейнера получить root на хосте? (без zero-day в ядре)
