# Лабораторная работа 12: Rootless-контейнеры (user namespace + uid mapping)

## Оглавление
<!-- TOC -->
- [Предварительные требования](#-)
- [Стартовая проверка](#-)
- [Часть 1: Стать root внутри user namespace](#-1--root--user-namespace)
  - [Теория для изучения перед частью](#----)
  - [1.1 root внутри, обычный пользователь снаружи](#11-root----)
- [Часть 2: Доказательство — «root» внутри = обычный uid снаружи](#-2---root----uid-)
  - [Теория для изучения перед частью](#----)
  - [2.1 Файл от root внутри принадлежит nobody на хосте](#21---root---nobody--)
- [Часть 3: От «фейкового root» к настоящему rootless-контейнеру](#-3---root---rootless-)
  - [Теория для изучения перед частью](#----)
  - [3.1 Single-uid ограничение](#31-single-uid-)
- [Часть 4: Troubleshooting](#-4-troubleshooting)
  - [Теория: диагностика по симптому](#---)
  - [Инцидент 1: внутри user-ns ты не root (забыт `-r`)](#-1--user-ns---root---r)
- [Проверка модуля](#-)
- [Финальная карта ресурсов модуля](#---)
- [Теоретические вопросы (итоговые)](#--)
- [Практические задания (отработка)](#--)
- [Шпаргалка](#)
- [Чему вы научились](#--)
- [Уборка](#)
<!-- /TOC -->


> ⏱ время ~30 мин · сложность 3/5 · пререквизиты: 02-namespaces (user-ns), 05-capabilities

Цель: запустить «контейнер» **без root на хосте**. Запускать контейнеры от uid 0
небезопасно: побег через уязвимость ядра = root на хосте. Решение — **rootless**:
снаружи процесс от обычного пользователя, а внутри своего **user namespace** он
отображён в uid 0 (root). Полные права — только внутри песочницы; на хосте процесс
безопасен. Так работают `podman` и rootless Docker.

> Развитие `02-namespaces` (USER-ns) и `05-capabilities`. Работает БЕЗ настоящего
> root, если в ядре включены непривилегированные user-ns (по умолчанию на
> WSL2/Ubuntu: `user.max_user_namespaces` > 0). Выводы сняты от `nobody` (uid 65534)
> на WSL2 — у вас будет свой uid. Multi-uid маппинг (`newuidmap`) — продвинутая часть.

---

## Предварительные требования

```bash
sudo ./00-setup/check.sh
sysctl user.max_user_namespaces          # > 0 → непривилегированные user-ns разрешены
unshare --user --map-root-user id -u     # 0 — можем стать root внутри своего ns
```

---

## Стартовая проверка

```bash
# от непривилегированного пользователя — создаём user-ns и проверяем uid внутри
su -s /bin/sh nobody -c 'unshare --user --map-root-user id'
# uid=0(root) gid=0(root) groups=0(root)
```

---

## Часть 1: Стать root внутри user namespace

### Теория для изучения перед частью

- **`unshare --user` (`-U`)** создаёт новый user namespace; **`--map-root-user`
  (`-r`)** отображает ТЕКУЩИЙ uid хоста в uid 0 внутри. Без `-r` внутри ты —
  «нулевой» неотображённый uid (65534/nobody) и НЕ можешь делать root-операции
  (Часть 4, Сценарий 01).
- Внутри user-ns ты получаешь полный набор capabilities **в пределах этого ns** —
  поэтому можешь создавать вложенные namespaces (uts/mnt/net/pid), монтировать
  tmpfs и т.п. Снаружи же ты остаёшься обычным пользователем.

---

### 1.1 root внутри, обычный пользователь снаружи

```bash
# от nobody: создаём user-ns, мапим себя в root, монтируем tmpfs внутри
su -s /bin/sh nobody -c 'unshare --user --mount --map-root-user sh -c "id -u; mount -t tmpfs none /mnt && echo MOUNT_OK"'
# 0           <- внутри мы root
# MOUNT_OK    <- и можем монтировать (в пределах своего mnt-ns)
```

**Контрольные вопросы:**
1. Что делают флаги `-U` и `-r` у `unshare`?
2. Почему root ВНУТРИ user-ns безопасен для хоста?
3. Откуда у непривилегированного пользователя capabilities внутри своего user-ns?

---

## Часть 2: Доказательство — «root» внутри = обычный uid снаружи

### Теория для изучения перед частью

- Файл, созданный «root-ом» (uid 0) внутри user-ns, на хосте принадлежит реальному
  uid того, кто создал namespace. Маппинг виден в `/proc/<pid>/uid_map`: строка
  `0 <host_uid> 1` = «uid 0 внутри ↔ host_uid снаружи, диапазон 1».
- Это и есть гарантия безопасности: что бы «root» ни натворил с файлами, владелец
  на хосте — непривилегированный пользователь, не настоящий root.

---

### 2.1 Файл от root внутри принадлежит nobody на хосте

```bash
su -s /bin/sh nobody -c 'unshare --user --map-root-user sh -c "touch /tmp/rootless-test"'
stat -c '%U (uid %u)' /tmp/rootless-test
# nobody (uid 65534)        <- НЕ root! файл создал «root» внутри, владелец — nobody

su -s /bin/sh nobody -c 'unshare --user --map-root-user cat /proc/self/uid_map'
#          0      65534          1     <- uid 0 внутри ↔ 65534 (nobody) снаружи
rm -f /tmp/rootless-test
```

**Контрольные вопросы:**
1. Кто владелец на хосте файла, созданного «root-ом» в rootless-контейнере?
2. Как прочитать маппинг uid и что значит строка `0 65534 1`?
3. Почему это безопаснее запуска контейнера от настоящего root?

---

## Часть 3: От «фейкового root» к настоящему rootless-контейнеру

### Теория для изучения перед частью

- Внутри user-ns можно поднять ВСЕ остальные namespaces (uts/pid/mnt/net) и
  собрать контейнер — без `sudo`. Так делают podman/rootless-docker.
- **Single-uid лимит:** `-r` отображает РОВНО один uid (твой → 0). Других uid
  внутри нет — `chown 1000 file` упадёт `Invalid argument` (uid 1000 не в маппинге).
  Для контейнеров с несколькими пользователями нужен **диапазон**: `/etc/subuid`
  (`user:100000:65536`) + setuid-утилиты **`newuidmap`/`newgidmap`** (пакет
  `uidmap`). Их и используют podman/Docker rootless под капотом.

---

### 3.1 Single-uid ограничение

```bash
su -s /bin/sh nobody -c 'unshare --user --map-root-user sh -c "touch /tmp/x; chown 1000 /tmp/x"'
# chown: changing ownership of '/tmp/x': Invalid argument    <- uid 1000 НЕ отображён
rm -f /tmp/x
```

**Контрольные вопросы:**
1. Почему `chown 1000` внутри single-uid rootless падает?
2. Что нужно, чтобы внутри было несколько uid (как в полноценном контейнере)?
3. Какие утилиты используют podman/rootless-docker для multi-uid маппинга?

---

## Часть 4: Troubleshooting

### Теория: диагностика по симптому

```
Симптом
├─ внутри user-ns ты не root (id -u = 65534), root-операции падают ─► забыт
│     --map-root-user (-r). unshare -U БЕЗ -r не мапит тебя в 0 (Сценарий 01)
├─ unshare -U: Operation not permitted ────────────────────────────► непривилегиров.
│     user-ns выключены в ядре: sysctl user.max_user_namespaces / unprivileged_userns_clone
├─ chown <чужой uid> внутри → Invalid argument ────────────────────► single-uid map;
│     нужен диапазон /etc/subuid + newuidmap (пакет uidmap)
└─ newuidmap: ... not permitted ───────────────────────────────────► нет записи в
      /etc/subuid для пользователя, или newuidmap не setuid-root
```

### Инцидент 1: внутри user-ns ты не root (забыт `-r`)
Разобран в `broken/scenario-01/` (`unshare -U` без `--map-root-user`). Воспроизвести и починить:
```bash
sudo ./broken/scenario-01/make-broken.sh        # без -r → uid 65534, mount запрещён
sudo ./solutions/01-map-root/fix.sh               # с -r → uid 0, mount работает
```

---

## Проверка модуля

```bash
sudo ./scripts/qa/run-module.sh 12-rootless
# --- module: 12-rootless ---
# prepare...
# [OK] непривилегированные user-ns доступны (nobody может создать user-ns)
# verify...
# [OK] rootless: внутри user-ns uid=0 (root)
# [OK] rootless: файл от 'root' внутри на хосте принадлежит nobody (uid 65534), НЕ root
# [OK] uid_map: 0→65534 (root внутри = nobody снаружи, single-uid)
# [OK] module 12-rootless verified
```

Если непривилегированные user-ns выключены в ядре, `verify/` печатает `[WARN]` и
проходит (skip). Демонстрация — команды из Частей выше.

---

## Финальная карта ресурсов модуля

| Ресурс | Что это | Демонстрирует |
|--------|---------|---------------|
| `unshare --user` (`-U`) | новый user namespace | основу rootless |
| `--map-root-user` (`-r`) | uid хоста → 0 внутри | «root внутри» |
| `/proc/self/uid_map` | таблица маппинга uid | `0 host_uid 1` |
| файл от root → владелец nobody | безопасность | root внутри ≠ root снаружи |
| `/etc/subuid` + `newuidmap` | диапазон uid (multi) | podman/rootless-docker |

---

## Теоретические вопросы (итоговые)
1. Зачем нужны rootless-контейнеры (какая угроза снимается)?
2. Что делают `-U` и `-r` и что будет без `-r`?
3. Кому на хосте принадлежит файл, созданный «root-ом» внутри rootless?
4. В чём ограничение single-uid маппинга и чем оно лечится?
5. Какие утилиты и файлы нужны для multi-uid (podman/Docker rootless)?

> Разбор ответов — в `ANSWERS.md`.

---

## Практические задания (отработка)

См. `tasks/`:
1. **`tasks/01-become-root.md`** — стать root внутри user-ns, смонтировать tmpfs.
2. **`tasks/02-uid-mapping.md`** — доказать, что файл от root внутри принадлежит вам на хосте.
3. **`tasks/03-single-uid-limit.md`** — поймать ограничение single-uid (`chown`).

Дополнительно:
4. Поставь `uidmap`, добавь диапазон в `/etc/subuid` и через `newuidmap` дай контейнеру несколько uid.
5. Внутри rootless подними uts+pid+mnt и собери мини-контейнер БЕЗ sudo.

---

## Шпаргалка

```bash
unshare --user --map-root-user id          # стать root в своём user-ns (-U -r)
unshare -U -m -r bash                       # + свой mount-ns (можно mount внутри)
cat /proc/self/uid_map                       # 0 <host_uid> 1  (single-uid)

# multi-uid (как podman/rootless-docker):
#   /etc/subuid:  user:100000:65536
#   newuidmap / newgidmap  (пакет uidmap, setuid-root)
```

---

## Чему вы научились
- Создавать user namespace без root и становиться root ВНУТРИ (`unshare -U -r`).
- Понимать, что «root» внутри = обычный пользователь снаружи (по `uid_map`/владельцу файла).
- Различать single-uid (`-r`) и multi-uid (`/etc/subuid` + `newuidmap`) маппинг.
- Видеть основу podman/rootless-Docker: контейнер без привилегий на хосте.

---

## Уборка

```bash
sudo ./verify/cleanup.sh
# [OK] cleanup 12-rootless
```

> Дальше — `13-oci-runc`: запуск контейнера через эталонный OCI-рантайм `runc`
> (то, что под капотом у Docker) — config.json + bundle.
