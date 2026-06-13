# Лабораторная работа 08: OverlayFS — слоистая файловая система (как образы Docker)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Собрать overlay из слоёв](#-1--overlay--)
  - [Теория для изучения перед частью](#----)
  - [1.1 mount -t overlay](#11-mount--t-overlay)
- [Часть 2: Copy-on-Write — запись не трогает lower](#-2-copy-on-write-----lower)
  - [Теория для изучения перед частью](#----)
  - [2.1 Правка файла из lower](#21----lower)
- [Часть 3: Whiteout и multi-layer](#-3-whiteout--multi-layer)
  - [Теория для изучения перед частью](#----)
  - [3.1 Whiteout при удалении](#31-whiteout--)
  - [3.2 Несколько слоёв (как образ из нескольких RUN)](#32-------run)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: `workdir and upperdir must reside under the same mount`](#-1-workdir-and-upperdir-must-reside-under-the-same-mount)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~35 мин · сложность 3/5 · пререквизиты: 01-chroot, базовое mount

Цель: понять, как из read-only слоёв собирается одна изменяемая файловая система —
механизм, на котором стоят образы контейнеров. **OverlayFS** объединяет нижние
слои (`lowerdir`, read-only) и верхний (`upperdir`, read-write) в единое дерево
(`merged`). Запись работает по **Copy-on-Write**: правка файла из lower копирует
его в upper, оригинал цел; удаление создаёт **whiteout** (char device 0,0). Это
ровно то, что делает Docker: слои образа = `lowerdir`, r/w-слой контейнера =
`upperdir`, `docker commit` = упаковка upper в новый слой.

> Развитие `01-chroot` (там rootfs был один каталог; здесь — слои). Все «ожидаемые
> выводы» сняты на WSL2 (overlayfs есть в ядре 6.6); на реальном хосте идентично.

---

## Предварительные требования

```bash
sudo ./00-setup/check.sh
grep -w overlay /proc/filesystems || modprobe overlay 2>/dev/null   # overlayfs доступен?
# nodev	overlay
```

---

## Стартовая проверка

```bash
grep -w overlay /proc/filesystems && echo "overlayfs в ядре есть"
# nodev	overlay
# overlayfs в ядре есть
```

---

## Часть 1: Собрать overlay из слоёв

### Теория для изучения перед частью

- Четыре каталога: **`lowerdir`** (один или несколько read-only слоёв через `:`),
  **`upperdir`** (read-write, сюда идут все изменения), **`workdir`** (служебный,
  ядро делает в нём атомарные операции CoW; **обязан быть на той же ФС, что
  `upperdir`** — иначе mount упадёт, Часть 4), **`merged`** (точка монтирования,
  объединённое дерево — это и видит процесс).
- При конфликте имён побеждает верхний слой: `upper` > `lower2` > `lower1`.

---

**Цель:** смонтировать overlay и увидеть объединённое дерево.

---

### 1.1 mount -t overlay

```bash
B=/lab/08; mkdir -p $B/{lower,upper,work,merged}
echo "from base layer" > $B/lower/readme.txt
echo "untouched"       > $B/lower/untouched.txt

sudo mount -t overlay overlay \
  -o "lowerdir=$B/lower,upperdir=$B/upper,workdir=$B/work" $B/merged

ls $B/merged
# readme.txt  untouched.txt        <- merged = объединение слоёв (пока только lower)
cat $B/merged/readme.txt
# from base layer
```

**Контрольные вопросы:**
1. За что отвечает каждый из `lowerdir`/`upperdir`/`workdir`/`merged`?
2. Почему `workdir` обязан быть на той же ФС, что `upperdir`?
3. Кто побеждает при конфликте имён в разных слоях?

---

## Часть 2: Copy-on-Write — запись не трогает lower

### Теория для изучения перед частью

- `lowerdir` read-only. При записи в существующий файл из lower ядро **копирует
  его в upper** (copy-up) и пишет туда — оригинал в lower остаётся нетронутым.
  Новые файлы создаются сразу в upper.
- Поэтому 100 контейнеров из одного образа = 1 образ + 100 маленьких upper-дельт,
  а не 100 копий. `docker diff` показывает содержимое upper.

---

### 2.1 Правка файла из lower

```bash
echo "modified by container" > $B/merged/readme.txt

cat $B/lower/readme.txt
# from base layer            <- lower НЕ изменился (CoW защитил исходник)
cat $B/upper/readme.txt
# modified by container       <- правка ушла в upper (copy-up)
```

**Контрольные вопросы:**
1. Что происходит с файлом из lower при первой записи в него через merged?
2. Почему это экономит место и время старта против `cp -r`?
3. Что показывает `docker diff <container>` в терминах overlay?

---

## Часть 3: Whiteout и multi-layer

### Теория для изучения перед частью

- Удаление файла, который есть только в lower, нельзя выполнить физически (lower
  read-only). Вместо этого в upper создаётся **whiteout** — character device с
  major=0, minor=0 и тем же именем. При `readdir` ядро видит whiteout и **скрывает**
  одноимённый файл из lower. Сам файл в lower остаётся жив.
- Несколько `lowerdir` через `:` — как слои образа (`FROM` … `RUN` … `COPY`).

---

### 3.1 Whiteout при удалении

```bash
rm $B/merged/untouched.txt

ls -la $B/upper/untouched.txt
# c--------- 2 root root 0, 0 ... untouched.txt   <- whiteout: char device 0,0
ls $B/merged
# readme.txt                                       <- в merged файла нет
cat $B/lower/untouched.txt
# untouched                                        <- но в lower он физически жив
```

### 3.2 Несколько слоёв (как образ из нескольких RUN)

```bash
sudo umount $B/merged
mkdir -p $B/lower2/etc; echo "host=layer2" > $B/lower2/etc/config
sudo mount -t overlay overlay \
  -o "lowerdir=$B/lower2:$B/lower,upperdir=$B/upper,workdir=$B/work" $B/merged
cat $B/merged/etc/config
# host=layer2        <- верхний lower (lower2) побеждает нижний
```

**Контрольные вопросы:**
1. Что такое whiteout физически и как ядро его интерпретирует?
2. Почему `RUN apt install && apt clean` в одной строке Dockerfile экономит место?
3. В каком порядке слои перекрывают друг друга в `lowerdir=A:B`?

---

## Часть 4: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ mount overlay: wrong fs type, bad option, bad superblock ──► смотри dmesg:
│    «workdir and upperdir must reside under the same mount» — workdir и upperdir
│    на РАЗНЫХ ФС. Положи их на одну ФС (Сценарий 01)
├─ mount: ... overlay does not exist ────────────────────────► не существует workdir/
│    upperdir каталога, либо забыт workdir у rw-overlay. Создай каталоги
├─ «not supported as upperdir» в dmesg ──────────────────────► upperdir на ФС, не
│    поддерживающей overlay как upper (вложенный overlay, сетевая ФС). Бери ext4/xfs
└─ удалённый файл «возвращается» после umount ───────────────► это lower, он жив;
      удаление в overlay = whiteout в upper, а не стирание lower
```

### Инцидент 1: `workdir and upperdir must reside under the same mount`
Разобран в `broken/scenario-01/` (workdir на tmpfs, upper на ext4). Воспроизвести и починить:
```bash
sudo ./broken/scenario-01/make-broken.sh        # work на tmpfs → mount overlay падает
sudo ./solutions/01-same-filesystem/fix.sh        # work на той же ФС → mount OK
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 08-overlayfs
# --- module: 08-overlayfs ---
# prepare...
# [OK] overlay смонтирован: lower+upper+work → merged
# verify...
# [OK] merged = union: виден файл из lower
# [OK] CoW: правка в merged ушла в upper, lower защищён
# [OK] whiteout: char device 0,0 в upper, файл скрыт в merged, жив в lower
# [OK] module 08-overlayfs verified
```

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| `lowerdir` (через `:`) | read-only слои | слои образа Docker (`FROM`…`RUN`) |
| `upperdir` | read-write слой | r/w-слой контейнера (`docker diff`) |
| `workdir` | служебный для CoW | требование «та же ФС, что upper» |
| `merged` | объединённое дерево | то, что видит процесс в контейнере |
| char device 0,0 | whiteout | удаление файла из lower (`RUN rm`) |

---

## Теоретические вопросы (итоговые)
1. Назначение `lowerdir`/`upperdir`/`workdir`/`merged`?
2. Что такое Copy-on-Write в overlay и почему lower не меняется при записи?
3. Что такое whiteout физически (тип файла, major/minor)?
4. Почему `workdir` обязан быть на той же ФС, что `upperdir`?
5. Как `docker commit` соотносится с upperdir?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-mount-overlay.md`** — собрать overlay из слоёв, увидеть union.
2. **`tasks/02-cow.md`** — поймать Copy-on-Write (lower цел, upper изменён).
3. **`tasks/03-whiteout.md`** — удалить файл из lower, найти whiteout-устройство.

Дополнительно:
4. Собери overlay из ТРЁХ lowerdir и проверь порядок перекрытия одноимённых файлов.
5. Сделай `lowerdir` read-only overlay (без upper/work) — какие операции записи упадут?

---

## Шпаргалка

```bash
B=/lab/ovl; mkdir -p $B/{lower,upper,work,merged}
mount -t overlay overlay \
  -o "lowerdir=$B/lower,upperdir=$B/upper,workdir=$B/work" $B/merged
# несколько слоёв: lowerdir=$B/l3:$B/l2:$B/l1   (l3 — самый верхний из lower)

# наблюдать:
cat $B/upper/<file>            # copy-up после записи в merged
ls -la $B/upper/<deleted>      # whiteout: c--------- 0, 0
docker diff <ctr>              # аналог: содержимое upperdir

umount $B/merged              # требование: workdir и upperdir на ОДНОЙ ФС
```

---

## Чему вы научились
- Собирать overlay из `lowerdir`/`upperdir`/`workdir` и понимать `merged` как union.
- Видеть Copy-on-Write: запись копирует файл в upper, lower остаётся нетронутым.
- Распознавать whiteout (char device 0,0) как механизм удаления из read-only слоя.
- Сопоставлять overlay со слоями образов Docker (`docker diff`/`commit`).

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 08-overlayfs
```

> Дальше — `09-networking`: veth-пары, bridge и NAT — как контейнер получает сеть
> (`docker0`, bridge-режим Docker).
