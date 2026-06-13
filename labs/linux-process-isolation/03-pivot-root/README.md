# Лабораторная работа 03: pivot_root — безопасная смена корня (закрываем побег из 01)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Механика pivot_root](#-1--pivot_root)
  - [Теория для изучения перед частью](#----)
  - [1.1 pivot_root в новом mount-namespace](#11-pivot_root---mount-namespace)
- [Часть 2: Закрываем побег из модуля 01](#-2-----01)
  - [Теория для изучения перед частью](#----)
  - [2.1 Побег теперь упирается в наш корень (CONFINED)](#21-------confined)
- [Часть 3: Troubleshooting](#-3-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: `pivot_root: ... Device or resource busy`](#-1-pivot_root--device-or-resource-busy)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~30 мин · сложность 3/5 · пререквизиты: 01-chroot, 02-namespaces

Цель: заменить дырявый `chroot` (этап 01) на то, что используют настоящие
рантаймы — `pivot_root(2)` внутри отдельного mount-namespace. Это меняет корень
в **дереве монтирования**, а не только видимость путей: после `pivot_root` +
`umount` старого корня хостовый корень **исчезает из дерева** и становится
недостижим. Тот самый побег `chroot /proc/1/root` из модуля 01 здесь
**перестаёт работать** — это и есть переход от «псевдо-изоляции» к настоящей.

> Связка `01` (rootfs) + `02` (mount-namespace). `runc`/`crun`/`LXC`/
> `systemd-nspawn` делают ровно это для каждого контейнера. Все «ожидаемые
> выводы» сняты на этом хосте (WSL2, ядро 6.6) — у вас числа/детали свои, важна
> структура и итог `escape=CONFINED`.

---

## Предварительные требования

```bash
sudo ./00-setup/check.sh          # unshare, busybox — должны быть
id -u                             # 0
```

---

## Стартовая проверка

```bash
command -v unshare busybox >/dev/null && echo "инструменты на месте"
# инструменты на месте
```

---

## Часть 1: Механика pivot_root

### Теория для изучения перед частью

- **`pivot_root(new_root, put_old)`** делает три вещи: (1) `new_root` становится
  корнем процесса; (2) текущий (старый) корень монтируется в `put_old` (он
  должен лежать внутри `new_root`); (3) после этого `put_old` можно **отмонтировать**
  — и старый корень полностью пропадает из дерева монтирования.
- **Два требования** (нарушишь — `EBUSY`/`EINVAL`, см. Часть 3):
  1. `new_root` обязан быть **отдельной точкой монтирования** (не просто каталог
     на той же ФС). Делается `mount -t tmpfs none new` или `mount --bind new new`.
  2. Делать это нужно в **новом mount-namespace** (`unshare --mount`), иначе
     `pivot_root` затронет хост целиком.
- Отличие от `chroot`: `chroot` меняет лишь видимый путь `/`, оставляя процесс в
  том же mount-ns, поэтому `/proc/1/root` всё ещё ведёт на хост (побег из 01).
  `pivot_root` + `umount old_root` убирает хостовый корень из дерева насовсем.

---

**Цель:** сделать pivot_root в новом mnt-ns и оказаться в новом корне.

**Скрипт:** `verify/verify.sh` выполняет всю последовательность внутри одного
`unshare` (после pivot хостовый `/tmp` недостижим, поэтому результат собирается
в stdout родителя — тот ещё в исходном namespace).

---

### 1.1 pivot_root в новом mount-namespace

```bash
sudo unshare --mount --pid --uts --fork --mount-proc /bin/bash <<'INNER'
set -e
NEW=/lab/03-pivot-root/newroot
mount --make-rprivate /
mount -t tmpfs none "$NEW"                      # (1) new_root = отдельный mount point
install -d "$NEW"/{bin,etc,proc,dev,old_root}
cp /bin/busybox "$NEW/bin/"
for a in sh ls cat hostname mount umount chroot head; do ln -sf busybox "$NEW/bin/$a"; done
echo pivoted-container > "$NEW/etc/hostname"
mount -t proc proc "$NEW/proc"; mount --rbind /dev "$NEW/dev"
cd "$NEW"
pivot_root . old_root                           # (2) меняем корень в дереве маунтов
hostname pivoted-container
echo "внутри pivoted: hostname=$(hostname)"
echo "корень /:"; ls /
INNER
# внутри pivoted: hostname=pivoted-container
# корень /:
# bin  dev  etc  old_root  proc
```

Мы в новом корне (tmpfs), старый корень пока виден в `/old_root`.

**Контрольные вопросы:**
1. Что делает `pivot_root(new, put_old)` по шагам?
2. Почему `new_root` обязан быть отдельной точкой монтирования?
3. Чем `pivot_root` принципиально отличается от `chroot`?

---

## Часть 2: Закрываем побег из модуля 01

### Теория для изучения перед частью

- В модуле 01 побег работал, потому что mount-ns общий с хостом → `/proc/1/root`
  (корень PID 1 в его mnt-ns) указывал на корень хоста.
- Здесь мы в **своём** mnt-ns, и после `umount -l /old_root` старый (хостовый)
  корень удалён из дерева монтирования. Теперь `/proc/1/root` ведёт в **наш**
  новый корень. Тот же `chroot /proc/1/root` остаётся «внутри» — `escape=CONFINED`.

---

**Цель:** повторить побег из 01 и убедиться, что он больше не выводит на хост.

---

### 2.1 Побег теперь упирается в наш корень (CONFINED)

```bash
# та же последовательность, но добавляем umount old_root и попытку побега
sudo unshare --mount --pid --uts --fork --mount-proc /bin/bash <<'INNER'
set -e
NEW=/lab/03-pivot-root/newroot
mount --make-rprivate /; mount -t tmpfs none "$NEW"
install -d "$NEW"/{bin,etc,proc,old_root}; cp /bin/busybox "$NEW/bin/"
for a in sh ls cat hostname chroot mount umount; do ln -sf busybox "$NEW/bin/$a"; done
mount -t proc proc "$NEW/proc"
cd "$NEW"; pivot_root . old_root
/bin/busybox umount -l /old_root                # старый корень исчезает из дерева
export PATH=/bin
echo "попытка побега chroot /proc/1/root:"
chroot /proc/1/root /bin/sh -c 'ls /'           # ведёт в НАШ корень, не на хост
INNER
# попытка побега chroot /proc/1/root:
# bin  etc  old_root  proc            <- наш минимальный корень, НЕ /home,/usr,/var хоста
```

Сравните с модулем 01, где `chroot /proc/1/root` выводил на корень хоста
(`/etc/os-release`, hostname хоста). Здесь — `escape=CONFINED`.

> Это и есть причина, по которой контейнерные рантаймы используют `pivot_root`,
> а не `chroot`: периметр действительно закрыт.

**Контрольные вопросы:**
1. Почему именно `umount old_root` закрывает побег, а не сам `pivot_root`?
2. Куда теперь указывает `/proc/1/root` и почему?
3. Что увидел бы атакующий при `chroot /proc/1/root` до и после этого модуля?

---

## Часть 3: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ pivot_root: ... Device or resource busy (EBUSY) ─► new_root НЕ отдельный mount
│     point. Сделай его маунтом: mount --bind new new  ИЛИ  mount -t tmpfs none new
│     (Сценарий 01)
├─ pivot_root: ... Invalid argument (EINVAL) ───────► put_old не внутри new_root,
│     либо корень — shared mount. Лечится mount --make-rprivate / в новом mnt-ns
├─ после pivot всё «command not found» ─────────────► не наполнен новый rootfs или
│     PATH указывает в старый корень (export PATH=/bin)
└─ pivot_root затронул хост ────────────────────────► забыт unshare --mount (делали
      в общем mount-ns). ВСЕГДА в отдельном mnt-ns
```

### Инцидент 1: `pivot_root: ... Device or resource busy`
Разобран в `broken/scenario-01/` (new_root — обычный каталог на той же ФС, а не
точка монтирования). Воспроизвести и починить:
```bash
sudo ./broken/scenario-01/make-broken.sh        # pivot_root на каталоге → EBUSY
sudo ./solutions/01-make-mountpoint/fix.sh        # сделать new_root маунтом → OK
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 03-pivot-root
# --- module: 03-pivot-root ---
# prepare...
# [OK] окружение готово: /lab/03-pivot-root (unshare/busybox на месте)
# verify...
# [OK] pivot_root выполнен, новый корень минимальный: bin,dev,etc,old_root,proc,
# [OK] UTS изолирован: hostname=pivoted-test
# [OK] побег /proc/1/root закрыт после pivot_root (escape=CONFINED)
# [OK] module 03-pivot-root verified
```

Пошаговое демо с пояснениями — `sudo ./run.sh`.

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| `tmpfs` в `/lab/03-pivot-root/newroot` | отдельная ФС-маунт | требование «new_root = mount point» |
| `pivot_root . old_root` | смена корня в дереве маунтов | механику pivot_root |
| `umount -l /old_root` | удаление старого корня из дерева | закрытие побега из 01 |
| `chroot /proc/1/root` после pivot | `escape=CONFINED` | что периметр реально закрыт |

---

## Теоретические вопросы (итоговые)
1. Три шага `pivot_root(new, put_old)` и зачем нужен `put_old`?
2. Почему `new_root` обязан быть отдельной точкой монтирования (что за `EBUSY`)?
3. Почему `pivot_root` без `unshare --mount` опасен?
4. Какой именно шаг закрывает побег `/proc/1/root` — `pivot_root` или `umount old_root`?
5. Что делает `runc` для каждого контейнера (bind → pivot_root → umount)?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-pivot-root.md`** — выполнить pivot_root в новом mnt-ns.
2. **`tasks/02-close-escape.md`** — доказать, что побег из 01 теперь CONFINED.
3. **`tasks/03-old-root-gone.md`** — показать, что после umount старый корень недостижим.

Дополнительно:
4. Замени `tmpfs` на `mount --bind newroot newroot` — pivot_root должен работать так же.
5. Пропусти `mount --make-rprivate /` и поймай `EINVAL` (корень — shared mount).

---

## Шпаргалка

```bash
# === pivot_root в новом mnt-ns (то, что делает runc) ===
unshare --mount --pid --uts --fork --mount-proc bash <<'EOF'
mount --make-rprivate /
mount -t tmpfs none /lab/nr           # new_root = отдельный mount point (иначе EBUSY)
install -d /lab/nr/{bin,proc,old_root}
cp /bin/busybox /lab/nr/bin/; ln -sf busybox /lab/nr/bin/sh
mount -t proc proc /lab/nr/proc
cd /lab/nr && pivot_root . old_root    # сменили корень в дереве маунтов
umount -l /old_root                    # старый корень исчез → побег закрыт
export PATH=/bin
EOF

# === диагностика ===
# EBUSY  → new_root не mount point  → mount --bind new new / tmpfs
# EINVAL → корень shared / put_old не внутри new → mount --make-rprivate /
```

---

## Чему вы научились
- Менять корень безопасно через `pivot_root` в отдельном mount-namespace.
- Понимать два требования (`new_root` = mount point; новый mnt-ns) и ошибки `EBUSY`/`EINVAL`.
- Закрывать побег `/proc/1/root` из модуля 01 через `umount old_root`.
- Сопоставлять это с реальной последовательностью `runc` (bind → pivot_root → umount).

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 03-pivot-root
```

> Дальше — `04-cgroups-v2`: к изоляции (что процесс ВИДИТ) добавляем лимиты
> (сколько процесс может ПОТРЕБИТЬ) — CPU/память/IO/PIDs.
