# Изоляция процессов в Linux — путь к контейнеризации

Практический курс из 14 этапов: собрать у студента модель «что такое контейнер
на самом деле», поэтапно реализовав каждый его слой руками, без Docker. К концу
курса студент пишет «свой Docker» из ~150 строк bash на одних примитивах ядра
(`chroot`, namespaces, cgroups, capabilities, seccomp, overlayfs, veth).

Формат модулей приведён к стандарту [k8s-лаб](../kubernetes/) этого репозитория:
README с оглавлением и теорией перед каждой частью, практические `tasks/`,
разбор инцидента в `broken/`, и программная верификация `verify/` с контрактом
`[OK]/[FAIL]`. Эталон формата — модуль **01-chroot** (остальные приводятся к
нему по мере раскатки, см. статус в индексе ниже).

## 🚀 Быстрый старт

```bash
# 1. Проверить хост и поставить зависимости (один раз, Ubuntu/Debian)
sudo ./00-setup/check.sh
sudo ./00-setup/install.sh

# 2. Пройти модуль: читаем README, делаем шаги/tasks, затем верификация
cd 01-chroot && less README.md
sudo ../scripts/qa/run-module.sh 01-chroot     # prepare → verify → cleanup

# 3. (опц.) пошаговое демо модуля с пояснениями
sudo ./01-chroot/run.sh
```

## 🗺️ Карта маршрута

| # | Этап | Что добавляет | Что Docker делал бы за тебя |
|---|---|---|---|
| 00 | setup | проверка ядра, установка утилит | — |
| 01 | chroot | свой rootfs, изоляция ФС | распаковка image |
| 02 | namespaces | UTS/PID/MNT/NET/USER/IPC | `unshare` всего сразу |
| 03 | pivot-root | безопасная смена корня | то же, что в `runc` |
| 04 | cgroups-v2 | лимиты CPU/RAM/IO/PIDs | `--memory`, `--cpus`, `--pids-limit` |
| 05 | capabilities | дробление root-прав | `--cap-drop`, `--cap-add` |
| 06 | seccomp | фильтрация системных вызовов | `--security-opt seccomp=...` |
| 07 | apparmor | мандатный контроль доступа | `--security-opt apparmor=...` |
| 08 | overlayfs | слоистая ФС, CoW, whiteout | `docker pull`, `docker commit` |
| 09 | networking | veth, bridge, NAT | сеть `bridge` (`docker0`) |
| 10 | rootfs+nspawn | сборка rootfs, systemd-nspawn | `FROM alpine`, `docker run` |
| 11 | capstone | свой контейнер из ~150 строк bash | весь `docker run` |
| 12 | rootless | контейнер без root (user-ns) | `podman`/rootless Docker |
| 13 | oci-runc | запуск через эталонный `runc` | рантайм под капотом Docker |
| 14 | ebpf | наблюдаемость изоляции | трассировка syscalls/сети |

## 📦 Модули

Статус формата: ✅ — приведён к стандарту (README+tasks+broken+verify);
🔸 — старый формат (README + `run.sh`/`check.sh`), в очереди на раскатку.

| # | Модуль | Тема | Статус |
|---|--------|------|--------|
| 00 | [00-setup](./00-setup) | Проверка хоста и установка зависимостей | 🔸 |
| 01 | [01-chroot](./01-chroot) | chroot: изоляция ФС и её дырявость (эталон) | ✅ |
| 02 | [02-namespaces](./02-namespaces) | UTS/PID/MNT/NET/USER/IPC namespaces | ✅ |
| 03 | [03-pivot-root](./03-pivot-root) | pivot_root: безопасная смена корня | ✅ |
| 04 | [04-cgroups-v2](./04-cgroups-v2) | Лимиты CPU/RAM/IO/PIDs (cgroup v2) | ✅ |
| 05 | [05-capabilities](./05-capabilities) | Дробление root-прав (capabilities) | ✅ |
| 06 | [06-seccomp](./06-seccomp) | Фильтрация системных вызовов | ✅ |
| 07 | [07-apparmor](./07-apparmor) | Мандатный контроль доступа (MAC) | ✅ |
| 08 | [08-overlayfs](./08-overlayfs) | Слоистая ФС, CoW, whiteout | ✅ |
| 09 | [09-networking](./09-networking) | veth, bridge, NAT | ✅ |
| 10 | [10-rootfs-and-nspawn](./10-rootfs-and-nspawn) | Сборка rootfs, systemd-nspawn | ✅ |
| 11 | [11-capstone](./11-capstone) | «Свой Docker» из ~150 строк bash | 🔸 |
| 12 | [12-rootless](./12-rootless) | Контейнер без root (user-ns) | 🔸 |
| 13 | [13-oci-runc](./13-oci-runc) | Запуск через эталонный `runc` | 🔸 |
| 14 | [14-ebpf](./14-ebpf) | Наблюдаемость изоляции через eBPF | 🔸 |

## ✅ QA и верификация

Для модуля нового стандарта верификация — одной командой (root обязателен):
```bash
sudo ./scripts/qa/run-module.sh 01-chroot   # prepare → verify → (trap) cleanup
```
Массовый прогон всех модулей (не падает на первом FAIL, собирает картину):
```bash
sudo ./run-all.sh
```
Линт перед коммитом (shellcheck + markdown-дисциплина модулей):
```bash
./scripts/qa/lint.sh
```
Сгенерировать/обновить оглавления в README модулей:
```bash
./scripts/qa/add-toc.sh
```

## 📂 Структура репозитория

- `scripts/verify/helpers.sh` — общие helper'ы для `verify/*.sh` (`ok`/`fail`/
  `need_root`/`need_bin`/`assert_eq`/`ns_inode` …).
- `scripts/qa/` — QA-обвязка: `run-module.sh`, `lint.sh`, `add-toc.sh`.
- `scripts/lib.sh` — helper'ы старого формата (`assert`/`summary`) для legacy `run.sh`/`check.sh`.
- `NN-stage/` — учебные модули (см. layout ниже).
- `legacy/` — исходные 7 лабораторных, на основе которых построен курс
  (теоретическая версия; не поддерживается под новый стандарт и линт).

Layout модуля нового стандарта (эталон — `01-chroot`):
```
NN-stage/
├── README.md            теория + практика (TOC, ⏱-строка, Части, Troubleshooting, Шпаргалка)
├── run.sh               (опц.) демо-прогон с пояснениями
├── ANSWERS.md           разбор итоговых вопросов
├── tasks/NN-*.md        практические задания (Задача / Проверка / Ожидаемый результат)
├── broken/scenario-NN/  инцидент: README (Симптом→Решение) + make-broken.sh
├── solutions/NN-*/      фикс к сценарию
└── verify/
    ├── prepare.sh       детерминированно собрать «ресурсы» модуля
    ├── verify.sh        автотест целей ([OK]/[FAIL] поверх helpers.sh)
    └── cleanup.sh       разобрать (umount/rm) — зовётся trap'ом run-module.sh
```

## 🖥 Системные требования

- Ubuntu 22.04 / 24.04 LTS (в других дистрибутивах часть команд отличается).
- Ядро **≥ 5.10** (cgroups v2 unified, time namespace, дружественный seccomp).
- Реальные root-права (sudo). На контейнерных хостах часть лаб не пройдёт
  (вложенные namespaces, AppArmor требует загрузки в ядро).
- ~2 ГБ свободного места под rootfs alpine + debootstrap.

> ⚠️ На WSL2 модули `07-apparmor` (AppArmor выключен), `10-rootfs-and-nspawn`
> (нет `systemd-nspawn`/`debootstrap`) и `14-ebpf` (нет `bpftrace`) вживую не
> прогоняются — нужен полноценный Ubuntu-хост. Остальные модули (01–06, 08, 09,
> 13) работают и на WSL2 с ядром 6.x.

## Связь с другими лабами

- `labs/linux-processes`, `labs/linux-basics` — базовая работа с процессами, fd,
  сигналами. Пройди их сначала, если темы непривычны.
- `labs/docker` — следующий шаг: применение этих примитивов к продовому Docker.
- `labs/kubernetes` — формат-эталон, по которому приведён этот курс.
