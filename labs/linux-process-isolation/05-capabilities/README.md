# Лабораторная работа 05: capabilities — дробление всемогущего root

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Что такое capability и где она живёт](#-1---capability----)
  - [Теория для изучения перед частью](#----)
  - [1.1 Посмотреть свои capabilities](#11---capabilities)
- [Часть 2: File capabilities — одна привилегия бинарю](#-2-file-capabilities----)
  - [Теория для изучения перед частью](#----)
  - [2.1 nobody биндит :80 только с CAP_NET_BIND_SERVICE](#21-nobody--80---cap_net_bind_service)
- [Часть 3: Обрезать привилегии — процесс с одной cap](#-3-------cap)
  - [Теория для изучения перед частью](#----)
  - [3.1 nobody ровно с одной привилегией (CAP_CHOWN)](#31-nobody-----cap_chown)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: `setcap +p` вместо `+ep` — привилегия не действует](#-1-setcap-p--ep----)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~35 мин · сложность 3/5 · пререквизиты: 02-namespaces, базовое понимание uid/прав

Цель: перестать думать про root как «всё или ничего». С ядра 2.2 root разбит на
~40 отдельных **capabilities** — точечных привилегий (открыть порт <1024, сменить
владельца файла, смонтировать ФС…). Научимся выдавать программе **ровно одну**
нужную привилегию (file capabilities, `setcap`) и наоборот — запускать процесс с
**обрезанным** набором (`capsh`), чтобы лишние права были недоступны. Это то, что
Docker делает через `--cap-add`/`--cap-drop`.

> Развитие `02-namespaces` (там USER-ns давал uid 0 внутри; здесь дробим сам root).
> Headline-демо (bind :80 только с `CAP_NET_BIND_SERVICE`) снято на реальном
> Ubuntu-хосте (GCP, ядро 6.8): **на WSL2 file-cap хранится, но не энфорсится для
> bind низких портов** — там используй `verify/` (он переносимый) и читай выводы
> отсюда. `capsh`/`setcap`/`getcap` есть на обоих.

---

## Предварительные требования

```bash
sudo ./00-setup/check.sh           # setcap/getcap/capsh — модуль 05 (libcap2-bin)
command -v setcap getcap capsh >/dev/null && echo "libcap на месте"
```

---

## Стартовая проверка

```bash
capsh --print | head -2
# Current: =ep
# Bounding set =cap_chown,cap_dac_override,...,cap_checkpoint_restore   (~41 cap)
```

---

## Часть 1: Что такое capability и где она живёт

### Теория для изучения перед частью

- **Capability** — одна из ~40 привилегий, на которые разбит root. Примеры:
  `CAP_NET_BIND_SERVICE` (порт <1024), `CAP_CHOWN` (chown чужого),
  `CAP_DAC_OVERRIDE` (обход прав rwx), `CAP_SYS_ADMIN` (mount/namespaces — «новый
  root», сотни операций), `CAP_NET_RAW` (raw-сокеты для ping/tcpdump).
- **Где живут.** У процесса — пять наборов в `/proc/<pid>/status`: `CapEff`
  (effective — что реально действует сейчас), `CapPrm` (permitted — что можно
  включить), `CapInh` (inheritable), `CapBnd` (bounding — потолок), `CapAmb`
  (ambient). У файла — **file capabilities** в xattr `security.capability`
  (`getcap`/`setcap`).
- **Флаги `setcap` (`+ep`/`+p`/`+i`).** `e` (effective) — активна сразу после
  `execve`; `p` (permitted) — разрешена, но программа должна включить её сама;
  `i` (inheritable) — протекает через `execve`. Обычной (не cap-aware) программе
  нужно `+ep` — иначе привилегия лежит в permitted, но не действует (Часть 4).
- **Декодировать маску:** `capsh --decode=0000000000000001` → `cap_chown`.

---

### 1.1 Посмотреть свои capabilities

```bash
grep Cap /proc/self/status
# CapInh:  0000000000000000
# CapPrm:  000001ffffffffff
# CapEff:  000001ffffffffff      <- root: все ~41 включены
# CapBnd:  000001ffffffffff
# CapAmb:  0000000000000000
capsh --decode=000001ffffffffff | head -1     # человекочитаемо
```

**Контрольные вопросы:**
1. Чем `CapEff` отличается от `CapPrm` и `CapBnd`?
2. Где хранятся file capabilities и как их посмотреть?
3. Что означают буквы `e`, `p`, `i` в `setcap cap_x+ep`?

---

## Часть 2: File capabilities — одна привилегия бинарю

### Теория для изучения перед частью

- `setcap cap_net_bind_service+ep <binary>` записывает в xattr файла право
  биндить порты <1024. Тогда **непривилегированный** процесс, запустивший этот
  бинарь, получает ровно эту привилегию — без полного root и без SUID.
- Это безопаснее SUID-бита: SUID даёт процессу ВСЕ права root, file-cap — строго
  одну. `--cap-add NET_BIND_SERVICE` у Docker — то же самое.

---

**Цель:** дать `nobody` забиндить порт 80 одной привилегией.

---

### 2.1 nobody биндит :80 только с CAP_NET_BIND_SERVICE

```bash
PY=/tmp/pyweb; cp "$(command -v python3)" "$PY"      # копия, чтобы не трогать системный

# nobody на 8080 (>1024) — можно всем; на 80 — нельзя без привилегии
su -s /bin/bash nobody -c "$PY -m http.server 8080 --bind 127.0.0.1"   # BOUND
su -s /bin/bash nobody -c "$PY -m http.server 80   --bind 127.0.0.1"   # PermissionError: [Errno 13]

sudo setcap cap_net_bind_service+ep "$PY"
getcap "$PY"
# /tmp/pyweb cap_net_bind_service=ep
su -s /bin/bash nobody -c "$PY -m http.server 80 --bind 127.0.0.1"     # теперь BOUND ✔

sudo setcap -r "$PY"     # снять привилегию → снова PermissionError
```

Реальный прогон (хост GCP, поллинг порта через `ss`):
```
nobody :8080 без cap          → BOUND   (>1024, можно всем)
nobody :80   без cap          → NOTBOUND
getcap (+ep): /tmp/pyweb cap_net_bind_service=ep
nobody :80   с +ep            → BOUND
nobody :80   после setcap -r  → NOTBOUND
```

**Контрольные вопросы:**
1. Чем file-capability безопаснее SUID-бита?
2. Почему `nobody` может слушать :8080, но не :80 без привилегии?
3. Какому флагу `docker run` соответствует `setcap cap_net_bind_service+ep`?

---

## Часть 3: Обрезать привилегии — процесс с одной cap

### Теория для изучения перед частью

- Обратная задача: запустить процесс с **минимальным** набором. `capsh` умеет
  сбрасывать привилегии из bounding set (`--drop`) и запускать команду от другого
  пользователя с заданным набором (`--user`, `--inh`, `--addamb`).
- **Ambient capabilities** (ядро ≥ 4.3) — привилегии, которые «текут» через
  `execve` без файловых атрибутов; так systemd выдаёт `AmbientCapabilities=`.

---

### 3.1 nobody ровно с одной привилегией (CAP_CHOWN)

```bash
# drop одной cap из bounding set — её больше нет даже у потомков
capsh --drop=cap_net_bind_service --print | sed -n 's/^Bounding set =//p' | grep -o cap_net_bind_service
# (пусто) — привилегия убрана из потолка

# запустить шелл от nobody РОВНО с cap_chown
sudo capsh --keep=1 --user=nobody --inh=cap_chown --addamb=cap_chown -- -c '
  grep CapEff /proc/self/status
  touch /tmp/d && chown root /tmp/d && echo "chown(CAP_CHOWN) → OK"
  mount -t tmpfs none /mnt 2>&1 | head -1
'
# uid=65534  CapEff:	0000000000000001       <- ровно одна привилегия (cap_chown)
# chown(CAP_CHOWN) → OK                          <- cap_chown действует
# mount: /mnt: must be superuser to use mount.   <- CAP_SYS_ADMIN нет → mount запрещён
```

Процесс — не root (uid 65534), но с одной точечной привилегией: `chown` работает,
`mount` — нет. Это и есть принцип наименьших привилегий.

**Контрольные вопросы:**
1. Что делает `capsh --drop=cap_x` с набором привилегий?
2. Зачем нужны ambient capabilities (что было нельзя до ядра 4.3)?
3. Почему `mount` упал, а `chown` — нет, при `CapEff=...0001`?

---

## Часть 4: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ setcap сделал, getcap показывает cap, а привилегия НЕ действует ─► флаг +p вместо
│     +ep: cap в permitted, но не effective; обычная программа её не включает.
│     Лечится setcap cap_x+ep (Сценарий 01)
├─ setcap: Failed to set capabilities ... Operation not supported ─► ФС без xattr
│     security.capability (tmpfs/overlay/9p, напр. /mnt/c в WSL2). Клади бинарь на ext4
├─ getcap пусто, хотя «давали» ─────────────────────────────────► setcap отработал по
│     другому пути/копии бинаря, либо его перезаписали (cap слетает при write)
└─ дропнул cap, но root всё может ──────────────────────────────► дропать надо из
      bounding set/effective; uid 0 с полным CapEff игнорирует DAC и пр.
```

### Инцидент 1: `setcap +p` вместо `+ep` — привилегия не действует
Разобран в `broken/scenario-01/` (cap в permitted, но не effective). Воспроизвести и починить:
```bash
sudo ./broken/scenario-01/make-broken.sh        # +p → bind :80 всё равно отказывает
sudo ./solutions/01-effective-flag/fix.sh         # +ep → заработало
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 05-capabilities
# --- module: 05-capabilities ---
# prepare...
# [OK] libcap на месте (setcap/getcap/capsh)
# verify...
# [OK] drop: cap_net_bind_service убран из bounding set через capsh --drop
# [OK] file-cap storage: setcap +ep → getcap '...=ep' → setcap -r → пусто
# [OK] enforcement: nobody с одной cap (cap_chown) → CapEff=...0001, chown работает
# [OK] module 05-capabilities verified
```

`verify/` переносимый (capsh + setcap-storage + ambient-enforcement) — зелёный и на
WSL2, и на реальном хосте. Headline bind-:80 — `sudo ./run.sh` (нужен реальный хост).

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| `setcap cap_net_bind_service+ep` | file capability в xattr | `--cap-add` Docker |
| `getcap` | чтение file caps | хранение привилегии на бинаре |
| `capsh --drop=cap_x` | убрать cap из bounding | `--cap-drop` Docker |
| `capsh --addamb` | ambient cap для не-root | минимальный набор привилегий |
| `/proc/self/status` Cap* | наборы caps процесса | где живут привилегии |

---

## Теоретические вопросы (итоговые)
1. Чем capability-подход лучше SUID-бита по площади атаки?
2. Пять наборов capabilities процесса — назначение каждого (Eff/Prm/Inh/Bnd/Amb)?
3. В чём разница `setcap cap_x+p` и `+ep` и почему обычной программе нужно `+ep`?
4. Что такое ambient capabilities и зачем они появились?
5. Почему `CAP_SYS_ADMIN` зовут «новым root» и почему её опасно оставлять контейнеру?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-file-cap-bind.md`** — выдать бинарю `cap_net_bind_service+ep`, bind :80 от nobody.
2. **`tasks/02-drop-caps.md`** — запустить процесс от nobody ровно с одной cap, проверить enforcement.
3. **`tasks/03-capsh-inspect.md`** — `capsh --print/--decode`, читать `/proc/self/status`.

Дополнительно:
4. Дай `cap_net_raw+ep` копии `ping` и пингуй от nobody (raw-сокет без root).
5. Сравни `setcap cap_x+p` и `+ep` на своём бинаре — поймай разницу в поведении.

---

## Шпаргалка

```bash
# === file capabilities ===
setcap cap_net_bind_service+ep ./bin     # дать привилегию (e=effective, p=permitted)
getcap ./bin                             # ./bin cap_net_bind_service=ep
setcap -r ./bin                          # снять все file-caps

# === смотреть/декодировать ===
grep Cap /proc/self/status               # CapEff/CapPrm/CapInh/CapBnd/CapAmb
capsh --print                            # человекочитаемо
capsh --decode=0000000000000001          # 0x...01=cap_chown

# === запуск с обрезанным набором ===
capsh --drop=cap_sys_admin --print                       # убрать из bounding
capsh --keep=1 --user=nobody --inh=cap_chown --addamb=cap_chown -- -c '...'  # nobody + 1 cap

# === Docker-аналоги ===
# --cap-add NET_BIND_SERVICE  ↔  setcap cap_net_bind_service+ep
# --cap-drop ALL              ↔  обнулить набор
```

---

## Чему вы научились
- Понимать, что root — это ~40 отдельных capabilities, и где они живут (процесс/файл).
- Выдавать бинарю одну привилегию через `setcap +ep` (file capabilities) — безопаснее SUID.
- Запускать процесс от не-root с минимальным набором (`capsh`, ambient) и видеть enforcement.
- Различать `+p` и `+ep` и диагностировать «cap есть, а не действует».

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 05-capabilities
```

> Дальше — `06-seccomp`: фильтруем сами системные вызовы (а не привилегии) —
> `--security-opt seccomp=…` у Docker.
