# Лабораторная работа: Управление памятью в Linux
---

## Предварительная установка пакетов

```bash
sudo apt-get update
sudo apt-get install -y \
  stress-ng strace procps util-linux \
  bsdmainutils sysstat python3
```

> `procps` даёт `free`, `vmstat`, `pmap`, `ps`. `util-linux` даёт `ipcs`, `ipcmk`,
> `ipcrm`, `lsipc`. Без этих пакетов часть команд не найдётся.

---

## Стартовая проверка

```bash
free -h
cat /proc/meminfo | head -10
getconf PAGESIZE
swapon --show
```

```
              total        used        free      shared  buff/cache   available
Mem:           1.9Gi       180Mi       1.4Gi       2.0Mi       320Mi       1.6Gi
Swap:            0B          0B          0B
```

> Если `Swap` уже подключён — это нормально, в модуле 4 будем добавлять
> ещё один swap-файл и снимать его, не трогая существующий.

---

## Модуль 1: Виртуальная и физическая память

### Теория для изучения перед модулем

- Виртуальная память: адресное пространство процесса, MMU и таблицы страниц
- Демандное выделение страниц (demand paging): почему `mmap(1GB)` не выделяет 1ГБ сразу
- Метрики процесса: VSZ (виртуальная), RSS (резидентная), SHR (разделяемая), PSS (proportional set size)
- Что показывает `free`: `total`, `used`, `free`, `buff/cache`, `available` — и как это связано с `/proc/meminfo`
- Page cache: зачем нужен, почему «съеденная» память — это не утечка
- `vmstat`: колонки `si/so` (swap in/out), `bi/bo` (block in/out), `wa` (wait IO)

---

**Цель:** Научиться читать `free -h`, `vmstat`, `/proc/meminfo` и понимать,
почему `top` показывает у процесса VIRT=10G, а на самом деле он жрёт 200 МБ.

---

### 1.1 Базовый снапшот памяти

```bash
# Память в человекочитаемом виде
free -h

# То же в килобайтах + сырые поля
cat /proc/meminfo | head -20

# Размер страницы памяти на этой системе (обычно 4096)
getconf PAGESIZE
```

Найди и сопоставь:
- `MemTotal` в `/proc/meminfo` = `total` в `free -h`
- `MemAvailable` в `/proc/meminfo` = `available` в `free -h`
- `Buffers + Cached + SReclaimable ≈ buff/cache` в `free -h`

> **Главная цифра для алёртов** — `MemAvailable`, а не `MemFree`.
> Высокое `used` без учёта `available` — это пугалка для красноглазых:
> page cache всегда занимает «свободную» память и моментально освобождается под нагрузку.

---

### 1.2 Наблюдение за памятью в динамике

```bash
# 5 сэмплов с интервалом 1 сек
vmstat 1 5
```

```
procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
 0  0      0  1450M    12M   320M    0    0     5     2   45   80  1  0 99  0  0
```

Ключевые колонки:
- `free` — свободная RAM
- `buff/cache` — page cache (буфер чтения/записи)
- `si/so` — swap in/out (если ненулевые — система свапается, плохой знак)
- `wa` — CPU ждёт I/O (если высокий — диск/память узкое место)

---

### 1.3 VIRT vs RES — где обман

Запусти процесс, который запрашивает 1 ГБ виртуальной памяти, но **не трогает** её:

```bash
python3 -c '
import mmap, os, time
m = mmap.mmap(-1, 1024*1024*1024)  # 1 ГБ анонимной памяти
print("PID:", os.getpid())
time.sleep(300)
' &
sleep 1
```

```bash
# Посмотри VSZ и RSS
ps -o pid,vsz,rss,comm -p $(pgrep -f 'mmap(-1, 1024')
# PID    VSZ  RSS  COMMAND
# 1234   1.0G  8M   python3       <- VIRT гигабайт, RES почти ничего
```

Теперь дотронемся до памяти:

```bash
# Послать в тот же процесс команду — но проще запустить новый, который реально пишет
killall python3 2>/dev/null
python3 -c '
import mmap, os, time
m = mmap.mmap(-1, 1024*1024*1024)
for i in range(0, len(m), 4096):
    m[i] = 1                          # пишем по 1 байту на страницу
print("PID:", os.getpid())
time.sleep(300)
' &
sleep 3
ps -o pid,vsz,rss,comm -p $(pgrep -f 'mmap(-1, 1024')
# RSS теперь ~1 ГБ — страницы реально выделились ядром
```

Вывод: VSZ — это «обещание», RSS — это правда. Алёрты надо строить по RSS / `MemAvailable`,
а не VSZ.

```bash
killall python3 2>/dev/null
```

---

### 1.4 Page cache: «съел» всю RAM — это норма

```bash
free -h
# запомни значение buff/cache

# Создаём файл на 1 ГБ — ядро прокеширует его
dd if=/dev/zero of=/tmp/bigfile bs=1M count=1024 status=progress
free -h
# buff/cache вырос на ~1 ГБ, available практически не изменился

# Сбрасываем page cache (нужно root)
sync && echo 3 | sudo tee /proc/sys/vm/drop_caches
free -h
# buff/cache упал
```

> `drop_caches` нужен только для тестов. В production его сбрасывать не нужно —
> ядро само вытеснит кеш, когда понадобится память.

```bash
rm -f /tmp/bigfile
```

**Контрольные вопросы:**
1. У процесса VSZ=8 ГБ, RSS=200 МБ. Сколько физической памяти он реально занимает?
2. `free -h` показывает `used=7G`, `available=12G` при `total=16G`. Стоит паниковать?
3. Чем отличаются колонки `free` и `available` в `free -h`? На какую алёртить?
4. Зачем в `vmstat` колонки `si` и `so`? Что значит если они стабильно ненулевые?

---

## Модуль 2: Аллокация памяти — malloc, mmap, brk, sbrk

### Теория для изучения перед модулем

- Адресное пространство процесса: text/data/bss/heap/mmap-region/stack
- Системные вызовы выделения памяти: `brk`/`sbrk` (двигают вершину heap) и `mmap` (отдельный регион)
- glibc `malloc()`: маленькие куски — через `brk`, большие (по умолчанию >128 КБ) — через `mmap`
- Почему `free()` мелких блоков не уменьшает RSS: память помечается свободной, но ядру не отдаётся (`M_TRIM_THRESHOLD`)
- `malloc_trim()`: принудительно вернуть свободные участки heap ядру
- Что показывают `/proc/<pid>/maps` и `pmap -x`: текст, библиотеки (mmap файла), `[heap]`, `[stack]`, anon-mmap

---

**Цель:** Увидеть глазами, какие системные вызовы делает `malloc` под капотом,
и понять, почему «процесс утёк память» — часто на самом деле «glibc не вернул её ядру».

---

### 2.1 Карта памяти процесса

```bash
# Любой долгоиграющий процесс — например текущий шелл
pmap -x $$ | head -30
```

В выводе найди:
- блок `[ heap ]` — сюда уходит `brk`/`sbrk` для мелких аллокаций
- блок `[ stack ]` — стек главного потока
- строки с путями на `.so` — это `mmap()` библиотек, **общая** между процессами
- безымянные блоки `anon` — `mmap()` для больших malloc или ручной `mmap()`

```bash
# То же сырьём
cat /proc/$$/maps | head -20
```

---

### 2.2 strace: видим brk и mmap живьём

```bash
# Малый malloc — пойдёт через brk
strace -e trace=brk,mmap python3 -c 'x = "a" * 1000' 2>&1 | tail -15

# Большой malloc — пойдёт через mmap
strace -e trace=brk,mmap python3 -c 'x = "a" * (10 * 1024 * 1024)' 2>&1 | tail -15
```

В первом случае увидишь несколько `brk(...)`. Во втором — отдельный `mmap(NULL, 10489856, ...)`
для 10 МБ блока. Это и есть разница между «малым» и «большим» malloc.

---

### 2.3 strace по живому процессу

В одном терминале:

```bash
python3 -c '
import time
data = []
for i in range(2000):
    data.append("x" * 1024 * 50)   # блоки по 50 КБ
    time.sleep(0.02)
time.sleep(60)
' &
echo "PID: $!"
```

В другом терминале (или том же, в новом окне):

```bash
sudo strace -e trace=brk,mmap,munmap -p <PID> 2>&1 | head -40
```

Увидишь поток `brk(...)` (heap растёт) и периодические `mmap(...)` для больших блоков.
Это и есть «как `malloc` работает» с точки зрения ядра.

```bash
killall python3 2>/dev/null
```

---

### 2.4 «Фантомная утечка»: память освобождена, RSS не падает

```bash
python3 <<'EOF' &
import ctypes, time, os
libc = ctypes.CDLL("libc.so.6")
PID = os.getpid()

def rss_kb():
    with open(f"/proc/{PID}/status") as f:
        for line in f:
            if line.startswith("VmRSS:"): return int(line.split()[1])

# 50 тысяч аллокаций по 1 КБ — пойдёт через brk
ptrs = [libc.malloc(1024) for _ in range(50_000)]
for p in ptrs:
    ctypes.memset(p, 0xAB, 1024)
print(f"PID={PID}  После malloc: {rss_kb()} KB")

for p in ptrs: libc.free(p)
print(f"PID={PID}  После free:   {rss_kb()} KB   <- RSS почти не упал")

libc.malloc_trim(0)
print(f"PID={PID}  После trim:   {rss_kb()} KB   <- вот теперь упал")

time.sleep(60)
EOF
wait
```

Это объясняет частый кейс: «Python/Java-сервис не возвращает память после пика нагрузки».
На уровне библиотеки память свободна, на уровне ядра — она ещё «у процесса».

```bash
killall python3 2>/dev/null
```

---

### 2.5 Сколько RAM реально занимают разделяемые библиотеки

```bash
# Найди любой большой процесс
ps -eo pid,rss,comm --sort=-rss | head -5

# Возьми его PID и посмотри карту
PID=$(ps -eo pid,rss --sort=-rss | awk 'NR==2{print $1}')
pmap -x $PID | grep -E '\.so' | head -10
```

Колонка `RSS` у `.so`-файлов будет ненулевой, но это **общая** память: одна копия
библиотеки в RAM на все процессы. Поэтому простой суммой RSS считать занятую RAM нельзя.

**Контрольные вопросы:**
1. Чем `brk`/`sbrk` отличается от `mmap` при `malloc`? Когда используется каждый?
2. Почему `free()` мелкого блока не уменьшает RSS?
3. Какой системный вызов используется для загрузки `.so`?
4. У процесса RSS=2 ГБ, но в `pmap` 80% — это `/usr/lib/.../some.so`. Это утечка?
5. Зачем нужен `malloc_trim()`? Что он делает с точки зрения ядра?

---

## Модуль 3: Страницы памяти и swappiness

### Теория для изучения перед модулем

- Страница памяти как единица работы MMU: типично 4 КБ на x86_64
- Huge pages: 2 МБ / 1 ГБ — для уменьшения промахов TLB (упоминание, без углубления)
- Что значит «вытеснить страницу»: anon-страницы → swap, file-backed → просто отбросить
- `vm.swappiness` (0..200): насколько агрессивно ядро вытесняет anon-страницы вместо очистки page cache
- Pressure Stall Information (PSI): `/proc/pressure/memory` — современная замена `vmstat` для алёртов
- OOM-killer: что включается, когда не помогает ни swap, ни drop_caches

---

**Цель:** Понять, что такое страница памяти, как `swappiness` управляет
поведением ядра под давлением, и где смотреть pressure-метрики.

---

### 3.1 Размер страницы и общая картина

```bash
# Размер страницы (почти всегда 4096)
getconf PAGESIZE

# Сколько страниц всего и сколько свободных
getconf _PHYS_PAGES
getconf _AVPHYS_PAGES

# Сколько грязных страниц ждёт записи на диск (важно при IO-проблемах)
grep -E 'Dirty|Writeback|AnonPages|Mapped|Shmem' /proc/meminfo
```

| Поле | Что это |
|------|---------|
| `AnonPages` | анонимные страницы процессов (heap, stack, anon mmap) — могут уйти в swap |
| `Mapped` | страницы, замапленные из файлов (`.so`, mmap файлов) — на диске уже есть, swap не нужен |
| `Shmem` | разделяемая память (`/dev/shm`, tmpfs, SysV shm) |
| `Dirty` | модифицированные страницы, которые надо записать на диск |
| `Writeback` | в процессе записи на диск прямо сейчас |

---

### 3.2 Swappiness — что это и где живёт

```bash
# Текущее значение (0..200, в новых ядрах верхняя граница 200)
cat /proc/sys/vm/swappiness
sysctl vm.swappiness
```

| Значение | Что означает |
|----------|--------------|
| 0 | Никогда не свопить anon-страницы, пока есть что вытеснить из page cache. Используется для БД, low-latency сервисов |
| 1 | То же, но не отключает swap полностью (есть нюансы с cgroups v2) |
| 10..30 | Типично для серверов с большим page cache (БД, файлсерверы) |
| 60 | Дефолт на большинстве дистрибутивов — сбалансированное поведение |
| 100..200 | Агрессивное использование swap. Применяется на десктопах с медленным HDD очень редко |

```bash
# Изменить временно (до перезагрузки)
sudo sysctl -w vm.swappiness=10

# Сделать постоянным
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf
sudo sysctl --system

# Вернуть как было
sudo sysctl -w vm.swappiness=60
```

> **Важно:** swappiness — это **направление** при выборе «кого вытеснить»,
> а не «при каком % памяти начинать свопить». Ядро начнёт свопить, когда
> ему действительно понадобится память, и `swappiness` лишь влияет на выбор:
> anon-страница или file-backed.

---

### 3.3 Pressure Stall Information — современный мониторинг

```bash
# Сколько времени за последний интервал процессы блокировались на нехватке памяти
cat /proc/pressure/memory
```

```
some avg10=0.00 avg60=0.00 avg300=0.00 total=0
full avg10=0.00 avg60=0.00 avg300=0.00 total=0
```

- `some` — хотя бы один процесс ждёт памяти
- `full` — **все** процессы ждут памяти (полная остановка)
- `avg10/60/300` — процент времени за последние 10/60/300 секунд

> `full avg10 > 10` уже плохо. Это лучший индикатор реального голодания памяти,
> чем «just look at `free`».

Аналогично есть `/proc/pressure/cpu` и `/proc/pressure/io`.

---

### 3.4 Создаём давление и смотрим, как реагирует ядро

В одном терминале — наблюдатель:

```bash
watch -n 1 'free -h; echo "---"; cat /proc/pressure/memory'
```

В другом — нагрузка (на 1.5x от свободной RAM, чтобы вызвать вытеснение):

```bash
# Сколько свободно?
free -h
# скажем, 1.4G — нагрузим 2G
stress-ng --vm 1 --vm-bytes 2G --vm-keep -t 60
```

Что увидишь:
- `available` упадёт почти до нуля
- если swap есть — `Swap used` начнёт расти, в `vmstat` появятся `si/so`
- если swap нет — сработает OOM-killer (см. `dmesg | tail`)
- `pressure/memory` покажет ненулевые `avg10`

---

### 3.5 Huge pages — упоминание

```bash
# Сколько HugePages настроено
grep -i huge /proc/meminfo
cat /sys/kernel/mm/transparent_hugepage/enabled    # always / madvise / never
```

> Tuning hugepages — отдельная большая тема. Для типичных DevOps-задач
> важно знать только: некоторые сервисы (PostgreSQL, JVM, Oracle, Redis)
> могут просить huge pages — и тогда `HugePages_Total > 0` это нормально, а не аномалия.

**Контрольные вопросы:**
1. Какой размер страницы памяти по умолчанию на x86_64?
2. Чем `vm.swappiness=0` отличается от `vm.swappiness=1`?
3. На сервере БД с большим page cache — какой swappiness разумно поставить и почему?
4. Что лучше использовать для алёрта на нехватку памяти: `free`, `vmstat` или `/proc/pressure/memory`?
5. Если RAM кончилась и swap пуст — кто примет решение и какое?

---

## Модуль 4: Swap — назначение, настройка, /etc/fstab

### Теория для изучения перед модулем

- Назначение swap: «overflow» для anon-страниц, когда не хватает RAM
- Когда swap полезен: пиковая нагрузка, гибернация, защита от OOM на не-критичных сервисах
- Когда swap вреден: low-latency сервисы (БД, kafka, kvm-хосты), SSD с ограниченным TBW
- Swap-файл vs swap-раздел: разница в гибкости (файл) vs скорости (раздел) — на современных SSD пренебрежимо мала
- Структура swap-области: signature + битмап используемых страниц (создаётся `mkswap`)
- Приоритеты swap: можно иметь несколько swap-областей, ядро выбирает по `pri`

---

**Цель:** Создать swap-файл, подключить его, прописать в `/etc/fstab`,
снять и удалить — не сломав уже существующий swap, если он есть.

---

### 4.1 Текущее состояние swap

```bash
# Все активные swap-устройства
swapon --show
swapon --show=NAME,TYPE,SIZE,USED,PRIO

# Альтернатива
cat /proc/swaps

# Сколько swap занято
free -h | grep Swap
```

> Если `swapon --show` ничего не выводит — swap не подключён. Создадим.

---

### 4.2 Создание swap-файла на 1 ГБ

```bash
# Создаём пустой файл нужного размера
# fallocate быстрее (выделяет место мгновенно), но не все ФС поддерживают
sudo fallocate -l 1G /swapfile-lab

# Альтернатива (медленнее, но работает везде):
# sudo dd if=/dev/zero of=/swapfile-lab bs=1M count=1024 status=progress

# Права: swap-файл должен быть доступен только root
sudo chmod 600 /swapfile-lab
ls -la /swapfile-lab

# Размечаем файл как swap-область (записываем заголовок)
sudo mkswap /swapfile-lab
```

```bash
# Подключаем
sudo swapon /swapfile-lab

# Проверяем
swapon --show
free -h
```

> Если получаешь `swapon: /swapfile-lab: swapon failed: Invalid argument` —
> чаще всего файл создан на ФС, которая не поддерживает swap (btrfs без CoW-отключения),
> либо `mkswap` забыли сделать.

---

### 4.3 Снять swap

```bash
# Снимаем без удаления файла
sudo swapoff /swapfile-lab

# Проверяем — наш файл исчез из списка
swapon --show

# Снять все swap-устройства разом (НЕ делать на проде без надобности)
# sudo swapoff -a
```

> `swapoff` может занять время — ядру нужно перенести все страницы из swap обратно в RAM.
> Если RAM не хватает — команда вернёт ошибку, ничего страшного.

---

### 4.4 Постоянное монтирование через /etc/fstab

```bash
# Подключаем заново
sudo swapon /swapfile-lab

# Смотрим текущий fstab
cat /etc/fstab

# Добавляем строку для swap
echo "/swapfile-lab  none  swap  sw  0  0" | sudo tee -a /etc/fstab
tail -3 /etc/fstab
```

Поля строки:
- `/swapfile-lab` — путь к файлу (или `UUID=...` для раздела)
- `none` — нет точки монтирования
- `swap` — тип
- `sw` — опции (стандарт)
- `0 0` — dump и fsck отключены

**Критическая проверка перед перезагрузкой:**

```bash
# Снимем и попробуем поднять всё из fstab
sudo swapoff /swapfile-lab
sudo swapon -a              # читает /etc/fstab

swapon --show
# наш /swapfile-lab должен снова появиться
```

> Если в fstab ошибка и `swapon -a` ругается — **исправь до перезагрузки**.
> Сервер с битым fstab может не загрузиться (для swap не критично, но привычка).

---

### 4.5 Несколько swap-областей и приоритеты

```bash
# Создаём второй swap-файл с более высоким приоритетом
sudo fallocate -l 512M /swapfile-lab2
sudo chmod 600 /swapfile-lab2
sudo mkswap /swapfile-lab2
sudo swapon -p 10 /swapfile-lab2     # -p задаёт приоритет

swapon --show
# Колонка PRIO — чем больше, тем раньше ядро использует
```

```bash
# Снимем второй
sudo swapoff /swapfile-lab2
sudo rm /swapfile-lab2
```

---

### 4.6 Удаление swap-файла полностью

```bash
# Снять
sudo swapoff /swapfile-lab

# Убрать из fstab (последняя строка с нашим файлом)
sudo sed -i '\#^/swapfile-lab[[:space:]]#d' /etc/fstab
tail -3 /etc/fstab

# Удалить файл
sudo rm /swapfile-lab

# Проверка
swapon --show
free -h
```

**Контрольные вопросы:**
1. Зачем нужен `chmod 600` для swap-файла перед `mkswap`?
2. Что произойдёт если `swapoff` запустить на хосте, где swap почти полный, а RAM на пределе?
3. Чем поле `sw` в `/etc/fstab` отличается от `defaults`?
4. На SSD с малым TBW (cheap consumer-grade) — стоит ли держать swap включённым? Какие альтернативы (`zram`)?
5. Сервер с PostgreSQL — что разумнее: больше RAM без swap, или RAM + swap с `swappiness=1`?

---

## Модуль 5: Анонимная и общая память

### Теория для изучения перед модулем

- Анонимная память: heap, stack, anon-mmap — принадлежит одному процессу
- Разделяемая память (shared memory): три «вкуса» в Linux
  - **SysV shm** — древний API: `shmget`/`shmat`/`shmctl`, идентификаторы видны в `ipcs`
  - **POSIX shm** — современный: `shm_open()` создаёт файлы в `/dev/shm`
  - **`mmap` с `MAP_SHARED`** — самый универсальный способ, через файл или anon-shared
- `tmpfs` и `/dev/shm`: где живут POSIX shm и почему `df /dev/shm` показывает RAM
- Утилиты: `ipcs`, `ipcmk`, `ipcrm`, `lsipc` — управление SysV IPC объектами
- Утечки SysV shm: процесс умер, сегмент остался — типичный «исчезающий гигабайт памяти»

---

**Цель:** Различать анонимную и разделяемую память, видеть SysV/POSIX shm
в системе, уметь найти и удалить осиротевшие сегменты.

---

### 5.1 Анонимная vs разделяемая в /proc/meminfo

```bash
grep -E 'AnonPages|Shmem|MemFree|MemAvailable' /proc/meminfo
```

- `AnonPages` — анонимная память всех процессов (heap, stack, anon mmap)
- `Shmem` — разделяемая память (tmpfs, `/dev/shm`, SysV shm, anon-shared mmap)

Эти две цифры **не пересекаются** и обе не входят в `MemFree`. Когда `Shmem` растёт
без понятной причины — ищи tmpfs/`/dev/shm` или утечку SysV shm.

```bash
# Что смонтировано как tmpfs — все эти точки едят память из Shmem
df -h -t tmpfs
mount | grep tmpfs
```

---

### 5.2 POSIX shared memory через /dev/shm

```bash
# /dev/shm — это просто tmpfs
mount | grep /dev/shm
df -h /dev/shm

# Создаём «POSIX shm сегмент» вручную — это обычный файл в /dev/shm
sudo dd if=/dev/zero of=/dev/shm/posix_demo bs=1M count=100 status=none
ls -lh /dev/shm/

# Где он в /proc/meminfo
grep Shmem /proc/meminfo

# Удаление
sudo rm /dev/shm/posix_demo
grep Shmem /proc/meminfo
```

> Любой процесс может сделать `shm_open("/имя", ...)` и получить тот же объект.
> Это и есть POSIX shared memory — простой и удобный механизм IPC.
> Программы Chrome/Firefox/PostgreSQL активно используют этот механизм.

---

### 5.3 SysV shared memory — древний API

```bash
# Что сейчас есть в системе
ipcs -m              # сегменты shared memory
ipcs -q              # очереди сообщений
ipcs -s              # семафоры
ipcs                 # всё разом

# Лимиты системы на SysV shm
ipcs -l
# либо
sysctl kernel.shmmax kernel.shmall kernel.shmmni
```

**Создаём свой сегмент через `ipcmk`:**

```bash
# 50 МБ shared memory
ipcmk -M 50M
# Shared memory id: 12345

ipcs -m
# key        shmid   owner  perms  bytes      nattch  status
# 0x12abcd   12345   root   644    52428800   0
```

В выводе:
- `key` — числовой ключ (по этому ключу разные процессы находят сегмент)
- `shmid` — ID сегмента в ядре
- `nattch` — сколько процессов сейчас подключено (`shmat`)
- `bytes` — размер

```bash
# Что в /proc/meminfo?
grep Shmem /proc/meminfo

# Удаление по shmid
SHMID=$(ipcs -m | awk '/^0x/ && $5=="52428800"{print $2}' | head -1)
ipcrm -m $SHMID
ipcs -m
```

---

### 5.4 Утечка SysV shm — «куда делся гигабайт RAM»

Классическая проблема: приложение упало, сегмент SysV shm остался — занятый,
но никем не используемый. В `top`/`free` память будет «занята», но не приписана
никакому процессу.

```bash
# Создаём «осиротевшие» сегменты
for i in 1 2 3; do ipcmk -M 100M; done
ipcs -m
grep Shmem /proc/meminfo

# В реальной системе мы бы заметили это так:
# 1) Shmem большой
grep Shmem /proc/meminfo
# 2) Никто не сидит на этих сегментах (nattch = 0)
ipcs -m | awk '$6==0 && $2 ~ /[0-9]+/{print $0}'
```

**Чистка:**

```bash
# Удалить ВСЕ сегменты SysV shm которые никто не использует
# (Осторожно в проде — убедись, что это правда мусор, а не «приложение запустится и подключится»)
ipcs -m | awk '$6==0 && $2 ~ /^[0-9]+$/{print $2}' | xargs -r -n1 ipcrm -m

# Современный аналог через lsipc (util-linux >= 2.27)
lsipc -m
```

> В современных приложениях `SysV shm` практически вытеснен POSIX shm и mmap.
> Видишь утечку SysV shm — почти наверняка это легаси на C/C++ или старый Oracle/Sybase.

---

### 5.5 mmap с MAP_SHARED — самый универсальный механизм

Два процесса могут разделить память через `mmap` файла:

```bash
# Готовим файл-бэкенд
dd if=/dev/zero of=/tmp/mmap-shared bs=1M count=10 status=none

# Процесс 1: пишет в файл через mmap
python3 -c '
import mmap, time
f = open("/tmp/mmap-shared", "r+b")
m = mmap.mmap(f.fileno(), 10*1024*1024, mmap.MAP_SHARED)
m[0:5] = b"HELLO"
print("writer wrote HELLO, sleeping")
time.sleep(60)
' &
sleep 1

# Процесс 2: читает из того же файла через mmap
python3 -c '
import mmap
f = open("/tmp/mmap-shared", "r+b")
m = mmap.mmap(f.fileno(), 10*1024*1024, mmap.MAP_SHARED)
print("reader sees:", m[0:5])
'
# reader sees: b'HELLO'

killall python3 2>/dev/null
rm /tmp/mmap-shared
```

Это базовый механизм, на котором построены и POSIX shm (это mmap файла в `/dev/shm`),
и многие другие. PostgreSQL, например, использует именно `mmap(MAP_SHARED)` или
POSIX shm для shared buffers.

**Контрольные вопросы:**
1. Чем отличаются три механизма shared memory в Linux (SysV, POSIX, `mmap`)? Какой выбирать сегодня для нового кода?
2. Где физически живут POSIX shm-объекты? Как посмотреть их список?
3. У тебя `Shmem=8G` в `/proc/meminfo`, но `du -sh /dev/shm` показывает 50М. Где остальное?
4. Как найти осиротевшие SysV shm сегменты и удалить их безопасно?
5. Почему «`Shmem`-страницы» не уходят в swap так же, как обычные anon? (подсказка: они file-backed на tmpfs)

---

## Финальная очистка

```bash
# Снимаем тестовый swap, если ещё подключён
sudo swapoff /swapfile-lab 2>/dev/null
sudo sed -i '\#^/swapfile-lab[[:space:]]#d' /etc/fstab
sudo rm -f /swapfile-lab /swapfile-lab2

# Удаляем все осиротевшие SysV shm (если создавали в модуле 5)
ipcs -m | awk '$6==0 && $2 ~ /^[0-9]+$/{print $2}' | xargs -r -n1 ipcrm -m 2>/dev/null

# Останавливаем все Python-скрипты из лабы
killall python3 stress-ng 2>/dev/null

# Возвращаем дефолтный swappiness, если меняли
sudo sysctl -w vm.swappiness=60 >/dev/null
sudo rm -f /etc/sysctl.d/99-swappiness.conf

# Чистим временные файлы
rm -f /tmp/bigfile /tmp/mmap-shared /dev/shm/posix_demo

free -h
swapon --show
```

---

## Теоретические вопросы (итоговые)

### Блок 1: Виртуальная и физическая память

1. Что такое виртуальная память и зачем она нужна, если у нас есть физическая RAM?
2. Объясни разницу между VSZ, RSS, SHR и PSS у процесса. Какую цифру брать для алёрта на «процесс жрёт память»?
3. Что такое demand paging? Почему `mmap(1GB)` не приводит к выделению 1ГБ физической памяти сразу?
4. Что означает строка `MemAvailable` в `/proc/meminfo`? Чем она отличается от `MemFree`?
5. Зачем `vmstat` показывает колонки `si` и `so`? Что плохого, если они стабильно ненулевые?

### Блок 2: Аллокация памяти

6. Какие системные вызовы стоят за `malloc()` в glibc? Когда вызывается какой?
7. Почему `free()` маленького блока не уменьшает RSS процесса? Какой механизм это меняет?
8. Что такое `M_MMAP_THRESHOLD` в glibc malloc? Какое значение по умолчанию?
9. Объясни, почему «`pmap -x | grep \.so`» показывает много памяти, но это не утечка.
10. У процесса в `/proc/<pid>/maps` много блоков `anon` без имени. Что это и кто их создал?

### Блок 3: Страницы и swappiness

11. Какой размер страницы памяти по умолчанию на x86_64 и почему он именно такой?
12. Чем `vm.swappiness=0` отличается от `vm.swappiness=1` в современных ядрах (cgroups v2)?
13. На каком классе нагрузок стоит уменьшать `swappiness` до 1-10? На каком — увеличивать?
14. Что такое PSI (Pressure Stall Information)? Почему это лучший индикатор «системе плохо от нехватки памяти», чем `free`?
15. Объясни разницу между «вытеснением anon-страницы» и «отбрасыванием file-backed страницы».

### Блок 4: Swap

16. Зачем вообще нужен swap, если RAM много? Назови минимум два валидных кейса.
17. На каких системах swap скорее вреден, чем полезен? Почему?
18. Чем swap-файл отличается от swap-раздела на современных SSD? Когда выбирать какой?
19. Что произойдёт, если в `/etc/fstab` указать несуществующий swap-файл и перезагрузиться?
20. Что такое `zram` и в каком сценарии его стоит использовать вместо обычного swap?

### Блок 5: Анонимная и общая память

21. Назови три механизма shared memory в Linux. Чем они различаются и какой выбирать для нового кода?
22. Где физически живут POSIX shm-объекты? Почему `df /dev/shm` показывает память?
23. Что такое `Shmem` в `/proc/meminfo`? Может ли он уйти в swap?
24. Как найти осиротевшие SysV shm сегменты? Почему они опасны для долгоживущих хостов?
25. Процесс PostgreSQL съел 4ГБ shared memory. Как посмотреть, что именно это за память, и она ли учитывается у каждого worker-процесса в RSS?

---

## Шпаргалка

```bash
# === Просмотр памяти ===
free -h                              # сводка
cat /proc/meminfo                    # сырые поля
vmstat 1 5                           # динамика
grep -E 'AnonPages|Shmem|Mapped|Dirty' /proc/meminfo

# === Память процесса ===
ps -eo pid,vsz,rss,comm --sort=-rss | head
pmap -x <PID>                        # карта памяти
cat /proc/<PID>/maps                 # сырьём
cat /proc/<PID>/status | grep -E 'Vm|Rss'

# === Что под капотом у malloc ===
strace -e trace=brk,mmap,munmap -p <PID>
strace -e trace=brk,mmap python3 -c 'x = "a" * 10000000' 2>&1 | tail

# === Page cache ===
sync && echo 3 | sudo tee /proc/sys/vm/drop_caches    # только для тестов!

# === Swappiness ===
cat /proc/sys/vm/swappiness
sudo sysctl -w vm.swappiness=10
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf

# === Pressure Stall Information ===
cat /proc/pressure/memory
cat /proc/pressure/cpu
cat /proc/pressure/io

# === Swap ===
swapon --show                        # текущие swap-области
sudo fallocate -l 1G /swapfile && sudo chmod 600 /swapfile
sudo mkswap /swapfile && sudo swapon /swapfile
sudo swapoff /swapfile
echo "/swapfile none swap sw 0 0" | sudo tee -a /etc/fstab
sudo swapon -a                       # активировать всё из fstab

# === Shared memory ===
ipcs                                 # все SysV IPC объекты
ipcs -m                              # только shared memory
ipcmk -M 100M                        # создать сегмент 100М
ipcrm -m <shmid>                     # удалить по shmid
lsipc -m                             # современный вариант
ls /dev/shm/                         # POSIX shm объекты

# === Чистка осиротевших SysV shm (nattch=0) ===
ipcs -m | awk '$6==0 && $2 ~ /^[0-9]+$/{print $2}' | xargs -r -n1 ipcrm -m
```
