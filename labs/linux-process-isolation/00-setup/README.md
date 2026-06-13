# 00 — Setup и проверка окружения

Служебный модуль: готовит хост к курсу (аналог `scripts/bootstrap/` в k8s-лабах,
а не учебный модуль — теории и `verify/` здесь нет). Проверки делятся на два класса:

- **CORE** — обязательны для основного трека (модули 01-09, 13). Если красное —
  курс на этом хосте не пойдёт:
  - ядро **≥ 5.10** (cgroups v2 unified, time namespace);
  - cgroups v2 примонтирована в `/sys/fs/cgroup`;
  - namespaces поддерживаются (`/proc/self/ns/*`) и user-ns реально создаётся;
  - утилиты: `unshare`, `nsenter`, `ip`, `chroot`, `busybox`, `runc`, `mount`, `stat`.
- **Per-module** — нужны лишь отдельным модулям; их отсутствие не «заваливает»
  сетап (печатаются как `info`, в summary не считаются):
  - `setcap`/`capsh` — модуль 05; `strace` — 06;
  - AppArmor + `apparmor_parser` — модуль 07;
  - `systemd-nspawn`, `debootstrap` — модуль 10;
  - `newuidmap` (пакет `uidmap`) — модуль 12 (rootless);
  - `bpftrace` — модуль 14; `stress-ng`/`fio` — нагрузка в модуле 04.

## Запуск

```bash
sudo ./00-setup/check.sh    # покажет CORE (зачёт) + per-module (инфо)
sudo ./00-setup/install.sh  # доустановит пакеты (Ubuntu/Debian)
sudo ./00-setup/check.sh    # перепроверит
```

После готового хоста модули нового формата гоняются так:
```bash
sudo ./scripts/qa/run-module.sh 01-chroot     # prepare → verify → cleanup
```

## Где это не сработает (и что пропустить)

- **WSL2**: CORE проходит (ядро 6.x, cgroup v2, namespaces, runc — на месте), но
  AppArmor выключен, нет `systemd-nspawn`/`debootstrap`/`bpftrace`/`newuidmap`.
  → CORE-сетап зелёный; модули **07/10/12/14** пройди на полноценном Ubuntu-хосте.
- **Голый Docker без `--privileged`**: вложенные namespaces, cgroups и mount не
  работают — используй настоящую ВМ.
- **macOS / Windows host**: нужен Linux-kernel; здесь не пройдёт совсем.
